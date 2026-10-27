using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Bllii.Setup.Controls;

/// <summary>
/// 带字距的文本。WPF 的 TextBlock 没有 letter-spacing，
/// 而设计稿里那些全大写的小标签（FOR WINDOWS / MORE STORIES, TOGETHER）全靠字距撑气质。
/// 实现方式：逐字排成一行 TextBlock，字距交给布局系统算，测量与渲染不会打架。
/// </summary>
public sealed class SpacedText : StackPanel
{
    public static readonly DependencyProperty TextProperty = DependencyProperty.Register(
        nameof(Text), typeof(string), typeof(SpacedText),
        new FrameworkPropertyMetadata(string.Empty, FrameworkPropertyMetadataOptions.AffectsMeasure, OnChanged));

    public static readonly DependencyProperty TrackingProperty = DependencyProperty.Register(
        nameof(Tracking), typeof(double), typeof(SpacedText),
        new FrameworkPropertyMetadata(1.0, FrameworkPropertyMetadataOptions.AffectsMeasure, OnChanged));

    public static readonly DependencyProperty ForegroundProperty = DependencyProperty.Register(
        nameof(Foreground), typeof(Brush), typeof(SpacedText),
        new FrameworkPropertyMetadata(Brushes.Black, FrameworkPropertyMetadataOptions.AffectsRender, OnChanged));

    public static readonly DependencyProperty FontFamilyProperty = DependencyProperty.Register(
        nameof(FontFamily), typeof(FontFamily), typeof(SpacedText),
        new FrameworkPropertyMetadata(new FontFamily("Segoe UI"), FrameworkPropertyMetadataOptions.AffectsMeasure, OnChanged));

    public static readonly DependencyProperty FontSizeProperty = DependencyProperty.Register(
        nameof(FontSize), typeof(double), typeof(SpacedText),
        new FrameworkPropertyMetadata(10.0, FrameworkPropertyMetadataOptions.AffectsMeasure, OnChanged));

    public static readonly DependencyProperty FontWeightProperty = DependencyProperty.Register(
        nameof(FontWeight), typeof(FontWeight), typeof(SpacedText),
        new FrameworkPropertyMetadata(FontWeights.Normal, FrameworkPropertyMetadataOptions.AffectsMeasure, OnChanged));

    public string Text
    {
        get => (string)GetValue(TextProperty);
        set => SetValue(TextProperty, value);
    }

    public double Tracking
    {
        get => (double)GetValue(TrackingProperty);
        set => SetValue(TrackingProperty, value);
    }

    public Brush Foreground
    {
        get => (Brush)GetValue(ForegroundProperty);
        set => SetValue(ForegroundProperty, value);
    }

    public FontFamily FontFamily
    {
        get => (FontFamily)GetValue(FontFamilyProperty);
        set => SetValue(FontFamilyProperty, value);
    }

    public double FontSize
    {
        get => (double)GetValue(FontSizeProperty);
        set => SetValue(FontSizeProperty, value);
    }

    public FontWeight FontWeight
    {
        get => (FontWeight)GetValue(FontWeightProperty);
        set => SetValue(FontWeightProperty, value);
    }

    public SpacedText()
    {
        Orientation = Orientation.Horizontal;
        SnapsToDevicePixels = true;
    }

    private static void OnChanged(DependencyObject d, DependencyPropertyChangedEventArgs e) => ((SpacedText)d).Rebuild();

    private void Rebuild()
    {
        Children.Clear();
        if (string.IsNullOrEmpty(Text)) return;

        var characters = Text.ToCharArray();
        for (var index = 0; index < characters.Length; index++)
        {
            var character = characters[index] == ' ' ? '\u00A0' : characters[index];
            Children.Add(new TextBlock
            {
                Text = character.ToString(),
                FontFamily = FontFamily,
                FontSize = FontSize,
                FontWeight = FontWeight,
                Foreground = Foreground,
                Margin = new Thickness(0, 0, index == characters.Length - 1 ? 0 : Tracking, 0),
            });
        }
    }
}
