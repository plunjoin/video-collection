/// 自研容器与动画组件:[Container]/[AnimatedContainer]/[AnimatedOpacity]/
/// [AnimatedScale]/[AnimatedBuilder]/[TweenAnimationBuilder]/
/// [ValueListenableBuilder]/[SafeArea]/[CustomPaint]/[ShaderMask]/
/// [BackdropFilter]/[AnnotatedRegion]。
///
/// 隐式动画用 AnimationController 驱动,在装饰/边距/尺寸属性间做 lerp。
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart' show Listenable, ValueListenable;
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiOverlayStyle;
import 'package:flutter/widgets.dart' as fw;

import 'layout.dart';
import 'theme.dart';

/// 构建器签名:监听器每次触发时用当前值重建子树。
typedef WidgetTransitionBuilder = fw.Widget Function(
  fw.BuildContext context,
  fw.Widget? child,
);

/// 组合容器:边距 + 装饰 + 内边距 + 尺寸 + 对齐 + 变换。
class Container extends fw.StatelessWidget {
  final Alignment? alignment;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final BoxDecoration? decoration;
  final BoxDecoration? foregroundDecoration;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? margin;
  final Matrix4? transform;
  final Alignment? transformAlignment;
  final Clip clipBehavior;
  final fw.Widget? child;

  const Container({
    fw.Key? key,
    this.alignment,
    this.padding,
    this.color,
    this.decoration,
    this.foregroundDecoration,
    this.width,
    this.height,
    this.constraints,
    this.margin,
    this.transform,
    this.transformAlignment,
    this.clipBehavior = Clip.none,
    this.child,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    fw.Widget? current = child;

    // 对齐
    if (alignment != null) {
      current = Align(alignment: alignment!, child: current);
    }

    // 约束与固定尺寸
    final effectiveConstraints = constraints ??
        (width != null || height != null
            ? BoxConstraints.tightFor(width: width, height: height)
            : null);
    if (effectiveConstraints != null) {
      current = ConstrainedBox(constraints: effectiveConstraints, child: current);
    } else if (current == null && (width == null && height == null)) {
      // 无子项且无约束时占满可用空间
      current = ConstrainedBox(
        constraints: const BoxConstraints.expand(),
        child: null,
      );
    }

    // 内边距 + 装饰
    final effectiveDecoration =
        decoration ?? (color != null ? BoxDecoration(color: color) : null);
    if (effectiveDecoration != null) {
      current = DecoratedBox(decoration: effectiveDecoration, child: current);
    }
    if (padding != null) {
      current = Padding(padding: padding!, child: current);
    }

    // 前景装饰
    if (foregroundDecoration != null) {
      current = DecoratedBox(
        decoration: foregroundDecoration!,
        child: current,
      );
    }

    // 变换
    if (transform != null) {
      current = Transform(
        transform: transform!,
        alignment: transformAlignment,
        child: current,
      );
    }

    // 外边距
    if (margin != null) {
      current = Padding(padding: margin!, child: current);
    }

    // 裁剪
    if (clipBehavior != Clip.none) {
      final radius = (decoration ?? foregroundDecoration)?.borderRadius;
      if (radius != null) {
        final resolved = radius.resolve(TextDirection.ltr);
        if (resolved != BorderRadius.zero) {
          current = ClipRRect(borderRadius: resolved, child: current);
        } else {
          current = ClipRect(child: current);
        }
      } else {
        current = ClipRect(child: current);
      }
    }

    return current ?? const SizedBox.shrink();
  }
}

/// 隐式动画容器(替代 material 的 AnimatedContainer)。
///
/// 单个 AnimationController 驱动多个属性的插值(装饰/边距/尺寸/对齐),
/// 避免为每个属性各建一个控制器。
class AnimatedContainer extends fw.StatefulWidget {
  final Alignment? alignment;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final BoxDecoration? decoration;
  final BoxDecoration? foregroundDecoration;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? margin;
  final Matrix4? transform;
  final Alignment? transformAlignment;
  final Clip clipBehavior;
  final Duration duration;
  final Curve curve;
  final VoidCallback? onEnd;
  final fw.Widget? child;

  const AnimatedContainer({
    fw.Key? key,
    this.alignment,
    this.padding,
    this.color,
    this.decoration,
    this.foregroundDecoration,
    this.width,
    this.height,
    this.constraints,
    this.margin,
    this.transform,
    this.transformAlignment,
    this.clipBehavior = Clip.none,
    required this.duration,
    this.curve = fw.Curves.linear,
    this.onEnd,
    this.child,
  }) : super(key: key);

  @override
  fw.State<AnimatedContainer> createState() => _AnimatedContainerState();
}

class _AnimatedContainerState extends fw.State<AnimatedContainer>
    with fw.SingleTickerProviderStateMixin {
  late final fw.AnimationController _controller;
  late fw.Animation<double> _curved;

  // 起始值(动画起点)与目标值(动画终点)
  BoxDecoration? _fromDecoration;
  BoxDecoration? _toDecoration;
  EdgeInsetsGeometry? _fromPadding;
  EdgeInsetsGeometry? _toPadding;
  EdgeInsetsGeometry? _fromMargin;
  EdgeInsetsGeometry? _toMargin;
  Alignment? _fromAlignment;
  Alignment? _toAlignment;
  Size? _fromSize;
  Size? _toSize;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = fw.AnimationController(vsync: this, duration: widget.duration);
    _curved = fw.CurvedAnimation(parent: _controller, curve: widget.curve);
    _syncTargets();
  }

  @override
  void didUpdateWidget(AnimatedContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != _controller.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.curve != oldWidget.curve) {
      _curved = fw.CurvedAnimation(parent: _controller, curve: widget.curve);
    }
    _syncTargets();
  }

  BoxDecoration? get _targetDecoration =>
      widget.decoration ??
      (widget.color != null ? BoxDecoration(color: widget.color) : null);

  Size? get _targetSize =>
      (widget.width != null || widget.height != null)
          ? Size(widget.width ?? 0, widget.height ?? 0)
          : null;

  /// 目标变化时:记录起点,启动动画。
  void _syncTargets() {
    final t = _curved.value;
    final newDecoration = _targetDecoration;
    final newPadding = widget.padding;
    final newMargin = widget.margin;
    final newAlignment = widget.alignment;
    final newSize = _targetSize;

    if (!_initialized) {
      _initialized = true;
      _fromDecoration = newDecoration;
      _toDecoration = newDecoration;
      _fromPadding = newPadding;
      _toPadding = newPadding;
      _fromMargin = newMargin;
      _toMargin = newMargin;
      _fromAlignment = newAlignment;
      _toAlignment = newAlignment;
      _fromSize = newSize;
      _toSize = newSize;
      return;
    }

    // 装饰对象每次 build 都会新建,需按内容比较,否则会无限重启动画
    final changed = !_sameDecoration(_toDecoration, newDecoration) ||
        _toPadding != newPadding ||
        _toMargin != newMargin ||
        _toAlignment != newAlignment ||
        _toSize != newSize;
    if (!changed) return;

    // 当前实际值作为动画起点
    _fromDecoration = _lerpDecoration(_fromDecoration, _toDecoration, t);
    _fromPadding = _lerpInsets(_fromPadding, _toPadding, t);
    _fromMargin = _lerpInsets(_fromMargin, _toMargin, t);
    _fromAlignment = Alignment.lerp(_fromAlignment, _toAlignment, t);
    _fromSize = _lerpSize(_fromSize, _toSize, t);

    _toDecoration = newDecoration;
    _toPadding = newPadding;
    _toMargin = newMargin;
    _toAlignment = newAlignment;
    _toSize = newSize;

    _controller.forward(from: 0);
  }

  /// 装饰内容比较(逐字段;BoxDecoration 未实现 == )。
  bool _sameDecoration(BoxDecoration? a, BoxDecoration? b) {
    if (a == null || b == null) return a == b;
    return a.color == b.color &&
        a.gradient == b.gradient &&
        a.borderRadius == b.borderRadius &&
        a.shape == b.shape &&
        a.border == b.border &&
        a.boxShadow == b.boxShadow &&
        a.image == b.image;
  }

  BoxDecoration? _lerpDecoration(
    BoxDecoration? a,
    BoxDecoration? b,
    double t,
  ) {
    if (a == null || b == null) return b ?? a;
    return BoxDecoration.lerp(a, b, t);
  }

  EdgeInsetsGeometry? _lerpInsets(
    EdgeInsetsGeometry? a,
    EdgeInsetsGeometry? b,
    double t,
  ) {
    if (a == null || b == null) return b ?? a;
    return EdgeInsetsGeometry.lerp(a, b, t);
  }

  Size? _lerpSize(Size? a, Size? b, double t) {
    if (a == null || b == null) return b ?? a;
    return Size.lerp(a, b, t);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _curved.value;
        final decoration = _lerpDecoration(_fromDecoration, _toDecoration, t);
        final padding = _lerpInsets(_fromPadding, _toPadding, t);
        final margin = _lerpInsets(_fromMargin, _toMargin, t);
        final alignment = Alignment.lerp(_fromAlignment, _toAlignment, t);
        final size = _lerpSize(_fromSize, _toSize, t);
        return Container(
          alignment: alignment,
          padding: padding,
          decoration: decoration,
          width: size?.width == 0 ? null : size?.width,
          height: size?.height == 0 ? null : size?.height,
          margin: margin,
          transform: widget.transform,
          transformAlignment: widget.transformAlignment,
          clipBehavior: widget.clipBehavior,
          child: widget.child,
        );
      },
      child: widget.child,
    );
  }
}

/// 隐式动画透明度。
class AnimatedOpacity extends fw.StatefulWidget {
  final double opacity;
  final Duration duration;
  final Curve curve;
  final VoidCallback? onEnd;
  final bool alwaysIncludeSemantics;
  final fw.Widget child;

  const AnimatedOpacity({
    fw.Key? key,
    required this.opacity,
    required this.duration,
    this.curve = Curves.linear,
    this.onEnd,
    this.alwaysIncludeSemantics = false,
    required this.child,
  }) : super(key: key);

  @override
  fw.State<AnimatedOpacity> createState() => _AnimatedOpacityState();
}

class _AnimatedOpacityState extends fw.State<AnimatedOpacity>
    with fw.SingleTickerProviderStateMixin {
  late final fw.AnimationController _controller;
  late fw.Animation<double> _animation;
  double _from = 1;

  @override
  void initState() {
    super.initState();
    _controller = fw.AnimationController(vsync: this, duration: widget.duration)
      ..value = widget.opacity;
    _animation = fw.CurvedAnimation(parent: _controller, curve: widget.curve);
  }

  @override
  void didUpdateWidget(AnimatedOpacity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.opacity != _controller.value) {
      _from = _controller.value;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = ui.lerpDouble(_from, widget.opacity, _animation.value)!;
        return Opacity(opacity: value, child: child);
      },
      child: widget.child,
    );
  }
}

/// 隐式动画缩放。
class AnimatedScale extends fw.StatefulWidget {
  final double scale;
  final Duration duration;
  final Curve curve;
  final Alignment alignment;
  final VoidCallback? onEnd;
  final fw.Widget child;

  const AnimatedScale({
    fw.Key? key,
    required this.scale,
    required this.duration,
    this.curve = Curves.linear,
    this.alignment = Alignment.center,
    this.onEnd,
    required this.child,
  }) : super(key: key);

  @override
  fw.State<AnimatedScale> createState() => _AnimatedScaleState();
}

class _AnimatedScaleState extends fw.State<AnimatedScale>
    with fw.SingleTickerProviderStateMixin {
  late final fw.AnimationController _controller;
  late fw.Animation<double> _animation;
  double _from = 1;

  @override
  void initState() {
    super.initState();
    _controller = fw.AnimationController(vsync: this, duration: widget.duration)
      ..value = widget.scale;
    _animation = fw.CurvedAnimation(parent: _controller, curve: widget.curve);
  }

  @override
  void didUpdateWidget(AnimatedScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scale != _controller.value) {
      _from = _controller.value;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = ui.lerpDouble(_from, widget.scale, _animation.value)!;
        return Transform.scale(
          scale: value,
          alignment: widget.alignment,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 监听 Listenable 重建(替代 widgets 的 AnimatedBuilder/ListenableBuilder)。
class AnimatedBuilder extends fw.StatelessWidget {
  final Listenable animation;
  final WidgetTransitionBuilder builder;
  final fw.Widget? child;

  const AnimatedBuilder({
    fw.Key? key,
    required this.animation,
    required this.builder,
    this.child,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    return _ListenableWidget(
      listenable: animation,
      builder: builder,
      child: child,
    );
  }
}

/// ListenableBuilder 别名。
class ListenableBuilder extends AnimatedBuilder {
  const ListenableBuilder({
    fw.Key? key,
    required Listenable listenable,
    required WidgetTransitionBuilder builder,
    fw.Widget? child,
  }) : super(key: key, animation: listenable, builder: builder, child: child);
}

class _ListenableWidget extends fw.StatefulWidget {
  final Listenable listenable;
  final WidgetTransitionBuilder builder;
  final fw.Widget? child;

  const _ListenableWidget({
    required this.listenable,
    required this.builder,
    this.child,
  });

  @override
  fw.State<_ListenableWidget> createState() => _ListenableWidgetState();
}

class _ListenableWidgetState extends fw.State<_ListenableWidget> {
  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(_ListenableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_rebuild);
      widget.listenable.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  fw.Widget build(fw.BuildContext context) {
    return widget.builder(context, widget.child);
  }
}

/// 值监听构建器。
class ValueListenableBuilder<T> extends fw.StatelessWidget {
  final ValueListenable<T> valueListenable;
  final fw.ValueWidgetBuilder<T> builder;
  final T? child;

  const ValueListenableBuilder({
    fw.Key? key,
    required this.valueListenable,
    required this.builder,
    this.child,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    return _ListenableWidget(
      listenable: valueListenable,
      builder: (context, _) =>
          builder(context, valueListenable.value, child as fw.Widget?),
      child: null,
    );
  }
}

/// 补间动画构建器(目标 tween 变化时平滑过渡)。
class TweenAnimationBuilder<T extends Object?> extends fw.StatefulWidget {
  final Tween<T> tween;
  final Duration duration;
  final Curve curve;
  final VoidCallback? onEnd;
  final fw.Widget Function(fw.BuildContext, T, fw.Widget?) builder;
  final fw.Widget? child;

  const TweenAnimationBuilder({
    fw.Key? key,
    required this.tween,
    required this.duration,
    this.curve = Curves.linear,
    this.onEnd,
    required this.builder,
    this.child,
  }) : super(key: key);

  @override
  fw.State<TweenAnimationBuilder<T>> createState() =>
      _TweenAnimationBuilderState<T>();
}

class _TweenAnimationBuilderState<T extends Object?>
    extends fw.State<TweenAnimationBuilder<T>>
    with fw.SingleTickerProviderStateMixin {
  late final fw.AnimationController _controller;
  late fw.CurvedAnimation _curved;
  Tween<T>? _currentTween;
  Tween<T>? _targetTween;

  @override
  void initState() {
    super.initState();
    _controller = fw.AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1,
    );
    _curved = fw.CurvedAnimation(parent: _controller, curve: widget.curve);
    _currentTween = widget.tween;
    _targetTween = widget.tween;
    _controller.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(TweenAnimationBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tween.end != _targetTween?.end) {
      final currentValue = _currentTween!.lerp(_curved.value);
      _currentTween = Tween<T>(begin: currentValue, end: widget.tween.end);
      _targetTween = widget.tween;
      _controller.forward(from: 0);
    }
    if (widget.duration != _controller.duration) {
      _controller.duration = widget.duration;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_rebuild);
    _controller.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (_controller.status == fw.AnimationStatus.completed) {
      widget.onEnd?.call();
    }
    setState(() {});
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    final value = _currentTween!.lerp(_curved.value);
    return widget.builder(context, value, widget.child);
  }
}

/// 安全区:避开系统刘海/状态栏。
class SafeArea extends fw.StatelessWidget {
  final bool left;
  final bool top;
  final bool right;
  final bool bottom;
  final EdgeInsets minimum;
  final bool maintainBottomViewPadding;
  final fw.Widget child;

  const SafeArea({
    fw.Key? key,
    this.left = true,
    this.top = true,
    this.right = true,
    this.bottom = true,
    this.minimum = EdgeInsets.zero,
    this.maintainBottomViewPadding = false,
    required this.child,
  }) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    final data = fw.MediaQuery.of(context);
    final padding = maintainBottomViewPadding && data.viewPadding.bottom > 0
        ? data.viewPadding
        : data.padding;
    return Padding(
      padding: EdgeInsets.only(
        left: mathMax(padding.left, minimum.left),
        top: mathMax(padding.top, minimum.top),
        right: mathMax(padding.right, minimum.right),
        bottom: mathMax(padding.bottom, minimum.bottom),
      ),
      child: fw.MediaQuery.removePadding(
        context: context,
        removeLeft: left,
        removeTop: top,
        removeRight: right,
        removeBottom: bottom,
        child: child,
      ),
    );
  }

  static double mathMax(double a, double b) => a > b ? a : b;
}

/// 自定义绘制(替代 widgets 的 CustomPaint)。
///
/// 绘制语义(前后景 painter、preferredSize、语义重建)复用框架渲染层的
/// RenderCustomPaint(painting/rendering 基础设施),组件本身为本库自研。
class CustomPaint extends fw.SingleChildRenderObjectWidget {
  final CustomPainter? painter;
  final CustomPainter? foregroundPainter;
  final Size size;
  final bool isComplex;
  final bool willChange;

  const CustomPaint({
    fw.Key? key,
    this.painter,
    this.foregroundPainter,
    this.size = Size.zero,
    this.isComplex = false,
    this.willChange = false,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderCustomPaint(
      painter: painter,
      foregroundPainter: foregroundPainter,
      preferredSize: size,
      isComplex: isComplex,
      willChange: willChange,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderCustomPaint renderObject,
  ) {
    renderObject
      ..painter = painter
      ..foregroundPainter = foregroundPainter
      ..preferredSize = size
      ..isComplex = isComplex
      ..willChange = willChange;
  }
}

/// 着色蒙版。
class ShaderMask extends fw.SingleChildRenderObjectWidget {
  final ShaderCallback shaderCallback;
  final BlendMode blendMode;

  const ShaderMask({
    fw.Key? key,
    required this.shaderCallback,
    this.blendMode = BlendMode.modulate,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderShaderMaskBox(
      shaderCallback: shaderCallback,
      blendMode: blendMode,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderShaderMaskBox renderObject,
  ) {
    renderObject
      ..shaderCallback = shaderCallback
      ..blendMode = blendMode;
  }
}

/// 自写着色蒙版渲染盒子。
class RenderShaderMaskBox extends RenderProxyBox {
  ShaderCallback _shaderCallback;
  BlendMode _blendMode;

  RenderShaderMaskBox({
    required ShaderCallback shaderCallback,
    required BlendMode blendMode,
  })  : _shaderCallback = shaderCallback,
        _blendMode = blendMode;

  set shaderCallback(ShaderCallback value) {
    if (_shaderCallback == value) return;
    _shaderCallback = value;
    markNeedsPaint();
  }

  set blendMode(BlendMode value) {
    if (_blendMode == value) return;
    _blendMode = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final bounds = offset & size;
    final layer = ShaderMaskLayer(
      shader: _shaderCallback(bounds),
      maskRect: bounds,
      blendMode: _blendMode,
    );
    context.pushLayer(
      layer,
      (context, offset) => context.paintChild(child!, offset),
      offset,
    );
  }
}

/// 背景模糊滤镜。
class BackdropFilter extends fw.SingleChildRenderObjectWidget {
  final ui.ImageFilter filter;

  const BackdropFilter({
    fw.Key? key,
    required this.filter,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderBackdropBox(filter: filter);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderBackdropBox renderObject,
  ) {
    renderObject.filter = filter;
  }
}

/// 自写背景滤镜渲染盒子。
class RenderBackdropBox extends RenderProxyBox {
  ui.ImageFilter _filter;

  RenderBackdropBox({required ui.ImageFilter filter}) : _filter = filter;

  set filter(ui.ImageFilter value) {
    if (_filter == value) return;
    _filter = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final layer = ImageFilterLayer()..imageFilter = _filter;
    context.pushLayer(
      layer,
      (context, offset) {
        if (child != null) context.paintChild(child!, offset);
      },
      offset,
    );
  }
}

/// 系统状态栏样式标注区(仅支持 SystemUiOverlayStyle)。
class AnnotatedRegion<T extends Object?> extends fw.StatefulWidget {
  final T value;
  final bool sized;
  final fw.Widget child;

  const AnnotatedRegion({
    fw.Key? key,
    required this.value,
    this.sized = true,
    required this.child,
  }) : super(key: key);

  @override
  fw.State<AnnotatedRegion<T>> createState() => _AnnotatedRegionState<T>();
}

class _AnnotatedRegionState<T extends Object?>
    extends fw.State<AnnotatedRegion<T>> {
  @override
  void initState() {
    super.initState();
    _apply();
  }

  @override
  void didUpdateWidget(AnnotatedRegion<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _apply();
    }
  }

  void _apply() {
    final value = widget.value;
    if (value is SystemUiOverlayStyle) {
      SystemChrome.setSystemUIOverlayStyle(value);
    }
  }

  @override
  fw.Widget build(fw.BuildContext context) => widget.child;
}


/// 图像滤镜(对子树整体应用 ui.ImageFilter;替代 widgets 的 ImageFiltered)。
class ImageFiltered extends fw.SingleChildRenderObjectWidget {
  final ui.ImageFilter imageFilter;

  const ImageFiltered({
    fw.Key? key,
    required this.imageFilter,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderImageFilteredBox(imageFilter: imageFilter);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderImageFilteredBox renderObject,
  ) {
    renderObject.imageFilter = imageFilter;
  }
}

/// 自写图像滤镜渲染盒子。
class RenderImageFilteredBox extends RenderProxyBox {
  ui.ImageFilter _imageFilter;

  RenderImageFilteredBox({required ui.ImageFilter imageFilter})
      : _imageFilter = imageFilter;

  set imageFilter(ui.ImageFilter value) {
    if (_imageFilter == value) return;
    _imageFilter = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final layer = ImageFilterLayer()..imageFilter = _imageFilter;
    context.pushLayer(
      layer,
      (context, offset) {
        if (child != null) context.paintChild(child!, offset);
      },
      offset,
    );
  }
}


/// 颜色滤镜(替代 widgets 的 ColorFiltered)。
class ColorFiltered extends fw.SingleChildRenderObjectWidget {
  final ui.ColorFilter colorFilter;

  const ColorFiltered({
    fw.Key? key,
    required this.colorFilter,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderColorFilteredBox(colorFilter: colorFilter);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderColorFilteredBox renderObject,
  ) {
    renderObject.colorFilter = colorFilter;
  }
}

class RenderColorFilteredBox extends RenderProxyBox {
  ui.ColorFilter _colorFilter;

  RenderColorFilteredBox({required ui.ColorFilter colorFilter})
      : _colorFilter = colorFilter;

  set colorFilter(ui.ColorFilter value) {
    if (_colorFilter == value) return;
    _colorFilter = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final layer = ColorFilterLayer()..colorFilter = _colorFilter;
    context.pushLayer(
      layer,
      (context, offset) {
        if (child != null) context.paintChild(child!, offset);
      },
      offset,
    );
  }
}

/// 尺寸过渡(自研简化版:尺寸变化时 160ms 缓动;替代 widgets 的 AnimatedSize)。
class AnimatedSize extends fw.StatefulWidget {
  final Duration duration;
  final Curve curve;
  final Alignment alignment;
  final fw.Widget child;

  const AnimatedSize({
    fw.Key? key,
    required this.duration,
    this.curve = fw.Curves.easeOutCubic,
    this.alignment = Alignment.center,
    required this.child,
  }) : super(key: key);

  @override
  fw.State<AnimatedSize> createState() => _AnimatedSizeState();
}

class _AnimatedSizeState extends fw.State<AnimatedSize>
    with fw.SingleTickerProviderStateMixin {
  late final fw.AnimationController _controller;
  Size _current = Size.zero;
  Size _target = Size.zero;
  Size _from = Size.zero;

  @override
  void initState() {
    super.initState();
    _controller = fw.AnimationController(
      vsync: this,
      duration: widget.duration,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    return _SizeProbe(
      onSize: (size) {
        if (size == _target) return;
        if (_current == Size.zero) {
          _current = size;
          _target = size;
          return;
        }
        setState(() {
          _from = _current;
          _target = size;
        });
        _controller.forward(from: 0);
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = fw.CurveTween(curve: widget.curve)
              .transform(_controller.value);
          final animated = Size(
            ui.lerpDouble(_from.width, _target.width, t)!,
            ui.lerpDouble(_from.height, _target.height, t)!,
          );
          _current = animated;
          return ClipRect(
            child: Align(
              alignment: widget.alignment,
              heightFactor: _target.height == 0
                  ? 1
                  : (animated.height / _target.height).clamp(0.0, 1.0),
              widthFactor: _target.width == 0
                  ? 1
                  : (animated.width / _target.width).clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// 测量子项实际尺寸的探针(内部管道)。
class _SizeProbe extends fw.SingleChildRenderObjectWidget {
  final fw.ValueChanged<Size> onSize;

  const _SizeProbe({required this.onSize, required super.child});

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderSizeProbe(onSize: onSize);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderSizeProbe renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class RenderSizeProbe extends RenderProxyBox {
  fw.ValueChanged<Size> onSize;
  Size _last = Size.zero;

  RenderSizeProbe({required this.onSize});

  @override
  void performLayout() {
    super.performLayout();
    if (size != _last) {
      _last = size;
      onSize(size);
    }
  }
}
