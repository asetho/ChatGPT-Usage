using System.Net.Http;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ChatGPTUsage.Windows;

public sealed record AvailableUpdateInfo(string Version, string ReleaseUrl);

internal static class UpdateCheckService
{
    private static readonly Uri LatestReleaseUri = new(
        "https://api.github.com/repos/asetho/ChatGPT-Usage/releases/latest");

    private static readonly HttpClient Client = new()
    {
        Timeout = TimeSpan.FromSeconds(8)
    };

    public static Version CurrentVersion =>
        Assembly.GetEntryAssembly()?.GetName().Version ?? new Version(0, 0, 0);

    public static string CurrentVersionText => FormatVersion(CurrentVersion);

    public static async Task<AvailableUpdateInfo?> FetchAvailableUpdateAsync(
        Version currentVersion,
        CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, LatestReleaseUri);
        request.Headers.Accept.ParseAdd("application/vnd.github+json");
        request.Headers.TryAddWithoutValidation("X-GitHub-Api-Version", "2026-03-10");
        request.Headers.UserAgent.ParseAdd($"asetho-ChatGPT-Usage/{FormatVersion(currentVersion)}");

        using var response = await Client.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();

        await using var body = await response.Content.ReadAsStreamAsync(cancellationToken);
        var release = await JsonSerializer.DeserializeAsync<GitHubRelease>(
            body,
            cancellationToken: cancellationToken);

        return AvailableUpdate(release, currentVersion);
    }

    internal static AvailableUpdateInfo? AvailableUpdate(
        GitHubRelease? release,
        Version currentVersion)
    {
        if (release is null ||
            !TryParseReleaseVersion(release.TagName, out var latestVersion) ||
            latestVersion <= currentVersion ||
            !Uri.TryCreate(release.HtmlUrl, UriKind.Absolute, out var releaseUri) ||
            releaseUri.Scheme != Uri.UriSchemeHttps ||
            !string.Equals(releaseUri.Host, "github.com", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        return new AvailableUpdateInfo(FormatVersion(latestVersion), releaseUri.AbsoluteUri);
    }

    private static bool TryParseReleaseVersion(string tagName, out Version version)
    {
        var normalized = tagName.Trim();
        if (normalized.StartsWith('v') || normalized.StartsWith('V'))
        {
            normalized = normalized[1..];
        }

        if (!Version.TryParse(normalized, out var parsed) ||
            parsed.Major < 0 || parsed.Minor < 0 || parsed.Build < 0 || parsed.Revision >= 0)
        {
            version = new Version();
            return false;
        }

        version = parsed;
        return true;
    }

    private static string FormatVersion(Version version) =>
        $"{version.Major}.{version.Minor}.{Math.Max(version.Build, 0)}";

    internal sealed record GitHubRelease(
        [property: JsonPropertyName("tag_name")] string TagName,
        [property: JsonPropertyName("html_url")] string HtmlUrl);
}
