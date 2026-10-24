using Microsoft.Win32;
using System.Windows;

namespace ChatGPTUsage.Windows;

public partial class MainWindow : Window
{
    private const double ScreenMargin = 16;
    private const string SettingsRegistryPath = @"Software\asetho\ChatGPT Usage";
    private const string TokenUsageExpandedValue = "TokenUsageExpanded";
    private bool canClose;
    private bool heightFitQueued;
    private bool isFittingHeight;
    private bool isShowingSettings;

    public MainWindow(UsageViewModel usage)
    {
        InitializeComponent();
        DataContext = usage;
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(SettingsRegistryPath);
            TokenUsageExpander.IsExpanded = key?.GetValue(TokenUsageExpandedValue) is 1;
        }
        catch
        {
            // Keep the default collapsed state if preferences cannot be read.
        }

        var availableHeight = Math.Max(1, SystemParameters.WorkArea.Height - (ScreenMargin * 2));
        MaxHeight = availableHeight;
    }

    public void ShowNearBottomRight()
    {
        var usage = (UsageViewModel)DataContext;
        usage.UpdateFreshnessStatus();
        _ = usage.RefreshAsync();
        Show();
        UpdateLayout();
        FitHeightToContent();
        PositionNearBottomRight();
        Activate();
    }

    public void AllowClose() => canClose = true;

    private void Window_Deactivated(object sender, EventArgs e)
    {
        if (!isShowingSettings) Hide();
    }

    private void Window_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (IsVisible)
        {
            PositionNearBottomRight();
        }
    }

    private void Window_Loaded(object sender, RoutedEventArgs e) => QueueHeightFit();

    private void LayoutPart_SizeChanged(object sender, SizeChangedEventArgs e) => QueueHeightFit();

    private void Disclosure_Changed(object sender, RoutedEventArgs e)
    {
        if (sender == TokenUsageExpander && IsLoaded)
        {
            try
            {
                using var key = Registry.CurrentUser.CreateSubKey(SettingsRegistryPath);
                key.SetValue(TokenUsageExpandedValue, TokenUsageExpander.IsExpanded ? 1 : 0, RegistryValueKind.DWord);
            }
            catch
            {
                // Disclosure controls still work if preferences cannot be saved.
            }
        }
        QueueHeightFit();
    }

    private void QueueHeightFit()
    {
        if (!IsLoaded || heightFitQueued || isFittingHeight)
        {
            return;
        }

        heightFitQueued = true;
        _ = Dispatcher.BeginInvoke(new Action(() =>
        {
            heightFitQueued = false;
            FitHeightToContent();
        }));
    }

    private void FitHeightToContent()
    {
        if (!IsLoaded || isFittingHeight)
        {
            return;
        }

        isFittingHeight = true;
        try
        {
            UpdateLayout();

            var borderHeight = RootBorder.Padding.Top + RootBorder.Padding.Bottom
                + RootBorder.BorderThickness.Top + RootBorder.BorderThickness.Bottom;
            var footerHeight = FooterPanel.DesiredSize.Height;
            var contentHeight = ContentStack.DesiredSize.Height;
            var targetHeight = Math.Min(MaxHeight, Math.Ceiling(borderHeight + footerHeight + contentHeight));

            SizeToContent = System.Windows.SizeToContent.Manual;
            Height = Math.Max(1, targetHeight);
            PositionNearBottomRight();
        }
        finally
        {
            isFittingHeight = false;
        }
    }

    private void PositionNearBottomRight()
    {
        var width = ActualWidth > 0 ? ActualWidth : Width;
        var height = ActualHeight > 0 ? ActualHeight : Math.Max(1, DesiredSize.Height);
        Left = SystemParameters.WorkArea.Right - width - ScreenMargin;
        Top = Math.Max(
            SystemParameters.WorkArea.Top + ScreenMargin,
            SystemParameters.WorkArea.Bottom - height - ScreenMargin);
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        base.OnClosing(e);
        if (!canClose)
        {
            e.Cancel = true;
            Hide();
        }
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e) => await ((UsageViewModel)DataContext).RefreshAsync();

    private void OpenUsage_Click(object sender, RoutedEventArgs e) =>
        ExternalLinkLauncher.TryOpen("https://chatgpt.com/settings/usage?tab=overview");

    private void OpenReserveGuide_Click(object sender, RoutedEventArgs e) =>
        ExternalLinkLauncher.TryOpen("https://help-lb.openai.com/en/articles/20001499-luna-reserve-in-codex-and-chatgpt-work");

    private async void InstallUpdate_Click(object sender, RoutedEventArgs e)
    {
        if (await ((UsageViewModel)DataContext).PrepareAvailableUpdateAsync())
            ((App)System.Windows.Application.Current).ExitApplication();
    }

    private void OpenUpdate_Click(object sender, RoutedEventArgs e)
    {
        if (((UsageViewModel)DataContext).UpdateUrl is { } url)
        {
            ExternalLinkLauncher.TryOpen(url);
        }
    }

    private void Settings_Click(object sender, RoutedEventArgs e)
    {
        isShowingSettings = true;
        try
        {
            new SettingsWindow((UsageViewModel)DataContext) { Owner = this }.ShowDialog();
        }
        finally
        {
            isShowingSettings = false;
        }
    }

    private void Quit_Click(object sender, RoutedEventArgs e) => ((App)System.Windows.Application.Current).ExitApplication();
}
