/// 桌面端入口 (Windows / macOS / Linux)。打包/运行:
/// `flutter build windows -t lib/main_desktop.dart`
/// `flutter run -t lib/main_desktop.dart -d windows`
library;
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop/desktop_app.dart';
import 'shared/app_bootstrap.dart';
import 'shared/ui/kit.dart';
import 'shared/utils/native_window.dart';
import 'shared/utils/responsive.dart';

Future<void> main(List<String> args) => desktopMain(args);

Future<void> desktopMain(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final launchArgs = AppLaunchArgs.parse(args);
  // 初始化 MediaKit 流媒体硬解内核 (原生全面支持 HLS/m3u8, mp4, ts 切片)
  MediaKit.ensureInitialized();

  // 桌面端窗口定制
  if (!kIsWeb && Responsive.isDesktopPlatform) {
    await windowManager.ensureInitialized();

    final windowOptions = WindowOptions(
      size: const Size(1280, 800),
      minimumSize: const Size(960, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: kIsWindowsDesktop
          ? TitleBarStyle.hidden // Windows:隐藏系统标题栏,由原生 C++ 控制条接管
          : TitleBarStyle.normal,
      title: 'bllii · More Stories, Together',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (kIsWindowsDesktop) {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
      }
      // 保留 WS_THICKFRAME 与 DWM 扩展区域,以启用 Windows 11 原生圆角与系统阴影,并保留窗口缩放手势
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(buildAppProviders(child: DesktopBlliiApp(launchArgs: launchArgs)));
}
