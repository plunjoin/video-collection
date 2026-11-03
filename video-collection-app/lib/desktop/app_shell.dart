/// 桌面端主外壳:左侧栏导航 + 内容区,附全局快捷键 (Ctrl/Cmd+K 搜索)。
library;
import 'package:flutter/services.dart';

import '../../shared/navigation/shell_chrome.dart';
import '../../shared/ui/kit.dart';
import '../../shared/utils/responsive.dart';
import 'pages/main_scaffold_desktop_page.dart';
import 'widgets/desktop_side_rail.dart';

class DesktopShell extends StatelessWidget {
  final int initialIndex;

  const DesktopShell({super.key, this.initialIndex = 0});

  KeyEventResult _handleGlobalKeys(
      ShellChrome chrome, FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final isControlOrMeta = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      // Ctrl/Cmd + K 打开搜索
      if (isControlOrMeta && event.logicalKey == LogicalKeyboardKey.keyK) {
        chrome.onOpenSearch();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return DesktopMainScaffold(
      initialIndex: initialIndex,
      chromeBuilder: (context, chrome, body) {
        return Focus(
          autofocus: true,
          onKeyEvent: (node, event) => _handleGlobalKeys(chrome, node, event),
          child: Scaffold(
            // Dart 自绘标题栏已完全移除:右上角为 windows/runner 原生实现的
            // 最小化/最大化/关闭按钮;窗口拖拽由页面标题栏承担。
            body: Row(
              children: [
                DesktopSideRail(
                  currentIndex: chrome.currentIndex,
                  onSelect: chrome.onSelect,
                  onSettings: chrome.onOpenSettings,
                  onAccount: chrome.onOpenAccount,
                ),
                Expanded(
                  child: DesktopInset(
                    sidebarWidth: sidebarExpandedWidth,
                    child: body,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
