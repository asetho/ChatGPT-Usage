using System.Diagnostics;
using System.Windows;

namespace ChatGPTUsage.Windows;

public partial class AboutWindow : Window
{
    public AboutWindow(UsageViewModel usage)
    {
        InitializeComponent();
        DataContext = usage;
        VersionText.Text = $"Version {UpdateCheckService.CurrentVersionText}";
    }

    private void OpenGitHub_Click(object sender, RoutedEventArgs e) =>
        OpenUrl("https://github.com/asetho/ChatGPT-Usage");

    private async void CheckForUpdates_Click(object sender, RoutedEventArgs e) =>
        await ((UsageViewModel)DataContext).CheckForUpdatesManuallyAsync();

    private void OpenUpdate_Click(object sender, RoutedEventArgs e)
    {
        if (((UsageViewModel)DataContext).UpdateUrl is { } url) OpenUrl(url);
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    private static void OpenUrl(string url) =>
        Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
}
