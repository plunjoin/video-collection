/// 自研按钮族:[ButtonStyle]/[TextButton]/[ElevatedButton]/[OutlinedButton]/
/// [FilledButton](含 .tonal)/[IconButton]/[FloatingActionButton]。
///
/// 视觉与原 M3 主题(AppTheme)对齐:无水波,悬停/按压用透明度叠加。
import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show MouseCursor;
import 'package:flutter/widgets.dart' as fw;

import 'gestures.dart';
import 'inputs.dart';
import 'layout.dart';
import 'text.dart';
import 'theme.dart';

/// 点击目标最小尺寸策略。
enum MaterialTapTargetSize { padded, shrinkWrap }

/// 按钮样式(自研;字段面 = 全库 styleFrom 用点)。
class ButtonStyle {
  final Color? foregroundColor;
  final Color? backgroundColor;
  final Color? disabledForegroundColor;
  final Color? disabledBackgroundColor;
  final Color? overlayColor;
  final Color? shadowColor;
  final double? elevation;
  final EdgeInsetsGeometry? padding;
  final Size? minimumSize;
  final Size? maximumSize;
  final Size? fixedSize;
  final BorderSide? side;
  final OutlinedBorder? shape;
  final TextStyle? textStyle;
  final double? iconSize;
  final MaterialTapTargetSize? tapTargetSize;
  final MouseCursor? mouseCursor;
  final AlignmentGeometry? alignment;

  const ButtonStyle({
    this.foregroundColor,
    this.backgroundColor,
    this.disabledForegroundColor,
    this.disabledBackgroundColor,
    this.overlayColor,
    this.shadowColor,
    this.elevation,
    this.padding,
    this.minimumSize,
    this.maximumSize,
    this.fixedSize,
    this.side,
    this.shape,
    this.textStyle,
    this.iconSize,
    this.tapTargetSize,
    this.mouseCursor,
    this.alignment,
  });

  ButtonStyle copyWith({
    Color? foregroundColor,
    Color? backgroundColor,
    Color? disabledForegroundColor,
    Color? disabledBackgroundColor,
    Color? overlayColor,
    Color? shadowColor,
    double? elevation,
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Size? maximumSize,
    Size? fixedSize,
    BorderSide? side,
    OutlinedBorder? shape,
    TextStyle? textStyle,
    double? iconSize,
    MaterialTapTargetSize? tapTargetSize,
    MouseCursor? mouseCursor,
    AlignmentGeometry? alignment,
  }) {
    return ButtonStyle(
      foregroundColor: foregroundColor ?? this.foregroundColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      disabledForegroundColor:
          disabledForegroundColor ?? this.disabledForegroundColor,
      disabledBackgroundColor:
          disabledBackgroundColor ?? this.disabledBackgroundColor,
      overlayColor: overlayColor ?? this.overlayColor,
      shadowColor: shadowColor ?? this.shadowColor,
      elevation: elevation ?? this.elevation,
      padding: padding ?? this.padding,
      minimumSize: minimumSize ?? this.minimumSize,
      maximumSize: maximumSize ?? this.maximumSize,
      fixedSize: fixedSize ?? this.fixedSize,
      side: side ?? this.side,
      shape: shape ?? this.shape,
      textStyle: textStyle ?? this.textStyle,
      iconSize: iconSize ?? this.iconSize,
      tapTargetSize: tapTargetSize ?? this.tapTargetSize,
      mouseCursor: mouseCursor ?? this.mouseCursor,
      alignment: alignment ?? this.alignment,
    );
  }
}

// 按钮形状直接使用框架 painting 层的 OutlinedBorder/RoundedRectangleBorder/
// StadiumBorder(绘制原语,非组件)。

/// 按钮基类:状态(hover/press)解析 + 绘制。
class _ButtonBase extends fw.StatefulWidget {
  final ButtonStyle? style;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final fw.Widget? child;
  final fw.FocusNode? focusNode;
  final bool autofocus;
  final String? tooltip;

  const _ButtonBase({
    required this.style,
    required this.onPressed,
    this.onLongPress,
    this.child,
    this.focusNode,
    this.autofocus = false,
    this.tooltip,
  });

  static _ButtonBaseState of(fw.BuildContext context) =>
      throw UnsupportedError('internal');

  @override
  fw.State<_ButtonBase> createState() => _ButtonBaseState();
}

class _ButtonBaseState extends fw.State<_ButtonBase> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null || widget.onLongPress != null;

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final style = widget.style ?? const ButtonStyle();

    final bg = _enabled
        ? style.backgroundColor
        : (style.disabledBackgroundColor ?? style.backgroundColor);
    final fg = _enabled
        ? (style.foregroundColor ??
            (theme.brightness == Brightness.dark
                ? const Color(0xFFF9FAFF)
                : const Color(0xFF353B58)))
        : (style.disabledForegroundColor ??
            const Color(0x61000000));

    final shape = style.shape ?? const RoundedRectangleBorder();
    final side = style.side ?? shape.side;
    BorderRadius shapeRadius = BorderRadius.zero;
    if (shape is RoundedRectangleBorder) {
      shapeRadius = shape.borderRadius.resolve(TextDirection.ltr);
    } else if (shape is StadiumBorder) {
      shapeRadius = BorderRadius.circular(999);
    }
    final elevation = _enabled ? (style.elevation ?? 0.0) : 0.0;
    final minSize = style.minimumSize ?? const Size(44, 44);
    final padding = style.padding ??
        const EdgeInsets.symmetric(horizontal: 18, vertical: 11);
    final labelStyle = (style.textStyle ??
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))
        .copyWith(
          color: fg,
          fontFamily:
              style.textStyle?.fontFamily ?? theme.fontFamily,
          fontFamilyFallback: style.textStyle?.fontFamilyFallback ??
              theme.fontFamilyFallback,
        );

    fw.Widget content = _buildContent(labelStyle, style);
    content = Padding(padding: padding, child: content);

    var decoration = BoxDecoration(
      color: bg,
      borderRadius: shapeRadius,
      border: side != BorderSide.none
          ? Border.all(
              color: side.color,
              width: side.width,
            )
          : null,
      boxShadow: elevation > 0
          ? [
              BoxShadow(
                color: style.shadowColor ?? const Color(0x22000000),
                blurRadius: elevation * 2,
                offset: Offset(0, elevation),
              ),
            ]
          : null,
    );

    // 悬停/按压叠加
    if (_enabled && _hovered) {
      final overlay =
          style.overlayColor ?? fg.withValues(alpha: .06);
      if (bg != null) {
        decoration = decoration.copyWith(
          color: Color.alphaBlend(overlay, bg),
        );
      } else {
        decoration = decoration.copyWith(color: overlay);
      }
    } else if (_enabled && _pressed) {
      final overlay =
          style.overlayColor ?? fg.withValues(alpha: .12);
      if (bg != null) {
        decoration = decoration.copyWith(
          color: Color.alphaBlend(overlay, bg),
        );
      } else {
        decoration = decoration.copyWith(color: overlay);
      }
    }

    fw.Widget button = Semantics(
      button: true,
      enabled: _enabled,
      child: MouseRegion(
        cursor: _enabled
            ? (style.mouseCursor ?? SystemMouseCursors.click)
            : MouseCursor.defer,
        onEnter: _enabled
            ? (_) => setState(() => _hovered = true)
            : null,
        onExit: _enabled
            ? (_) => setState(() {
                  _hovered = false;
                  _pressed = false;
                })
            : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          onLongPress: widget.onLongPress,
          onTapDown: _enabled
              ? (_) => setState(() => _pressed = true)
              : null,
          onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: _enabled
              ? () => setState(() => _pressed = false)
              : null,
          child: _MinSizeBox(
            minWidth: minSize.width,
            minHeight: minSize.height,
            child: DecoratedBox(
              decoration: decoration,
              child: content,
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = _TooltipHost(message: widget.tooltip!, child: button);
    }
    return button;
  }

  fw.Widget _buildContent(TextStyle labelStyle, ButtonStyle style) {
    final child = widget.child;
    if (child == null) return const SizedBox.shrink();
    return DefaultTextStyle(
      style: labelStyle,
      child: IconTheme(
        data: IconThemeData(
          color: labelStyle.color,
          size: style.iconSize ?? 20,
        ),
        child: child,
      ),
    );
  }
}

/// 最小尺寸约束盒子(可放大,不小于指定值)。
class _MinSizeBox extends fw.SingleChildRenderObjectWidget {
  final double minWidth;
  final double minHeight;

  const _MinSizeBox({
    required this.minWidth,
    required this.minHeight,
    super.child,
  });

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderMinSizeBox(
      minWidth: minWidth,
      minHeight: minHeight,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderMinSizeBox renderObject,
  ) {
    renderObject
      ..minWidth = minWidth
      ..minHeight = minHeight;
  }
}

class RenderMinSizeBox extends RenderProxyBox {
  double _minWidth;
  double _minHeight;

  RenderMinSizeBox({required double minWidth, required double minHeight})
      : _minWidth = minWidth,
        _minHeight = minHeight;

  set minWidth(double value) {
    if (_minWidth == value) return;
    _minWidth = value;
    markNeedsLayout();
  }

  set minHeight(double value) {
    if (_minHeight == value) return;
    _minHeight = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    size = Size(
      size.width < _minWidth ? _minWidth : size.width,
      size.height < _minHeight ? _minHeight : size.height,
    );
  }
}

/// 按钮内部:悬停提示宿主占位(由 overlay.dart 提供真正实现前的简单包装)。
class _TooltipHost extends fw.StatelessWidget {
  final String message;
  final fw.Widget child;

  const _TooltipHost({required this.message, required this.child});

  @override
  fw.Widget build(fw.BuildContext context) => child;
}

// ---------------------------------------------------------------------------
// 具体按钮
// ---------------------------------------------------------------------------

/// 扁平文本按钮。
class TextButton extends fw.StatelessWidget {
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final ButtonStyle? style;
  final fw.FocusNode? focusNode;
  final bool autofocus;
  final fw.Widget? child;
  final fw.Widget? icon;

  const TextButton({
    fw.Key? key,
    required this.onPressed,
    this.onLongPress,
    this.style,
    this.focusNode,
    this.autofocus = false,
    required this.child,
  })  : icon = null,
        super(key: key);

  const TextButton.icon({
    fw.Key? key,
    required this.onPressed,
    this.onLongPress,
    this.style,
    this.focusNode,
    this.autofocus = false,
    required fw.Widget this.icon,
    required fw.Widget this.child,
  }) : super(key: key);

  static ButtonStyle styleFrom({
    Color? foregroundColor,
    Color? backgroundColor,
    Color? disabledForegroundColor,
    Color? disabledBackgroundColor,
    Color? overlayColor,
    Color? shadowColor,
    double? elevation,
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Size? maximumSize,
    Size? fixedSize,
    BorderSide? side,
    OutlinedBorder? shape,
    TextStyle? textStyle,
    double? iconSize,
    MaterialTapTargetSize? tapTargetSize,
    MouseCursor? mouseCursor,
    AlignmentGeometry? alignment,
    bool? enableFeedback,
  }) {
    return ButtonStyle(
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      disabledForegroundColor: disabledForegroundColor,
      disabledBackgroundColor: disabledBackgroundColor,
      overlayColor: overlayColor,
      shadowColor: shadowColor,
      elevation: elevation,
      padding: padding,
      minimumSize: minimumSize,
      maximumSize: maximumSize,
      fixedSize: fixedSize,
      side: side,
      shape: shape,
      textStyle: textStyle,
      iconSize: iconSize,
      tapTargetSize: tapTargetSize,
      mouseCursor: mouseCursor,
      alignment: alignment,
    );
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final base = style ??
        ButtonStyle(
          foregroundColor: theme.colorScheme.primary,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        );
    final effective = icon != null
        ? base.copyWith(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          )
        : base;
    return _ButtonBase(
      style: effective,
      onPressed: onPressed,
      onLongPress: onLongPress,
      focusNode: focusNode,
      autofocus: autofocus,
      child: icon != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon!,
                const SizedBox(width: 7),
                child!,
              ],
            )
          : child,
    );
  }
}

/// 实心主按钮。
class ElevatedButton extends fw.StatelessWidget {
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final ButtonStyle? style;
  final fw.FocusNode? focusNode;
  final bool autofocus;
  final fw.Widget? child;
  final fw.Widget? icon;

  const ElevatedButton({
    fw.Key? key,
    required this.onPressed,
    this.onLongPress,
    this.style,
    this.focusNode,
    this.autofocus = false,
    required this.child,
  })  : icon = null,
        super(key: key);

  const ElevatedButton.icon({
    fw.Key? key,
    required this.onPressed,
    this.onLongPress,
    this.style,
    this.focusNode,
    this.autofocus = false,
    required fw.Widget this.icon,
    required fw.Widget this.child,
  }) : super(key: key);

  static ButtonStyle styleFrom({
    Color? foregroundColor,
    Color? backgroundColor,
    Color? disabledForegroundColor,
    Color? disabledBackgroundColor,
    Color? overlayColor,
    Color? shadowColor,
    double? elevation,
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Size? maximumSize,
    Size? fixedSize,
    BorderSide? side,
    OutlinedBorder? shape,
    TextStyle? textStyle,
    double? iconSize,
    MaterialTapTargetSize? tapTargetSize,
    MouseCursor? mouseCursor,
    AlignmentGeometry? alignment,
    bool? enableFeedback,
  }) {
    return ButtonStyle(
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      disabledForegroundColor: disabledForegroundColor,
      disabledBackgroundColor: disabledBackgroundColor,
      overlayColor: overlayColor,
      shadowColor: shadowColor,
      elevation: elevation,
      padding: padding,
      minimumSize: minimumSize,
      maximumSize: maximumSize,
      fixedSize: fixedSize,
      side: side,
      shape: shape,
      textStyle: textStyle,
      iconSize: iconSize,
      tapTargetSize: tapTargetSize,
      mouseCursor: mouseCursor,
      alignment: alignment,
    );
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final base = style ??
        ButtonStyle(
          foregroundColor: Colors.white,
          backgroundColor: theme.colorScheme.primary,
          disabledForegroundColor: Colors.white60,
          disabledBackgroundColor:
              theme.colorScheme.primary.withValues(alpha: .35),
          elevation: 0,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        );
    final effective = icon != null
        ? base.copyWith(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          )
        : base;
    return _ButtonBase(
      style: effective,
      onPressed: onPressed,
      onLongPress: onLongPress,
      focusNode: focusNode,
      autofocus: autofocus,
      child: icon != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon!,
                const SizedBox(width: 8),
                child!,
              ],
            )
          : child,
    );
  }
}

/// 描边按钮。
class OutlinedButton extends fw.StatelessWidget {
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final ButtonStyle? style;
  final fw.FocusNode? focusNode;
  final bool autofocus;
  final fw.Widget? child;
  final fw.Widget? icon;

  const OutlinedButton({
    fw.Key? key,
    required this.onPressed,
    this.onLongPress,
    this.style,
    this.focusNode,
    this.autofocus = false,
    required this.child,
  })  : icon = null,
        super(key: key);

  const OutlinedButton.icon({
    fw.Key? key,
    required this.onPressed,
    this.onLongPress,
    this.style,
    this.focusNode,
    this.autofocus = false,
    required fw.Widget this.icon,
    required fw.Widget this.child,
  }) : super(key: key);

  static ButtonStyle styleFrom({
    Color? foregroundColor,
    Color? backgroundColor,
    Color? disabledForegroundColor,
    Color? disabledBackgroundColor,
    Color? overlayColor,
    Color? shadowColor,
    double? elevation,
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Size? maximumSize,
    Size? fixedSize,
    BorderSide? side,
    OutlinedBorder? shape,
    TextStyle? textStyle,
    double? iconSize,
    MaterialTapTargetSize? tapTargetSize,
    MouseCursor? mouseCursor,
    AlignmentGeometry? alignment,
    bool? enableFeedback,
  }) {
    return ButtonStyle(
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      disabledForegroundColor: disabledForegroundColor,
      disabledBackgroundColor: disabledBackgroundColor,
      overlayColor: overlayColor,
      shadowColor: shadowColor,
      elevation: elevation,
      padding: padding,
      minimumSize: minimumSize,
      maximumSize: maximumSize,
      fixedSize: fixedSize,
      side: side,
      shape: shape,
      textStyle: textStyle,
      iconSize: iconSize,
      tapTargetSize: tapTargetSize,
      mouseCursor: mouseCursor,
      alignment: alignment,
    );
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final base = style ??
        ButtonStyle(
          foregroundColor:
              dark ? const Color(0xFFD5E0FF) : const Color(0xFF7E79B6),
          backgroundColor: dark
              ? const Color(0xFF243049)
              : const Color(0xFFF4F6FE),
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 12),
          side: BorderSide(color: theme.dividerColor),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        );
    final effective = icon != null
        ? base.copyWith(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          )
        : base;
    return _ButtonBase(
      style: effective,
      onPressed: onPressed,
      onLongPress: onLongPress,
      focusNode: focusNode,
      autofocus: autofocus,
      child: icon != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon!,
                const SizedBox(width: 7),
                child!,
              ],
            )
          : child,
    );
  }
}

/// 高亮填充按钮(M3 FilledButton;含 .tonal 变体)。
class FilledButton extends fw.StatelessWidget {
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final ButtonStyle? style;
  final fw.FocusNode? focusNode;
  final bool autofocus;
  final fw.Widget? child;
  final fw.Widget? icon;
  final bool tonal;

  const FilledButton({
    fw.Key? key,
    required this.onPressed,
    this.onLongPress,
    this.style,
    this.focusNode,
    this.autofocus = false,
    required this.child,
  })  : icon = null,
        tonal = false,
        super(key: key);

  const FilledButton.tonal({
    fw.Key? key,
    required this.onPressed,
    this.onLongPress,
    this.style,
    this.focusNode,
    this.autofocus = false,
    required this.child,
  })  : icon = null,
        tonal = true,
        super(key: key);

  const FilledButton.icon({
    fw.Key? key,
    required this.onPressed,
    this.onLongPress,
    this.style,
    this.focusNode,
    this.autofocus = false,
    required fw.Widget this.icon,
    required fw.Widget this.child,
  })  : tonal = false,
        super(key: key);

  static ButtonStyle styleFrom({
    Color? foregroundColor,
    Color? backgroundColor,
    Color? disabledForegroundColor,
    Color? disabledBackgroundColor,
    Color? overlayColor,
    Color? shadowColor,
    double? elevation,
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Size? maximumSize,
    Size? fixedSize,
    BorderSide? side,
    OutlinedBorder? shape,
    TextStyle? textStyle,
    double? iconSize,
    MaterialTapTargetSize? tapTargetSize,
    MouseCursor? mouseCursor,
    AlignmentGeometry? alignment,
    bool? enableFeedback,
  }) {
    return ButtonStyle(
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      disabledForegroundColor: disabledForegroundColor,
      disabledBackgroundColor: disabledBackgroundColor,
      overlayColor: overlayColor,
      shadowColor: shadowColor,
      elevation: elevation,
      padding: padding,
      minimumSize: minimumSize,
      maximumSize: maximumSize,
      fixedSize: fixedSize,
      side: side,
      shape: shape,
      textStyle: textStyle,
      iconSize: iconSize,
      tapTargetSize: tapTargetSize,
      mouseCursor: mouseCursor,
      alignment: alignment,
    );
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final ButtonStyle base;
    if (tonal) {
      base = style ??
          ButtonStyle(
            foregroundColor: theme.colorScheme.primary,
            backgroundColor:
                theme.colorScheme.primary.withValues(alpha: .12),
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          );
    } else {
      base = style ??
          ButtonStyle(
            foregroundColor: Colors.white,
            backgroundColor: theme.colorScheme.primary,
            disabledForegroundColor: Colors.white60,
            disabledBackgroundColor:
                theme.colorScheme.primary.withValues(alpha: .35),
            elevation: 0,
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          );
    }
    final effective = icon != null
        ? base.copyWith(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          )
        : base;
    return _ButtonBase(
      style: effective,
      onPressed: onPressed,
      onLongPress: onLongPress,
      focusNode: focusNode,
      autofocus: autofocus,
      child: icon != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon!,
                const SizedBox(width: 8),
                child!,
              ],
            )
          : child,
    );
  }
}

/// 图标按钮。
class IconButton extends fw.StatelessWidget {
  final VoidCallback? onPressed;
  final String? tooltip;
  final fw.Widget icon;
  final fw.Widget? selectedIcon;
  final bool isSelected;
  final ButtonStyle? style;
  final double? iconSize;
  final Color? color;
  final Color? hoverColor;
  final Color? focusColor;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final double? splashRadius;
  final fw.FocusNode? focusNode;
  final bool autofocus;
  final MouseCursor? mouseCursor;
  final bool enableFeedback;

  const IconButton({
    fw.Key? key,
    required this.onPressed,
    this.tooltip,
    required this.icon,
    this.selectedIcon,
    this.isSelected = false,
    this.style,
    this.iconSize,
    this.color,
    this.hoverColor,
    this.focusColor,
    this.padding,
    this.constraints,
    this.splashRadius,
    this.focusNode,
    this.autofocus = false,
    this.mouseCursor,
    this.enableFeedback = true,
  }) : super(key: key);

  static ButtonStyle styleFrom({
    Color? foregroundColor,
    Color? backgroundColor,
    Color? disabledForegroundColor,
    Color? disabledBackgroundColor,
    Color? overlayColor,
    Color? shadowColor,
    double? elevation,
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Size? maximumSize,
    Size? fixedSize,
    BorderSide? side,
    OutlinedBorder? shape,
    TextStyle? textStyle,
    double? iconSize,
    MaterialTapTargetSize? tapTargetSize,
    MouseCursor? mouseCursor,
    AlignmentGeometry? alignment,
    bool? enableFeedback,
  }) {
    return ButtonStyle(
      foregroundColor: foregroundColor,
      backgroundColor: backgroundColor,
      disabledForegroundColor: disabledForegroundColor,
      disabledBackgroundColor: disabledBackgroundColor,
      overlayColor: overlayColor,
      shadowColor: shadowColor,
      elevation: elevation,
      padding: padding,
      minimumSize: minimumSize,
      maximumSize: maximumSize,
      fixedSize: fixedSize,
      side: side,
      shape: shape,
      textStyle: textStyle,
      iconSize: iconSize,
      tapTargetSize: tapTargetSize,
      mouseCursor: mouseCursor,
      alignment: alignment,
    );
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    final base = style ??
        ButtonStyle(
          foregroundColor: theme.iconTheme.color,
          iconSize: iconSize ?? theme.iconTheme.size ?? 21,
          minimumSize: const Size(44, 44),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        );
    final merged = base.copyWith(
      foregroundColor:
          style?.foregroundColor ?? color ?? base.foregroundColor,
      iconSize: iconSize ?? base.iconSize,
    );
    return _ButtonBase(
      style: merged,
      onPressed: onPressed,
      tooltip: tooltip,
      focusNode: focusNode,
      autofocus: autofocus,
      child: isSelected && selectedIcon != null ? selectedIcon! : icon,
    );
  }
}

/// 悬浮操作按钮。
class FloatingActionButton extends fw.StatelessWidget {
  final VoidCallback? onPressed;
  final String? tooltip;
  final fw.Widget child;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const FloatingActionButton({
    fw.Key? key,
    required this.onPressed,
    this.tooltip,
    required this.child,
    this.backgroundColor,
    this.foregroundColor,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    return _ButtonBase(
      style: ButtonStyle(
        backgroundColor:
            backgroundColor ?? theme.colorScheme.primary,
        foregroundColor: foregroundColor ?? Colors.white,
        minimumSize: const Size(56, 56),
        padding: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(),
        elevation: 3,
        shadowColor: const Color(0x33000000),
      ),
      onPressed: onPressed,
      tooltip: tooltip,
      child: child,
    );
  }
}
