using Forms = System.Windows.Forms;
using System.Threading;
using System.Windows;
using System.Windows.Threading;

namespace ChatGPTUsage.Windows;

public partial class App : System.Windows.Application
{
    private Forms.NotifyIcon? notifyIcon;
    private MainWindow? mainWindow;
    private UsageWidget? usageWidget;
    private DispatcherTimer? refreshTimer;
    private DispatcherTimer? updateCheckTimer;
    private Mutex? instanceMutex;

    protected override void OnStartup(StartupEventArgs e)
    {
        instanceMutex = new Mutex(initiallyOwned: true, name: @"Local\ChatGPTUsage.Windows", createdNew: out var isFirstInstance);
        if (!isFirstInstance)
        {
            instanceMutex.Dispose();
            instanceMutex = null;
            Shutdown();
            return;
        }

        base.OnStartup(e);

        var usage = new UsageViewModel();
        mainWindow = new MainWindow(usage);
        mainWindow.Show();
        mainWindow.Hide();
        usageWidget = new UsageWidget(usage, mainWindow.ShowNearBottomRight);
        usageWidget.ShowNearClock();

        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Show usage", null, (_, _) => Dispatcher.Invoke(mainWindow.ShowNearBottomRight));
        menu.Items.Add("Refresh", null, async (_, _) => await Dispatcher.InvokeAsync(usage.RefreshAsync));
        menu.Items.Add("Reset widget position", null, (_, _) => Dispatcher.Invoke(usageWidget.ResetPosition));
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Quit", null, (_, _) => Dispatcher.Invoke(ExitApplication));

        notifyIcon = new Forms.NotifyIcon
        {
            Icon = TrayIcon.Create(),
            Text = "ChatGPT Usage",
            Visible = true,
            ContextMenuStrip = menu
        };
        notifyIcon.MouseClick += (_, args) =>
        {
            if (args.Button == Forms.MouseButtons.Left)
            {
                Dispatcher.Invoke(mainWindow.ShowNearBottomRight);
            }
        };

        usage.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(UsageViewModel.TrayText) && notifyIcon is not null)
            {
                notifyIcon.Text = usage.TrayText;
            }
        };

        refreshTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMinutes(1)
        };
        refreshTimer.Tick += (_, _) => _ = usage.RefreshInBackgroundAsync();
        refreshTimer.Start();

        updateCheckTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromHours(12)
        };
        updateCheckTimer.Tick += (_, _) => _ = usage.CheckForUpdatesAsync();
        updateCheckTimer.Start();

        _ = usage.RefreshAsync();
        _ = usage.CheckForUpdatesAsync();
    }

    public void ExitApplication()
    {
        mainWindow?.AllowClose();
        usageWidget?.Close();
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        refreshTimer?.Stop();
        updateCheckTimer?.Stop();
        notifyIcon?.Dispose();
        instanceMutex?.ReleaseMutex();
        instanceMutex?.Dispose();
        base.OnExit(e);
    }
}
