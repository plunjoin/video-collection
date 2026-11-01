/// 自研滚动体系:[ScrollController]/[SingleChildScrollView]/[ListView]/
/// [GridView]/[RefreshIndicator]。
///
/// 滚动视口为自写 RenderBox:拖拽 / 滚轮(PointerScrollEvent)驱动,桌面端
/// 默认钳制物理(到边界即停)。ListView 用"可视窗口 + 已测高度缓存"懒加载,
/// 长列表只布局可视区附近的子项。RefreshIndicator 通过滚动事件总线 +
/// 原始指针监听实现下拉刷新,不与内容手势抢占竞技场。
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' as fw;

import 'container.dart';
import 'gestures.dart';
import 'layout.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// 控制器与物理
// ---------------------------------------------------------------------------

/// 滚动位置快照。
class ScrollPosition {
  double pixels = 0;
  double minScrollExtent = 0;
  double maxScrollExtent = 0;
  double viewportDimension = 0;

  bool get hasContentDimensions => true;

  bool get hasPixels => true;

  double get extentAfter =>
      (maxScrollExtent - pixels).clamp(0.0, double.infinity);

  double get extentBefore => pixels.clamp(0.0, double.infinity);

  AxisDirection get axisDirection => AxisDirection.down;

  /// 滚轮增量(桌面端)。
  void pointerScroll(double delta) {
    pixels = (pixels + delta).clamp(
      minScrollExtent,
      maxScrollExtent,
    );
  }

  void forcePixels(double value) {
    pixels = value;
  }
}

/// 滚动控制器(自研;attach 后可读 offset / jumpTo / animateTo)。
class ScrollController extends ChangeNotifier {
  /// 附着后由滚动容器更新;附着前是全零占位。
  ScrollPosition position = ScrollPosition();
  double initialScrollOffset;

  ScrollController({this.initialScrollOffset = 0}) {
    position.pixels = initialScrollOffset;
  }

  bool get hasClients => _attached;

  bool _attached = false;

  double get offset => position.pixels;

  double get maxScrollExtent => position.maxScrollExtent;

  double get minScrollExtent => position.minScrollExtent;

  void jumpTo(double value) {
    position.pixels = value.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    notifyListeners();
  }

  Future<void> animateTo(
    double target, {
    required Duration duration,
    required Curve curve,
  }) async {
    jumpTo(target);
  }

  @override
  void dispose() {
    _attached = false;
    super.dispose();
  }
}

/// 滚动物理(自研;仅用于表达"可滚/不可滚")。
class ScrollPhysics {
  const ScrollPhysics();

  bool get allowUserScrolling => true;
}

/// 禁止用户滚动。
class NeverScrollableScrollPhysics extends ScrollPhysics {
  const NeverScrollableScrollPhysics();

  @override
  bool get allowUserScrolling => false;
}

/// 允许滚动(与桌面钳制物理一致)。
class AlwaysScrollableScrollPhysics extends ScrollPhysics {
  const AlwaysScrollableScrollPhysics();
}

// ---------------------------------------------------------------------------
// 滚动事件总线(RefreshIndicator 监听用)
// ---------------------------------------------------------------------------

/// 滚动事件。
class UiScrollReport {
  final double offset;
  final double minExtent;
  final double maxExtent;
  final bool dragging;

  const UiScrollReport({
    required this.offset,
    required this.minExtent,
    required this.maxExtent,
    required this.dragging,
  });

  bool get atTop => offset <= minExtent;
}

/// 滚动报告作用域(滚动容器向上冒泡给 RefreshIndicator)。
class ScrollReportScope extends fw.InheritedWidget {
  final void Function(UiScrollReport report)? onReport;

  const ScrollReportScope({
    fw.Key? key,
    this.onReport,
    required fw.Widget child,
  }) : super(key: key, child: child);

  static ScrollReportScope? of(fw.BuildContext context) {
    return context.findAncestorWidgetOfExactType<ScrollReportScope>();
  }

  @override
  bool updateShouldNotify(ScrollReportScope oldWidget) =>
      onReport != oldWidget.onReport;
}

// ---------------------------------------------------------------------------
// 滚动视口渲染件
// ---------------------------------------------------------------------------

/// 视口渲染件:裁剪 + 按给定偏移绘制子项(仅绘制视口内的子项)。
class ScrollViewportWidget extends fw.MultiChildRenderObjectWidget {
  final Axis scrollDirection;
  final double scrollOffset;
  final List<double> childOffsets;

  const ScrollViewportWidget({
    fw.Key? key,
    required this.scrollDirection,
    required this.scrollOffset,
    required this.childOffsets,
    required List<fw.Widget> children,
  }) : super(key: key, children: children);

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderScrollViewViewport(
      scrollDirection: scrollDirection,
      scrollOffset: scrollOffset,
      childOffsets: childOffsets,
    );
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderScrollViewViewport renderObject,
  ) {
    renderObject
      ..scrollDirection = scrollDirection
      ..scrollOffset = scrollOffset
      ..childOffsets = childOffsets;
  }
}

class _ViewportParentData extends ContainerBoxParentData<RenderBox> {}

/// 自写滚动视口渲染盒子。
class RenderScrollViewViewport extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ViewportParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ViewportParentData> {
  Axis _scrollDirection;
  double _scrollOffset;
  List<double> _childOffsets;

  RenderScrollViewViewport({
    required Axis scrollDirection,
    required double scrollOffset,
    required List<double> childOffsets,
  })  : _scrollDirection = scrollDirection,
        _scrollOffset = scrollOffset,
        _childOffsets = childOffsets;

  set scrollDirection(Axis value) {
    if (_scrollDirection == value) return;
    _scrollDirection = value;
    markNeedsLayout();
  }

  set scrollOffset(double value) {
    if (_scrollOffset == value) return;
    _scrollOffset = value;
    markNeedsPaint();
  }

  set childOffsets(List<double> value) {
    _childOffsets = value;
    markNeedsLayout();
  }

  Iterable<RenderBox> get _children sync* {
    var child = firstChild;
    while (child != null) {
      yield child;
      child = (child.parentData as _ViewportParentData).nextSibling;
    }
  }

  @override
  void setupParentData(covariant fw.RenderObject child) {
    if (child.parentData is! _ViewportParentData) {
      child.parentData = _ViewportParentData();
    }
  }

  @override
  void performLayout() {
    final isHorizontal = _scrollDirection == Axis.horizontal;
    final crossMax =
        isHorizontal ? constraints.maxHeight : constraints.maxWidth;
    final crossMin =
        isHorizontal ? constraints.minHeight : constraints.minWidth;

    var index = 0;
    for (final child in _children) {
      final inner = isHorizontal
          ? BoxConstraints(
              minHeight: crossMin,
              maxHeight: math.max(crossMax, crossMin),
            )
          : BoxConstraints(
              minWidth: crossMin,
              maxWidth: math.max(crossMax, crossMin),
            );
      child.layout(inner, parentUsesSize: true);
      final offset =
          index < _childOffsets.length ? _childOffsets[index] : 0.0;
      (child.parentData as _ViewportParentData).offset = isHorizontal
          ? Offset(offset, 0)
          : Offset(0, offset);
      index++;
    }

    final mainMax =
        isHorizontal ? constraints.maxWidth : constraints.maxHeight;
    final mainMin =
        isHorizontal ? constraints.minWidth : constraints.minHeight;
    final mainSize = mainMax.isFinite ? mainMax : mainMin;
    size = constraints.constrain(
      isHorizontal
          ? Size(math.max(mainMin, mainSize), math.max(crossMin, crossMax))
          : Size(math.max(crossMin, crossMax), math.max(mainMin, mainSize)),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final isHorizontal = _scrollDirection == Axis.horizontal;
    final viewportMain = isHorizontal ? size.width : size.height;
    context.pushClipRect(
      needsCompositing,
      offset,
      offset & size,
      (context, offset) {
        var index = 0;
        var child = firstChild;
        while (child != null) {
          final data = child.parentData as _ViewportParentData;
          final childOffset = index < _childOffsets.length
              ? _childOffsets[index]
              : 0.0;
          final screenPos = childOffset - _scrollOffset;
          final extent = isHorizontal ? child.size.width : child.size.height;
          if (screenPos + extent >= 0 && screenPos <= viewportMain) {
            context.paintChild(
              child,
              isHorizontal
                  ? offset + Offset(screenPos, data.offset.dy)
                  : offset + Offset(data.offset.dx, screenPos),
            );
          }
          child = data.nextSibling;
          index++;
        }
      },
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final isHorizontal = _scrollDirection == Axis.horizontal;
    final viewportMain = isHorizontal ? size.width : size.height;
    final children = <RenderBox>[];
    var it = firstChild;
    while (it != null) {
      children.add(it);
      it = (it.parentData as _ViewportParentData).nextSibling;
    }
    var index = 0;
    for (final child in children.reversed) {
      final data = child.parentData as _ViewportParentData;
      final childOffset =
          index < _childOffsets.length ? _childOffsets[index] : 0.0;
      final screenPos = childOffset - _scrollOffset;
      final extent = isHorizontal ? child.size.width : child.size.height;
      if (screenPos + extent >= 0 && screenPos <= viewportMain) {
        final hit = result.addWithPaintOffset(
          offset: isHorizontal
              ? Offset(screenPos, data.offset.dy)
              : Offset(data.offset.dx, screenPos),
          position: position,
          hitTest: (result, transformed) =>
              child.hitTest(result, position: transformed),
        );
        if (hit) return true;
      }
      index++;
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// 滚动核心 State(供 SingleChildScrollView/ListView/GridView 复用)
// ---------------------------------------------------------------------------

mixin UiScrollableState<T extends fw.StatefulWidget> on fw.State<T> {
  double _offset = 0;
  double _maxExtent = 0;
  double _viewportExtent = 0;

  Axis get scrollDirection;

  ScrollPhysics? get scrollPhysics => null;

  ScrollController? get scrollController => null;

  bool get shrinkWrap => false;

  double get scrollOffset => _offset;

  bool get canScroll =>
      (scrollPhysics?.allowUserScrolling ?? true) && _maxExtent > 0;

  void _syncController() {
    final controller = scrollController;
    if (controller != null) {
      controller._attached = true;
      _offset = controller.position.pixels;
    }
  }

  void applyScroll(double newOffset, {required bool dragging}) {
    final clamped =
        newOffset.clamp(0.0, math.max(0.0, _maxExtent)) as double;
    if (clamped == _offset) return;
    _offset = clamped;
    scrollController?.position?.pixels = _offset;
    _report(dragging: dragging);
    if (mounted) setState(() {});
  }

  void _measureViewport() {
    final ro = context.findRenderObject();
    if (ro is RenderBox && ro.hasSize) {
      final extent = scrollDirection == Axis.horizontal
          ? ro.size.width
          : ro.size.height;
      if (extent > 0) _viewportExtent = extent;
    }
    if (_viewportExtent <= 0) _viewportExtent = 600;
  }

  void _report({required bool dragging}) {
    ScrollReportScope.of(context)?.onReport?.call(UiScrollReport(
      offset: _offset,
      minExtent: 0,
      maxExtent: _maxExtent,
      dragging: dragging,
    ));
  }

  /// 构建滚动容器:padding 统一折算进子项偏移与内容总长。
  fw.Widget buildScrollable({
    required double contentExtent,
    required List<fw.Widget> children,
    required List<double> childOffsets,
    EdgeInsetsGeometry? padding,
  }) {
    _syncController();
    _measureViewport();

    final isHorizontal = scrollDirection == Axis.horizontal;
    final padStart = padding != null
        ? (isHorizontal ? (padding as EdgeInsets).left : (padding as EdgeInsets).top)
        : 0.0;
    final padEnd = padding != null
        ? (isHorizontal
            ? (padding as EdgeInsets).right
            : (padding as EdgeInsets).bottom)
        : 0.0;

    _maxExtent = math.max(
      0,
      contentExtent + padStart + padEnd - _viewportExtent,
    );

    final shiftedOffsets = [
      for (final o in childOffsets) o + padStart,
    ];

    fw.Widget viewport = ScrollViewportWidget(
      scrollDirection: scrollDirection,
      scrollOffset: _offset,
      childOffsets: shiftedOffsets,
      children: children,
    );

    viewport = Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent && canScroll) {
          // 经仲裁器注册:最近的(内层)滚动容器优先响应滚轮
          GestureBinding.instance.pointerSignalResolver.register(
            event,
            (resolved) {
              if (resolved is PointerScrollEvent) {
                applyScroll(_offset + resolved.scrollDelta.dy,
                    dragging: false);
              }
            },
          );
        }
      },
      child: viewport,
    );

    viewport = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: !isHorizontal && canScroll
          ? (details) =>
              applyScroll(_offset - details.delta.dy, dragging: true)
          : null,
      onVerticalDragEnd: !isHorizontal && canScroll
          ? (details) => _report(dragging: false)
          : null,
      onHorizontalDragUpdate: isHorizontal && canScroll
          ? (details) =>
              applyScroll(_offset - details.delta.dx, dragging: true)
          : null,
      onHorizontalDragEnd: isHorizontal && canScroll
          ? (details) => _report(dragging: false)
          : null,
      child: viewport,
    );

    return viewport;
  }
}

// ---------------------------------------------------------------------------
// SingleChildScrollView
// ---------------------------------------------------------------------------

/// 单子项滚动容器。
class SingleChildScrollView extends fw.StatefulWidget {
  final Axis scrollDirection;
  final fw.Widget? child;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;

  const SingleChildScrollView({
    fw.Key? key,
    this.scrollDirection = Axis.vertical,
    this.child,
    this.padding,
    this.controller,
    this.physics,
  }) : super(key: key);

  @override
  fw.State<SingleChildScrollView> createState() =>
      _SingleChildScrollViewState();
}

class _SingleChildScrollViewState extends fw.State<SingleChildScrollView>
    with UiScrollableState<SingleChildScrollView> {
  final fw.GlobalKey _childKey = fw.GlobalKey();
  double _contentExtent = 0;
  bool _measuredOnce = false;

  @override
  Axis get scrollDirection => widget.scrollDirection;

  @override
  ScrollPhysics? get scrollPhysics => widget.physics;

  @override
  ScrollController? get scrollController => widget.controller;

  @override
  fw.Widget build(fw.BuildContext context) {
    final child = widget.child;
    final isHorizontal = widget.scrollDirection == Axis.horizontal;

    // 首帧后测量内容尺寸并重建
    if (!_measuredOnce) {
      fw.WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ro = _childKey.currentContext?.findRenderObject();
        if (ro is RenderBox && ro.hasSize) {
          final extent = isHorizontal ? ro.size.width : ro.size.height;
          if (extent != _contentExtent) {
            setState(() => _contentExtent = extent);
          }
        }
      });
    }

    return buildScrollable(
      contentExtent: _contentExtent,
      children: child != null
          ? [KeyedSubtree(key: _childKey, child: child)]
          : const [],
      childOffsets: const [0.0],
      padding: widget.padding,
    );
  }
}

/// 保持子树状态的包装(内部管道)。
class KeyedSubtree extends fw.StatelessWidget {
  final fw.Key key;
  final fw.Widget child;

  const KeyedSubtree({required this.key, required this.child});

  @override
  fw.Widget build(fw.BuildContext context) => child;
}

// ---------------------------------------------------------------------------
// ListView
// ---------------------------------------------------------------------------

/// 滚动列表(替代 widgets 的 ListView;含 builder/separated 变体)。
class ListView extends fw.StatefulWidget {
  final Axis scrollDirection;
  final List<fw.Widget>? children;
  final int? itemCount;
  final fw.Widget? Function(fw.BuildContext, int)? itemBuilder;
  final fw.Widget? Function(fw.BuildContext, int)? separatorBuilder;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final bool shrinkWrap;

  const ListView({
    fw.Key? key,
    this.children,
    this.scrollDirection = Axis.vertical,
    this.padding,
    this.controller,
    this.physics,
    this.shrinkWrap = false,
  })  : itemCount = children?.length,
        itemBuilder = null,
        separatorBuilder = null,
        super(key: key);

  const ListView.builder({
    fw.Key? key,
    this.scrollDirection = Axis.vertical,
    required int this.itemCount,
    required fw.Widget? Function(fw.BuildContext, int) this.itemBuilder,
    this.padding,
    this.controller,
    this.physics,
    this.shrinkWrap = false,
  })  : children = null,
        separatorBuilder = null,
        super(key: key);

  const ListView.separated({
    fw.Key? key,
    this.scrollDirection = Axis.vertical,
    required int this.itemCount,
    required fw.Widget? Function(fw.BuildContext, int) this.itemBuilder,
    required fw.Widget? Function(fw.BuildContext, int) this.separatorBuilder,
    this.padding,
    this.controller,
    this.physics,
    this.shrinkWrap = false,
  })  : children = null,
        super(key: key);

  @override
  fw.State<ListView> createState() => _ListViewState();
}

class _ListViewState extends fw.State<ListView>
    with UiScrollableState<ListView> {
  static const double _defaultEstimate = 88;
  static const int _cacheSlots = 8;

  final List<double?> _extents = [];
  bool _extentsDirty = false;

  int get _effectiveCount {
    if (widget.itemCount != null) return widget.itemCount!;
    return widget.children?.length ?? 0;
  }

  bool get _hasSeparator => widget.separatorBuilder != null;

  int get _totalSlots =>
      _hasSeparator ? math.max(0, _effectiveCount * 2 - 1) : _effectiveCount;

  int _itemIndexForSlot(int slot) {
    if (!_hasSeparator) return slot;
    return slot.isEven ? slot ~/ 2 : (slot - 1) ~/ 2;
  }

  bool _isSeparator(int slot) => _hasSeparator && slot.isOdd;

  double _extentFor(int slot) =>
      slot < _extents.length ? (_extents[slot] ?? _defaultEstimate) : _defaultEstimate;

  void _recordExtent(int slot, double extent) {
    while (_extents.length <= slot) {
      _extents.add(null);
    }
    if (_extents[slot] != extent) {
      _extents[slot] = extent;
      _extentsDirty = true;
    }
  }

  double _totalExtent() {
    var sum = 0.0;
    for (var i = 0; i < _totalSlots; i++) {
      sum += _extentFor(i);
    }
    return sum;
  }

  fw.Widget _slotChild(int slot) {
    final index = _itemIndexForSlot(slot);
    return _MeasuredSlot(
      key: fw.ValueKey<int>(slot),
      slot: slot,
      onMeasured: (s, extent) {
        _recordExtent(s, extent);
        if (_extentsDirty && mounted) {
          // 高度测量变化后下一帧重排
          fw.WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
      },
      child: _isSeparator(slot)
          ? widget.separatorBuilder!(context, index) ?? const SizedBox.shrink()
          : widget.itemBuilder != null
              ? widget.itemBuilder!(context, index) ?? const SizedBox.shrink()
              : widget.children![index],
    );
  }

  @override
  Axis get scrollDirection => widget.scrollDirection;

  @override
  ScrollPhysics? get scrollPhysics => widget.physics;

  @override
  ScrollController? get scrollController => widget.controller;

  @override
  bool get shrinkWrap => widget.shrinkWrap;

  @override
  fw.Widget build(fw.BuildContext context) {
    _extentsDirty = false;

    if (widget.shrinkWrap || _totalSlots <= 48) {
      // 全量布局(小列表 / shrinkWrap)
      final children = <fw.Widget>[];
      final offsets = <double>[];
      var cursor = 0.0;
      for (var slot = 0; slot < _totalSlots; slot++) {
        offsets.add(cursor);
        children.add(_slotChild(slot));
        cursor += _extentFor(slot);
      }
      return buildScrollable(
        contentExtent: _totalExtent(),
        children: children,
        childOffsets: offsets,
        padding: widget.padding,
      );
    }

    // 可视窗口懒加载
    _measureViewport();
    final viewportMain = scrollDirection == Axis.horizontal
        ? _viewportExtent
        : _viewportExtent;

    final scroll = scrollOffset;
    var firstSlot = 0;
    var acc = 0.0;
    while (firstSlot < _totalSlots &&
        acc + _extentFor(firstSlot) <
            scroll - _defaultEstimate * _cacheSlots) {
      acc += _extentFor(firstSlot);
      firstSlot++;
    }
    final windowBase = acc;
    var remaining = scroll + viewportMain - windowBase + _defaultEstimate * _cacheSlots;
    var lastSlot = firstSlot;
    var acc2 = 0.0;
    while (lastSlot < _totalSlots && acc2 < remaining) {
      acc2 += _extentFor(lastSlot);
      lastSlot++;
    }

    final children = <fw.Widget>[];
    final offsets = <double>[];
    var cursor = windowBase;
    for (var slot = firstSlot; slot < lastSlot; slot++) {
      offsets.add(cursor);
      children.add(_slotChild(slot));
      cursor += _extentFor(slot);
    }

    return buildScrollable(
      contentExtent: _totalExtent(),
      children: children,
      childOffsets: offsets,
      padding: widget.padding,
    );
  }
}

/// 测量子项:布局后把实际尺寸回传给列表 State。
class _MeasuredSlot extends fw.SingleChildRenderObjectWidget {
  final int slot;
  final void Function(int slot, double extent) onMeasured;
  final fw.Widget child;

  const _MeasuredSlot({
    super.key,
    required this.slot,
    required this.onMeasured,
    required this.child,
  });

  @override
  fw.RenderObject createRenderObject(fw.BuildContext context) {
    return RenderMeasuredSlot(slot: slot, onMeasured: onMeasured);
  }

  @override
  void updateRenderObject(
    fw.BuildContext context,
    covariant RenderMeasuredSlot renderObject,
  ) {
    renderObject
      ..slot = slot
      ..onMeasured = onMeasured;
  }
}

class RenderMeasuredSlot extends RenderProxyBox {
  int _slot;
  void Function(int, double) _onMeasured;
  double _lastExtent = -1;

  RenderMeasuredSlot({required int slot, required void Function(int, double) onMeasured})
      : _slot = slot,
        _onMeasured = onMeasured;

  set slot(int value) => _slot = value;

  set onMeasured(void Function(int, double) value) => _onMeasured = value;

  @override
  void performLayout() {
    super.performLayout();
    final extent = size.height;
    if (extent != _lastExtent) {
      _lastExtent = extent;
      _onMeasured(_slot, extent);
    }
  }
}

// ---------------------------------------------------------------------------
// GridView
// ---------------------------------------------------------------------------

/// 网格布局委托基类(自研)。
abstract class SliverGridDelegate {
  const SliverGridDelegate();
}

/// 固定列数网格。
class SliverGridDelegateWithFixedCrossAxisCount extends SliverGridDelegate {
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final double? mainAxisExtent;

  const SliverGridDelegateWithFixedCrossAxisCount({
    required this.crossAxisCount,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
    this.childAspectRatio = 1,
    this.mainAxisExtent,
  });
}

/// 按最大列宽自适应网格。
class SliverGridDelegateWithMaxCrossAxisExtent extends SliverGridDelegate {
  final double maxCrossAxisExtent;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final double? mainAxisExtent;

  const SliverGridDelegateWithMaxCrossAxisExtent({
    required this.maxCrossAxisExtent,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
    this.childAspectRatio = 1,
    this.mainAxisExtent,
  });
}

/// 网格(替代 widgets 的 GridView;builder/children 变体)。
class GridView extends fw.StatefulWidget {
  final SliverGridDelegate gridDelegate;
  final List<fw.Widget>? children;
  final int? itemCount;
  final fw.Widget? Function(fw.BuildContext, int)? itemBuilder;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final Axis scrollDirection;

  const GridView({
    fw.Key? key,
    required this.gridDelegate,
    this.children,
    this.padding,
    this.controller,
    this.physics,
    this.shrinkWrap = false,
    this.scrollDirection = Axis.vertical,
  })  : itemCount = children?.length,
        itemBuilder = null,
        super(key: key);

  GridView.count({
    fw.Key? key,
    required int crossAxisCount,
    double mainAxisSpacing = 0,
    double crossAxisSpacing = 0,
    double childAspectRatio = 1,
    double? mainAxisExtent,
    this.children,
    this.padding,
    this.controller,
    this.physics,
    this.shrinkWrap = false,
    this.scrollDirection = Axis.vertical,
  })  : gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: mainAxisSpacing,
          crossAxisSpacing: crossAxisSpacing,
          childAspectRatio: childAspectRatio,
          mainAxisExtent: mainAxisExtent,
        ),
        itemCount = null,
        itemBuilder = null,
        super(key: key);

  const GridView.builder({
    fw.Key? key,
    required this.gridDelegate,
    required int this.itemCount,
    required fw.Widget? Function(fw.BuildContext, int) this.itemBuilder,
    this.padding,
    this.controller,
    this.physics,
    this.shrinkWrap = false,
    this.scrollDirection = Axis.vertical,
  })  : children = null,
        super(key: key);

  @override
  fw.State<GridView> createState() => _GridViewState();
}

class _GridViewState extends fw.State<GridView>
    with UiScrollableState<GridView> {
  int _crossCount = 1;
  double _rowExtent = 220;
  double _cellWidth = 0;

  void _computeMetrics(double viewportWidth) {
    final delegate = widget.gridDelegate;
    double crossSpacing = 0;
    double aspect = 1;
    double? mainExtent;
    if (delegate is SliverGridDelegateWithFixedCrossAxisCount) {
      _crossCount = math.max(1, delegate.crossAxisCount);
      crossSpacing = delegate.crossAxisSpacing;
      aspect = delegate.childAspectRatio;
      mainExtent = delegate.mainAxisExtent;
    } else if (delegate is SliverGridDelegateWithMaxCrossAxisExtent) {
      _crossCount = math.max(
        1,
        (viewportWidth / delegate.maxCrossAxisExtent).floor(),
      );
      crossSpacing = delegate.crossAxisSpacing;
      aspect = delegate.childAspectRatio;
      mainExtent = delegate.mainAxisExtent;
    }
    _cellWidth =
        (viewportWidth - crossSpacing * (_crossCount - 1)) / _crossCount;
    _rowExtent = mainExtent ?? (_cellWidth / math.max(0.01, aspect));
  }

  int get _effectiveCount {
    if (widget.itemCount != null) return widget.itemCount!;
    return widget.children?.length ?? 0;
  }

  @override
  Axis get scrollDirection => widget.scrollDirection;

  @override
  ScrollPhysics? get scrollPhysics => widget.physics;

  @override
  ScrollController? get scrollController => widget.controller;

  @override
  bool get shrinkWrap => widget.shrinkWrap;

  @override
  fw.Widget build(fw.BuildContext context) {
    _measureViewport();
    // 网格主轴为纵向时,交叉轴宽度 = 视口宽度
    _computeMetrics(_viewportExtent);

    final delegate = widget.gridDelegate;
    double mainSpacing = 0;
    double crossSpacing = 0;
    if (delegate is SliverGridDelegateWithFixedCrossAxisCount) {
      mainSpacing = delegate.mainAxisSpacing;
      crossSpacing = delegate.crossAxisSpacing;
    } else if (delegate is SliverGridDelegateWithMaxCrossAxisExtent) {
      mainSpacing = delegate.mainAxisSpacing;
      crossSpacing = delegate.crossAxisSpacing;
    }

    final count = _effectiveCount;
    final rowCount = (count + _crossCount - 1) ~/ _crossCount;

    final children = <fw.Widget>[];
    final offsets = <double>[];
    var cursor = 0.0;
    for (var row = 0; row < rowCount; row++) {
      offsets.add(cursor);
      final rowChildren = <fw.Widget>[];
      for (var col = 0; col < _crossCount; col++) {
        final index = row * _crossCount + col;
        if (index < count) {
          rowChildren.add(
            Expanded(
              child: SizedBox(
                height: _rowExtent,
                child: _buildItem(index),
              ),
            ),
          );
        } else {
          rowChildren.add(const Expanded(child: SizedBox.shrink()));
        }
        if (col < _crossCount - 1) {
          rowChildren.add(SizedBox(width: crossSpacing));
        }
      }
      children.add(
        Row(
          children: rowChildren,
          crossAxisAlignment: CrossAxisAlignment.start,
        ),
      );
      cursor += _rowExtent + mainSpacing;
    }

    return buildScrollable(
      contentExtent: rowCount > 0 ? cursor - mainSpacing : 0,
      children: children,
      childOffsets: offsets,
      padding: widget.padding,
    );
  }

  fw.Widget _buildItem(int index) {
    if (widget.itemBuilder != null) {
      return widget.itemBuilder!(context, index) ?? const SizedBox.shrink();
    }
    return widget.children![index];
  }
}

// ---------------------------------------------------------------------------
// RefreshIndicator
// ---------------------------------------------------------------------------

/// 下拉刷新(替代 material 的 RefreshIndicator)。
class RefreshIndicator extends fw.StatefulWidget {
  final fw.Widget child;
  final Future<void> Function() onRefresh;
  final Color? color;
  final Color? backgroundColor;
  final double displacement;
  final double edgeOffset;

  const RefreshIndicator({
    fw.Key? key,
    required this.child,
    required this.onRefresh,
    this.color,
    this.backgroundColor,
    this.displacement = 40,
    this.edgeOffset = 0,
  }) : super(key: key);

  @override
  fw.State<RefreshIndicator> createState() => _RefreshIndicatorState();
}

class _RefreshIndicatorState extends fw.State<RefreshIndicator> {
  double _dragOffset = 0;
  bool _refreshing = false;
  Offset? _pointerStart;
  bool _atTop = true;

  void _onReport(UiScrollReport report) {
    _atTop = report.atTop;
    if (!_atTop && !_refreshing && _dragOffset > 0) {
      setState(() => _dragOffset = 0);
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointerStart = event.position;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_refreshing || _pointerStart == null || !_atTop) return;
    final dy = event.position.dy - _pointerStart!.dy;
    if (dy > 0) {
      // 阻尼:越拉越紧
      final damped = math.min(120.0, dy * 0.55);
      if ((damped - _dragOffset).abs() > 0.5) {
        setState(() => _dragOffset = damped);
      }
    } else if (_dragOffset > 0) {
      setState(() => _dragOffset = 0);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointerStart = null;
    if (_refreshing) return;
    if (_dragOffset >= 64) {
      setState(() {
        _refreshing = true;
        _dragOffset = 64;
      });
      () async {
        try {
          await widget.onRefresh();
        } finally {
          if (mounted) {
            setState(() {
              _refreshing = false;
              _dragOffset = 0;
            });
          }
        }
      }();
    } else {
      setState(() => _dragOffset = 0);
    }
  }

  @override
  fw.Widget build(fw.BuildContext context) {
    final theme = Theme.of(context);
    return ScrollReportScope(
      onReport: _onReport,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: (event) => _pointerStart = null,
            child: widget.child,
          ),
          if (_dragOffset > 0 || _refreshing)
            Positioned(
              top: widget.edgeOffset,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: EdgeInsets.only(top: math.max(0, _dragOffset - 20)),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.backgroundColor ??
                        (theme.brightness == Brightness.dark
                            ? const Color(0xFF1E293B)
                            : Colors.white),
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: _SpinningMark(
                    color: widget.color ?? theme.colorScheme.primary,
                    spin: _refreshing,
                    progress:
                        _refreshing ? null : math.min(1, _dragOffset / 64),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 下拉刷新的圆形指示标记。
class _SpinningMark extends fw.StatefulWidget {
  final Color color;
  final bool spin;
  final double? progress;

  const _SpinningMark({
    required this.color,
    required this.spin,
    this.progress,
  });

  @override
  fw.State<_SpinningMark> createState() => _SpinningMarkState();
}

class _SpinningMarkState extends fw.State<_SpinningMark>
    with fw.SingleTickerProviderStateMixin {
  late final fw.AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = fw.AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.spin) _controller.repeat();
  }

  @override
  void didUpdateWidget(_SpinningMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spin && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.spin && _controller.isAnimating) {
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _RefreshMarkPainter(
            color: widget.color,
            rotation: _controller.value,
            progress: widget.progress ?? 1,
          ),
        );
      },
    );
  }
}

class _RefreshMarkPainter extends CustomPainter {
  final Color color;
  final double rotation;
  final double progress;

  _RefreshMarkPainter({
    required this.color,
    required this.rotation,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 4;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation * math.pi * 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = color;
    final sweep = math.pi * 2 * (0.25 + 0.5 * progress);
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RefreshMarkPainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.progress != progress ||
      oldDelegate.color != color;
}
