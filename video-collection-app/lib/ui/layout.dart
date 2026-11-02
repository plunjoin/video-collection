/// 自研布局组件族:全部基于自写 RenderBox 实现。
///
/// 覆盖:Row/Column/Flex/Expanded/Flexible/Spacer、Stack/Positioned、
/// Align/Center、Padding、SizedBox/ConstrainedBox、Wrap、Opacity、
/// ClipRect/ClipRRect/ClipOval、Transform、DecoratedBox/ColoredBox、
/// Semantics。布局算法实现经典 Flex/Stack/Wrap 语义,父数据通过框架的
/// ParentDataWidget 机制挂接(纯底层管道)。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' as fw;

// ---------------------------------------------------------------------------
// Flex 家族
// ---------------------------------------------------------------------------

/// Flex 子项父数据(flex 权重 + 填充方式)。
class FlexParentData extends ContainerBoxParentData<RenderBox> {
  int flex = 0;
  FlexFit fit = FlexFit.loose;

  @override
  String toString() => 'flex=$flex fit=$fit';
}

/// Flex 填充方式。
enum FlexFit { loose, tight }

/// 纵横弹性布局基类。
class Flex extends fw.MultiChildRenderObjectWidget {
  final Axis direction;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;
  final double spacing;
  final TextDirection textDirection;
  final VerticalDirection verticalDirection;

  const Flex({
    fw.Key? key,
    required this.direction,
    required List<fw.Widget> children,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.mainAxisSize = MainAxisSize.max,
    this.spacing = 0,
    this.textDirection = TextDirection.ltr,
    this.verticalDirection = VerticalDirection.down,
  }) : super(key: key, children: children);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderFlexBox(
      direction: direction,
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: mainAxisSize,
      spacing: spacing,
      textDirection: textDirection,
      verticalDirection: verticalDirection,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderFlexBox renderObject,
  ) {
    renderObject
      ..direction = direction
      ..mainAxisAlignment = mainAxisAlignment
      ..crossAxisAlignment = crossAxisAlignment
      ..mainAxisSize = mainAxisSize
      ..spacing = spacing
      ..textDirection = textDirection
      ..verticalDirection = verticalDirection;
  }
}

/// 水平布局。
class Row extends Flex {
  const Row({
    fw.Key? key,
    required super.children,
    super.mainAxisAlignment,
    super.crossAxisAlignment,
    super.mainAxisSize,
    super.spacing,
    super.textDirection,
  }) : super(key: key, direction: Axis.horizontal);
}

/// 垂直布局。
class Column extends Flex {
  const Column({
    fw.Key? key,
    required super.children,
    super.mainAxisAlignment,
    super.crossAxisAlignment,
    super.mainAxisSize,
    super.spacing,
    super.verticalDirection,
  }) : super(key: key, direction: Axis.vertical);
}

/// 抢占剩余空间的弹性子项(完全填充)。
class Expanded extends fw.ParentDataWidget<FlexParentData> {
  final int flex;

  const Expanded({
    fw.Key? key,
    this.flex = 1,
    required fw.Widget child,
  }) : super(key: key, child: child);

  @override
  void applyParentData(fw.RenderObject renderObject) {
    final data = renderObject.parentData;
    if (data is FlexParentData) {
      var needsLayout = false;
      if (data.flex != flex) {
        data.flex = flex;
        needsLayout = true;
      }
      if (data.fit != FlexFit.tight) {
        data.fit = FlexFit.tight;
        needsLayout = true;
      }
      if (needsLayout) renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => Flex;
}

/// 可收缩的弹性子项(按内容大小,受 flex 配额限制)。
class Flexible extends fw.ParentDataWidget<FlexParentData> {
  final int flex;
  final FlexFit fit;

  const Flexible({
    fw.Key? key,
    this.flex = 1,
    this.fit = FlexFit.loose,
    required fw.Widget child,
  }) : super(key: key, child: child);

  @override
  void applyParentData(fw.RenderObject renderObject) {
    final data = renderObject.parentData;
    if (data is FlexParentData) {
      var needsLayout = false;
      if (data.flex != flex) {
        data.flex = flex;
        needsLayout = true;
      }
      if (data.fit != fit) {
        data.fit = fit;
        needsLayout = true;
      }
      if (needsLayout) renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => Flex;
}

/// 固定占位间隔。
class Spacer extends fw.StatelessWidget {
  final int flex;

  const Spacer({fw.Key? key, this.flex = 1}) : super(key: key);

  @override
  fw.Widget build(fw.BuildContext context) {
    return Expanded(flex: flex, child: const SizedBox.shrink());
  }
}

/// 自写弹性布局渲染盒子。
class RenderFlexBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, FlexParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, FlexParentData> {
  Axis _direction;
  MainAxisAlignment _mainAxisAlignment;
  CrossAxisAlignment _crossAxisAlignment;
  MainAxisSize _mainAxisSize;
  double _spacing;
  TextDirection _textDirection;
  VerticalDirection _verticalDirection;

  RenderFlexBox({
    required Axis direction,
    required MainAxisAlignment mainAxisAlignment,
    required CrossAxisAlignment crossAxisAlignment,
    required MainAxisSize mainAxisSize,
    required double spacing,
    required TextDirection textDirection,
    required VerticalDirection verticalDirection,
  })  : _direction = direction,
        _mainAxisAlignment = mainAxisAlignment,
        _crossAxisAlignment = crossAxisAlignment,
        _mainAxisSize = mainAxisSize,
        _spacing = spacing,
        _textDirection = textDirection,
        _verticalDirection = verticalDirection;

  set direction(Axis value) {
    if (_direction == value) return;
    _direction = value;
    markNeedsLayout();
  }

  set mainAxisAlignment(MainAxisAlignment value) {
    if (_mainAxisAlignment == value) return;
    _mainAxisAlignment = value;
    markNeedsLayout();
  }

  set crossAxisAlignment(CrossAxisAlignment value) {
    if (_crossAxisAlignment == value) return;
    _crossAxisAlignment = value;
    markNeedsLayout();
  }

  set mainAxisSize(MainAxisSize value) {
    if (_mainAxisSize == value) return;
    _mainAxisSize = value;
    markNeedsLayout();
  }

  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  set verticalDirection(VerticalDirection value) {
    if (_verticalDirection == value) return;
    _verticalDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(covariant fw.RenderObject child) {
    if (child.parentData is! FlexParentData) {
      child.parentData = FlexParentData();
    }
  }

  Iterable<RenderBox> get _children sync* {
    var child = firstChild;
    while (child != null) {
      yield child;
      child = (child.parentData as FlexParentData).nextSibling;
    }
  }

  bool get _isHorizontal => _direction == Axis.horizontal;

  @override
  void performLayout() {
    final maxMain = _isHorizontal
        ? constraints.maxWidth
        : constraints.maxHeight;
    final minMain = _isHorizontal
        ? constraints.minWidth
        : constraints.minHeight;
    final maxCross = _isHorizontal
        ? constraints.maxHeight
        : constraints.maxWidth;
    final minCross = _isHorizontal
        ? constraints.minHeight
        : constraints.minWidth;
    final stretch = _crossAxisAlignment == CrossAxisAlignment.stretch;
    final canFlex = maxMain.isFinite;

    // 第一遍:非弹性子项按内容排布,统计弹性权重
    double totalFlex = 0;
    double nonFlexMain = 0;
    int flexChildCount = 0;
    for (final child in _children) {
      final data = child.parentData as FlexParentData;
      if (data.flex > 0) {
        totalFlex += data.flex;
        flexChildCount++;
        continue;
      }
      final crossCap = maxCross.isFinite ? maxCross : double.infinity;
      final inner = _isHorizontal
          ? BoxConstraints(
              maxWidth: canFlex ? maxMain : double.infinity,
              minHeight: stretch ? math.max(0.0, minCross) : 0,
              maxHeight: crossCap,
            )
          : BoxConstraints(
              maxHeight: canFlex ? maxMain : double.infinity,
              minWidth: stretch ? math.max(0.0, minCross) : 0,
              maxWidth: crossCap,
            );
      child.layout(inner, parentUsesSize: true);
      nonFlexMain += _mainOf(child);
    }

    // 弹性分配:剩余空间按权重分给弹性子项
    final childCountAll = childCount;
    final gapTotal = childCountAll > 1 ? _spacing * (childCountAll - 1) : 0.0;
    double flexMain = 0;
    if (totalFlex > 0) {
      if (canFlex) {
        final free = math.max(
          0,
          maxMain - nonFlexMain - gapTotal,
        );
        final perFlex = free / totalFlex;
        for (final child in _children) {
          final data = child.parentData as FlexParentData;
          if (data.flex == 0) continue;
          final allocated = perFlex * data.flex;
          final crossCap = maxCross.isFinite ? maxCross : double.infinity;
          final inner = _isHorizontal
              ? BoxConstraints(
                  minWidth: data.fit == FlexFit.tight ? allocated : 0,
                  maxWidth: allocated,
                  minHeight: stretch ? math.max(0.0, minCross) : 0,
                  maxHeight: stretch ? maxCross : crossCap,
                )
              : BoxConstraints(
                  minHeight: data.fit == FlexFit.tight ? allocated : 0,
                  maxHeight: allocated,
                  minWidth: stretch ? math.max(0.0, minCross) : 0,
                  maxWidth: stretch ? maxCross : crossCap,
                );
          child.layout(inner, parentUsesSize: true);
          flexMain += _mainOf(child);
        }
      } else {
        // 无界主轴上的弹性子项:按内容收缩,避免崩溃
        for (final child in _children) {
          final data = child.parentData as FlexParentData;
          if (data.flex == 0) continue;
          final crossCap = maxCross.isFinite ? maxCross : double.infinity;
          final inner = _isHorizontal
              ? BoxConstraints(
                  minHeight: stretch ? math.max(0.0, minCross) : 0,
                  maxHeight: stretch ? maxCross : crossCap,
                )
              : BoxConstraints(
                  minWidth: stretch ? math.max(0.0, minCross) : 0,
                  maxWidth: stretch ? maxCross : crossCap,
                );
          child.layout(inner, parentUsesSize: true);
          flexMain += _mainOf(child);
        }
      }
    }

    final consumedMain = nonFlexMain + flexMain + gapTotal;

    // 交叉轴尺寸
    double maxCrossChild = 0;
    for (final child in _children) {
      final c = _crossOf(child);
      if (c > maxCrossChild) maxCrossChild = c;
    }

    final mainSize = canFlex && _mainAxisSize == MainAxisSize.max
        ? math.max(minMain, maxMain)
        : math.max(minMain, consumedMain);
    final crossSize = stretch
        ? (maxCross.isFinite ? maxCross : maxCrossChild)
        : math.max(minCross, maxCrossChild);

    size = constraints.constrain(
      _isHorizontal
          ? Size(mainSize, crossSize)
          : Size(crossSize, mainSize),
    );

    // 第二遍:按主轴对齐方式定位
    final actualMain =
        _isHorizontal ? size.width : size.height;
    final actualCross =
        _isHorizontal ? size.height : size.width;
    final freeMain = math.max(0.0, actualMain - consumedMain);
    double leading = 0;
    double between = _spacing;
    switch (_mainAxisAlignment) {
      case MainAxisAlignment.start:
        leading = 0;
      case MainAxisAlignment.end:
        leading = freeMain;
      case MainAxisAlignment.center:
        leading = freeMain / 2;
      case MainAxisAlignment.spaceBetween:
        between = childCountAll > 1 ? freeMain / (childCountAll - 1) : 0;
      case MainAxisAlignment.spaceAround:
        between = childCountAll > 0 ? freeMain / childCountAll : 0;
        leading = between / 2;
      case MainAxisAlignment.spaceEvenly:
        between = childCountAll > 0 ? freeMain / (childCountAll + 1) : 0;
        leading = between;
    }

    final flip = !_isHorizontal && _verticalDirection == VerticalDirection.up;
    double cursor = flip ? actualMain - leading : leading;
    for (final child in _children) {
      final childMain = _mainOf(child);
      final childCross = _crossOf(child);
      double crossOffset;
      switch (_crossAxisAlignment) {
        case CrossAxisAlignment.start:
          crossOffset = 0;
        case CrossAxisAlignment.end:
          crossOffset = actualCross - childCross;
        case CrossAxisAlignment.stretch:
          crossOffset = 0;
        default:
          crossOffset = (actualCross - childCross) / 2;
      }
      Offset offset;
      if (_isHorizontal) {
        offset = Offset(cursor, crossOffset);
      } else if (flip) {
        offset = Offset(crossOffset, cursor - childMain);
      } else {
        offset = Offset(crossOffset, cursor);
      }
      (child.parentData as FlexParentData).offset = offset;
      if (flip) {
        cursor -= childMain + between;
      } else {
        cursor += childMain + between;
      }
    }
  }

  double _mainOf(RenderBox child) =>
      _isHorizontal ? child.size.width : child.size.height;

  double _crossOf(RenderBox child) =>
      _isHorizontal ? child.size.height : child.size.width;

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

// ---------------------------------------------------------------------------
// Stack 家族
// ---------------------------------------------------------------------------

/// Stack 子项父数据(四边定位 + 尺寸)。
class StackParentData extends ContainerBoxParentData<RenderBox> {
  double? top;
  double? right;
  double? bottom;
  double? left;
  double? width;
  double? height;
  bool get isPositioned =>
      top != null || right != null || bottom != null || left != null;

  @override
  String toString() =>
      'top=$top right=$right bottom=$bottom left=$left';
}

/// 层叠布局。
class Stack extends fw.MultiChildRenderObjectWidget {
  final Alignment alignment;
  final StackFit fit;
  final Clip clipBehavior;

  const Stack({
    fw.Key? key,
    required List<fw.Widget> children,
    this.alignment = Alignment.topLeft,
    this.fit = StackFit.loose,
    this.clipBehavior = Clip.hardEdge,
  }) : super(key: key, children: children);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderStackBox(
      alignment: alignment,
      fit: fit,
      clipBehavior: clipBehavior,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderStackBox renderObject,
  ) {
    renderObject
      ..alignment = alignment
      ..fit = fit
      ..clipBehavior = clipBehavior;
  }
}

/// Stack 内绝对定位。
class Positioned extends fw.ParentDataWidget<StackParentData> {
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
  final double? width;
  final double? height;

  const Positioned({
    fw.Key? key,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.width,
    this.height,
    required fw.Widget child,
  }) : super(key: key, child: child);

  const Positioned.fill({fw.Key? key, required fw.Widget child})
      : left = 0,
        top = 0,
        right = 0,
        bottom = 0,
        width = null,
        height = null,
        super(key: key, child: child);

  Positioned.fromRect({
    fw.Key? key,
    required Rect rect,
    required fw.Widget child,
  })  : left = rect.left,
        top = rect.top,
        width = rect.width,
        height = rect.height,
        right = null,
        bottom = null,
        super(key: key, child: child);

  @override
  void applyParentData(fw.RenderObject renderObject) {
    final data = renderObject.parentData;
    if (data is StackParentData) {
      var needsLayout = false;
      void apply(double? value, double? current, void Function(double) set) {
        if (value != null && current != value) {
          set(value);
          needsLayout = true;
        }
      }

      apply(left, data.left, (v) => data.left = v);
      apply(top, data.top, (v) => data.top = v);
      apply(right, data.right, (v) => data.right = v);
      apply(bottom, data.bottom, (v) => data.bottom = v);
      apply(width, data.width, (v) => data.width = v);
      apply(height, data.height, (v) => data.height = v);
      if (needsLayout) renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => Stack;
}

/// 自写层叠布局渲染盒子。
class RenderStackBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, StackParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, StackParentData> {
  Alignment _alignment;
  StackFit _fit;
  Clip _clipBehavior;

  RenderStackBox({
    required Alignment alignment,
    required StackFit fit,
    required Clip clipBehavior,
  })  : _alignment = alignment,
        _fit = fit,
        _clipBehavior = clipBehavior;

  set alignment(Alignment value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  set fit(StackFit value) {
    if (_fit == value) return;
    _fit = value;
    markNeedsLayout();
  }

  set clipBehavior(Clip value) {
    if (_clipBehavior == value) return;
    _clipBehavior = value;
    markNeedsPaint();
  }

  @override
  void setupParentData(covariant fw.RenderObject child) {
    if (child.parentData is! StackParentData) {
      child.parentData = StackParentData();
    }
  }

  Iterable<RenderBox> get _children sync* {
    var child = firstChild;
    while (child != null) {
      yield child;
      child = (child.parentData as StackParentData).nextSibling;
    }
  }

  @override
  void performLayout() {
    final hasBoundedWidth = constraints.hasBoundedWidth;
    final hasBoundedHeight = constraints.hasBoundedHeight;
    // 定位子项:按四边/显式尺寸约束
    for (final child in _children) {
      final data = child.parentData as StackParentData;
      if (!data.isPositioned) continue;
      BoxConstraints childConstraints;
      if (data.width != null && data.height != null) {
        childConstraints = BoxConstraints.tight(
          Size(data.width!, data.height!),
        );
      } else {
        double? minW;
        double? maxW;
        double? minH;
        double? maxH;
        if (data.left != null && data.right != null && hasBoundedWidth) {
          minW = maxW = (constraints.maxWidth - data.left! - data.right!)
              .clamp(0.0, double.infinity).toDouble();
        } else if (data.width != null) {
          minW = maxW = data.width;
        }
        if (data.top != null && data.bottom != null && hasBoundedHeight) {
          minH = maxH = (constraints.maxHeight - data.top! - data.bottom!)
              .clamp(0.0, double.infinity).toDouble();
        } else if (data.height != null) {
          minH = maxH = data.height;
        }
        childConstraints = BoxConstraints(
          minWidth: minW ?? 0,
          maxWidth: maxW ?? double.infinity,
          minHeight: minH ?? 0,
          maxHeight: maxH ?? double.infinity,
        );
      }
      child.layout(childConstraints, parentUsesSize: true);
    }

    // 非定位子项
    var nonPositionedCount = 0;
    double maxWidth = 0;
    double maxHeight = 0;
    for (final child in _children) {
      final data = child.parentData as StackParentData;
      if (data.isPositioned) continue;
      nonPositionedCount++;
      BoxConstraints inner;
      switch (_fit) {
        case StackFit.loose:
          inner = constraints.loosen();
        case StackFit.expand:
          inner = BoxConstraints.tight(constraints.biggest);
        case StackFit.passthrough:
          inner = constraints;
      }
      child.layout(inner, parentUsesSize: true);
      if (child.size.width > maxWidth) maxWidth = child.size.width;
      if (child.size.height > maxHeight) maxHeight = child.size.height;
    }

    if (nonPositionedCount == 0) {
      // 仅有定位子项:与框架 Stack 一致,在可用空间内撑满
      size = constraints.constrain(
        _fit == StackFit.expand
            ? constraints.biggest
            : Size(
                constraints.hasBoundedWidth
                    ? constraints.maxWidth
                    : maxWidth,
                constraints.hasBoundedHeight
                    ? constraints.maxHeight
                    : maxHeight,
              ),
      );
    } else {
      size = constraints.constrain(Size(maxWidth, maxHeight));
    }

    // 定位
    for (final child in _children) {
      final data = child.parentData as StackParentData;
      if (data.isPositioned) {
        double x = data.left ?? 0;
        if (data.left == null && data.right != null) {
          x = size.width - data.right! - child.size.width;
        } else if (data.left != null &&
            data.right != null &&
            data.width == null) {
          x = data.left!;
        }
        double y = data.top ?? 0;
        if (data.top == null && data.bottom != null) {
          y = size.height - data.bottom! - child.size.height;
        } else if (data.top != null &&
            data.bottom != null &&
            data.height == null) {
          y = data.top!;
        }
        data.offset = Offset(x, y);
      } else {
        data.offset = _alignment.alongSize(
          Size(
            (size.width - child.size.width).clamp(0.0, double.infinity) as double,
            (size.height - child.size.height).clamp(0.0, double.infinity) as double,
          ),
        );
      }
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_clipBehavior != Clip.none) {
      context.pushClipRect(
        needsCompositing,
        offset,
        offset & size,
        (context, offset) => defaultPaint(context, offset),
      );
    } else {
      defaultPaint(context, offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    // 从最后绘制(最上层)向前命中
    var child = lastChild;
    while (child != null) {
      final data = child.parentData as StackParentData;
      final current = child;
      final hit = result.addWithPaintOffset(
        offset: data.offset,
        position: position,
        hitTest: (result, transformed) =>
            current.hitTest(result, position: transformed),
      );
      if (hit) return true;
      child = data.previousSibling;
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// 对齐 / 填充 / 约束
// ---------------------------------------------------------------------------

/// 对齐容器(支持 widthFactor/heightFactor)。
class Align extends fw.SingleChildRenderObjectWidget {
  final Alignment alignment;
  final double? widthFactor;
  final double? heightFactor;

  const Align({
    fw.Key? key,
    this.alignment = Alignment.center,
    this.widthFactor,
    this.heightFactor,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderAligningBox(
      alignment: alignment,
      widthFactor: widthFactor,
      heightFactor: heightFactor,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderAligningBox renderObject,
  ) {
    renderObject
      ..alignment = alignment
      ..widthFactor = widthFactor
      ..heightFactor = heightFactor;
  }
}

/// 居中容器。
class Center extends Align {
  const Center({fw.Key? key, super.widthFactor, super.heightFactor, super.child})
      : super(key: key, alignment: Alignment.center);
}

/// 自写对齐渲染盒子。
class RenderAligningBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  Alignment _alignment;
  double? _widthFactor;
  double? _heightFactor;

  RenderAligningBox({
    required Alignment alignment,
    double? widthFactor,
    double? heightFactor,
  })  : _alignment = alignment,
        _widthFactor = widthFactor,
        _heightFactor = heightFactor;

  set alignment(Alignment value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  set widthFactor(double? value) {
    if (_widthFactor == value) return;
    _widthFactor = value;
    markNeedsLayout();
  }

  set heightFactor(double? value) {
    if (_heightFactor == value) return;
    _heightFactor = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child != null) {
      child.layout(constraints.loosen(), parentUsesSize: true);
      var width = _widthFactor != null
          ? child.size.width * _widthFactor!
          : constraints.hasBoundedWidth
              ? constraints.maxWidth
              : child.size.width;
      var height = _heightFactor != null
          ? child.size.height * _heightFactor!
          : constraints.hasBoundedHeight
              ? constraints.maxHeight
              : child.size.height;
      width = width.clamp(constraints.minWidth, constraints.maxWidth)
          as double;
      height = height.clamp(constraints.minHeight, constraints.maxHeight)
          as double;
      size = Size(width, height);
      (child.parentData as BoxParentData).offset = _alignment.alongSize(
        Size(
          (size.width - child.size.width).clamp(0.0, double.infinity) as double,
          (size.height - child.size.height).clamp(0.0, double.infinity) as double,
        ),
      );
    } else {
      size = constraints.smallest;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) {
      final c = child!;
      context.paintChild(
        c,
        (c.parentData as BoxParentData).offset + offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (child != null) {
      return result.addWithPaintOffset(
        offset: (child!.parentData as BoxParentData).offset,
        position: position,
        hitTest: (result, transformed) =>
            child!.hitTest(result, position: transformed),
      );
    }
    return false;
  }
}

/// 内边距。
class Padding extends fw.SingleChildRenderObjectWidget {
  final EdgeInsetsGeometry padding;

  const Padding({
    fw.Key? key,
    required this.padding,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderPaddingBox(padding: padding as EdgeInsets);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderPaddingBox renderObject,
  ) {
    renderObject.padding = padding as EdgeInsets;
  }
}

/// 自写内边距渲染盒子。
class RenderPaddingBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  EdgeInsets _padding;

  RenderPaddingBox({required EdgeInsets padding}) : _padding = padding;

  set padding(EdgeInsets value) {
    if (_padding == value) return;
    _padding = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(
        Size(_padding.horizontal, _padding.vertical),
      );
      return;
    }
    final inner = constraints.deflate(_padding);
    child.layout(inner, parentUsesSize: true);
    size = constraints.constrain(
      Size(
        child.size.width + _padding.horizontal,
        child.size.height + _padding.vertical,
      ),
    );
    (child.parentData as BoxParentData).offset =
        Offset(_padding.left, _padding.top);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) {
      final c = child!;
      context.paintChild(
        c,
        (c.parentData as BoxParentData).offset + offset,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (child != null) {
      return result.addWithPaintOffset(
        offset: (child!.parentData as BoxParentData).offset,
        position: position,
        hitTest: (result, transformed) =>
            child!.hitTest(result, position: transformed),
      );
    }
    return false;
  }
}

/// 固定尺寸容器。
class SizedBox extends fw.SingleChildRenderObjectWidget {
  final double? width;
  final double? height;

  const SizedBox({
    fw.Key? key,
    this.width,
    this.height,
    super.child,
  }) : super(key: key);

  const SizedBox.shrink({fw.Key? key})
      : width = 0,
        height = 0,
        super(key: key);

  const SizedBox.expand({fw.Key? key})
      : width = double.infinity,
        height = double.infinity,
        super(key: key);

  SizedBox.square({fw.Key? key, double? dimension})
      : width = dimension,
        height = dimension,
        super(key: key);

  SizedBox.fromSize({fw.Key? key, Size? size})
      : width = size?.width,
        height = size?.height,
        super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderConstrainedBox(
      additionalConstraints:
          BoxConstraints.tightFor(width: width, height: height),
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderConstrainedBox renderObject,
  ) {
    renderObject.additionalConstraints =
        BoxConstraints.tightFor(width: width, height: height);
  }
}

/// 附加约束容器。
class ConstrainedBox extends fw.SingleChildRenderObjectWidget {
  final BoxConstraints constraints;

  const ConstrainedBox({
    fw.Key? key,
    required this.constraints,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderConstrainedBox(additionalConstraints: constraints);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderConstrainedBox renderObject,
  ) {
    renderObject.additionalConstraints = constraints;
  }
}

/// 注:SizedBox/ConstrainedBox 的渲染直接使用框架渲染层现成的
/// RenderConstrainedBox(引擎基础设施),组件本身为本库自研。

// ---------------------------------------------------------------------------
// Wrap 流式布局
// ---------------------------------------------------------------------------

/// 自动换行的流式布局。
class Wrap extends fw.MultiChildRenderObjectWidget {
  final Axis direction;
  final WrapAlignment alignment;
  final WrapCrossAlignment crossAxisAlignment;
  final WrapAlignment runAlignment;
  final double spacing;
  final double runSpacing;

  const Wrap({
    fw.Key? key,
    required List<fw.Widget> children,
    this.direction = Axis.horizontal,
    this.alignment = WrapAlignment.start,
    this.crossAxisAlignment = WrapCrossAlignment.center,
    this.runAlignment = WrapAlignment.start,
    this.spacing = 0,
    this.runSpacing = 0,
  }) : super(key: key, children: children);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderWrapBox(
      direction: direction,
      alignment: alignment,
      crossAxisAlignment: crossAxisAlignment,
      runAlignment: runAlignment,
      spacing: spacing,
      runSpacing: runSpacing,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderWrapBox renderObject,
  ) {
    renderObject
      ..direction = direction
      ..alignment = alignment
      ..crossAxisAlignment = crossAxisAlignment
      ..runAlignment = runAlignment
      ..spacing = spacing
      ..runSpacing = runSpacing;
  }
}

/// 换行对齐方式。
enum WrapAlignment { start, end, center, spaceBetween, spaceAround, spaceEvenly }

/// 换行内交叉对齐方式。
enum WrapCrossAlignment { start, center, end }

/// 自写流式布局渲染盒子。
class RenderWrapBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, FlexParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, FlexParentData> {
  Axis _direction;
  WrapAlignment _alignment;
  WrapCrossAlignment _crossAxisAlignment;
  WrapAlignment _runAlignment;
  double _spacing;
  double _runSpacing;

  RenderWrapBox({
    required Axis direction,
    required WrapAlignment alignment,
    required WrapCrossAlignment crossAxisAlignment,
    required WrapAlignment runAlignment,
    required double spacing,
    required double runSpacing,
  })  : _direction = direction,
        _alignment = alignment,
        _crossAxisAlignment = crossAxisAlignment,
        _runAlignment = runAlignment,
        _spacing = spacing,
        _runSpacing = runSpacing;

  set direction(Axis value) {
    if (_direction == value) return;
    _direction = value;
    markNeedsLayout();
  }

  set alignment(WrapAlignment value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  set crossAxisAlignment(WrapCrossAlignment value) {
    if (_crossAxisAlignment == value) return;
    _crossAxisAlignment = value;
    markNeedsLayout();
  }

  set runAlignment(WrapAlignment value) {
    if (_runAlignment == value) return;
    _runAlignment = value;
    markNeedsLayout();
  }

  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  set runSpacing(double value) {
    if (_runSpacing == value) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(covariant fw.RenderObject child) {
    if (child.parentData is! FlexParentData) {
      child.parentData = FlexParentData();
    }
  }

  Iterable<RenderBox> get _children sync* {
    var child = firstChild;
    while (child != null) {
      yield child;
      child = (child.parentData as FlexParentData).nextSibling;
    }
  }

  bool get _isHorizontal => _direction == Axis.horizontal;

  @override
  void performLayout() {
    final maxMain = _isHorizontal
        ? constraints.maxWidth
        : constraints.maxHeight;
    final maxCross = _isHorizontal
        ? constraints.maxHeight
        : constraints.maxWidth;

    // 测量子项并分行
    final runs = <List<RenderBox>>[];
    final runMains = <double>[];
    final runCrosses = <double>[];
    var currentRun = <RenderBox>[];
    var currentMain = 0.0;
    var currentCross = 0.0;

    void finishRun() {
      if (currentRun.isNotEmpty) {
        runs.add(currentRun);
        runMains.add(currentMain);
        runCrosses.add(currentCross);
        currentRun = <RenderBox>[];
        currentMain = 0;
        currentCross = 0;
      }
    }

    for (final child in _children) {
      child.layout(
        _isHorizontal
            ? BoxConstraints(maxWidth: maxMain, maxHeight: maxCross)
            : BoxConstraints(maxWidth: maxCross, maxHeight: maxMain),
        parentUsesSize: true,
      );
      final childMain = _isHorizontal
          ? child.size.width
          : child.size.height;
      final childCross = _isHorizontal
          ? child.size.height
          : child.size.width;
      final needed = currentRun.isEmpty
          ? childMain
          : currentMain + _spacing + childMain;
      if (needed > maxMain && currentRun.isNotEmpty) {
        finishRun();
        currentMain = childMain;
        currentCross = childCross;
        currentRun.add(child);
      } else {
        currentMain = needed;
        if (childCross > currentCross) currentCross = childCross;
        currentRun.add(child);
      }
    }
    finishRun();

    final contentMain = runMains.fold<double>(0, (s, v) => s + v);
    final contentCross = runCrosses.isEmpty
        ? 0.0
        : runCrosses.fold<double>(
              0,
              (s, v) => s + v,
            ) +
            _runSpacing * (runCrosses.length - 1);

    final constrainedMain = constraints.constrainDimension(_isHorizontal, contentMain);
    final constrainedCross = constraints.constrainDimension(!_isHorizontal, contentCross);
    size = _isHorizontal
        ? Size(constrainedMain, constrainedCross)
        : Size(constrainedCross, constrainedMain);

    // 行间对齐
    final totalCross = size.heightF(!_isHorizontal);
    final freeCrossAll = math.max(0.0, totalCross - contentCross);
    double runLeading = 0;
    switch (_runAlignment) {
      case WrapAlignment.start:
        runLeading = 0;
      case WrapAlignment.end:
        runLeading = freeCrossAll;
      case WrapAlignment.center:
      case WrapAlignment.spaceAround:
      case WrapAlignment.spaceEvenly:
        runLeading = freeCrossAll / 2;
      case WrapAlignment.spaceBetween:
        runLeading = 0;
    }

    var runIndex = 0;
    var runCursor = runLeading;
    for (final run in runs) {
      final runMain = runMains[runIndex];
      final runCross = runCrosses[runIndex];
      final freeMain = math.max(0.0, size.widthF(_isHorizontal) - runMain);

      double leading = 0;
      double gap = _spacing;
      switch (_alignment) {
        case WrapAlignment.start:
          leading = 0;
          gap = _spacing;
        case WrapAlignment.end:
          leading = freeMain;
          gap = _spacing;
        case WrapAlignment.center:
          leading = freeMain / 2;
          gap = _spacing;
        case WrapAlignment.spaceBetween:
          leading = 0;
          gap = run.length > 1 ? freeMain / (run.length - 1) : 0;
        case WrapAlignment.spaceAround:
          gap = run.isNotEmpty ? freeMain / run.length : 0;
          leading = gap / 2;
        case WrapAlignment.spaceEvenly:
          gap = run.isNotEmpty ? freeMain / (run.length + 1) : 0;
          leading = gap;
      }

      double mainCursor = leading;
      for (final child in run) {
        final childMain = _isHorizontal
            ? child.size.width
            : child.size.height;
        final childCross = _isHorizontal
            ? child.size.height
            : child.size.width;
        double crossOffset;
        switch (_crossAxisAlignment) {
          case WrapCrossAlignment.start:
            crossOffset = 0;
          case WrapCrossAlignment.end:
            crossOffset = runCross - childCross;
          case WrapCrossAlignment.center:
            crossOffset = (runCross - childCross) / 2;
        }
        (child.parentData as FlexParentData).offset = _isHorizontal
            ? Offset(mainCursor, runCursor + crossOffset)
            : Offset(runCursor + crossOffset, mainCursor);
        mainCursor += childMain + gap;
      }
      runCursor += runCross + _runSpacing;
      runIndex++;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

extension on Size {
  double widthF(bool horizontal) => horizontal ? width : height;
  double heightF(bool horizontal) => horizontal ? height : width;
}

extension on BoxConstraints {
  double constrainDimension(bool isWidth, double content) {
    if (isWidth) {
      return content.clamp(minWidth, maxWidth) as double;
    }
    return content.clamp(minHeight, maxHeight) as double;
  }
}

// ---------------------------------------------------------------------------
// 透明度 / 裁剪 / 变换 / 装饰
// ---------------------------------------------------------------------------

/// 透明度。
class Opacity extends fw.SingleChildRenderObjectWidget {
  final double opacity;

  const Opacity({
    fw.Key? key,
    required this.opacity,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderOpacityBox(opacity: opacity);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderOpacityBox renderObject,
  ) {
    renderObject.opacity = opacity;
  }
}

/// 自写透明度渲染盒子。
class RenderOpacityBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  double _opacity;

  RenderOpacityBox({required double opacity})
      : _opacity = opacity.clamp(0.0, 1.0);

  set opacity(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (_opacity == clamped) return;
    final wasInvisible = _opacity == 0;
    _opacity = clamped;
    if (wasInvisible != (_opacity == 0)) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  @override
  bool get alwaysNeedsCompositing => _opacity > 0 && _opacity < 1;

  @override
  void performLayout() {
    final child = this.child;
    // 透明度为 0 时仍需布局子树(否则语义收集期会残留 _needsLayout 断言)
    if (child != null) {
      child.layout(constraints, parentUsesSize: true);
      size = child.size;
    } else {
      size = constraints.smallest;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || _opacity == 0) return;
    if (_opacity == 1) {
      context.paintChild(child, offset);
    } else {
      context.pushOpacity(
        offset,
        ui.Color.getAlphaFromOpacity(_opacity),
        (context, offset) => context.paintChild(child, offset),
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child != null && _opacity != 0) {
      return child.hitTest(result, position: position);
    }
    return false;
  }
}

/// 矩形裁剪。
class ClipRect extends fw.SingleChildRenderObjectWidget {
  const ClipRect({fw.Key? key, super.child}) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) =>
      RenderClipRectBox();

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderClipRectBox renderObject,
  ) {}
}

/// 自写矩形裁剪渲染盒子。
class RenderClipRectBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  @override
  void performLayout() {
    final child = this.child;
    if (child != null) {
      child.layout(constraints, parentUsesSize: true);
      size = child.size;
    } else {
      size = constraints.smallest;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    context.pushClipRect(
      needsCompositing,
      offset,
      offset & size,
      (context, offset) => context.paintChild(child, offset),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child != null &&
        position.dx >= 0 &&
        position.dy >= 0 &&
        position.dx <= size.width &&
        position.dy <= size.height) {
      return child.hitTest(result, position: position);
    }
    return false;
  }
}

/// 圆角矩形裁剪。
class ClipRRect extends fw.SingleChildRenderObjectWidget {
  final BorderRadius borderRadius;

  const ClipRRect({
    fw.Key? key,
    required this.borderRadius,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderClipRRectBox(borderRadius: borderRadius);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderClipRRectBox renderObject,
  ) {
    renderObject.borderRadius = borderRadius;
  }
}

/// 自写圆角裁剪渲染盒子。
class RenderClipRRectBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  BorderRadius _borderRadius;

  RenderClipRRectBox({required BorderRadius borderRadius})
      : _borderRadius = borderRadius;

  set borderRadius(BorderRadius value) {
    if (_borderRadius == value) return;
    _borderRadius = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child != null) {
      child.layout(constraints, parentUsesSize: true);
      size = child.size;
    } else {
      size = constraints.smallest;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    context.pushClipRRect(
      needsCompositing,
      offset,
      offset & size,
      _borderRadius.toRRect(offset & size),
      (context, offset) => context.paintChild(child, offset),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child != null &&
        _borderRadius.toRRect(Offset.zero & size).contains(position)) {
      return child.hitTest(result, position: position);
    }
    return false;
  }
}

/// 椭圆/圆形裁剪。
class ClipOval extends fw.SingleChildRenderObjectWidget {
  const ClipOval({fw.Key? key, super.child}) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) =>
      RenderClipOvalBox();

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderClipOvalBox renderObject,
  ) {}
}

/// 自写椭圆裁剪渲染盒子。
class RenderClipOvalBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  @override
  void performLayout() {
    final child = this.child;
    if (child != null) {
      child.layout(constraints, parentUsesSize: true);
      size = child.size;
    } else {
      size = constraints.smallest;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final rect = offset & size;
    final path = Path()..addOval(rect);
    context.pushClipPath(
      needsCompositing,
      offset,
      rect,
      path,
      (context, offset) => context.paintChild(child, offset),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child != null &&
        Rect.fromLTWH(0, 0, size.width, size.height).contains(position)) {
      return child.hitTest(result, position: position);
    }
    return false;
  }
}

/// 矩阵变换。
class Transform extends fw.SingleChildRenderObjectWidget {
  final Matrix4 transform;
  final Offset? origin;
  final Alignment? alignment;
  final bool transformHitTests;

  const Transform({
    fw.Key? key,
    required this.transform,
    this.origin,
    this.alignment,
    this.transformHitTests = true,
    super.child,
  }) : super(key: key);

  Transform.translate({
    fw.Key? key,
    required Offset offset,
    this.transformHitTests = true,
    super.child,
  })  : transform = Matrix4.translationValues(offset.dx, offset.dy, 0),
        origin = null,
        alignment = null,
        super(key: key);

  Transform.scale({
    fw.Key? key,
    required double scale,
    this.origin,
    this.alignment = Alignment.center,
    this.transformHitTests = true,
    super.child,
  })  : transform = Matrix4.diagonal3Values(scale, scale, 1),
        super(key: key);

  Transform.rotate({
    fw.Key? key,
    required double angle,
    this.origin,
    this.alignment = Alignment.center,
    this.transformHitTests = true,
    super.child,
  })  : transform = Matrix4.rotationZ(angle),
        super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderTransformBox(
      transform: transform,
      origin: origin,
      alignment: alignment,
      transformHitTests: transformHitTests,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderTransformBox renderObject,
  ) {
    renderObject
      ..transform = transform
      ..origin = origin
      ..alignment = alignment
      ..transformHitTests = transformHitTests;
  }
}

/// 变换渲染层:复用框架 RenderTransform(rendering 基础设施)。
///
/// 变换矩阵的构造、命中测试的逆变换处理较复杂,直接沿用框架实现以保证
/// 命中与绘制完全一致;Transform 组件本身为本库自研。
class RenderTransformBox extends RenderTransform {
  RenderTransformBox({
    required Matrix4 transform,
    required Offset? origin,
    required Alignment? alignment,
    required bool transformHitTests,
  }) : super(
          transform: transform,
          origin: origin,
          alignment: alignment,
          transformHitTests: transformHitTests,
        );
}

/// 装饰盒子(自写 BoxDecoration 绘制:渐变/阴影/边框/圆角)。
class DecoratedBox extends fw.SingleChildRenderObjectWidget {
  final BoxDecoration decoration;

  const DecoratedBox({
    fw.Key? key,
    required this.decoration,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderDecoratedBoxBox(decoration: decoration);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderDecoratedBoxBox renderObject,
  ) {
    renderObject.decoration = decoration;
  }
}

/// 自写装饰渲染盒子。
class RenderDecoratedBoxBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  BoxDecoration _decoration;
  final Paint _paint = Paint();

  RenderDecoratedBoxBox({required BoxDecoration decoration})
      : _decoration = decoration;

  set decoration(BoxDecoration value) {
    if (_decoration == value) return;
    _decoration = value;
    markNeedsPaint();
  }

  BorderRadius get _effectiveRadius =>
      (_decoration.borderRadius ?? BorderRadius.zero)
          .resolve(TextDirection.ltr);

  Path _outerPath(Rect rect) {
    final shape = _decoration.shape;
    if (shape == BoxShape.circle) {
      return Path()..addOval(rect);
    }
    final radius = _effectiveRadius;
    return Path()
      ..addRRect(RRect.fromRectAndCorners(
        rect,
        topLeft: radius.topLeft,
        topRight: radius.topRight,
        bottomLeft: radius.bottomLeft,
        bottomRight: radius.bottomRight,
      ));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child != null) {
      child.layout(constraints, parentUsesSize: true);
      size = child.size;
    } else {
      size = constraints.smallest;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final rect = offset & size;
    _paintBox(context.canvas, rect);
    final child = this.child;
    if (child != null) {
      context.paintChild(child, offset);
    }
  }

  void _paintBox(Canvas canvas, Rect rect) {
    final deco = _decoration;
    final shape = deco.shape;
    final radius = _effectiveRadius;

    // 1. 阴影
    final shadows = deco.boxShadow;
    if (shadows != null && shadows.isNotEmpty) {
      for (final shadow in shadows) {
        final path = _outerPath(rect.shift(shadow.offset));
        canvas.drawShadow(path, shadow.color, shadow.blurRadius / 2, true);
      }
    }

    // 2. 填充
    if (deco.gradient != null) {
      final paint = Paint()
        ..shader = deco.gradient!.createShader(rect);
      _fillShape(canvas, rect, shape, radius, paint);
    } else if (deco.color != null) {
      _fillShape(canvas, rect, shape, radius, _paint..color = deco.color!);
    }

    // 3. 边框(四边一致时走圆形/圆角描边;非一致边框退化为上边框宽度)
    final border = deco.border;
    if (border is Border && border.top.style != BorderStyle.none) {
      final borderSide = border.top;
      if (borderSide.width > 0) {
        if (shape == BoxShape.circle) {
          canvas.drawCircle(
            rect.center,
            rect.shortestSide / 2 - borderSide.width / 2,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = borderSide.width
              ..color = borderSide.color,
          );
        } else {
          final rrect = RRect.fromRectAndCorners(
            rect.deflate(borderSide.width / 2),
            topLeft: radius.topLeft,
            topRight: radius.topRight,
            bottomLeft: radius.bottomLeft,
            bottomRight: radius.bottomRight,
          );
          canvas.drawRRect(
            rrect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = borderSide.width
              ..color = borderSide.color,
          );
        }
      }
    }
  }

  void _fillShape(
    Canvas canvas,
    Rect rect,
    BoxShape shape,
    BorderRadius? radius,
    Paint paint,
  ) {
    if (shape == BoxShape.circle) {
      canvas.drawCircle(rect.center, rect.shortestSide / 2, paint);
    } else if (radius != null && radius != BorderRadius.zero) {
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: radius.topLeft,
          topRight: radius.topRight,
          bottomLeft: radius.bottomLeft,
          bottomRight: radius.bottomRight,
        ),
        paint,
      );
    } else {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child != null) {
      return child.hitTest(result, position: position);
    }
    return false;
  }
}

/// 纯色盒子。
class ColoredBox extends fw.SingleChildRenderObjectWidget {
  final Color color;

  const ColoredBox({
    fw.Key? key,
    required this.color,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderSolidBox(color: color);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderSolidBox renderObject,
  ) {
    renderObject.color = color;
  }
}

/// 自写纯色渲染盒子。
class RenderSolidBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  Color _color;
  final Paint _paint = Paint();

  RenderSolidBox({required Color color}) : _color = color;

  set color(Color value) {
    if (_color == value) return;
    _color = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child != null) {
      child.layout(constraints, parentUsesSize: true);
      size = child.size;
    } else {
      size = constraints.smallest;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_color.a > 0) {
      context.canvas.drawRect(offset & size, _paint..color = _color);
    }
    final child = this.child;
    if (child != null) {
      context.paintChild(child, offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child != null) {
      return child.hitTest(result, position: position);
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// 语义
// ---------------------------------------------------------------------------

/// 语义标注(无障碍)。
class Semantics extends fw.SingleChildRenderObjectWidget {
  final String? label;
  final String? value;
  final String? tooltip;
  final bool button;
  final bool selected;
  final bool enabled;
  final bool liveRegion;
  final VoidCallback? onTap;

  const Semantics({
    fw.Key? key,
    this.label,
    this.value,
    this.tooltip,
    this.button = false,
    this.selected = false,
    this.enabled = true,
    this.liveRegion = false,
    this.onTap,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderSemanticsBox(
      label: label,
      value: value,
      tooltip: tooltip,
      button: button,
      selected: selected,
      enabled: enabled,
      liveRegion: liveRegion,
      onTap: onTap,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderSemanticsBox renderObject,
  ) {
    renderObject
      ..label = label
      ..value = value
      ..tooltip = tooltip
      ..button = button
      ..selected = selected
      ..enabled = enabled
      ..liveRegion = liveRegion
      ..onTap = onTap;
  }
}

/// 自写语义渲染盒子。
class RenderSemanticsBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  String? _label;
  String? _value;
  String? _tooltip;
  bool _button;
  bool _selected;
  bool _enabled;
  bool _liveRegion;
  VoidCallback? _onTap;

  RenderSemanticsBox({
    required String? label,
    required String? value,
    required String? tooltip,
    required bool button,
    required bool selected,
    required bool enabled,
    required bool liveRegion,
    required VoidCallback? onTap,
  })  : _label = label,
        _value = value,
        _tooltip = tooltip,
        _button = button,
        _selected = selected,
        _enabled = enabled,
        _liveRegion = liveRegion,
        _onTap = onTap;

  set label(String? value) {
    if (_label == value) return;
    _label = value;
    markNeedsSemanticsUpdate();
  }

  set value(String? v) {
    if (_value == v) return;
    _value = v;
    markNeedsSemanticsUpdate();
  }

  set tooltip(String? v) {
    if (_tooltip == v) return;
    _tooltip = v;
    markNeedsSemanticsUpdate();
  }

  set button(bool value) {
    if (_button == value) return;
    _button = value;
    markNeedsSemanticsUpdate();
  }

  set selected(bool value) {
    if (_selected == value) return;
    _selected = value;
    markNeedsSemanticsUpdate();
  }

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    markNeedsSemanticsUpdate();
  }

  set liveRegion(bool value) {
    if (_liveRegion == value) return;
    _liveRegion = value;
    markNeedsSemanticsUpdate();
  }

  set onTap(VoidCallback? value) {
    if (_onTap == value) return;
    _onTap = value;
    markNeedsSemanticsUpdate();
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    config.isSemanticBoundary = true;
    if (_label != null) config.label = _label!;
    if (_value != null) config.value = _value!;
    if (_tooltip != null) config.tooltip = _tooltip!;
    config.isButton = _button;
    config.isSelected = _selected;
    config.isEnabled = _enabled;
    config.liveRegion = _liveRegion;
    if (_onTap != null) config.onTap = _onTap;
    // 框架要求:提供 label 时必须给出 textDirection
    config.textDirection = TextDirection.ltr;
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child != null) {
      child.layout(constraints, parentUsesSize: true);
      size = child.size;
    } else {
      size = constraints.smallest;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) {
      context.paintChild(child, offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child != null) {
      return child.hitTest(result, position: position);
    }
    return false;
  }
}

/// 屏蔽子树语义(直接复用框架渲染层的 RenderExcludeSemantics)。
class ExcludeSemantics extends fw.SingleChildRenderObjectWidget {
  const ExcludeSemantics({fw.Key? key, super.child}) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderExcludeSemantics();
  }
}

// ---------------------------------------------------------------------------
// IndexedStack
// ---------------------------------------------------------------------------

/// 索引栈:所有子项保持挂载(状态保留),仅绘制/命中指定索引。
class IndexedStack extends fw.StatefulWidget {
  final int index;
  final Alignment alignment;
  final List<fw.Widget> children;
  final StackFit? sizing;

  const IndexedStack({
    fw.Key? key,
    this.index = 0,
    this.alignment = Alignment.topLeft,
    this.sizing,
    required this.children,
  }) : super(key: key);

  @override
  fw.State<IndexedStack> createState() => _IndexedStackState();
}

class _IndexedStackState extends fw.State<IndexedStack> {
  @override
  fw.Widget build(fw.BuildContext context) {
    return _IndexedStackRender(
      index: widget.index,
      alignment: widget.alignment,
      sizing: widget.sizing,
      children: widget.children,
    );
  }
}

class _IndexedStackRender extends fw.MultiChildRenderObjectWidget {
  final int index;
  final Alignment alignment;
  final StackFit? sizing;

  const _IndexedStackRender({
    required this.index,
    required this.alignment,
    this.sizing,
    required List<fw.Widget> children,
  }) : super(children: children);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderIndexedStackBox(index: index, alignment: alignment);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderIndexedStackBox renderObject,
  ) {
    renderObject
      ..activeIndex = index
      ..alignment = alignment;
  }
}

class _IndexedParentData extends ContainerBoxParentData<RenderBox> {}

/// 自写索引栈渲染盒子:全部子项全尺寸布局,仅绘制活跃项。
class RenderIndexedStackBox extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _IndexedParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _IndexedParentData> {
  int _index;
  Alignment _alignment;

  RenderIndexedStackBox({required int index, required Alignment alignment})
      : _index = index,
        _alignment = alignment;

  set activeIndex(int value) {
    if (_index == value) return;
    _index = value;
    markNeedsPaint();
  }

  set alignment(Alignment value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsPaint();
  }

  @override
  void setupParentData(covariant fw.RenderObject child) {
    if (child.parentData is! _IndexedParentData) {
      child.parentData = _IndexedParentData();
    }
  }

  Iterable<RenderBox> get _children sync* {
    var child = firstChild;
    while (child != null) {
      yield child;
      child = (child.parentData as _IndexedParentData).nextSibling;
    }
  }

  @override
  void performLayout() {
    var maxWidth = 0.0;
    var maxHeight = 0.0;
    for (final child in _children) {
      child.layout(constraints.loosen(), parentUsesSize: true);
      if (child.size.width > maxWidth) maxWidth = child.size.width;
      if (child.size.height > maxHeight) maxHeight = child.size.height;
    }
    size = constraints.constrain(Size(maxWidth, maxHeight));
    for (final child in _children) {
      (child.parentData as _IndexedParentData).offset = _alignment.alongSize(
        Size(
          (size.width - child.size.width).clamp(0.0, double.infinity),
          (size.height - child.size.height).clamp(0.0, double.infinity),
        ),
      );
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var index = 0;
    for (final child in _children) {
      if (index == _index) {
        context.paintChild(
          child,
          (child.parentData as _IndexedParentData).offset + offset,
        );
        return;
      }
      index++;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var index = 0;
    for (final child in _children) {
      if (index == _index) {
        return result.addWithPaintOffset(
          offset: (child.parentData as _IndexedParentData).offset,
          position: position,
          hitTest: (result, transformed) =>
              child.hitTest(result, position: transformed),
        );
      }
      index++;
    }
    return false;
  }
}

/// 宽高比容器(自研;以父约束与 ratio 求最大可用尺寸)。
class AspectRatio extends fw.SingleChildRenderObjectWidget {
  final double aspectRatio;

  const AspectRatio({
    fw.Key? key,
    required this.aspectRatio,
    super.child,
  }) : super(key: key);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderAspectRatioBox(aspectRatio: aspectRatio);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderAspectRatioBox renderObject,
  ) {
    renderObject.aspectRatio = aspectRatio;
  }
}

/// 自写宽高比渲染盒子。
class RenderAspectRatioBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  double _aspectRatio;

  RenderAspectRatioBox({required double aspectRatio})
      : _aspectRatio = aspectRatio;

  set aspectRatio(double value) {
    if (_aspectRatio == value) return;
    _aspectRatio = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final c = constraints;
    double width;
    double height;
    if (c.hasBoundedWidth && c.hasBoundedHeight) {
      // 两者皆有界:取能放下的最大比例尺寸
      width = c.maxWidth;
      height = width / _aspectRatio;
      if (height > c.maxHeight) {
        height = c.maxHeight;
        width = height * _aspectRatio;
      }
    } else if (c.hasBoundedWidth) {
      width = c.maxWidth;
      height = width / _aspectRatio;
    } else if (c.hasBoundedHeight) {
      height = c.maxHeight;
      width = height * _aspectRatio;
    } else {
      width = 0;
      height = 0;
    }
    size = Size(width, height);
    final child = this.child;
    if (child != null) {
      child.layout(BoxConstraints.tight(size), parentUsesSize: true);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) {
      context.paintChild(child, offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child != null) {
      return child.hitTest(result, position: position);
    }
    return false;
  }
}


/// 遍历组件子树(深度优先),对每个节点调用 [visitor]。
///
/// 供测试与工具代码做结构检索;只处理渲染型组件的子节点。
void forEachDescendant(
  fw.Widget widget,
  void Function(fw.Widget node) visitor,
) {
  visitor(widget);
  final children = _directChildrenOf(widget);
  for (final child in children) {
    forEachDescendant(child, visitor);
  }
}

/// 取渲染型组件的直接子节点。
List<fw.Widget> _directChildrenOf(fw.Widget widget) {
  if (widget is fw.SingleChildRenderObjectWidget) {
    final child = widget.child;
    return child == null ? const [] : [child];
  }
  if (widget is fw.MultiChildRenderObjectWidget) {
    return widget.children;
  }
  return const [];
}
