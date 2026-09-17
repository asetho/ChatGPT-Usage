using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;

namespace ChatGPTUsage.Windows;

public sealed class UsageViewModel : INotifyPropertyChanged
{
    private bool isRefreshing;
    private string weeklyRemaining = "—";
    private string weeklyReset = "—";
    private string resetTitle = "Open ChatGPT Usage";
    private string resetExpiration = "";
    private string errorMessage = "";
    private string refreshStatus = "";
    private string updateDescription = "";
    private string updateCheckStatus = "";
    private string? updateUrl;
    private Visibility additionalLimitsVisibility = Visibility.Collapsed;
    private Visibility tokenUsageVisibility = Visibility.Collapsed;
    private Visibility updateAvailableVisibility = Visibility.Collapsed;
    private Visibility resetExpirationVisibility = Visibility.Collapsed;
    private bool isCheckingForUpdates;

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<LimitDisplay> AdditionalLimits { get; } = [];
    public ObservableCollection<UsageDetail> TokenUsage { get; } = [];

    public string WeeklyRemaining { get => weeklyRemaining; private set => Set(ref weeklyRemaining, value); }
    public string WeeklyReset { get => weeklyReset; private set => Set(ref weeklyReset, value); }
    public string ResetTitle { get => resetTitle; private set => Set(ref resetTitle, value); }
    public string ResetExpiration { get => resetExpiration; private set => Set(ref resetExpiration, value); }
    public string ErrorMessage { get => errorMessage; private set => Set(ref errorMessage, value); }
    public string RefreshStatus { get => refreshStatus; private set => Set(ref refreshStatus, value); }
    public string UpdateDescription { get => updateDescription; private set => Set(ref updateDescription, value); }
    public string UpdateCheckStatus { get => updateCheckStatus; private set => Set(ref updateCheckStatus, value); }
    public string? UpdateUrl { get => updateUrl; private set => Set(ref updateUrl, value); }
    public Visibility AdditionalLimitsVisibility { get => additionalLimitsVisibility; private set => Set(ref additionalLimitsVisibility, value); }
    public Visibility TokenUsageVisibility { get => tokenUsageVisibility; private set => Set(ref tokenUsageVisibility, value); }
    public Visibility UpdateAvailableVisibility { get => updateAvailableVisibility; private set => Set(ref updateAvailableVisibility, value); }
    public Visibility ResetExpirationVisibility { get => resetExpirationVisibility; private set => Set(ref resetExpirationVisibility, value); }
    public string TrayText => $"ChatGPT weekly usage: {WeeklyRemaining} remaining";

    public Task RefreshAsync() => RefreshAsync(showErrors: true);

    public Task RefreshInBackgroundAsync() => RefreshAsync(showErrors: false);

    public Task CheckForUpdatesAsync() => CheckForUpdatesAsync(isManual: false);

    public Task CheckForUpdatesManuallyAsync()
    {
        if (isCheckingForUpdates)
        {
            UpdateCheckStatus = "An update check is already in progress.";
            return Task.CompletedTask;
        }
        UpdateCheckStatus = "Checking for updates…";
        return CheckForUpdatesAsync(isManual: true);
    }

    private async Task CheckForUpdatesAsync(bool isManual)
    {
        if (isCheckingForUpdates) return;

        isCheckingForUpdates = true;
        try
        {
            var update = await UpdateCheckService.FetchAvailableUpdateAsync(UpdateCheckService.CurrentVersion);
            if (update is null)
            {
                UpdateAvailableVisibility = Visibility.Collapsed;
                UpdateDescription = "";
                UpdateUrl = null;
                if (isManual) UpdateCheckStatus = "You’re up to date.";
                return;
            }

            UpdateDescription = $"Version {update.Version} · View release";
            UpdateUrl = update.ReleaseUrl;
            UpdateAvailableVisibility = Visibility.Visible;
            if (isManual) UpdateCheckStatus = $"Version {update.Version} is available.";
        }
        catch
        {
            if (isManual) UpdateCheckStatus = "Unable to check for updates right now.";
            // Update checks never interfere with usage refreshes.
        }
        finally
        {
            isCheckingForUpdates = false;
        }
    }

    private async Task RefreshAsync(bool showErrors)
    {
        if (isRefreshing) return;

        isRefreshing = true;
        if (showErrors)
        {
            RefreshStatus = "Refreshing…";
            ErrorMessage = "";
        }
        try
        {
            ApplySnapshot(await CodexUsageService.FetchAsync());
            ErrorMessage = "";
            RefreshStatus = "Updated just now";
        }
        catch (Exception error)
        {
            if (showErrors || WeeklyRemaining == "—")
            {
                ErrorMessage = error is TimeoutException
                    ? "Refresh timed out. It will retry automatically."
                    : error.Message;
                RefreshStatus = "Unavailable";
            }
        }
        finally
        {
            isRefreshing = false;
        }
    }

    private void ApplySnapshot(UsageSnapshot snapshot)
    {
        var limits = snapshot.CodexRateLimits;
        WeeklyRemaining = Remaining(limits.WeeklyWindow);
        WeeklyReset = ResetDetail(limits.WeeklyWindow?.ResetsAt, fullDate: true);
        ResetTitle = snapshot.RateLimitResetCredits?.AvailableCount is long count && count > 0
            ? count == 1 ? "1 reset available" : $"{count} resets available"
            : "Open ChatGPT Usage";
        ResetExpiration = snapshot.RateLimitResetCredits?.NextExpiration is long expiration
            ? $"Expires {FullDateTime(expiration)}"
            : "";
        ResetExpirationVisibility = string.IsNullOrEmpty(ResetExpiration) ? Visibility.Collapsed : Visibility.Visible;

        AdditionalLimits.Clear();
        foreach (var limit in snapshot.AdditionalRateLimits)
        {
            var fiveHour = limit.FiveHourWindow;
            var weekly = limit.WeeklyWindow;
            AdditionalLimits.Add(new LimitDisplay(
                limit.DisplayName,
                limit.IsLunaReserve ? Visibility.Visible : Visibility.Collapsed,
                fiveHour is null ? "" : ResetValue(fiveHour.ResetsAt, fullDate: false),
                fiveHour is null ? "" : Remaining(fiveHour),
                fiveHour is null ? Visibility.Collapsed : Visibility.Visible,
                weekly is null ? "" : ResetDetail(weekly.ResetsAt, fullDate: true),
                weekly is null ? "" : Remaining(weekly),
                weekly is null ? Visibility.Collapsed : Visibility.Visible));
        }
        AdditionalLimitsVisibility = AdditionalLimits.Count == 0 ? Visibility.Collapsed : Visibility.Visible;

        TokenUsage.Clear();
        if (snapshot.AccountUsage is { } accountUsage)
        {
            TokenUsage.Add(new UsageDetail("Today", TokenCount(snapshot.TodayTokens)));
            TokenUsage.Add(new UsageDetail("Lifetime", TokenCount(accountUsage.Summary.LifetimeTokens)));
            if (accountUsage.Summary.CurrentStreakDays is long streak)
            {
                TokenUsage.Add(new UsageDetail("Current streak", $"{streak} days"));
            }
        }
        TokenUsageVisibility = TokenUsage.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
    }

    private static string Remaining(RateLimitWindow? window) => window is null ? "—" : $"{Math.Clamp(100 - window.UsedPercent, 0, 100)}%";

    private static string ResetDetail(long? timestamp, bool fullDate)
    {
        if (timestamp is null) return "Reset date unavailable";
        return $"Resets {ResetValue(timestamp, fullDate)}";
    }

    private static string ResetValue(long? timestamp, bool fullDate)
    {
        if (timestamp is null) return "—";
        var reset = DateTimeOffset.FromUnixTimeSeconds(timestamp.Value).ToLocalTime();
        var interval = reset - DateTimeOffset.Now;
        return !fullDate && (reset.Date == DateTimeOffset.Now.Date || (interval >= TimeSpan.Zero && interval < TimeSpan.FromDays(1)))
            ? reset.ToString("t")
            : reset.ToString("MMM d, yyyy, h:mm tt");
    }

    private static string FullDateTime(long timestamp) =>
        DateTimeOffset.FromUnixTimeSeconds(timestamp).ToLocalTime().ToString("MMM d, yyyy, h:mm tt");

    private static string TokenCount(long? value)
    {
        if (value is null) return "—";
        return Math.Abs(value.Value) switch
        {
            >= 1_000_000_000 => $"{value.Value / 1_000_000_000d:0.#}B",
            >= 1_000_000 => $"{value.Value / 1_000_000d:0.#}M",
            >= 1_000 => $"{value.Value / 1_000d:0.#}K",
            _ => value.Value.ToString("N0")
        };
    }

    private void Set<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        if (propertyName is nameof(WeeklyRemaining))
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(TrayText)));
        }
    }
}

public sealed record LimitDisplay(
    string Name,
    Visibility GuideVisibility,
    string FiveHourReset,
    string FiveHourRemaining,
    Visibility FiveHourVisibility,
    string WeeklyReset,
    string WeeklyRemaining,
    Visibility WeeklyVisibility);
public sealed record UsageDetail(string Title, string Value);
