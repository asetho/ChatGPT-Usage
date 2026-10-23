using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Globalization;
using System.Xml.Linq;
using Control = System.Windows.Controls.Control;
using Point = System.Windows.Point;
using Pen = System.Windows.Media.Pen;

namespace ChatGPTUsage.Windows;

public enum SymbolKind { Gauge, Settings, Refresh, ExternalLink, Help, Warning, LimitReached, Download, ChevronDown, ChevronRight, Check, GitHub }

// Both apps consume the same bundled SVGs: Lucide plus our own usage gauge.
// No SVG runtime or font dependency is needed.
public sealed class SymbolIcon : Control
{
    public static readonly DependencyProperty KindProperty = DependencyProperty.Register(
        nameof(Kind), typeof(SymbolKind), typeof(SymbolIcon),
        new FrameworkPropertyMetadata(SymbolKind.Gauge, FrameworkPropertyMetadataOptions.AffectsRender));

    public SymbolKind Kind
    {
        get => (SymbolKind)GetValue(KindProperty);
        set => SetValue(KindProperty, value);
    }

    private static readonly Dictionary<SymbolKind, Geometry> Icons = new();

    internal static Geometry GetGeometry(SymbolKind kind)
    {
        if (Icons.TryGetValue(kind, out var cached)) return cached;
        var name = kind switch
        {
            SymbolKind.Gauge => "usage-gauge", SymbolKind.Settings => "settings", SymbolKind.Refresh => "refresh-cw",
            SymbolKind.ExternalLink => "external-link", SymbolKind.Help => "circle-question-mark",
            SymbolKind.Warning => "triangle-alert", SymbolKind.LimitReached => "circle-alert",
            SymbolKind.Download => "circle-arrow-down", SymbolKind.ChevronDown => "chevron-down",
            SymbolKind.ChevronRight => "chevron-right", SymbolKind.Check => "check",
            SymbolKind.GitHub => "GitHubMark",
            _ => throw new ArgumentOutOfRangeException(nameof(kind))
        };
        using var stream = typeof(SymbolIcon).Assembly.GetManifestResourceStream($"Lucide.{name}.svg")
            ?? throw new InvalidOperationException($"Missing Lucide icon: {name}");
        var group = new GeometryGroup { FillRule = FillRule.Nonzero };
        foreach (var element in XDocument.Load(stream).Root!.Elements())
        {
            double Number(string attribute) => double.Parse(element.Attribute(attribute)!.Value, CultureInfo.InvariantCulture);
            group.Children.Add(element.Name.LocalName switch
            {
                "path" => Geometry.Parse(element.Attribute("d")!.Value),
                "circle" => new EllipseGeometry(new Point(Number("cx"), Number("cy")), Number("r"), Number("r")),
                "line" => new LineGeometry(new Point(Number("x1"), Number("y1")), new Point(Number("x2"), Number("y2"))),
                _ => throw new InvalidOperationException($"Unsupported element in bundled icon: {name}")
            });
        }
        group.Freeze();
        Icons.Add(kind, group);
        return group;
    }

    protected override void OnRender(DrawingContext drawing)
    {
        base.OnRender(drawing);
        const int units = 24;
        var scale = Math.Min(ActualWidth, ActualHeight) / units;
        drawing.PushTransform(new TranslateTransform((ActualWidth - units * scale) / 2, (ActualHeight - units * scale) / 2));
        drawing.PushTransform(new ScaleTransform(scale, scale));
        var pen = new Pen(Foreground, 2) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
        drawing.DrawGeometry(Kind == SymbolKind.GitHub ? Foreground : null,
            Kind == SymbolKind.GitHub ? null : pen, GetGeometry(Kind));
        drawing.Pop();
        drawing.Pop();
    }
}
