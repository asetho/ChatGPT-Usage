using System.Diagnostics;
using System.Windows;

namespace ChatGPTUsage.Windows;

public partial class MainWindow : Window
{
    private const double ScreenMargin = 16;
    private bool canClose;
    private bool heightFitQueued;
    private bool isFittingHeight;
    private bool isShowingAbout;

    public MainWindow(UsageViewModel usage)
    {
        InitializeComponent();
        DataContext = usage;

        var availableHeight = Math.Max(1, SystemParameters.WorkArea.Height - (ScreenMargin * 2));
        MaxHeight = availableHeight;
    }

    public void ShowNearBottomRight()
    {
        _ = ((UsageViewModel)DataContext).RefreshAsync();
        Show();
        UpdateLayout();
        FitHeightToContent();
        PositionNearBottomRight();
        Activate();
    }

    public void AllowClose() => canClose = true;

    private void Window_Deactivated(object sender, EventArgs e)
    {
        if (!isShowingAbout) Hide();
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

    private void Disclosure_Changed(object sender, RoutedEventArgs e) => QueueHeightFit();

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

    private void OpenUsage_Click(object sender, RoutedEventArgs e) => OpenUrl("https://chatgpt.com/codex/settings/usage");

    private void OpenReserveGuide_Click(object sender, RoutedEventArgs e) =>
        OpenUrl("https://help-lb.openai.com/en/articles/20001499-luna-reserve-in-codex-and-chatgpt-work");

    private void OpenUpdate_Click(object sender, RoutedEventArgs e)
    {
        if (((UsageViewModel)DataContext).UpdateUrl is { } url)
        {
            OpenUrl(url);
        }
    }

    private void About_Click(object sender, RoutedEventArgs e)
    {
        isShowingAbout = true;
        try
        {
            new AboutWindow((UsageViewModel)DataContext) { Owner = this }.ShowDialog();
        }
        finally
        {
            isShowingAbout = false;
        }
    }

    private void Quit_Click(object sender, RoutedEventArgs e) => ((App)System.Windows.Application.Current).ExitApplication();

    private static void OpenUrl(string url) => Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
}
