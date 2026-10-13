import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 把纵向滚轮换成横向位移。正数表示内容向右滚。
double horizontalWheelDelta(AxisDirection direction, double dy) {
  if (dy == 0) return 0;
  return axisDirectionIsReversed(direction) ? -dy : dy;
}

/// 桌面端横向列表。鼠标可以按住拖动，悬停时滚轮也横向滚动。
class DesktopHorizontalScroll extends StatelessWidget {
  final Widget child;

  const DesktopHorizontalScroll({super.key, required this.child});

  static const Set<PointerDeviceKind> dragDevices = {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context)
          .copyWith(dragDevices: dragDevices),
      child: _HorizontalWheelRelay(child: child),
    );
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
    // 触控板本身就有横向分量，交给列表自己处理。
    if (event.scrollDelta.dx.abs() >= event.scrollDelta.dy.abs()) return;
    final position = _horizontalPosition();
    if (position == null ||
        !position.hasContentDimensions ||
        position.maxScrollExtent <= position.minScrollExtent) {
      return;
    }
    final delta = horizontalWheelDelta(
      position.axisDirection,
      event.scrollDelta.dy,
    );
    if (delta == 0) return;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (resolved is! PointerScrollEvent) return;
      if (!position.hasContentDimensions) return;
      position.pointerScroll(delta);
      resolved.respond(allowPlatformDefault: false);
    });
  }

  ScrollPosition? _horizontalPosition() {
    ScrollPosition? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is ScrollableState) {
        final scrollable = element.state as ScrollableState;
        if (scrollable.widget.axis == Axis.horizontal) {
          found = scrollable.position;
          return;
        }
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
