/// 自研控制组件族:[Switch]/[Slider]/[ListTile]/[Card]/[ChoiceChip]/
/// [CircleAvatar]/[Tooltip]/[Divider]/[CircularProgressIndicator]/
/// [LinearProgressIndicator]/[TabController]/[TabBarView]/[PageView]/
/// [PopupMenuButton]。
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Brightness;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show GestureTapCallback;
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' as fw;

import 'buttons.dart';
import 'container.dart';
import 'tooltip.dart';
import 'gestures.dart';
import 'layout.dart';
import 'overlay.dart';
import 'scroll.dart';
import 'text.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Switch
// ---------------------------------------------------------------------------

/// 开关(替代 material 的 Switch;自带平滑过渡)。
class Switch extends fw.StatelessWidget {
  final bool value;
  final fw.ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final Color? activeTrackColor;
  final Color? activeThumbColor;
  final Color? inactiveThumbColor;
  final Color? inactiveTrackColor;
  final MaterialTapTargetSize? materialTapTargetSize;
  final fw.FocusNode? focusNode;
  final bool autofocus;

  const Switch({
    fw.Key? key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.activeTrackColor,
    this.activeThumbColor,
    this.inactiveThumbColor,
    this.inactiveTrackColor,
    this.materialTapTargetSize,
    this.focusNode,
    this.autofocus = false,
  }) : super(key: key);

  const Switch.adaptive({
    fw.Key? key,
    required bool value,
    required fw.ValueChanged<bool>? onChanged,
    Color? activeColor,
    Color? activeTrackColor,
    Color? activeThumbColor,
    Color? inactiveThumbColor,
    Color? inactiveTrackColor,
    MaterialTapTargetSize? materialTapTargetSize,
    fw.FocusNode? focusNode,
    bool autofocus = false,
  }) : this(
          key: key,
          value: value,
          onChanged: onChanged,
          activeColor: activeColor,
          activeTrackColor: activeTrackColor,
          activeThumbColor: activeThumbColor,
          inactiveThumbColor: inactiveThumbColor,
          inactiveTrackColor: inactiveTrackColor,
          materialTapTargetSize: materialTapTargetSize,
          focusNode: focusNode,
          autofocus: autofocus,
        );

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onChanged != null;
    final trackActive = activeTrackColor ?? theme.colorScheme.primary;
    final trackInactive = inactiveTrackColor ??
        (theme.brightness == Brightness.dark
            ? const Color(0xFF334155)
            : const Color(0xFFE2E8F5));
    final thumbActive = activeThumbColor ?? activeColor ?? Colors.white;
    final thumbInactive = inactiveThumbColor ?? Colors.white;

    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        onHorizontalDragUpdate: enabled
            ? (details) {
                // 拖动切换:滑过中点即翻转
                final ro = context.findRenderObject();
                if (ro is RenderBox && ro.hasSize) {
                  final local = ro.globalToLocal(details.globalPosition);
                  if (value && local.dx < ro.size.width / 2) {
                    onChanged!(false);
                  } else if (!value &&
                      local.dx > ro.size.width / 2) {
                    onChanged!(true);
                  }
                }
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: TweenAnimationBuilder<double>(
            tween: fw.Tween<double>(begin: 0, end: value ? 1 : 0),
            duration: const Duration(milliseconds: 180),
            curve: fw.Curves.easeOutCubic,
            builder: (context, t, _) {
              return CustomPaint(
                size: const Size(46, 26),
                painter: _SwitchPainter(
                  progress: t,
                  trackActive: trackActive,
                  trackInactive: trackInactive,
                  thumbActive: thumbActive,
                  thumbInactive: thumbInactive,
                  enabled: enabled,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SwitchPainter extends CustomPainter {
  final double progress;
  final Color trackActive;
  final Color trackInactive;
  final Color thumbActive;
  final Color thumbInactive;
  final bool enabled;

  _SwitchPainter({
    required this.progress,
    required this.trackActive,
    required this.trackInactive,
    required this.thumbActive,
    required this.thumbInactive,
    required this.enabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackR = size.height / 2;
    final trackRect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(trackR));
    final track = Color.lerp(trackInactive, trackActive, progress)!;
    canvas.drawRRect(trackRect, Paint()..color = track);

    final thumbRadius = trackR - 3;
    final travel = size.width - size.height;
    final cx = trackR + travel * progress;
    final thumb = Color.lerp(thumbInactive, thumbActive, progress)!;
    canvas.drawCircle(Offset(cx, trackR), thumbRadius, Paint()..color = thumb);
    if (enabled) {
      canvas.drawCircle(
        Offset(cx, trackR),
        thumbRadius,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.06)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SwitchPainter old) =>
      old.progress != progress || old.trackActive != trackActive;
}

/// 开关 + 列表行组合。
class SwitchListTile extends fw.StatelessWidget {
  final bool value;
  final fw.ValueChanged<bool>? onChanged;
  final fw.Widget? title;
  final fw.Widget? subtitle;
  final EdgeInsetsGeometry? contentPadding;
  final Color? activeColor;
  final Color? activeTrackColor;
  final bool dense;

  const SwitchListTile({
    fw.Key? key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.contentPadding,
    this.activeColor,
    this.activeTrackColor,
    this.dense = false,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final titleColor = dark ? const Color(0xFFF9FAFF) : const Color(0xFF353B58);
    final subColor = dark ? const Color(0xFF94A3B8) : const Color(0xFF7D88AA);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChanged != null ? () => onChanged!(!value) : null,
      child: Padding(
        padding: contentPadding ?? EdgeInsets.zero,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    DefaultTextStyle(
                      style: TextStyle(
                        fontFamily: theme.fontFamily,
                        fontFamilyFallback: theme.fontFamilyFallback,
                        fontSize: dense ? 13 : 14,
                        fontWeight: FontWeight.w500,
                        color: titleColor,
                      ),
                      child: title!,
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    DefaultTextStyle(
                      style: TextStyle(
                        fontFamily: theme.fontFamily,
                        fontFamilyFallback: theme.fontFamilyFallback,
                        fontSize: 12,
                        color: subColor,
                      ),
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: activeColor,
              activeTrackColor: activeTrackColor,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slider
// ---------------------------------------------------------------------------

/// 滑杆(替代 material 的 Slider;支持 SliderTheme 与自定义轨道形状)。
class Slider extends fw.StatefulWidget {
  final double value;
  final fw.ValueChanged<double>? onChanged;
  final fw.ValueChanged<double>? onChangeStart;
  final fw.ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;
  final Color? activeColor;
  final Color? inactiveColor;
  final String? label;
  final fw.FocusNode? focusNode;

  const Slider({
    fw.Key? key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.activeColor,
    this.inactiveColor,
    this.label,
    this.focusNode,
  }) : super(key: key);

  @override
  fw.State<Slider> createState() => _SliderState();
}

class _SliderState extends fw.State<Slider> {
  void _updateValue(double localDx) {
    final ro = context.findRenderObject();
    final width = ro is RenderBox && ro.hasSize ? ro.size.width : 1.0;
    final ratio = (localDx / math.max(1, width)).clamp(0.0, 1.0);
    var v = widget.min + ratio * (widget.max - widget.min);
    if (widget.divisions != null && widget.divisions! > 1) {
      final step = (widget.max - widget.min) / widget.divisions!;
      final snapped =
          ((v - widget.min) / step).round() * step + widget.min;
      v = snapped.clamp(widget.min, widget.max) as double;
    }
    widget.onChanged?.call(v);
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final sliderTheme = SliderTheme.of(context);
    final effectiveTheme = sliderTheme.copyWith(
      activeTrackColor:
          widget.activeColor ?? sliderTheme.activeTrackColor,
      inactiveTrackColor:
          widget.inactiveColor ?? sliderTheme.inactiveTrackColor,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        widget.onChangeStart?.call(widget.value);
        _updateValue(details.localPosition.dx);
      },
      onTapUp: (_) => widget.onChangeEnd?.call(widget.value),
      onHorizontalDragStart: (details) {
        widget.onChangeStart?.call(widget.value);
        _updateValue(details.localPosition.dx);
      },
      onHorizontalDragUpdate: (details) =>
          _updateValue(details.localPosition.dx),
      onHorizontalDragEnd: (_) => widget.onChangeEnd?.call(widget.value),
      child: SizedBox(
        height: 32,
        child: CustomPaint(
          painter: _SliderPainter(
            value: widget.value,
            min: widget.min,
            max: widget.max,
            theme: effectiveTheme,
          ),
        ),
      ),
    );
  }
}

/// 简化版布局构建器(视口尺寸回调)。
class LayoutBuilderLite extends fw.StatelessWidget {
  final fw.Widget Function(fw.BuildContext, BoxConstraints) builder;

  const LayoutBuilderLite({fw.Key? key, required this.builder})
      : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    return fw.LayoutBuilder(builder: builder);
  }
}

class _SliderPainter extends CustomPainter {
  final double value;
  final double min;
  final double max;
  final SliderThemeData theme;

  _SliderPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackShape = theme.trackShape ?? const RoundedRectSliderTrackShape();
    final rect = Offset.zero & size;
    final thumbCenter = Offset(
      rect.left +
          ((value - min) / math.max(0.0001, max - min)) * rect.width,
      rect.center.dy,
    );
    final overlayShape = theme.overlayShape ?? const RoundSliderOverlayShape();
    overlayShape.paint(
      canvas,
      thumbCenter,
      enabled: true,
      theme: theme,
      value: value,
    );
    trackShape.paint(
      canvas,
      rect,
      value: value,
      min: min,
      max: max,
      enabled: true,
      theme: theme,
      thumbCenter: thumbCenter,
    );
    final thumbShape = theme.thumbShape ?? const RoundSliderThumbShape();
    thumbShape.paint(canvas, thumbCenter, enabled: true, theme: theme);
  }

  @override
  bool shouldRepaint(covariant _SliderPainter old) =>
      old.value != value || old.theme != theme;
}

// ---------------------------------------------------------------------------
// ListTile / Card
// ---------------------------------------------------------------------------

/// 列表行(替代 material 的 ListTile)。
class ListTile extends fw.StatelessWidget {
  final fw.Widget? leading;
  final fw.Widget? title;
  final fw.Widget? subtitle;
  final fw.Widget? trailing;
  final GestureTapCallback? onTap;
  final bool dense;
  final bool? isThreeLine;
  final EdgeInsetsGeometry? contentPadding;
  final bool selected;
  final ShapeBorder? shape;
  final Color? tileColor;
  final bool enabled;
  final Color? iconColor;
  final Color? textColor;

  const ListTile({
    fw.Key? key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.dense = false,
    this.isThreeLine,
    this.contentPadding,
    this.selected = false,
    this.shape,
    this.tileColor,
    this.enabled = true,
    this.iconColor,
    this.textColor,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final titleColor = textColor ??
        (dark ? const Color(0xFFF9FAFF) : const Color(0xFF353B58));
    final subColor = dark ? const Color(0xFF94A3B8) : const Color(0xFF7D88AA);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: contentPadding ??
            const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(
          color: tileColor,
          borderRadius: shape is RoundedRectangleBorder
              ? (shape as RoundedRectangleBorder).borderRadius
              : BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              IconTheme(
                data: IconThemeData(
                  color: iconColor ?? const Color(0xFF9A83FF),
                ),
                child: leading!,
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (title != null)
                    DefaultTextStyle(
                      style: TextStyle(
                        fontFamily: theme.fontFamily,
                        fontFamilyFallback: theme.fontFamilyFallback,
                        fontSize: dense ? 13 : 14,
                        fontWeight: FontWeight.w500,
                        color: selected
                            ? theme.colorScheme.primary
                            : titleColor,
                      ),
                      child: title!,
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    DefaultTextStyle(
                      style: TextStyle(
                        fontFamily: theme.fontFamily,
                        fontFamilyFallback: theme.fontFamilyFallback,
                        fontSize: 12,
                        color: subColor,
                      ),
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 卡片容器(替代 material 的 Card)。
class Card extends fw.StatelessWidget {
  final Color? color;
  final Color? shadowColor;
  final double? elevation;
  final ShapeBorder? shape;
  final EdgeInsetsGeometry? margin;
  final Clip clipBehavior;
  final fw.Widget? child;

  const Card({
    fw.Key? key,
    this.color,
    this.shadowColor,
    this.elevation,
    this.shape,
    this.margin,
    this.clipBehavior = Clip.none,
    this.child,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final line = theme.dividerColor;
    final borderRadius = shape is RoundedRectangleBorder
        ? (shape as RoundedRectangleBorder).borderRadius
        : BorderRadius.circular(18);
    final elev = elevation ?? 0;
    return Container(
      margin: margin ?? EdgeInsets.zero,
      decoration: BoxDecoration(
        color: color ?? (dark ? const Color(0xFF1E293B) : Colors.white),
        borderRadius: borderRadius,
        border: Border.all(color: line),
        boxShadow: elev > 0
            ? [
                BoxShadow(
                  color: shadowColor ?? const Color(0x14000000),
                  blurRadius: elev * 3,
                  offset: Offset(0, elev),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Chip
// ---------------------------------------------------------------------------

/// 通用标签片。
class Chip extends fw.StatelessWidget {
  final fw.Widget label;
  final fw.Widget? avatar;
  final Color? backgroundColor;
  final TextStyle? labelStyle;
  final BorderSide? side;
  final VoidCallback? onDeleted;
  final EdgeInsetsGeometry? padding;
  final OutlinedBorder? shape;

  const Chip({
    fw.Key? key,
    required this.label,
    this.avatar,
    this.backgroundColor,
    this.labelStyle,
    this.side,
    this.onDeleted,
    this.padding,
    this.shape,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor ??
            (dark ? const Color(0xFF222E43) : const Color(0xFFF4F7FF)),
        borderRadius: BorderRadius.circular(20),
        border: side != null
            ? Border.all(color: side!.color, width: side!.width)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (avatar != null) ...[
            avatar!,
            const SizedBox(width: 6),
          ],
          DefaultTextStyle(
            style: labelStyle ??
                TextStyle(
                  fontFamily: theme.fontFamily,
                  fontFamilyFallback: theme.fontFamilyFallback,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: dark
                      ? const Color(0xFFB9C2D8)
                      : const Color(0xFF55607E),
                ),
            child: label,
          ),
        ],
      ),
    );
  }
}

/// 单选标签片(替代 material 的 ChoiceChip)。
class ChoiceChip extends fw.StatelessWidget {
  final fw.Widget label;
  final fw.Widget? avatar;
  final bool selected;
  final fw.ValueChanged<bool>? onSelected;
  final Color? backgroundColor;
  final Color? selectedColor;
  final TextStyle? labelStyle;
  final BorderSide? side;
  final EdgeInsetsGeometry? padding;
  final OutlinedBorder? shape;
  final bool showCheckmark;
  final double? pressElevation;

  const ChoiceChip({
    fw.Key? key,
    required this.label,
    this.avatar,
    required this.selected,
    required this.onSelected,
    this.backgroundColor,
    this.selectedColor,
    this.labelStyle,
    this.side,
    this.padding,
    this.shape,
    this.showCheckmark = true,
    this.pressElevation,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final effectiveBg = selected
        ? (selectedColor ?? primary.withValues(alpha: dark ? .22 : .12))
        : (backgroundColor ??
            (dark ? const Color(0xFF222E43) : const Color(0xFFF4F7FF)));
    final effectiveSide = side ??
        (selected
            ? BorderSide(color: primary.withValues(alpha: .35))
            : BorderSide.none);
    final effectiveStyle = labelStyle ??
        TextStyle(
          fontFamily: theme.fontFamily,
          fontFamilyFallback: theme.fontFamilyFallback,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected
              ? primary
              : (dark
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF7D88AA)),
        );

    return InkWell(
      onTap: onSelected != null ? () => onSelected!(!selected) : null,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: padding ??
            const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
        decoration: BoxDecoration(
          color: effectiveBg,
          borderRadius: BorderRadius.circular(24),
          border: effectiveSide != BorderSide.none
              ? Border.all(color: effectiveSide.color, width: effectiveSide.width)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (avatar != null) ...[
              avatar!,
              const SizedBox(width: 7),
            ],
            DefaultTextStyle(
              style: effectiveStyle,
              child: label,
            ),
          ],
        ),
      ),
    );
  }
}

/// 圆形头像(替代 material 的 CircleAvatar)。
class CircleAvatar extends fw.StatelessWidget {
  final double? radius;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final fw.Widget? child;
  final fw.ImageProvider? backgroundImage;

  const CircleAvatar({
    fw.Key? key,
    this.radius,
    this.backgroundColor,
    this.foregroundColor,
    this.child,
    this.backgroundImage,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final r = radius ?? 20;
    final theme = Theme.of(context);
    return Container(
      width: r * 2,
      height: r * 2,
      decoration: BoxDecoration(
        color: backgroundColor ??
            theme.colorScheme.primary.withValues(alpha: .18),
        shape: BoxShape.circle,
        image: backgroundImage != null
            ? DecorationImage(image: backgroundImage!, fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: child != null
          ? DefaultTextStyle(
              style: TextStyle(
                fontFamily: theme.fontFamily,
                fontFamilyFallback: theme.fontFamilyFallback,
                fontSize: r * 0.7,
                fontWeight: FontWeight.w600,
                color: foregroundColor ?? theme.colorScheme.primary,
              ),
              child: child!,
            )
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Tooltip / Divider
// ---------------------------------------------------------------------------

/// 纵向分隔线。
class VerticalDivider extends fw.StatelessWidget {
  final double? width;
  final double? thickness;
  final double? indent;
  final double? endIndent;
  final Color? color;

  const VerticalDivider({
    fw.Key? key,
    this.width,
    this.thickness,
    this.indent,
    this.endIndent,
    this.color,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final w = width ?? 16;
    final t = thickness ?? 0.7;
    return SizedBox(
      width: w,
      child: Center(
        child: Container(
          width: t,
          margin: EdgeInsets.only(
            top: indent ?? 0,
            bottom: endIndent ?? 0,
          ),
          color: color ?? theme.dividerColor,
        ),
      ),
    );
  }
}

/// 分隔线(替代 material 的 Divider)。
class Divider extends fw.StatelessWidget {
  final double? height;
  final double? thickness;
  final double? indent;
  final double? endIndent;
  final Color? color;

  const Divider({
    fw.Key? key,
    this.height,
    this.thickness,
    this.indent,
    this.endIndent,
    this.color,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final h = height ?? 16;
    final t = thickness ?? 0.7;
    return SizedBox(
      height: h,
      child: Center(
        child: Container(
          height: t,
          margin: EdgeInsets.only(
            left: indent ?? 0,
            right: endIndent ?? 0,
          ),
          color: color ?? theme.dividerColor,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 进度指示
// ---------------------------------------------------------------------------

/// 圆形进度(替代 material 的 CircularProgressIndicator)。
class CircularProgressIndicator extends fw.StatefulWidget {
  final double? value;
  final double? strokeWidth;
  final Color? color;
  final Color? backgroundColor;
  final fw.Animation<Color?>? valueColor;

  const CircularProgressIndicator({
    fw.Key? key,
    this.value,
    this.strokeWidth,
    this.color,
    this.backgroundColor,
    this.valueColor,
  }) : super(key: key);

  @override
  fw.State<CircularProgressIndicator> createState() =>
      _CircularProgressIndicatorState();
}

class _CircularProgressIndicatorState
    extends fw.State<CircularProgressIndicator>
    with fw.SingleTickerProviderStateMixin {
  late final fw.AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = fw.AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.value == null) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(CircularProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == null && !_controller.isAnimating) {
      _controller.repeat();
    } else if (widget.value != null && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(24, 24),
          painter: _CircularPainter(
            value: widget.value,
            rotation: _controller.value,
            color: widget.valueColor?.value ??
                widget.color ??
                const Color(0xFF9A83FF),
            backgroundColor: widget.backgroundColor,
            strokeWidth: widget.strokeWidth ?? 2.6,
          ),
        );
      },
    );
  }
}

class _CircularPainter extends CustomPainter {
  final double? value;
  final double rotation;
  final Color color;
  final Color? backgroundColor;
  final double strokeWidth;

  _CircularPainter({
    required this.value,
    required this.rotation,
    required this.color,
    required this.backgroundColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - strokeWidth;
    if (backgroundColor != null) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = backgroundColor!,
      );
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    if (value != null) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * value!.clamp(0.0, 1.0),
        false,
        paint,
      );
    } else {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation * 2 * math.pi);
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius),
        -math.pi / 2,
        math.pi * 1.4,
        false,
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CircularPainter old) =>
      old.rotation != rotation ||
      old.value != value ||
      old.color != color;
}

/// 线性进度(替代 material 的 LinearProgressIndicator)。
class LinearProgressIndicator extends fw.StatelessWidget {
  final double? value;
  final double? minHeight;
  final Color? color;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final fw.Animation<Color?>? valueColor;

  const LinearProgressIndicator({
    fw.Key? key,
    this.value,
    this.minHeight,
    this.color,
    this.backgroundColor,
    this.borderRadius,
    this.valueColor,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final h = minHeight ?? 3.0;
    final fg = valueColor?.value ?? color ?? const Color(0xFF9A83FF);
    final bg = backgroundColor ?? fg.withValues(alpha: .18);
    return SizedBox(
      height: h,
      child: _LinearProgressRender(
        value: value,
        foreground: fg,
        background: bg,
        borderRadius: borderRadius ?? BorderRadius.circular(h),
      ),
    );
  }
}

/// 线性进度渲染件:背景轨道 + 比例填充。
class _LinearProgressRender extends fw.LeafRenderObjectWidget {
  final double? value;
  final Color foreground;
  final Color background;
  final BorderRadius borderRadius;

  const _LinearProgressRender({
    required this.value,
    required this.foreground,
    required this.background,
    required this.borderRadius,
  });

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderLinearProgress(
      value: value,
      foreground: foreground,
      background: background,
      borderRadius: borderRadius,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderLinearProgress renderObject,
  ) {
    renderObject
      ..value = value
      ..foreground = foreground
      ..background = background
      ..borderRadius = borderRadius;
  }
}

class RenderLinearProgress extends RenderBox {
  double? _value;
  Color _foreground;
  Color _background;
  BorderRadius _borderRadius;

  RenderLinearProgress({
    required double? value,
    required Color foreground,
    required Color background,
    required BorderRadius borderRadius,
  })  : _value = value,
        _foreground = foreground,
        _background = background,
        _borderRadius = borderRadius;

  set value(double? v) {
    if (_value == v) return;
    _value = v;
    markNeedsPaint();
  }

  set foreground(Color c) {
    if (_foreground == c) return;
    _foreground = c;
    markNeedsPaint();
  }

  set background(Color c) {
    if (_background == c) return;
    _background = c;
    markNeedsPaint();
  }

  set borderRadius(BorderRadius r) {
    if (_borderRadius == r) return;
    _borderRadius = r;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    size = Size(
      constraints.maxWidth,
      constraints.constrainHeight(3),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final rrect = RRect.fromRectAndCorners(
      offset & size,
      topLeft: _borderRadius.topLeft,
      topRight: _borderRadius.topRight,
      bottomLeft: _borderRadius.bottomLeft,
      bottomRight: _borderRadius.bottomRight,
    );
    canvas.drawRRect(rrect, Paint()..color = _background);
    if (_value != null && _value! > 0) {
      final w = (size.width * _value!.clamp(0.0, 1.0)).clamp(0.0, size.width);
      final fill = RRect.fromRectAndCorners(
        Rect.fromLTWH(offset.dx, offset.dy, w, size.height),
        topLeft: _borderRadius.topLeft,
        topRight: _borderRadius.topRight,
        bottomLeft: _borderRadius.bottomLeft,
        bottomRight: _borderRadius.bottomRight,
      );
      canvas.drawRRect(fill, Paint()..color = _foreground);
    }
  }
}

// ---------------------------------------------------------------------------
// Tabs / PageView
// ---------------------------------------------------------------------------

/// 标签页控制器(自研;ChangeNotifier 语义)。
class TabController extends ChangeNotifier {
  final int length;
  final fw.TickerProvider vsync;
  final Duration animationDuration;

  int _index;
  int _previousIndex = 0;

  TabController({
    required this.length,
    required this.vsync,
    int initialIndex = 0,
    this.animationDuration = const Duration(milliseconds: 240),
  }) : _index = initialIndex.clamp(0, math.max(0, length - 1)) {
    _previousIndex = _index;
  }

  int get index => _index;
  int get previousIndex => _previousIndex;

  set index(int value) {
    animateTo(value);
  }

  void animateTo(int value) {
    final target = value.clamp(0, math.max(0, length - 1)).toInt();
    if (target == _index) return;
    _previousIndex = _index;
    _index = target;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}

/// 横向分页器核心:吸附 + 控制器联动(TabBarView/PageView 共用)。
class _PagerWidget extends fw.StatefulWidget {
  final int pageCount;
  final fw.Widget Function(fw.BuildContext, int index) pageBuilder;
  final TabController? tabController;
  final PageController? pageController;
  final fw.ValueChanged<int>? onPageChanged;

  const _PagerWidget({
    required this.pageCount,
    required this.pageBuilder,
    this.tabController,
    this.pageController,
    this.onPageChanged,
  });

  @override
  fw.State<_PagerWidget> createState() => _PagerWidgetState();
}

class _PagerWidgetState extends fw.State<_PagerWidget> {
  double _offset = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    widget.tabController?.addListener(_followTab);
  }

  @override
  void didUpdateWidget(_PagerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabController != widget.tabController) {
      oldWidget.tabController?.removeListener(_followTab);
      widget.tabController?.addListener(_followTab);
    }
  }

  @override
  void dispose() {
    widget.tabController?.removeListener(_followTab);
    super.dispose();
  }

  void _followTab() {
    if (!mounted || _dragging) return;
    final tab = widget.tabController!;
    final page = _pageExtent();
    if (page > 0) {
      setState(() => _offset = tab.index * page);
    }
  }

  /// 页面宽度:由 [fw.LayoutBuilder] 在布局阶段提供真实宽度。
  double _pageExtent() {
    if (_layoutWidth > 0) return _layoutWidth;
    final ro = context.findRenderObject();
    if (ro is RenderBox && ro.hasSize && ro.size.width > 0) {
      return ro.size.width;
    }
    return 600;
  }

  double _layoutWidth = 0;

  void _snapTo(int page) {
    final clamped = page.clamp(0, widget.pageCount - 1);
    setState(() => _offset = clamped * _pageExtent());
    widget.tabController?.animateTo(clamped);
    widget.pageController?.jumpTo(_offset);
    widget.onPageChanged?.call(clamped);
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    return fw.LayoutBuilder(
      builder: (context, constraints) {
        _layoutWidth = constraints.maxWidth;
        return _buildPager(context, constraints.maxWidth);
      },
    );
  }

  fw.Widget _buildPager(fw.BuildContext context, double pageExtent) {
    // 只构建当前页与相邻页(懒加载),用 Transform 平移实现滑动效果。
    final currentPage = _offset / pageExtent;
    final base = currentPage.round().clamp(0, widget.pageCount - 1);
    final first = (base - 1).clamp(0, widget.pageCount - 1);
    final last = (base + 1).clamp(0, widget.pageCount - 1);

    final pages = <int, fw.Widget>{};
    for (var i = first; i <= last; i++) {
      pages[i] = widget.pageBuilder(context, i);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _dragging = true,
      onHorizontalDragUpdate: (details) {
        setState(() {
          _offset = (_offset - details.delta.dx).clamp(
            0.0,
            math.max(0.0, pageExtent * (widget.pageCount - 1)),
          ) as double;
        });
      },
      onHorizontalDragEnd: (details) {
        _dragging = false;
        final current = (_offset / math.max(1, pageExtent));
        var target = current.round();
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() > 220) {
          target = velocity < 0 ? current.floor() + 1 : current.floor();
        }
        _snapTo(target);
      },
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            for (final entry in pages.entries)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: entry.key != base,
                  child: Transform.translate(
                    offset: Offset(
                      (entry.key - currentPage) * pageExtent,
                      0,
                    ),
                    child: entry.value,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 标签页视图(横向滑动分页;替代 material 的 TabBarView)。
class TabBarView extends fw.StatelessWidget {
  final TabController? controller;
  final List<fw.Widget> children;

  const TabBarView({
    fw.Key? key,
    required this.children,
    this.controller,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    return _PagerWidget(
      pageCount: children.length,
      pageBuilder: (context, index) =>
          index < children.length ? children[index] : const SizedBox.shrink(),
      tabController: controller,
    );
  }
}

/// 分页视图(替代 material 的 PageView)。
class PageView extends fw.StatelessWidget {
  final List<fw.Widget>? children;
  final int? itemCount;
  final fw.Widget? Function(fw.BuildContext, int)? itemBuilder;
  final PageController? controller;
  final Axis scrollDirection;
  final fw.ValueChanged<int>? onPageChanged;

  const PageView({
    fw.Key? key,
    required this.children,
    this.controller,
    this.scrollDirection = Axis.horizontal,
    this.onPageChanged,
  })  : itemCount = null,
        itemBuilder = null,
        super(key: key);

  const PageView.builder({
    fw.Key? key,
    required int this.itemCount,
    required fw.Widget? Function(fw.BuildContext, int) this.itemBuilder,
    this.controller,
    this.scrollDirection = Axis.horizontal,
    this.onPageChanged,
  })  : children = null,
        super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final count = itemCount ?? children?.length ?? 0;
    return _PagerWidget(
      pageCount: count,
      pageBuilder: (context, index) {
        if (itemBuilder != null) {
          return itemBuilder!(context, index) ?? const SizedBox.shrink();
        }
        return index < (children?.length ?? 0)
            ? children![index]
            : const SizedBox.shrink();
      },
      pageController: controller,
      onPageChanged: onPageChanged,
    );
  }
}

/// 分页控制器(自研;与 PageView 搭配)。
class PageController extends ScrollController {
  int get page {
    final pos = position;
    if (pos == null) return 0;
    return (pos.pixels / 600).round();
  }

  Future<void> animateToPage(
    int page, {
    required Duration duration,
    required Curve curve,
  }) async {
    jumpTo(page.toDouble());
  }

  void jumpToPage(int page) {
    jumpTo(page.toDouble());
  }
}

// ---------------------------------------------------------------------------
// Tab / 分段按钮 / ActionChip
// ---------------------------------------------------------------------------

/// 标签(与 BrandTabs 搭配;替代 material 的 Tab)。
class Tab extends fw.StatelessWidget {
  final String? text;
  final fw.Widget? child;
  final fw.Widget? icon;
  final double? iconSize;
  final double height;

  const Tab({
    fw.Key? key,
    this.text,
    this.icon,
    this.iconSize,
    this.child,
    this.height = 46,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    if (child != null) return child!;
    final label = text != null
        ? Text(text!, maxLines: 1, overflow: TextOverflow.ellipsis)
        : (icon ?? const SizedBox.shrink());
    return icon != null && text != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme(
                data: IconThemeData(size: iconSize ?? 18),
                child: icon!,
              ),
              const SizedBox(width: 6),
              label,
            ],
          )
        : label;
  }
}

/// 分段选择器(替代 material 的 SegmentedButton)。
class SegmentedButton<T> extends fw.StatelessWidget {
  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final void Function(Set<T>)? onSelectionChanged;
  final bool showSelectedIcon;
  final fw.Widget? selectedIcon;

  const SegmentedButton({
    fw.Key? key,
    required this.segments,
    required this.selected,
    this.onSelectionChanged,
    this.showSelectedIcon = true,
    this.selectedIcon,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF222E43) : const Color(0xFFF3F5FE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            segments[i].buildSeg(
              context,
              selected: selected.contains(segments[i].value),
              showSelectedIcon: showSelectedIcon,
              primary: primary,
              onSelect: onSelectionChanged == null
                  ? null
                  : () => onSelectionChanged!({segments[i].value}),
            ),
          ],
        ],
      ),
    );
  }
}

/// 分段按钮的单段。
class ButtonSegment<T> {
  final T value;
  final fw.Widget? label;
  final fw.Widget? icon;
  final fw.Widget? selectedIcon;
  final bool enabled;

  const ButtonSegment({
    required this.value,
    this.label,
    this.icon,
    this.selectedIcon,
    this.enabled = true,
  });

  fw.Widget buildSeg(
    fw.BuildContext context, {
    required bool selected,
    required bool showSelectedIcon,
    required Color primary,
    required VoidCallback? onSelect,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: enabled ? onSelect : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? (dark ? const Color(0xFF38405B) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected && !dark
              ? const [
                  BoxShadow(
                    color: Color(0x0C667AAE),
                    blurRadius: 7,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected && showSelectedIcon) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
            ] else if (icon != null) ...[
              IconTheme(
                data: IconThemeData(
                  color: selected
                      ? primary
                      : (dark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF7D88AA)),
                  size: 15,
                ),
                child: icon!,
              ),
              const SizedBox(width: 5),
            ],
            if (label != null)
              DefaultTextStyle(
                style: TextStyle(
                  fontFamily: theme.fontFamily,
                  fontFamilyFallback: theme.fontFamilyFallback,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? primary
                      : (dark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF7D88AA)),
                ),
                child: label!,
              ),
          ],
        ),
      ),
    );
  }
}

/// 可点击标签片(替代 material 的 ActionChip)。
class ActionChip extends fw.StatelessWidget {
  final fw.Widget? avatar;
  final fw.Widget label;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final BorderSide? side;
  final EdgeInsetsGeometry? padding;

  const ActionChip({
    fw.Key? key,
    this.avatar,
    required this.label,
    this.onPressed,
    this.backgroundColor,
    this.side,
    this.padding,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: padding ??
            const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor ??
              (dark ? const Color(0xFF222E43) : const Color(0xFFF4F7FF)),
          borderRadius: BorderRadius.circular(20),
          border: side != null
              ? Border.all(color: side!.color, width: side!.width)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (avatar != null) ...[
              avatar!,
              const SizedBox(width: 6),
            ],
            DefaultTextStyle(
              style: TextStyle(
                fontFamily: theme.fontFamily,
                fontFamilyFallback: theme.fontFamilyFallback,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: dark ? const Color(0xFFB9C2D8) : const Color(0xFF55607E),
              ),
              child: label,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PopupMenuButton
// ---------------------------------------------------------------------------

/// 弹出菜单位置。
enum PopupMenuPosition { under, over }

/// 菜单条目基类。
abstract class PopupMenuEntry<T> {
  const PopupMenuEntry();

  double get height;
}

/// 具体菜单项。
class PopupMenuItem<T> extends PopupMenuEntry<T> {
  final T? value;
  final fw.Widget child;
  final double height;
  final bool enabled;

  const PopupMenuItem({
    fw.Key? key,
    this.value,
    required this.child,
    this.height = 40,
    this.enabled = true,
  });
}

/// 菜单分隔线。
class PopupMenuDivider extends PopupMenuEntry<Never> {
  final double height;

  const PopupMenuDivider({fw.Key? key, this.height = 9});

  @override
  fw.Widget build(fw.BuildContext context) => const Divider(height: 9);
}

/// 弹出菜单按钮(替代 material 的 PopupMenuButton)。
class PopupMenuButton<T> extends fw.StatefulWidget {
  final List<PopupMenuEntry<T>> Function(fw.BuildContext) itemBuilder;
  final fw.ValueChanged<T>? onSelected;
  final String? tooltip;
  final fw.Widget? icon;
  final fw.Widget? child;
  final PopupMenuPosition position;
  final Offset offset;
  final Color? color;
  final ShapeBorder? shape;
  final double elevation;
  final EdgeInsetsGeometry? padding;

  const PopupMenuButton({
    fw.Key? key,
    required this.itemBuilder,
    this.onSelected,
    this.tooltip,
    this.icon,
    this.child,
    this.position = PopupMenuPosition.under,
    this.offset = Offset.zero,
    this.color,
    this.shape,
    this.elevation = 3,
    this.padding = const EdgeInsets.all(8),
  }) : super(key: key);

  @override
  fw.State<PopupMenuButton<T>> createState() => _PopupMenuButtonState<T>();
}

class _PopupMenuButtonState<T> extends fw.State<PopupMenuButton<T>> {
  void _openMenu() {
    final host = OverlayHost.of(context);
    final ro = context.findRenderObject();
    Offset anchor = Offset.zero;
    Size boxSize = Size.zero;
    if (ro is RenderBox && ro.hasSize) {
      anchor = ro.localToGlobal(Offset.zero);
      boxSize = ro.size;
    }
    final items = widget.itemBuilder(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final themeRadius = widget.shape is RoundedRectangleBorder
        ? (widget.shape as RoundedRectangleBorder).borderRadius
        : BorderRadius.circular(14);
    final themeSide = widget.shape is RoundedRectangleBorder
        ? (widget.shape as RoundedRectangleBorder).side
        : BorderSide.none;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => entry.remove(),
          child: Stack(
            children: [
              Positioned(
                left: anchor.dx,
                top: widget.position == PopupMenuPosition.under
                    ? anchor.dy + boxSize.height + widget.offset.dy
                    : math.max(
                        8,
                        anchor.dy +
                            boxSize.height / 2 +
                            widget.offset.dy -
                            items.fold<double>(
                                0, (sum, item) => sum + item.height) /
                                2,
                      ),
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.color ??
                          (dark
                              ? const Color(0xFF1E293B)
                              : Colors.white),
                      borderRadius: themeRadius,
                      border: themeSide != BorderSide.none
                          ? Border.all(
                              color: themeSide.color,
                              width: themeSide.width,
                            )
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .16),
                          blurRadius: widget.elevation * 4,
                          offset: Offset(0, widget.elevation),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final item in items)
                          if (item is PopupMenuDivider)
                            SizedBox(height: item.height)
                          else if (item is PopupMenuItem<T>)
                            InkWell(
                              onTap: !item.enabled
                                  ? null
                                  : () {
                                      entry.remove();
                                      if (item.value != null) {
                                        widget.onSelected
                                            ?.call(item.value as T);
                                      }
                                    },
                              child: Opacity(
                                opacity: item.enabled ? 1 : .45,
                                child: Container(
                                height: item.height,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                alignment: Alignment.centerLeft,
                                child: DefaultTextStyle(
                                  style: TextStyle(
                                    fontFamily: theme.fontFamily,
                                    fontFamilyFallback:
                                        theme.fontFamilyFallback,
                                    fontSize: 12,
                                    color: dark
                                        ? const Color(0xFFD5E0FF)
                                        : const Color(0xFF353B58),
                                  ),
                                    child: item.child,
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    host.insertEntry(entry);
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    if (widget.child != null) {
      return InkWell(
        onTap: _openMenu,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: widget.padding ?? const EdgeInsets.all(8),
          child: widget.child,
        ),
      );
    }
    return IconButton(
      onPressed: _openMenu,
      tooltip: widget.tooltip,
      icon: widget.icon ?? const SizedBox(width: 24, height: 24),
    );
  }
}
