using System.Globalization;
using Microsoft.Win32;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Forms = System.Windows.Forms;
using Point = System.Windows.Point;

namespace ChatGPTUsage.Windows;

public partial class UsageWidget : Window
{
    private const double ScreenMargin = 12;
    private const string PositionRegistryPath = @"Software\asetho\ChatGPT Usage";
    private const string LeftRegistryValue = "WidgetLeft";
    private const string TopRegistryValue = "WidgetTop";

    private readonly Action openUsage;
    private bool hasCustomPosition;
    private bool isDragging;
    private bool positionQueued;

    public UsageWidget(UsageViewModel usage, Action openUsage)
    {
        InitializeComponent();
        DataContext = usage;
        this.openUsage = openUsage;

        Loaded += (_, _) => QueuePositionUpdate();
        SizeChanged += (_, _) => QueuePositionUpdate();
        DpiChanged += (_, _) => QueuePositionUpdate();
        Closed += (_, _) => SystemParameters.StaticPropertyChanged -= SystemParameters_StaticPropertyChanged;
        SystemParameters.StaticPropertyChanged += SystemParameters_StaticPropertyChanged;
    }

    public void ShowNearClock()
    {
        Show();
        UpdateLayout();

        hasCustomPosition = TryLoadPosition(out var savedPosition);
        if (hasCustomPosition)
        {
            Left = savedPosition.X;
            Top = savedPosition.Y;
        }

        QueuePositionUpdate();
    }

    public void ResetPosition()
    {
        hasCustomPosition = false;
        ClearSavedPosition();
        QueuePositionUpdate();
    }

    private void Widget_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left)
        {
            return;
        }

        e.Handled = true;
        var startingPosition = new Point(Left, Top);

        isDragging = true;
        try
        {
            DragMove();
        }
        catch (InvalidOperationException)
        {
            return;
        }
        finally
        {
            isDragging = false;
        }

        var moved = Math.Abs(Left - startingPosition.X) >= 0.5
            || Math.Abs(Top - startingPosition.Y) >= 0.5;
        if (!moved)
        {
            openUsage();
            return;
        }

        hasCustomPosition = true;
        KeepCustomPositionOnScreen();
        SavePosition(new Point(Left, Top));
    }

    private void SystemParameters_StaticPropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(SystemParameters.WorkArea)
            or nameof(SystemParameters.VirtualScreenWidth)
            or nameof(SystemParameters.VirtualScreenHeight)
            or nameof(SystemParameters.VirtualScreenLeft)
            or nameof(SystemParameters.VirtualScreenTop))
        {
            QueuePositionUpdate();
        }
    }

    private void QueuePositionUpdate()
    {
        if (!IsLoaded || isDragging || positionQueued)
        {
            return;
        }

        positionQueued = true;
        _ = Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() =>
        {
            positionQueued = false;
            if (hasCustomPosition)
            {
                KeepCustomPositionOnScreen();
                SavePosition(new Point(Left, Top));
            }
            else
            {
                PositionNearClock();
            }
        }));
    }

    private void PositionNearClock()
    {
        var workArea = CurrentMonitorWorkArea();
        var width = ActualWidth > 0 ? ActualWidth : MinWidth;
        var height = ActualHeight > 0 ? ActualHeight : Height;
        Left = workArea.Right - width - ScreenMargin;
        Top = workArea.Bottom - height - ScreenMargin;
    }

    private void KeepCustomPositionOnScreen()
    {
        var workArea = CurrentMonitorWorkArea();
        var width = ActualWidth > 0 ? ActualWidth : MinWidth;
        var height = ActualHeight > 0 ? ActualHeight : Height;
        Left = Math.Clamp(Left, workArea.Left, Math.Max(workArea.Left, workArea.Right - width));
        Top = Math.Clamp(Top, workArea.Top, Math.Max(workArea.Top, workArea.Bottom - height));
    }

    private Rect CurrentMonitorWorkArea()
    {
        var handle = new WindowInteropHelper(this).Handle;
        var workingArea = Forms.Screen.FromHandle(handle).WorkingArea;
        var transform = PresentationSource.FromVisual(this)?.CompositionTarget?.TransformFromDevice
            ?? Matrix.Identity;
        var topLeft = transform.Transform(new Point(workingArea.Left, workingArea.Top));
        var bottomRight = transform.Transform(new Point(workingArea.Right, workingArea.Bottom));
        return new Rect(topLeft, bottomRight);
    }

    private static bool TryLoadPosition(out Point position)
    {
        position = default;
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(PositionRegistryPath);
            var leftText = key?.GetValue(LeftRegistryValue) as string;
            var topText = key?.GetValue(TopRegistryValue) as string;
            if (!double.TryParse(leftText, NumberStyles.Float, CultureInfo.InvariantCulture, out var left)
                || !double.TryParse(topText, NumberStyles.Float, CultureInfo.InvariantCulture, out var top)
                || !double.IsFinite(left)
                || !double.IsFinite(top))
            {
                return false;
            }

            position = new Point(left, top);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static void SavePosition(Point position)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(PositionRegistryPath);
            key.SetValue(LeftRegistryValue, position.X.ToString("R", CultureInfo.InvariantCulture));
            key.SetValue(TopRegistryValue, position.Y.ToString("R", CultureInfo.InvariantCulture));
        }
        catch
        {
            // Position persistence must never prevent the widget from running.
        }
    }

    private static void ClearSavedPosition()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(PositionRegistryPath, writable: true);
            key?.DeleteValue(LeftRegistryValue, throwOnMissingValue: false);
            key?.DeleteValue(TopRegistryValue, throwOnMissingValue: false);
        }
        catch
        {
            // Resetting the in-memory position still works if registry access is unavailable.
        }
    }
}
