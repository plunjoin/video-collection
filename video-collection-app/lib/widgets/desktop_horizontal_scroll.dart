import 'package:flutter/gestures.dart';
import '../ui/kit.dart';

/// 把纵向滚轮换成横向位移。正数表示内容向右滚。
double horizontalWheelDelta(AxisDirection direction, double dy) {
  if (dy == 0) return 0;
  return axisDirectionIsReversed(direction) ? -dy : dy;
}

/// 桌面端横向列表包装。
///
/// 自研滚动体系里,横向 Scrollable 已直接处理纵向滚轮(经
/// pointerSignalResolver 仲裁,最近的横向列表优先),这里保留为
/// 语义包装 + 兜底:对未自行处理滚轮的横向列表做一次转发。
class DesktopHorizontalScroll extends StatelessWidget {
  final Widget child;

  const DesktopHorizontalScroll({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return _HorizontalWheelRelay(child: child);
  }
}

class _HorizontalWheelRelay extends StatefulWidget {
  final Widget child;

  const _HorizontalWheelRelay({required this.child});

  @override
  State<_HorizontalWheelRelay> createState() => _HorizontalWheelRelayState();
}

class _HorizontalWheelRelayState extends State<_HorizontalWheelRelay> {
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // 触控板本身就有横向分量,交给列表自己处理。
    if (event.scrollDelta.dx.abs() >= event.scrollDelta.dy.abs()) return;
    final scrollable = _horizontalScrollable();
    if (scrollable == null || !scrollable.canScroll) return;
    final delta = horizontalWheelDelta(
      AxisDirection.right,
      event.scrollDelta.dy,
    );
    if (delta == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (resolved is! PointerScrollEvent) return;
      scrollable.applyScroll(
        scrollable.scrollOffset + delta,
        dragging: false,
      );
    });
  }

  /// 在子树中查找最近的横向自研滚动容器。
  UiScrollableState? _horizontalScrollable() {
    UiScrollableState? found;
    void visit(Element element) {
      if (found != null) return;
      final state = element is StatefulElement ? element.state : null;
      if (state is UiScrollableState &&
          state.scrollDirection == Axis.horizontal) {
        found = state;
        return;
      }
      element.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(onPointerSignal: _onPointerSignal, child: widget.child);
  }
}
