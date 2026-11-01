/// 自研主题层:配色常量、明暗模式与 [Theme] 继承作用域。
///
/// 不依赖任何 Flutter 自带组件,只用框架底层(InheritedWidget 等)与绘制层
/// 类型。字段面按全库真实用点裁剪:
/// `Theme.of` → brightness / colorScheme.primary|error / textTheme.* /
/// iconTheme / appBarTheme.iconTheme / scaffoldBackgroundColor / dividerColor。
import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' as fw;

import 'fonts.dart';
import 'inputs.dart';

/// 主题模式(自研枚举,替代 material 的 ThemeMode)。
enum ThemeMode { light, dark, system }

/// 常用色值常量(替代 material 的 Colors,字段按用点覆盖)。
abstract final class Colors {
  static const Color transparent = Color(0x00000000);
  static const Color black = Color(0xFF000000);
  static const Color black87 = Color(0xDD000000);
  static const Color black54 = Color(0x8A000000);
  static const Color black45 = Color(0x73000000);
  static const Color black38 = Color(0x61000000);
  static const Color black26 = Color(0x42000000);
  static const Color black12 = Color(0x1F000000);
  static const Color white = Color(0xFFFFFFFF);
  static const Color white70 = Color(0xB3FFFFFF);
  static const Color white60 = Color(0x99FFFFFF);
  static const Color white54 = Color(0x8AFFFFFF);
  static const Color white38 = Color(0x62FFFFFF);
  static const Color white30 = Color(0x4DFFFFFF);
  static const Color white24 = Color(0x3DFFFFFF);
  static const Color white12 = Color(0x1FFFFFFF);
  static const Color white10 = Color(0x1AFFFFFF);

  static const Color red = Color(0xFFF44336);
  static const Color redAccent = Color(0xFFFF5252);
  static const Color orange = Color(0xFFFF9800);
  static const Color orangeAccent = Color(0xFFFFAB40);
  static const Color amber = Color(0xFFFFC107);
  static const Color amberAccent = Color(0xFFFFD740);
  static const Color yellow = Color(0xFFFFEB3B);
  static const Color yellowAccent = Color(0xFFFFEA00);
  static const Color lime = Color(0xFFCDDC39);
  static const Color limeAccent = Color(0xFFEEFF41);
  static const Color green = Color(0xFF4CAF50);
  static const Color greenAccent = Color(0xFF69F0AE);
  static const Color lightGreen = Color(0xFF8BC34A);
  static const Color teal = Color(0xFF009688);
  static const Color tealAccent = Color(0xFF64FFDA);
  static const Color cyan = Color(0xFF00BCD4);
  static const Color cyanAccent = Color(0xFF18FFFF);
  static const Color lightBlue = Color(0xFF03A9F4);
  static const Color lightBlueAccent = Color(0xFF40C4FF);
  static const Color blue = Color(0xFF2196F3);
  static const Color blueAccent = Color(0xFF448AFF);
  static const Color indigo = Color(0xFF3F51B5);
  static const Color indigoAccent = Color(0xFF536DFE);
  static const Color purple = Color(0xFF9C27B0);
  static const Color purpleAccent = Color(0xFFE040FB);
  static const Color deepPurple = Color(0xFF673AB7);
  static const Color deepPurpleAccent = Color(0xFF7C4DFF);
  static const Color pink = Color(0xFFE91E63);
  static const Color pinkAccent = Color(0xFFFF4081);
  static const Color brown = Color(0xFF795548);
  static const Color blueGrey = Color(0xFF607D8B);

  /// 灰色梯度(替代 material 的 Colors.grey.shadeXXX)。
  static const GreySwatch grey = GreySwatch();
}

/// 单色系梯度色板(grey/red/….shadeXXX 的载体)。
class GreySwatch {
  const GreySwatch();

  static const Color shade50 = Color(0xFFFAFAFA);
  static const Color shade100 = Color(0xFFF5F5F5);
  static const Color shade200 = Color(0xFFEEEEEE);
  static const Color shade300 = Color(0xFFE0E0E0);
  static const Color shade350 = Color(0xFFD6D6D6);
  static const Color shade400 = Color(0xFFBDBDBD);
  static const Color shade450 = Color(0xFFA9A9A9);
  static const Color shade500 = Color(0xFF9E9E9E);
  static const Color shade600 = Color(0xFF757575);
  static const Color shade700 = Color(0xFF616161);
  static const Color shade800 = Color(0xFF424242);
  static const Color shade850 = Color(0xFF303030);
  static const Color shade900 = Color(0xFF212121);
}

/// 文本样式集合(自研,字段面与用点对齐)。
class TextTheme {
  final TextStyle? displayLarge;
  final TextStyle? displayMedium;
  final TextStyle? displaySmall;
  final TextStyle? headlineLarge;
  final TextStyle? headlineMedium;
  final TextStyle? headlineSmall;
  final TextStyle? titleLarge;
  final TextStyle? titleMedium;
  final TextStyle? titleSmall;
  final TextStyle? bodyLarge;
  final TextStyle? bodyMedium;
  final TextStyle? bodySmall;
  final TextStyle? labelLarge;
  final TextStyle? labelMedium;
  final TextStyle? labelSmall;

  const TextTheme({
    this.displayLarge,
    this.displayMedium,
    this.displaySmall,
    this.headlineLarge,
    this.headlineMedium,
    this.headlineSmall,
    this.titleLarge,
    this.titleMedium,
    this.titleSmall,
    this.bodyLarge,
    this.bodyMedium,
    this.bodySmall,
    this.labelLarge,
    this.labelMedium,
    this.labelSmall,
  });
}

/// 色彩方案(自研,字段面 = 全库用点:primary / error 等)。
class ColorScheme {
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final Color error;
  final Color onError;
  final Color surface;
  final Color onSurface;
  final Color outline;
  final Color surfaceTint;

  const ColorScheme({
    required this.primary,
    this.onPrimary = Colors.white,
    required this.secondary,
    this.onSecondary = Colors.white,
    required this.error,
    this.onError = Colors.white,
    required this.surface,
    required this.onSurface,
    this.outline = Colors.transparent,
    this.surfaceTint = Colors.transparent,
  });

  ColorScheme copyWith({
    Color? primary,
    Color? onPrimary,
    Color? secondary,
    Color? onSecondary,
    Color? error,
    Color? onError,
    Color? surface,
    Color? onSurface,
    Color? outline,
    Color? surfaceTint,
  }) {
    return ColorScheme(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      secondary: secondary ?? this.secondary,
      onSecondary: onSecondary ?? this.onSecondary,
      error: error ?? this.error,
      onError: onError ?? this.onError,
      surface: surface ?? this.surface,
      onSurface: onSurface ?? this.onSurface,
      outline: outline ?? this.outline,
      surfaceTint: surfaceTint ?? this.surfaceTint,
    );
  }
}

/// 图标默认颜色/尺寸(继承作用域)。
class IconThemeData {
  final Color? color;
  final double? size;
  final double? opacity;

  const IconThemeData({this.color, this.size, this.opacity});

  IconThemeData copyWith({Color? color, double? size, double? opacity}) {
    return IconThemeData(
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is IconThemeData &&
      other.color == color &&
      other.size == size &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(color, size, opacity);
}

/// 图标默认样式继承作用域(`IconTheme.of(context)`)。
class IconTheme extends fw.InheritedWidget {
  final IconThemeData data;

  const IconTheme({fw.Key? key, required this.data, required fw.Widget child})
      : super(key: key, child: child);

  static IconThemeData of(fw.BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<IconTheme>();
    return scope?.data ?? const IconThemeData();
  }

  @override
  bool updateShouldNotify(IconTheme oldWidget) => data != oldWidget.data;
}

/// 页头配置(自研,字段面 = appBarTheme.iconTheme / titleTextStyle)。
class AppBarTheme {
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? elevation;
  final IconThemeData? iconTheme;
  final TextStyle? titleTextStyle;

  const AppBarTheme({
    this.backgroundColor,
    this.foregroundColor,
    this.elevation,
    this.iconTheme,
    this.titleTextStyle,
  });
}

/// 输入框默认装饰(自研;类型本体在 inputs.dart)。
class InputDecorationTheme {
  final bool filled;
  final Color? fillColor;
  final InputBorder? border;
  final InputBorder? enabledBorder;
  final InputBorder? focusedBorder;
  final InputBorder? errorBorder;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? labelStyle;
  final TextStyle? hintStyle;
  final TextStyle? floatingLabelStyle;
  final TextStyle? helperStyle;
  final TextStyle? errorStyle;
  final Color? prefixIconColor;
  final Color? suffixIconColor;
  final bool isDense;

  const InputDecorationTheme({
    this.filled = false,
    this.fillColor,
    this.border,
    this.enabledBorder,
    this.focusedBorder,
    this.errorBorder,
    this.contentPadding,
    this.labelStyle,
    this.hintStyle,
    this.floatingLabelStyle,
    this.helperStyle,
    this.errorStyle,
    this.prefixIconColor,
    this.suffixIconColor,
    this.isDense = false,
  });
}

/// 滑杆视觉配置(自研;滑杆形状接口也在本文件)。
class SliderThemeData {
  final double trackHeight;
  final Color? activeTrackColor;
  final Color? inactiveTrackColor;
  final Color? disabledActiveTrackColor;
  final Color? disabledInactiveTrackColor;
  final Color? thumbColor;
  final Color? disabledThumbColor;
  final Color? overlayColor;
  final Color? valueIndicatorColor;
  final SliderTrackShape? trackShape;
  final SliderThumbShape? thumbShape;
  final SliderOverlayShape? overlayShape;

  const SliderThemeData({
    this.trackHeight = 4,
    this.activeTrackColor,
    this.inactiveTrackColor,
    this.disabledActiveTrackColor,
    this.disabledInactiveTrackColor,
    this.thumbColor,
    this.disabledThumbColor,
    this.overlayColor,
    this.valueIndicatorColor,
    this.trackShape,
    this.thumbShape,
    this.overlayShape,
  });

  SliderThemeData copyWith({
    double? trackHeight,
    Color? activeTrackColor,
    Color? inactiveTrackColor,
    Color? disabledActiveTrackColor,
    Color? disabledInactiveTrackColor,
    Color? thumbColor,
    Color? disabledThumbColor,
    Color? overlayColor,
    Color? valueIndicatorColor,
    SliderTrackShape? trackShape,
    SliderThumbShape? thumbShape,
    SliderOverlayShape? overlayShape,
  }) {
    return SliderThemeData(
      trackHeight: trackHeight ?? this.trackHeight,
      activeTrackColor: activeTrackColor ?? this.activeTrackColor,
      inactiveTrackColor: inactiveTrackColor ?? this.inactiveTrackColor,
      disabledActiveTrackColor:
          disabledActiveTrackColor ?? this.disabledActiveTrackColor,
      disabledInactiveTrackColor:
          disabledInactiveTrackColor ?? this.disabledInactiveTrackColor,
      thumbColor: thumbColor ?? this.thumbColor,
      disabledThumbColor: disabledThumbColor ?? this.disabledThumbColor,
      overlayColor: overlayColor ?? this.overlayColor,
      valueIndicatorColor: valueIndicatorColor ?? this.valueIndicatorColor,
      trackShape: trackShape ?? this.trackShape,
      thumbShape: thumbShape ?? this.thumbShape,
      overlayShape: overlayShape ?? this.overlayShape,
    );
  }
}

/// 滑杆轨道形状接口(自研;实现类按此协议绘制整条轨道)。
abstract class SliderTrackShape {
  const SliderTrackShape();

  /// 返回轨道在可用宽度内实际希望占据的长度。
  double getPreferredLength(double maxWidth, double trackHeight) => maxWidth;

  /// 绘制轨道。rect 为整条滑杆的可用区域。
  void paint(
    Canvas canvas,
    Rect rect, {
    required double value,
    required double min,
    required double max,
    required bool enabled,
    required SliderThemeData theme,
    required Offset thumbCenter,
    double? bufferValue,
  });
}

/// 滑杆拇指形状接口。
abstract class SliderThumbShape {
  const SliderThumbShape();

  Size getPreferredSize(bool isEnabled) => const Size.square(12);

  void paint(
    Canvas canvas,
    Offset center, {
    required bool enabled,
    required SliderThemeData theme,
  });
}

/// 滑杆按压/悬停水波形状接口。
abstract class SliderOverlayShape {
  const SliderOverlayShape();

  Size getPreferredSize(bool isEnabled) => const Size.square(24);

  void paint(
    Canvas canvas,
    Offset center, {
    required bool enabled,
    required SliderThemeData theme,
    required double value,
  });
}

/// 圆形拇指(默认形状,与原 M3 视觉一致)。
class RoundSliderThumbShape extends SliderThumbShape {
  final double enabledThumbRadius;
  final double disabledThumbRadius;
  final double elevation;

  const RoundSliderThumbShape({
    this.enabledThumbRadius = 10,
    this.disabledThumbRadius = 8,
    this.elevation = 1,
  });

  @override
  Size getPreferredSize(bool isEnabled) =>
      Size.fromRadius(isEnabled ? enabledThumbRadius : disabledThumbRadius);

  @override
  void paint(
    Canvas canvas,
    Offset center, {
    required bool enabled,
    required SliderThemeData theme,
  }) {
    final radius = enabled ? enabledThumbRadius : disabledThumbRadius;
    final color = enabled
        ? (theme.thumbColor ?? Colors.white)
        : (theme.disabledThumbColor ?? Colors.white38);
    if (elevation > 0) {
      canvas.drawShadow(
        Path()
          ..addOval(Rect.fromCircle(center: center, radius: radius)),
        Colors.black26,
        elevation,
        true,
      );
    }
    canvas.drawCircle(center, radius, Paint()..color = color);
  }
}

/// 圆形按压水波。
class RoundSliderOverlayShape extends SliderOverlayShape {
  final double overlayRadius;

  const RoundSliderOverlayShape({this.overlayRadius = 24});

  @override
  Size getPreferredSize(bool isEnabled) =>
      Size.fromRadius(isEnabled ? overlayRadius : 0);

  @override
  void paint(
    Canvas canvas,
    Offset center, {
    required bool enabled,
    required SliderThemeData theme,
    required double value,
  }) {
    if (!enabled) return;
    final color = theme.overlayColor;
    if (color == null || color.a == 0) return;
    canvas.drawCircle(center, overlayRadius, Paint()..color = color);
  }
}

/// 圆角矩形轨道(默认形状)。
class RoundedRectSliderTrackShape extends SliderTrackShape {
  const RoundedRectSliderTrackShape();

  @override
  double getPreferredLength(double maxWidth, double trackHeight) => maxWidth;

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    required double value,
    required double min,
    required double max,
    required bool enabled,
    required SliderThemeData theme,
    required Offset thumbCenter,
    double? bufferValue,
  }) {
    final h = theme.trackHeight;
    final trackRect = Rect.fromLTWH(
      rect.left,
      rect.center.dy - h / 2,
      rect.width,
      h,
    );
    final radius = Radius.circular(h / 2);
    final rrect = RRect.fromRectAndRadius(trackRect, radius);

    final inactive = enabled
        ? (theme.inactiveTrackColor ?? Colors.black26)
        : (theme.disabledInactiveTrackColor ?? Colors.black12);
    canvas.drawRRect(rrect, Paint()..color = inactive);

    if (value > min) {
      final activeRight = (thumbCenter.dx - trackRect.left)
          .clamp(0.0, trackRect.width);
      if (activeRight > 0) {
        final activeRect = Rect.fromLTWH(
          trackRect.left,
          trackRect.top,
          activeRight,
          h,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(activeRect, radius),
          Paint()
            ..color = enabled
                ? (theme.activeTrackColor ?? Colors.black87)
                : (theme.disabledActiveTrackColor ?? Colors.black12),
        );
      }
    }
  }
}

/// 主题数据(自研;字段面 = 全库真实用点)。
class ThemeData {
  final Brightness brightness;
  final String? fontFamily;
  final List<String>? fontFamilyFallback;
  final Color scaffoldBackgroundColor;
  final Color primaryColor;
  final Color dividerColor;
  final Color hoverColor;
  final Color highlightColor;
  final Color splashColor;
  final Color disabledColor;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final IconThemeData iconTheme;
  final AppBarTheme appBarTheme;
  final InputDecorationTheme inputDecorationTheme;
  final SliderThemeData sliderTheme;

  const ThemeData({
    this.brightness = Brightness.light,
    this.fontFamily,
    this.fontFamilyFallback,
    Color? scaffoldBackgroundColor,
    Color? primaryColor,
    Color? dividerColor,
    Color? hoverColor,
    Color? highlightColor,
    Color? splashColor,
    this.disabledColor = const Color(0x61000000),
    ColorScheme? colorScheme,
    TextTheme? textTheme,
    IconThemeData? iconTheme,
    AppBarTheme? appBarTheme,
    InputDecorationTheme? inputDecorationTheme,
    SliderThemeData? sliderTheme,
  })  : scaffoldBackgroundColor =
            scaffoldBackgroundColor ?? const Color(0xFFF9FAFF),
        primaryColor = primaryColor ?? const Color(0xFF597BEA),
        dividerColor = dividerColor ?? const Color(0xFFE9EDFA),
        hoverColor = hoverColor ?? const Color(0x0D9A83FF),
        highlightColor = highlightColor ?? Colors.transparent,
        splashColor = splashColor ?? const Color(0x0A000000),
        colorScheme = colorScheme ?? const ColorScheme(primary: Color(0xFF597BEA), secondary: Color(0xFF597BEA), error: Color(0xFFFF5252), surface: Colors.white, onSurface: Color(0xFF353B58)),
        textTheme = textTheme ?? const TextTheme(),
        iconTheme = iconTheme ?? const IconThemeData(),
        appBarTheme = appBarTheme ?? const AppBarTheme(),
        inputDecorationTheme =
            inputDecorationTheme ?? const InputDecorationTheme(),
        sliderTheme = sliderTheme ?? const SliderThemeData();

  ThemeData copyWith({
    Brightness? brightness,
    String? fontFamily,
    List<String>? fontFamilyFallback,
    Color? scaffoldBackgroundColor,
    Color? primaryColor,
    Color? dividerColor,
    Color? hoverColor,
    Color? highlightColor,
    Color? splashColor,
    Color? disabledColor,
    ColorScheme? colorScheme,
    TextTheme? textTheme,
    IconThemeData? iconTheme,
    AppBarTheme? appBarTheme,
    InputDecorationTheme? inputDecorationTheme,
    SliderThemeData? sliderTheme,
  }) {
    return ThemeData(
      brightness: brightness ?? this.brightness,
      fontFamily: fontFamily ?? this.fontFamily,
      fontFamilyFallback: fontFamilyFallback ?? this.fontFamilyFallback,
      scaffoldBackgroundColor:
          scaffoldBackgroundColor ?? this.scaffoldBackgroundColor,
      primaryColor: primaryColor ?? this.primaryColor,
      dividerColor: dividerColor ?? this.dividerColor,
      hoverColor: hoverColor ?? this.hoverColor,
      highlightColor: highlightColor ?? this.highlightColor,
      splashColor: splashColor ?? this.splashColor,
      disabledColor: disabledColor ?? this.disabledColor,
      colorScheme: colorScheme ?? this.colorScheme,
      textTheme: textTheme ?? this.textTheme,
      iconTheme: iconTheme ?? this.iconTheme,
      appBarTheme: appBarTheme ?? this.appBarTheme,
      inputDecorationTheme:
          inputDecorationTheme ?? this.inputDecorationTheme,
      sliderTheme: sliderTheme ?? this.sliderTheme,
    );
  }
}

/// 主题继承作用域(`Theme.of(context)`)。
class Theme extends fw.InheritedWidget {
  final ThemeData data;

  const Theme({fw.Key? key, required this.data, required fw.Widget child})
      : super(key: key, child: child);

  static ThemeData of(fw.BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<Theme>();
    return scope?.data ?? const ThemeData();
  }

  /// 向上查找最近的主题而不建立依赖(只读场景)。
  static ThemeData? maybeOf(fw.BuildContext context) {
    return context.getInheritedWidgetOfExactType<Theme>()?.data;
  }

  @override
  bool updateShouldNotify(Theme oldWidget) => data != oldWidget.data;
}

/// 滑杆主题继承作用域(`SliderTheme.of(context)`)。
class SliderTheme extends fw.InheritedWidget {
  final SliderThemeData data;

  const SliderTheme({
    fw.Key? key,
    required this.data,
    required fw.Widget child,
  }) : super(key: key, child: child);

  static SliderThemeData of(fw.BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SliderTheme>();
    return scope?.data ?? const SliderThemeData();
  }

  @override
  bool updateShouldNotify(SliderTheme oldWidget) => data != oldWidget.data;
}

/// 构建一套完整的自研主题(明暗 + 强调色),视觉与原 AppTheme 一一对应。
ThemeData buildAppTheme(Brightness brightness, Color accent) {
  final dark = brightness == Brightness.dark;
  final ink = dark ? const Color(0xFFF9FAFF) : const Color(0xFF353B58);
  final muted = dark ? const Color(0xFF94A3B8) : const Color(0xFF7D88AA);
  final surface = dark ? const Color(0xFF1E293B) : Colors.white;
  final canvas = dark ? const Color(0xFF0F172A) : const Color(0xFFF9FAFF);
  final line = dark ? const Color(0xFF334155) : const Color(0xFFE9EDFA);
  final fill = dark ? const Color(0xFF243049) : const Color(0xFFF4F6FE);

  TextStyle ts({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: AppFonts.family,
        fontFamilyFallback: AppFonts.fallback,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? ink,
        height: height,
        letterSpacing: letterSpacing,
      );

  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(15),
    borderSide: BorderSide(color: line),
  );

  return ThemeData(
    brightness: brightness,
    fontFamily: AppFonts.family,
    fontFamilyFallback: AppFonts.fallback,
    scaffoldBackgroundColor: canvas,
    primaryColor: accent,
    dividerColor: line,
    hoverColor: const Color(0xFF9A83FF).withValues(alpha: .05),
    highlightColor: Colors.transparent,
    colorScheme: ColorScheme(
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent,
      error: const Color(0xFFC64C91),
      surface: surface,
      onSurface: ink,
      outline: line,
      surfaceTint: Colors.transparent,
    ),
    textTheme: TextTheme(
      titleLarge: ts(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: .4),
      titleMedium: ts(fontSize: 15, fontWeight: FontWeight.w600),
      titleSmall: ts(fontSize: 13, fontWeight: FontWeight.w600),
      bodyLarge: ts(fontSize: 14, height: 1.6),
      bodyMedium: ts(fontSize: 13, height: 1.5),
      bodySmall: ts(fontSize: 11, height: 1.6, color: muted),
      labelLarge: ts(fontSize: 12, fontWeight: FontWeight.w600),
      labelMedium: ts(fontSize: 11, fontWeight: FontWeight.w600),
      labelSmall: ts(fontSize: 10, fontWeight: FontWeight.w600),
    ),
    iconTheme: IconThemeData(color: muted, size: 21),
    appBarTheme: AppBarTheme(
      backgroundColor: canvas,
      elevation: 0,
      iconTheme: IconThemeData(color: muted, size: 21),
      titleTextStyle: ts(fontSize: 19, fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fill,
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: BorderSide(
          color: const Color(0xFF9A83FF).withValues(alpha: .6),
          width: 1.2,
        ),
      ),
      errorBorder: outline.copyWith(
        borderSide: const BorderSide(color: Color(0xFFFF89C7)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: ts(fontSize: 12, color: muted),
      hintStyle: ts(fontSize: 12, color: muted),
      floatingLabelStyle: ts(fontSize: 12, color: const Color(0xFF9A83FF)),
      prefixIconColor: muted,
      suffixIconColor: muted,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: const Color(0xFF9A83FF),
      inactiveTrackColor: line,
      thumbColor: const Color(0xFFFF89C7),
      trackHeight: 3,
      overlayColor: const Color(0xFF9A83FF).withValues(alpha: .1),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      trackShape: const RoundedRectSliderTrackShape(),
      overlayShape: const RoundSliderOverlayShape(),
    ),
  );
}
