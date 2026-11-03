/// 移动端应用根:沉浸式透明系统栏,注入移动外壳与导航工厂。
library;
import 'package:provider/provider.dart';

import '../shared/app_bootstrap.dart';
import '../shared/navigation/app_nav_actions.dart';
import '../shared/providers/app_state_provider.dart';
import '../shared/ui/kit.dart';
import 'pages/startup_mobile_page.dart';
import 'router/mobile_router.dart';

class MobileBlliiApp extends StatelessWidget {
  final AppLaunchArgs launchArgs;

  const MobileBlliiApp({super.key, required this.launchArgs});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, child) {
        return AppRoot(
          title: 'AniPocket 故事口袋 · More Stories, Together',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light, appState.accentColor),
          darkTheme: buildAppTheme(Brightness.dark, appState.accentColor),
          themeMode: appState.themeMode,
          home: AppNavActions(
            openAccount: MobileRouter.pushAccount,
            openContentDetail: (ctx, {required kind, required contentId}) {
              MobileRouter.pushContentDetail(
                ctx,
                kind: kind,
                contentId: contentId,
              );
            },
            openWikiSubject: (ctx, {required subjectId}) {
              MobileRouter.pushWikiSubject(ctx, subjectId);
            },
            settingsBuilder: (_) => MobileRouter.settings(),
            child: launchArgs.openSettingsDirectly
                ? DirectSettingsHome(
                    settingsBuilder: (_) => MobileRouter.settings(),
                  )
                : StartupMobilePage(
                    openPlayerVideoId: launchArgs.openPlayerVideoId,
                  ),
          ),
        );
      },
    );
  }
}
