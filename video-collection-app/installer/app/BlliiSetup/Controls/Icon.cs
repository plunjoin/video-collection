using System.Windows;
using System.Windows.Media;
using System.Windows.Shapes;

namespace Bllii.Setup.Controls;

public enum IconKind
{
    Arrow,
    Folder,
    Check,
    Close,
    Desktop,
    Shield,
    Heart,
    Sparkle,
    Info,
    Trash,
    Minus,
}

/// <summary>
/// 设计稿里的线性图标集（24×24 viewBox，圆头圆角描边）。
/// 用矢量而不是图片，任何 DPI 下都清晰。
/// </summary>
public sealed class Icon : Shape
{
    private static readonly Dictionary<IconKind, string> Source = new()
    {
        [IconKind.Arrow] = "M4,12 H20 M14,6 L20,12 L14,18",
        [IconKind.Folder] = "M3,8 A2,2 0 0 1 5,6 H10 L12,9 H19 A2,2 0 0 1 21,11 V18 A2,2 0 0 1 19,20 H5 A2,2 0 0 1 3,18 Z",
        [IconKind.Check] = "M5,12.6 L9.2,16.8 L19,6.4",
        [IconKind.Close] = "M6,6 L18,18 M18,6 L6,18",
        [IconKind.Desktop] = "M3,7 A3,3 0 0 1 6,4 H18 A3,3 0 0 1 21,7 V14 A3,3 0 0 1 18,17 H6 A3,3 0 0 1 3,14 Z M8,21 H16 M12,17 V21",
        [IconKind.Shield] = "M12,3 L20,6 V12 C20,17 12,21 12,21 C12,21 4,17 4,12 V6 Z M8,12 L11,15 L16,9",
        [IconKind.Heart] = "M12,20 C12,20 3,15 3,8 A5,5 0 0 1 12,5 A5,5 0 0 1 21,8 C21,15 12,20 12,20 Z",
        [IconKind.Sparkle] = "M12,3 L14.5,9.5 L21,12 L14.5,14.5 L12,21 L9.5,14.5 L3,12 L9.5,9.5 Z",
        [IconKind.Info] = "M12,3 A9,9 0 0 1 21,12 A9,9 0 0 1 12,21 A9,9 0 0 1 3,12 A9,9 0 0 1 12,3 Z M12,11 V17 M12,7.2 V7.5",
        [IconKind.Trash] = "M3,6 H21 M9,6 V3 H15 V6 M5,6 L6,21 H18 L19,6 M10,10 V17 M14,10 V17",
        [IconKind.Minus] = "M7,12 H17",
    };

    private static readonly Dictionary<IconKind, Geometry> GeometryCache = new();
    private Geometry _geometry = Geometry.Empty;

    public static readonly DependencyProperty KindProperty = DependencyProperty.Register(
        nameof(Kind), typeof(IconKind), typeof(Icon),
        new FrameworkPropertyMetadata(IconKind.Arrow, FrameworkPropertyMetadataOptions.AffectsRender, OnKindChanged));

    public IconKind Kind
    {
        get => (IconKind)GetValue(KindProperty);
        set => SetValue(KindProperty, value);
    }

    public Icon()
    {
        StrokeThickness = 2.1;
        StrokeStartLineCap = PenLineCap.Round;
        StrokeEndLineCap = PenLineCap.Round;
        StrokeLineJoin = PenLineJoin.Round;
        Stretch = Stretch.Uniform;
        Fill = null;
        _geometry = Resolve(IconKind.Arrow);
    }

    protected override Geometry DefiningGeometry => _geometry;

    private static void OnKindChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var icon = (Icon)d;
        icon._geometry = Resolve((IconKind)e.NewValue);
        icon.InvalidateVisual();
    }

    private static Geometry Resolve(IconKind kind)
    {
        if (GeometryCache.TryGetValue(kind, out var cached)) return cached;
        var geometry = Geometry.Parse(Source[kind]);
        geometry.Freeze();
        GeometryCache[kind] = geometry;
        return geometry;
    }
}
