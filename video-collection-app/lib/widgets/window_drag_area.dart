import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import '../ui/kit.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/responsive.dart';

/// 可开关的窗口拖拽区域：启用且在桌面平台时，整个矩形（含透明/无内容区域）
/// 都能拖动窗口，双击最大化/还原；否则原样返回子组件。
///
/// 两种触发模式：
/// - 默认（手势模式）：拖动超过阈值后进入移动窗口，子组件点击不受影响；
/// - startOnPress（按下即拖）：指针按下立即进入系统移动循环（原生标题栏手感），
///   不经过手势竞技场，适合叠在其它手势（如播放器画布）之上时使用。
class WindowDragArea extends StatelessWidget {
  final bool enabled;
  final bool startOnPress;
  final Widget child;

  const WindowDragArea({
    super.key,
    required this.enabled,
    required this.child,
    this.startOnPress = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled || kIsWeb || !Responsive.isDesktopPlatform) {
      return child;
    }
    if (startOnPress) {
      return Listener(
        onPointerDown: (event) {
          // 仅主键按下才进入移动循环；原生移动循环会独占后续指针事件，
          // 因此不会与下层手势（画布拖进度/双击暂停等）产生竞技冲突
          if (event.buttons == kPrimaryButton) {
            windowManager.startDragging();
          }
        },
        child: child,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 与原生标题栏一致的交互：按住拖动、双击最大化/还原
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      },
      child: child,
    );
  }
}
