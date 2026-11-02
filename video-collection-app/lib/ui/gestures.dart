/// 自研手势与指针交互组件:[Listener]/[MouseRegion]/[GestureDetector]/
/// [InkWell]/[IgnorePointer]/[AbsorbPointer]。
///
/// 手势识别复用引擎层 recognizers(Tap/DoubleTap/LongPress/Pan/Drag/Scale),
/// 指针转发基于渲染层 RenderPointerListener / RenderMouseRegion。
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as fw;


import 'layout.dart';
import 'theme.dart';

/// 原始指针事件监听。
class Listener extends fw.SingleChildRenderObjectWidget {
  final PointerDownEventListener? onPointerDown;
  final PointerMoveEventListener? onPointerMove;
  final PointerUpEventListener? onPointerUp;
  final PointerCancelEventListener? onPointerCancel;
  final PointerSignalEventListener? onPointerSignal;
  final PointerPanZoomStartEventListener? onPointerPanZoomStart;
  final PointerPanZoomUpdateEventListener? onPointerPanZoomUpdate;
  final PointerPanZoomEndEventListener? onPointerPanZoomEnd;

  const Listener({
    fw.Key? key,
    this.onPointerDown,
    this.onPointerMove,
    this.onPointerUp,
    this.onPointerCancel,
    this.onPointerSignal,
    this.onPointerPanZoomStart,
    this.onPointerPanZoomUpdate,
    this.onPointerPanZoomEnd,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderPointerListener(
      onPointerDown: onPointerDown,
      onPointerMove: onPointerMove,
      onPointerUp: onPointerUp,
      onPointerCancel: onPointerCancel,
      onPointerSignal: onPointerSignal,
      onPointerPanZoomStart: onPointerPanZoomStart,
      onPointerPanZoomUpdate: onPointerPanZoomUpdate,
      onPointerPanZoomEnd: onPointerPanZoomEnd,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderPointerListener renderObject,
  ) {
    renderObject
      ..onPointerDown = onPointerDown
      ..onPointerMove = onPointerMove
      ..onPointerUp = onPointerUp
      ..onPointerCancel = onPointerCancel
      ..onPointerSignal = onPointerSignal
      ..onPointerPanZoomStart = onPointerPanZoomStart
      ..onPointerPanZoomUpdate = onPointerPanZoomUpdate
      ..onPointerPanZoomEnd = onPointerPanZoomEnd;
  }
}

/// 鼠标悬停区域(光标 + 进入/离开/移动回调)。
class MouseRegion extends fw.SingleChildRenderObjectWidget {
  final PointerEnterEventListener? onEnter;
  final PointerExitEventListener? onExit;
  final PointerHoverEventListener? onHover;
  final MouseCursor cursor;
  final bool opaque;

  const MouseRegion({
    fw.Key? key,
    this.onEnter,
    this.onExit,
    this.onHover,
    this.cursor = MouseCursor.defer,
    this.opaque = true,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderMouseRegion(
      onEnter: onEnter,
      onExit: onExit,
      onHover: onHover,
      cursor: cursor,
      opaque: opaque,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderMouseRegion renderObject,
  ) {
    renderObject
      ..onEnter = onEnter
      ..onExit = onExit
      ..onHover = onHover
      ..cursor = cursor
      ..opaque = opaque;
  }
}

/// 手势检测器:把指针事件分发给引擎层手势识别器。
class GestureDetector extends fw.StatefulWidget {
  final fw.Widget? child;

  // 单击族
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureTapCallback? onTap;
  final GestureTapCancelCallback? onTapCancel;
  final GestureTapCallback? onSecondaryTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final GestureTapUpCallback? onSecondaryTapUp;
  final GestureTapCancelCallback? onSecondaryTapCancel;

  // 双击族
  final GestureTapDownCallback? onDoubleTapDown;
  final GestureTapCallback? onDoubleTap;
  final GestureTapCancelCallback? onDoubleTapCancel;

  // 长按族
  final GestureLongPressDownCallback? onLongPressDown;
  final GestureLongPressCancelCallback? onLongPressCancel;
  final GestureLongPressCallback? onLongPress;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressEndCallback? onLongPressEnd;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;

  // 拖动族
  final GestureDragDownCallback? onPanDown;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final GestureDragCancelCallback? onPanCancel;
  final GestureDragDownCallback? onHorizontalDragDown;
  final GestureDragStartCallback? onHorizontalDragStart;
  final GestureDragUpdateCallback? onHorizontalDragUpdate;
  final GestureDragEndCallback? onHorizontalDragEnd;
  final GestureDragCancelCallback? onHorizontalDragCancel;
  final GestureDragDownCallback? onVerticalDragDown;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final GestureDragCancelCallback? onVerticalDragCancel;

  // 缩放族
  final GestureScaleStartCallback? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;

  final HitTestBehavior behavior;
  final DragStartBehavior dragStartBehavior;
  final bool excludeFromSemantics;

  const GestureDetector({
    fw.Key? key,
    this.child,
    this.onTapDown,
    this.onTapUp,
    this.onTap,
    this.onTapCancel,
    this.onSecondaryTap,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onSecondaryTapCancel,
    this.onDoubleTapDown,
    this.onDoubleTap,
    this.onDoubleTapCancel,
    this.onLongPressDown,
    this.onLongPressCancel,
    this.onLongPress,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.onLongPressMoveUpdate,
    this.onPanDown,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
    this.onHorizontalDragDown,
    this.onHorizontalDragStart,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
    this.onHorizontalDragCancel,
    this.onVerticalDragDown,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onVerticalDragCancel,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    this.behavior = HitTestBehavior.deferToChild,
    this.dragStartBehavior = DragStartBehavior.start,
    this.excludeFromSemantics = false,
  }) : super(key: key);

  @override
  fw.State<GestureDetector> createState() => _GestureDetectorState();
}

class _GestureDetectorState extends fw.State<GestureDetector> {
  @override
  fw.Widget build(fw.BuildContext context) {
    final w = widget;
    final child = w.child ?? const _EmptyBox();
    final recognizers = <Type, fw.GestureRecognizerFactory>{};

    // 单击
    if (w.onTapDown != null ||
        w.onTapUp != null ||
        w.onTap != null ||
        w.onTapCancel != null) {
      recognizers[TapGestureRecognizer] =
          fw.GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
        () => TapGestureRecognizer(debugOwner: w),
        (TapGestureRecognizer instance) {
          instance
            ..onTapDown = w.onTapDown
            ..onTapUp = w.onTapUp
            ..onTap = w.onTap
            ..onTapCancel = w.onTapCancel;
        },
      );
    }

    // 右键单击
    if (w.onSecondaryTap != null ||
        w.onSecondaryTapDown != null ||
        w.onSecondaryTapUp != null ||
        w.onSecondaryTapCancel != null) {
      recognizers[TapGestureRecognizer] =
          fw.GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
        () => TapGestureRecognizer(debugOwner: w),
        (TapGestureRecognizer instance) {
          instance
            ..onSecondaryTapDown = w.onSecondaryTapDown
            ..onSecondaryTapUp = w.onSecondaryTapUp
            ..onSecondaryTap = w.onSecondaryTap
            ..onSecondaryTapCancel = w.onSecondaryTapCancel;
        },
      );
    }

    // 双击
    if (w.onDoubleTap != null ||
        w.onDoubleTapDown != null ||
        w.onDoubleTapCancel != null) {
      recognizers[DoubleTapGestureRecognizer] =
          fw.GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
        () => DoubleTapGestureRecognizer(debugOwner: w),
        (DoubleTapGestureRecognizer instance) {
          instance
            ..onDoubleTapDown = w.onDoubleTapDown
            ..onDoubleTap = w.onDoubleTap
            ..onDoubleTapCancel = w.onDoubleTapCancel;
        },
      );
    }

    // 长按
    if (w.onLongPressDown != null ||
        w.onLongPressCancel != null ||
        w.onLongPress != null ||
        w.onLongPressStart != null ||
        w.onLongPressEnd != null ||
        w.onLongPressMoveUpdate != null) {
      recognizers[LongPressGestureRecognizer] =
          fw.GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
        () => LongPressGestureRecognizer(debugOwner: w),
        (LongPressGestureRecognizer instance) {
          instance
            ..onLongPressDown = w.onLongPressDown
            ..onLongPressCancel = w.onLongPressCancel
            ..onLongPress = w.onLongPress
            ..onLongPressStart = w.onLongPressStart
            ..onLongPressEnd = w.onLongPressEnd
            ..onLongPressMoveUpdate = w.onLongPressMoveUpdate;
        },
      );
    }

    // 平移
    if (w.onPanDown != null ||
        w.onPanStart != null ||
        w.onPanUpdate != null ||
        w.onPanEnd != null ||
        w.onPanCancel != null) {
      recognizers[PanGestureRecognizer] =
          fw.GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
        () => PanGestureRecognizer(debugOwner: w),
        (PanGestureRecognizer instance) {
          instance
            ..dragStartBehavior = w.dragStartBehavior
            ..onDown = w.onPanDown
            ..onStart = w.onPanStart
            ..onUpdate = w.onPanUpdate
            ..onEnd = w.onPanEnd
            ..onCancel = w.onPanCancel;
        },
      );
    }

    // 水平拖动
    if (w.onHorizontalDragDown != null ||
        w.onHorizontalDragStart != null ||
        w.onHorizontalDragUpdate != null ||
        w.onHorizontalDragEnd != null ||
        w.onHorizontalDragCancel != null) {
      recognizers[HorizontalDragGestureRecognizer] =
          fw.GestureRecognizerFactoryWithHandlers<
              HorizontalDragGestureRecognizer>(
        () => HorizontalDragGestureRecognizer(debugOwner: w),
        (HorizontalDragGestureRecognizer instance) {
          instance
            ..dragStartBehavior = w.dragStartBehavior
            ..onDown = w.onHorizontalDragDown
            ..onStart = w.onHorizontalDragStart
            ..onUpdate = w.onHorizontalDragUpdate
            ..onEnd = w.onHorizontalDragEnd
            ..onCancel = w.onHorizontalDragCancel;
        },
      );
    }

    // 垂直拖动
    if (w.onVerticalDragDown != null ||
        w.onVerticalDragStart != null ||
        w.onVerticalDragUpdate != null ||
        w.onVerticalDragEnd != null ||
        w.onVerticalDragCancel != null) {
      recognizers[VerticalDragGestureRecognizer] =
          fw.GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
        () => VerticalDragGestureRecognizer(debugOwner: w),
        (VerticalDragGestureRecognizer instance) {
          instance
            ..dragStartBehavior = w.dragStartBehavior
            ..onDown = w.onVerticalDragDown
            ..onStart = w.onVerticalDragStart
            ..onUpdate = w.onVerticalDragUpdate
            ..onEnd = w.onVerticalDragEnd
            ..onCancel = w.onVerticalDragCancel;
        },
      );
    }

    // 缩放
    if (w.onScaleStart != null ||
        w.onScaleUpdate != null ||
        w.onScaleEnd != null) {
      recognizers[ScaleGestureRecognizer] =
          fw.GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
        () => ScaleGestureRecognizer(debugOwner: w),
        (ScaleGestureRecognizer instance) {
          instance
            ..dragStartBehavior = w.dragStartBehavior
            ..onStart = w.onScaleStart
            ..onUpdate = w.onScaleUpdate
            ..onEnd = w.onScaleEnd;
        },
      );
    }

    fw.HitTestBehavior behavior;
    switch (widget.behavior) {
      case HitTestBehavior.opaque:
        behavior = fw.HitTestBehavior.opaque;
      case HitTestBehavior.translucent:
        behavior = fw.HitTestBehavior.translucent;
      case HitTestBehavior.deferToChild:
        behavior = fw.HitTestBehavior.deferToChild;
    }

    return fw.RawGestureDetector(
      behavior: behavior,
      gestures: recognizers,
      child: child,
    );
  }
}

class _EmptyBox extends fw.SingleChildRenderObjectWidget {
  const _EmptyBox();

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) =>
      RenderConstrainedBox(additionalConstraints: BoxConstraints.tight(Size.zero));
}

/// 命中行为盒子(opaque/translucent 的行为语义)。
class _BehaviorBox extends fw.SingleChildRenderObjectWidget {
  final HitTestBehavior? behavior;

  const _BehaviorBox({required this.behavior, required super.child});

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderBehaviorBox(behavior: behavior);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderBehaviorBox renderObject,
  ) {
    renderObject.behavior = behavior ?? HitTestBehavior.deferToChild;
  }
}

class RenderBehaviorBox extends RenderProxyBoxWithHitTestBehavior {
  RenderBehaviorBox({required HitTestBehavior? behavior})
      : super(behavior: behavior ?? HitTestBehavior.deferToChild);

  @override
  set behavior(HitTestBehavior value) {
    super.behavior = value;
  }
}

/// 无水波标记(替代 material 的 NoSplash;自研按钮无水波,仅兼容传参)。
abstract final class NoSplash {
  static const Object splashFactory = _NoSplashFactory();
}

class _NoSplashFactory {
  const _NoSplashFactory();
}

/// 可点击区域:悬停/按压高亮 + 点击/双击/长按(替代 material 的 InkWell)。
class InkWell extends fw.StatefulWidget {
  final fw.Widget? child;
  final GestureTapCallback? onTap;
  final GestureTapCallback? onDoubleTap;
  final GestureLongPressCallback? onLongPress;
  final fw.ValueChanged<bool>? onHover;
  final fw.ValueChanged<bool>? onHighlightChanged;
  final BorderRadius? borderRadius;
  final double? radius;
  final ShapeBorder? customBorder;
  final Color? overlayColor;
  final Color? highlightColor;
  final Color? splashColor;
  final Color? hoverColor;
  final Color? focusColor;
  final Object? splashFactory;
  final MouseCursor? mouseCursor;
  final bool enableFeedback;
  final bool canRequestFocus;
  final bool autofocus;
  final bool excludeFromSemantics;

  const InkWell({
    fw.Key? key,
    this.child,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onHover,
    this.onHighlightChanged,
    this.borderRadius,
    this.radius,
    this.customBorder,
    this.overlayColor,
    this.highlightColor,
    this.splashColor,
    this.hoverColor,
    this.focusColor,
    this.splashFactory,
    this.mouseCursor,
    this.enableFeedback = true,
    this.canRequestFocus = true,
    this.autofocus = false,
    this.excludeFromSemantics = false,
  }) : super(key: key);

  @override
  fw.State<InkWell> createState() => _InkWellState();
}

class _InkWellState extends fw.State<InkWell> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _interactive =>
      widget.onTap != null ||
      widget.onDoubleTap != null ||
      widget.onLongPress != null;

  Color? _effectiveOverlay() {
    final theme = Theme.of(context);
    if (!_interactive) return null;
    final base = widget.overlayColor;
    if (_pressed) {
      final color = base ?? widget.highlightColor ?? theme.highlightColor;
      if (color.a == 0) return null;
      return color.withValues(alpha: .16);
    }
    if (_hovered) {
      final color = base ?? widget.hoverColor ?? theme.hoverColor;
      if (color.a == 0) return null;
      return color.withValues(alpha: .12);
    }
    return null;
  }

  BorderRadius? get _clipRadius =>
      widget.borderRadius ??
      (widget.radius != null
          ? BorderRadius.circular(widget.radius!)
          : (widget.customBorder is RoundedRectangleBorder
              ? (widget.customBorder as RoundedRectangleBorder)
                  .borderRadius
                  .resolve(TextDirection.ltr)
              : null));

  @override
  fw.Widget build(fw.BuildContext context) {
    final child = widget.child ?? const SizedBox.shrink();
    final overlay = _effectiveOverlay();
    return MouseRegion(
      cursor: widget.mouseCursor ??
          (_interactive ? SystemMouseCursors.click : MouseCursor.defer),
      onEnter: _interactive
          ? (_) {
              setState(() => _hovered = true);
              widget.onHover?.call(true);
            }
          : null,
      onExit: _interactive
          ? (_) {
              setState(() {
                _hovered = false;
                _pressed = false;
              });
              widget.onHover?.call(false);
            }
          : null,
      child: GestureDetector(
        onTap: widget.onTap == null
            ? null
            : () {
                setState(() => _pressed = false);
                widget.onHighlightChanged?.call(false);
                widget.onTap!();
              },
        onTapDown: widget.onTap == null
            ? null
            : (_) {
                setState(() => _pressed = true);
                widget.onHighlightChanged?.call(true);
              },
        onTapCancel: widget.onTap == null
            ? null
            : () {
                setState(() => _pressed = false);
                widget.onHighlightChanged?.call(false);
              },
        onDoubleTap: widget.onDoubleTap,
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: overlay,
            borderRadius: _clipRadius,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 指针穿透(事件与语义都不进入子树)。
class IgnorePointer extends fw.SingleChildRenderObjectWidget {
  final bool ignoring;

  const IgnorePointer({
    fw.Key? key,
    this.ignoring = true,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderIgnorePointerBox(ignoring: ignoring);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderIgnorePointerBox renderObject,
  ) {
    renderObject.ignoring = ignoring;
  }
}

class RenderIgnorePointerBox extends RenderProxyBox {
  bool _ignoring;

  RenderIgnorePointerBox({required bool ignoring}) : _ignoring = ignoring;

  set ignoring(bool value) {
    if (_ignoring == value) return;
    _ignoring = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    return !_ignoring && super.hitTest(result, position: position);
  }
}

/// 吞掉命中(事件到此为止,不进入子树)。
class AbsorbPointer extends fw.SingleChildRenderObjectWidget {
  final bool absorbing;

  const AbsorbPointer({
    fw.Key? key,
    this.absorbing = true,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderAbsorbPointerBox(absorbing: absorbing);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderAbsorbPointerBox renderObject,
  ) {
    renderObject.absorbing = absorbing;
  }
}

class RenderAbsorbPointerBox extends RenderProxyBox {
  bool _absorbing;

  RenderAbsorbPointerBox({required bool absorbing})
      : _absorbing = absorbing;

  set absorbing(bool value) {
    if (_absorbing == value) return;
    _absorbing = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_absorbing) {
      // 吞掉事件:自身命中但不给子树
      return size.contains(position);
    }
    return super.hitTest(result, position: position);
  }
}
