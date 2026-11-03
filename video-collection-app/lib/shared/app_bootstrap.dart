/// 共享启动装配:命令行参数解析、全局 Provider 注入、`--open-settings` 直达页。
///
/// 端专属入口(desktop/ 与 mobile/)在 runApp 前完成平台初始化
/// (桌面窗口定制 / 移动沉浸式状态栏),再调用这里两端共享的装配。
library;
import 'package:provider/provider.dart';

import 'providers/app_state_provider.dart';
import 'ui/kit.dart';

/// 命令行深链:`--open-player=视频ID` 启动后直达播放页;`--open-settings` 直达设置页
class AppLaunchArgs {
  final String? openPlayerVideoId;
  final bool openSettingsDirectly;

  const AppLaunchArgs({
    this.openPlayerVideoId,
    this.openSettingsDirectly = false,
  });

  static AppLaunchArgs parse(List<String> args) {
    String? openPlayerVideoId;
    var openSettingsDirectly = false;
    for (final arg in args) {
      if (arg.startsWith('--open-player=')) {
        openPlayerVideoId = arg.substring('--open-player='.length);
      } else if (arg == '--open-settings') {
        openSettingsDirectly = true;
      }
    }
    return AppLaunchArgs(
      openPlayerVideoId: openPlayerVideoId,
      openSettingsDirectly: openSettingsDirectly,
    );
  }
}

/// 两端共享的全局状态装配
Widget buildAppProviders({required Widget child}) {
  return MultiProvider(
    providers: [ChangeNotifierProvider(create: (_) => AppStateProvider())],
    child: child,
  );
}

/// `--open-settings` 直达页:挂载后立即 push 设置页,背景保持空壳
class DirectSettingsHome extends StatelessWidget {
  final WidgetBuilder settingsBuilder;

  const DirectSettingsHome({super.key, required this.settingsBuilder});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (ctx) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(ctx).push(
              MaterialPageRoute(builder: settingsBuilder),
            );
          });
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
