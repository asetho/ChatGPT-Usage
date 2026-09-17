using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ChatGPTUsage.Windows;

internal static class CodexUsageService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public static async Task<UsageSnapshot> FetchAsync(CancellationToken cancellationToken = default)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(30));
        var executable = FindExecutable();
        var startInfo = new ProcessStartInfo
        {
            FileName = Path.GetExtension(executable).Equals(".cmd", StringComparison.OrdinalIgnoreCase)
                ? Environment.GetEnvironmentVariable("ComSpec") ?? "cmd.exe"
                : executable,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
        };
        if (Path.GetExtension(executable).Equals(".cmd", StringComparison.OrdinalIgnoreCase))
        {
            startInfo.ArgumentList.Add("/c");
            startInfo.ArgumentList.Add(executable);
        }
        startInfo.ArgumentList.Add("app-server");
        startInfo.ArgumentList.Add("--stdio");

        using var process = new Process { StartInfo = startInfo };
        try
        {
            if (!process.Start()) throw new InvalidOperationException("Could not start Codex.");
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            throw new InvalidOperationException("Codex CLI was not found. Install Codex or set CODEX_EXECUTABLE.", error);
        }

        // Do not cancel the stderr drain with the request timeout. The process
        // is terminated in finally, which closes the stream; canceling this
        // task can otherwise mask the useful timeout error below.
        var standardError = process.StandardError.ReadToEndAsync();
        try
        {
            await WriteAsync(process.StandardInput, new
            {
                id = 1,
                method = "initialize",
                @params = new
                {
                    clientInfo = new { name = "chatgpt_usage_windows", title = "ChatGPT Usage", version = "1.0.0" },
                    capabilities = new { experimentalApi = true }
                }
            });

            RateLimitsResponse? rateLimits = null;
            AccountUsageResponse? accountUsage = null;
            var usageFinished = false;
            while (!timeout.IsCancellationRequested)
            {
                var line = await process.StandardOutput.ReadLineAsync(timeout.Token);
                if (line is null) break;
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                if (!root.TryGetProperty("id", out var idElement) || !idElement.TryGetInt32(out var id)) continue;

                if (root.TryGetProperty("error", out var errorElement))
                {
                    if (id == 4)
                    {
                        usageFinished = true;
                        if (rateLimits is not null) break;
                        continue;
                    }
                    throw new InvalidOperationException(errorElement.TryGetProperty("message", out var message)
                        ? message.GetString() ?? "Codex could not read usage data."
                        : "Codex could not read usage data.");
                }

                if (!root.TryGetProperty("result", out var result)) continue;
                if (id == 1)
                {
                    await WriteAsync(process.StandardInput, new { method = "initialized" });
                    await WriteAsync(process.StandardInput, new { id = 3, method = "account/rateLimits/read" });
                    await WriteAsync(process.StandardInput, new { id = 4, method = "account/usage/read" });
                }
                else if (id == 3)
                {
                    rateLimits = JsonSerializer.Deserialize<RateLimitsResponse>(result.GetRawText(), JsonOptions);
                }
                else if (id == 4)
                {
                    accountUsage = JsonSerializer.Deserialize<AccountUsageResponse>(result.GetRawText(), JsonOptions);
                    usageFinished = true;
                }

                if (rateLimits is not null && usageFinished) break;
            }

            if (rateLimits is null)
            {
                throw new InvalidOperationException("Codex returned usage data in an unexpected format.");
            }

            var limitsById = rateLimits.RateLimitsByLimitId ?? new Dictionary<string, RateLimitSnapshot>();
            if (limitsById.Count == 0)
            {
                limitsById[rateLimits.RateLimits.LimitId ?? "codex"] = rateLimits.RateLimits;
            }
            foreach (var (limitId, limit) in limitsById)
            {
                limit.FallbackLimitId = limitId;
            }
            return new UsageSnapshot(rateLimits.RateLimits, limitsById, rateLimits.RateLimitResetCredits, accountUsage);
        }
        catch (OperationCanceledException) when (timeout.IsCancellationRequested)
        {
            throw new TimeoutException("Codex took too long to return usage data.");
        }
        finally
        {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            _ = await standardError;
        }
    }

    private static async Task WriteAsync(StreamWriter writer, object message)
    {
        await writer.WriteLineAsync(JsonSerializer.Serialize(message, JsonOptions));
        await writer.FlushAsync();
    }

    private static string FindExecutable()
    {
        var configured = Environment.GetEnvironmentVariable("CODEX_EXECUTABLE");
        if (!string.IsNullOrWhiteSpace(configured) && File.Exists(configured)) return configured;

        var standaloneCodex = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs",
            "OpenAI",
            "Codex",
            "bin",
            "codex.exe");
        if (File.Exists(standaloneCodex)) return standaloneCodex;

        var npmCodex = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "npm",
            "codex.cmd");
        if (File.Exists(npmCodex)) return npmCodex;

        var windowsApps = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            "WindowsApps");
        try
        {
            var packagedCodex = Directory.EnumerateDirectories(windowsApps, "OpenAI.Codex*")
                .OrderByDescending(Path.GetFileName)
                .Select(directory => Path.Combine(directory, "app", "resources", "codex.exe"))
                .FirstOrDefault(File.Exists);
            if (packagedCodex is not null) return packagedCodex;
        }
        catch (UnauthorizedAccessException)
        {
            // Fall back to a Codex CLI installed on PATH.
        }

        return configured ?? "codex.exe";
    }
}

internal sealed class RateLimitsResponse
{
    public RateLimitSnapshot RateLimits { get; init; } = new();
    public Dictionary<string, RateLimitSnapshot>? RateLimitsByLimitId { get; init; }
    public RateLimitResetCreditsSummary? RateLimitResetCredits { get; init; }
}

internal sealed class RateLimitResetCreditsSummary
{
    public long AvailableCount { get; init; }
    public List<RateLimitResetCredit>? Credits { get; init; }
    public long? NextExpiration => Credits?
        .Where(credit => credit.Status == "available" && credit.ExpiresAt.HasValue)
        .Select(credit => credit.ExpiresAt)
        .Min();
}

internal sealed class RateLimitResetCredit
{
    public long? ExpiresAt { get; init; }
    public string Status { get; init; } = "unknown";
    public string? Title { get; init; }
}

internal sealed class RateLimitSnapshot
{
    public string? LimitId { get; init; }
    public string? LimitName { get; init; }
    public RateLimitWindow? Primary { get; init; }
    public RateLimitWindow? Secondary { get; init; }

    [JsonIgnore]
    public string? FallbackLimitId { get; set; }

    private string? EffectiveLimitId => string.IsNullOrWhiteSpace(LimitId) ? FallbackLimitId : LimitId;
    public bool IsLunaReserve => IsReserveName(EffectiveLimitId) || IsReserveName(LimitName);
    public string DisplayName => IsLunaReserve ? "Luna Reserve" : !string.IsNullOrWhiteSpace(LimitName)
        ? LimitName
        : EffectiveLimitId is null or "codex" ? "Codex" : EffectiveLimitId.Replace("_", " ");
    public RateLimitWindow? FiveHourWindow => new[] { Primary, Secondary }.FirstOrDefault(window => window?.WindowDurationMins == 300);
    public RateLimitWindow? WeeklyWindow => new[] { Primary, Secondary }.FirstOrDefault(window => window?.WindowDurationMins == 10_080);

    private static bool IsReserveName(string? value) =>
        string.Equals(value?.Trim().Replace('_', '-'), "gpt-reserve", StringComparison.OrdinalIgnoreCase);
}

internal sealed class RateLimitWindow
{
    public int UsedPercent { get; init; }
    public long? WindowDurationMins { get; init; }
    public long? ResetsAt { get; init; }
}

internal sealed class AccountUsageResponse
{
    public AccountTokenUsageSummary Summary { get; init; } = new();
    public List<AccountTokenUsageDailyBucket>? DailyUsageBuckets { get; init; }
}

internal sealed class AccountTokenUsageSummary
{
    public long? CurrentStreakDays { get; init; }
    public long? LifetimeTokens { get; init; }
}

internal sealed class AccountTokenUsageDailyBucket
{
    public string StartDate { get; init; } = "";
    public long? Tokens { get; init; }
}

internal sealed class UsageSnapshot(
    RateLimitSnapshot defaultRateLimits,
    Dictionary<string, RateLimitSnapshot> rateLimitsById,
    RateLimitResetCreditsSummary? rateLimitResetCredits,
    AccountUsageResponse? accountUsage)
{
    public RateLimitSnapshot CodexRateLimits => rateLimitsById.GetValueOrDefault("codex") ?? defaultRateLimits;
    public RateLimitResetCreditsSummary? RateLimitResetCredits => rateLimitResetCredits;
    public AccountUsageResponse? AccountUsage => accountUsage;
    public IEnumerable<RateLimitSnapshot> AdditionalRateLimits => rateLimitsById
        .Where(pair => pair.Key != "codex")
        .Select(pair => pair.Value)
        .OrderBy(limit => limit.DisplayName, StringComparer.CurrentCultureIgnoreCase);
    public long? TodayTokens => accountUsage?.DailyUsageBuckets?
        .FirstOrDefault(bucket => bucket.StartDate == DateTime.Now.ToString("yyyy-MM-dd"))?.Tokens;
}
