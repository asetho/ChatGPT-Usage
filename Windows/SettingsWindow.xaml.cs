using System.Windows;

namespace ChatGPTUsage.Windows;

public partial class SettingsWindow : Window
{
    public SettingsWindow(UsageViewModel usage)
    {
        InitializeComponent();
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
        const double margin = 8;
        var area = SystemParameters.WorkArea;
        Left = Math.Clamp(Left, area.Left + margin, Math.Max(area.Left + margin, area.Right - ActualWidth - margin));
        Top = Math.Clamp(Top, area.Top + margin, Math.Max(area.Top + margin, area.Bottom - ActualHeight - margin));
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
        CodexPathText.Text = CodexUsageService.FindExecutable();
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
