using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Point = System.Windows.Point;
using Color = System.Windows.Media.Color;
using Brushes = System.Windows.Media.Brushes;

namespace ChatGPTUsage.Windows;

public sealed class UpdateCheckIcon : Grid
{
    public static readonly DependencyProperty IsCheckingProperty = DependencyProperty.Register(
        nameof(IsChecking), typeof(bool), typeof(UpdateCheckIcon), new PropertyMetadata(false, StateChanged));
    public static readonly DependencyProperty IsUpToDateProperty = DependencyProperty.Register(
        nameof(IsUpToDate), typeof(bool), typeof(UpdateCheckIcon), new PropertyMetadata(false, StateChanged));

    public bool IsChecking { get => (bool)GetValue(IsCheckingProperty); set => SetValue(IsCheckingProperty, value); }
    public bool IsUpToDate { get => (bool)GetValue(IsUpToDateProperty); set => SetValue(IsUpToDateProperty, value); }

    private readonly RotateTransform rotation = new();
    private readonly SymbolIcon refresh = new() { Kind = SymbolKind.Refresh, Width = 16, Height = 16 };
    private readonly SymbolIcon check = new()
    {
        Kind = SymbolKind.Check, Foreground = Brushes.Black, Width = 12, Height = 12,
        HorizontalAlignment = System.Windows.HorizontalAlignment.Center,
        VerticalAlignment = System.Windows.VerticalAlignment.Center
    };
    private readonly RectangleGeometry checkReveal = new(new Rect(0, 0, 12, 12));
    private readonly Border confirmation;
    private bool wasConfirmed;

    public UpdateCheckIcon()
    {
        Width = Height = 16;
        IsHitTestVisible = false;
        refresh.Foreground = new SolidColorBrush(Color.FromRgb(230, 232, 238));
        refresh.RenderTransform = rotation;
        refresh.RenderTransformOrigin = new Point(0.5, 0.5);
        check.Clip = checkReveal;
        confirmation = new Border
        {
            Width = 14, Height = 14, CornerRadius = new CornerRadius(2.5),
            Background = new SolidColorBrush(Color.FromRgb(74, 222, 128)), Child = check
        };
        Children.Add(refresh);
        Children.Add(confirmation);
        Loaded += (_, _) => UpdateState(animateConfirmation: false);
        Unloaded += (_, _) => rotation.BeginAnimation(RotateTransform.AngleProperty, null);
        UpdateState(animateConfirmation: false);
    }

    private static void StateChanged(DependencyObject target, DependencyPropertyChangedEventArgs args) =>
        ((UpdateCheckIcon)target).UpdateState(animateConfirmation: true);

    private void UpdateState(bool animateConfirmation)
    {
        rotation.BeginAnimation(RotateTransform.AngleProperty, null);
        checkReveal.BeginAnimation(RectangleGeometry.RectProperty, null);
        rotation.Angle = 0;
        var confirmed = IsUpToDate && !IsChecking;
        var becameConfirmed = confirmed && !wasConfirmed;
        wasConfirmed = confirmed;
        refresh.Visibility = confirmed ? Visibility.Collapsed : Visibility.Visible;
        confirmation.Visibility = confirmed ? Visibility.Visible : Visibility.Collapsed;
        if (!IsLoaded || !SystemParameters.ClientAreaAnimation) return;
        if (IsChecking)
            rotation.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360, TimeSpan.FromSeconds(0.8)) { RepeatBehavior = RepeatBehavior.Forever });
        else if (becameConfirmed && animateConfirmation)
            checkReveal.BeginAnimation(RectangleGeometry.RectProperty, new RectAnimation(
                new Rect(0, 0, 0, 12), new Rect(0, 0, 12, 12), TimeSpan.FromSeconds(0.4)));
    }
}
