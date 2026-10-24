using System.Windows;

namespace ChatGPTUsage.Windows;

public partial class SettingsWindow : Window
{
    private const double ScreenMargin = 8;

    public SettingsWindow(UsageViewModel usage)
    {
        InitializeComponent();
        MaxHeight = Math.Max(1, SystemParameters.WorkArea.Height - 2 * ScreenMargin);
        DataContext = usage;
        VersionText.Text = $"Version {UpdateCheckService.CurrentVersionText}";
    }

    private void Window_Loaded(object sender, RoutedEventArgs e)
    {
        ((UsageViewModel)DataContext).ClearUpdateCheckConfirmation();
        ReloadSettings();
        KeepWithinWorkArea();
    }

    private void Window_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (IsLoaded) KeepWithinWorkArea();
    }

    private void KeepWithinWorkArea()
    {
        var area = SystemParameters.WorkArea;
        Left = Math.Clamp(Left, area.Left + ScreenMargin, Math.Max(area.Left + ScreenMargin, area.Right - ActualWidth - ScreenMargin));
        Top = Math.Clamp(Top, area.Top + ScreenMargin, Math.Max(area.Top + ScreenMargin, area.Bottom - ActualHeight - ScreenMargin));
    }

    private void ReloadSettings()
    {
        LoginError.Visibility = StartupSettingsButton.Visibility = Visibility.Collapsed;
        try
        {
            LaunchAtLoginCheckBox.IsChecked = AppSettings.LaunchAtLogin;
            if (AppSettings.LaunchAtLogin && AppSettings.StartupDisabledByWindows)
            {
                LoginError.Text = "Allow ChatGPT Usage in Windows Startup Settings to finish enabling launch at login.";
                LoginError.Visibility = StartupSettingsButton.Visibility = Visibility.Visible;
            }
        }
        catch { LoginError.Text = "Couldn’t read launch at login settings."; LoginError.Visibility = Visibility.Visible; }
        var selected = AppSettings.CodexExecutablePath;
        CodexDetectionText.Text = selected is null ? "Automatic detection" : "Selected executable";
        try { CodexPathText.Text = CodexUsageService.FindExecutable(); }
        catch { CodexPathText.Text = "Codex was not found. Choose its executable."; }
        CodexPathText.ToolTip = CodexPathText.Text;
        AutomaticCodexButton.Visibility = selected is null ? Visibility.Collapsed : Visibility.Visible;
    }

    private void LaunchAtLogin_Click(object sender, RoutedEventArgs e)
    {
        try { AppSettings.LaunchAtLogin = LaunchAtLoginCheckBox.IsChecked == true; ReloadSettings(); }
        catch { ReloadSettings(); LoginError.Text = "Couldn’t change launch at login."; LoginError.Visibility = Visibility.Visible; }
    }

    private void StartupSettings_Click(object sender, RoutedEventArgs e) =>
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("ms-settings:startupapps") { UseShellExecute = true });

    private async void ChooseCodex_Click(object sender, RoutedEventArgs e)
    {
        var picker = new Microsoft.Win32.OpenFileDialog { Title = "Choose Codex", Filter = "Codex executable (*.exe;*.cmd)|*.exe;*.cmd", CheckFileExists = true };
        if (picker.ShowDialog(this) != true) return;
        if (SelectExecutable(picker.FileName)) await ((UsageViewModel)DataContext).RefreshAsync();
    }

    private async void AutomaticCodex_Click(object sender, RoutedEventArgs e)
    {
        if (SelectExecutable(null)) await ((UsageViewModel)DataContext).RefreshAsync();
    }

    private bool SelectExecutable(string? path)
    {
        try { AppSettings.SelectExecutable(path); CodexError.Visibility = Visibility.Collapsed; ReloadSettings(); return true; }
        catch { CodexError.Text = "Couldn’t save the Codex selection. Choose an existing .exe or .cmd file."; CodexError.Visibility = Visibility.Visible; return false; }
    }

    private void OpenGitHub_Click(object sender, RoutedEventArgs e) =>
        ExternalLinkLauncher.TryOpen("https://github.com/asetho/ChatGPT-Usage");

    private async void CheckForUpdates_Click(object sender, RoutedEventArgs e) =>
        await ((UsageViewModel)DataContext).CheckForUpdatesManuallyAsync();

    private async void InstallUpdate_Click(object sender, RoutedEventArgs e)
    {
        if (await ((UsageViewModel)DataContext).PrepareAvailableUpdateAsync())
            ((App)System.Windows.Application.Current).ExitApplication();
    }

    private void OpenUpdate_Click(object sender, RoutedEventArgs e)
    {
        if (((UsageViewModel)DataContext).UpdateUrl is { } url) ExternalLinkLauncher.TryOpen(url);
    }

    private void Done_Click(object sender, RoutedEventArgs e) => Close();
}
