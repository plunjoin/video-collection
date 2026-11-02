/// 自研悬停提示(替代 material 的 Tooltip)。
///
/// 浮层宿主渲染提示气泡;同时提供语义标签,便于无障碍与自动化测试定位。
import 'dart:async';
import 'dart:math' as math;

import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' as fw;

import 'container.dart';
import 'gestures.dart';
import 'layout.dart';
import 'overlay.dart';
import 'text.dart';
import 'theme.dart';

/// 悬停提示(替代 material 的 Tooltip;走浮层宿主)。
class Tooltip extends fw.StatefulWidget {
  final String? message;
  final fw.Widget child;
  final Duration? waitDuration;
  final Duration? showDuration;
  final bool preferBelow;
  final BoxDecoration? decoration;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? margin;

  const Tooltip({
    fw.Key? key,
    required this.message,
    required this.child,
    this.waitDuration,
    this.showDuration,
    this.preferBelow = true,
    this.decoration,
    this.textStyle,
    this.margin,
  }) : super(key: key);

  @override
  fw.State<Tooltip> createState() => _TooltipState();
}

class _TooltipState extends fw.State<Tooltip> {
  Timer? _showTimer;
  OverlayEntry? _entry;
  bool _waiting = false;

  void _scheduleShow() {
    if (_entry != null || _waiting) return;
    if ((widget.message ?? '').isEmpty) return;
    _waiting = true;
    _showTimer =
        Timer(widget.waitDuration ?? const Duration(milliseconds: 500), () {
      _waiting = false;
      if (mounted) _show();
    });
  }

  void _show() {
    final host = OverlayHost.of(context);
    final ro = context.findRenderObject();
    Offset anchor = Offset.zero;
    Size boxSize = Size.zero;
    if (ro is RenderBox && ro.hasSize) {
      anchor = ro.localToGlobal(Offset.zero);
      boxSize = ro.size;
    }
    final entry = OverlayEntry(
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final dark = theme.brightness == Brightness.dark;
        return Positioned(
          left: anchor.dx,
          top: widget.preferBelow
              ? anchor.dy + boxSize.height + 6
              : math.max(4, anchor.dy - 40),
          child: Container(
            margin: widget.margin ?? EdgeInsets.zero,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: widget.decoration ??
                BoxDecoration(
                  color: dark
                      ? const Color(0xFF243049)
                      : const Color(0xFF555F83),
                  borderRadius: BorderRadius.circular(8),
                ),
            child: DefaultTextStyle(
              style: widget.textStyle ??
                  TextStyle(
                    fontFamily: theme.fontFamily,
                    fontFamilyFallback: theme.fontFamilyFallback,
                    fontSize: 11,
                    color: Colors.white,
                  ),
              child: Text(widget.message ?? '', maxLines: 2),
            ),
          ),
        );
      },
    );
    _entry = entry;
    host.insertEntry(entry);
  }

  void _cancel() {
    _showTimer?.cancel();
    _waiting = false;
    if (_entry != null) {
      _entry!.remove();
      _entry = null;
    }
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    // 语义与悬停触发借用框架 RawTooltip(纯管道组件,无 Material 视觉);
    // 气泡外观仍由本库自研的浮层绘制。
    // 语义层提供 tooltip 文案(供无障碍与自动化定位);
    // 悬停触发与气泡外观由本库自研浮层完成。
    return Semantics(
      tooltip: widget.message,
      child: MouseRegion(
        onEnter: (_) => _scheduleShow(),
        onExit: (_) => _cancel(),
        child: widget.child,
      ),
    );
  }
}

