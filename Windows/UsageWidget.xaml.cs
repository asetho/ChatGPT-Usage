using System.Globalization;
using System.Runtime.InteropServices;
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
    private const uint SetWindowPosFlags = 0x0001 | 0x0004 | 0x0010;

    private readonly Action openUsage;
    private Point? clickStartPosition;
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
            hasCustomPosition = RestorePosition(savedPosition);
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
        clickStartPosition = e.GetPosition(this);
        _ = Mouse.Capture(this);
    }

    private void Widget_MouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (clickStartPosition is not { } startingPosition
            || e.LeftButton != MouseButtonState.Pressed)
        {
            return;
        }

        var currentPosition = e.GetPosition(this);
        if (Math.Abs(currentPosition.X - startingPosition.X) < SystemParameters.MinimumHorizontalDragDistance
            && Math.Abs(currentPosition.Y - startingPosition.Y) < SystemParameters.MinimumVerticalDragDistance)
        {
            return;
        }

        clickStartPosition = null;
        if (IsMouseCaptured)
        {
            ReleaseMouseCapture();
        }

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

        hasCustomPosition = true;
        KeepCustomPositionOnScreen();
        SaveCurrentPosition();
    }

    private void Widget_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left)
        {
            return;
        }

        e.Handled = true;
        var shouldOpenUsage = clickStartPosition is not null;
        clickStartPosition = null;
        if (IsMouseCaptured)
        {
            ReleaseMouseCapture();
        }

        if (shouldOpenUsage)
        {
            openUsage();
        }
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
                SaveCurrentPosition();
            }
            else
            {
                PositionNearClock();
            }
        }));
    }

    private void PositionNearClock()
    {
        MoveToPrimaryMonitor();

        var workArea = CurrentMonitorWorkArea();
        var width = ActualWidth > 0 ? ActualWidth : MinWidth;
        var height = ActualHeight > 0 ? ActualHeight : Height;
        Left = workArea.Right - width - ScreenMargin;
        Top = workArea.Bottom - height - ScreenMargin;
    }

    private void MoveToPrimaryMonitor()
    {
        var primaryScreen = Forms.Screen.PrimaryScreen;
        var handle = new WindowInteropHelper(this).Handle;
        if (primaryScreen is null
            || handle == IntPtr.Zero
            || string.Equals(
                Forms.Screen.FromHandle(handle).DeviceName,
                primaryScreen.DeviceName,
                StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var workArea = primaryScreen.WorkingArea;
        _ = RestorePosition(new Point(
            workArea.Left + (workArea.Width / 2.0),
            workArea.Top + (workArea.Height / 2.0)));
        UpdateLayout();
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

    private bool RestorePosition(Point screenPosition)
    {
        var handle = new WindowInteropHelper(this).Handle;
        return handle != IntPtr.Zero
            && SetWindowPos(
                handle,
                IntPtr.Zero,
                (int)Math.Round(screenPosition.X),
                (int)Math.Round(screenPosition.Y),
                0,
                0,
                SetWindowPosFlags);
    }

    private void SaveCurrentPosition()
    {
        try
        {
            SavePosition(PointToScreen(new Point(0, 0)));
        }
        catch (InvalidOperationException)
        {
            // The window can disappear while a queued position update is running.
        }
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

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int x,
        int y,
        int cx,
        int cy,
        uint flags);
}
