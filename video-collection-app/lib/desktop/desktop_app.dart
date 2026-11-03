/// 桌面端应用根:明暗主题同步到 Windows 原生窗口控制条,
/// 注入 VirtualWindowFrame、桌面外壳与导航工厂。
library;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../shared/app_bootstrap.dart';
import '../shared/navigation/app_nav_actions.dart';
import '../shared/providers/app_state_provider.dart';
import '../shared/ui/kit.dart';
import '../shared/utils/native_window.dart';
import 'pages/startup_desktop_page.dart';
import 'router/desktop_router.dart';

class DesktopBlliiApp extends StatelessWidget {
  final AppLaunchArgs launchArgs;

  const DesktopBlliiApp({super.key, required this.launchArgs});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, child) {
        // 同步明暗主题到 Windows 原生窗口控制条按钮配色
        final darkNow = appState.themeMode == ThemeMode.dark ||
            (appState.themeMode == ThemeMode.system &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);
        NativeWindow.setTheme(darkNow);
        return AppRoot(
          title: 'AniPocket 故事口袋 · More Stories, Together',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light, appState.accentColor),
          darkTheme: buildAppTheme(Brightness.dark, appState.accentColor),
          themeMode: appState.themeMode,
          builder: (context, child) => VirtualWindowFrame(
            child: child ?? const SizedBox.shrink(),
          ),
          home: AppNavActions(
            openAccount: DesktopRouter.pushAccount,
            openContentDetail: (ctx, {required kind, required contentId}) {
              DesktopRouter.pushContentDetail(
                ctx,
                kind: kind,
                contentId: contentId,
              );
            },
            openWikiSubject: (ctx, {required subjectId}) {
              DesktopRouter.pushWikiSubject(ctx, subjectId);
            },
            settingsBuilder: (_) => DesktopRouter.settings(),
            child: launchArgs.openSettingsDirectly
                ? DirectSettingsHome(
                    settingsBuilder: (_) => DesktopRouter.settings(),
                  )
                : StartupDesktopPage(
                    openPlayerVideoId: launchArgs.openPlayerVideoId,
                  ),
          ),
        );
      },
    );
  }
}
