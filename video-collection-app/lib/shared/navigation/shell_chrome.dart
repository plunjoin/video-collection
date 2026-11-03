import '../ui/kit.dart';

/// 外壳 chrome 契约:MainScaffold / 端专属脚手架只持有 tab 状态与页面内容,
/// 导航载体由端专属外壳决定。
class ShellChrome {
  /// 当前选中的 tab 下标
  final int currentIndex;

  /// 切换 tab
  final ValueChanged<int> onSelect;

  /// 打开搜索
  final VoidCallback onOpenSearch;

  /// 打开设置
  final VoidCallback onOpenSettings;

  /// 打开账号
  final VoidCallback onOpenAccount;

  const ShellChrome({
    required this.currentIndex,
    required this.onSelect,
    required this.onOpenSearch,
    required this.onOpenSettings,
    required this.onOpenAccount,
  });
}

/// 外壳构建器:[body] 是五个 tab 的 IndexedStack 内容,外壳负责包上导航 chrome。
typedef ShellChromeBuilder = Widget Function(
  BuildContext context,
  ShellChrome chrome,
  Widget body,
);
