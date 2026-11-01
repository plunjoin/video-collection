import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/app_state_provider.dart';
import 'screens/startup_screen.dart';
import 'theme/app_theme.dart';
import 'utils/native_window.dart';
import 'utils/responsive.dart';

/// 命令行深链：`--open-player=视频ID` 启动后直达播放页
String? _openPlayerVideoId;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  for (final arg in args) {
    if (arg.startsWith('--open-player=')) {
      _openPlayerVideoId = arg.substring('--open-player='.length);
    }
  }
  // 初始化 MediaKit 流媒体硬解内核 (原生全面支持 HLS/m3u8, mp4, ts 切片)
  MediaKit.ensureInitialized();

  // 1. 桌面端窗口定制
  if (!kIsWeb && Responsive.isDesktopPlatform) {
    await windowManager.ensureInitialized();

    final windowOptions = WindowOptions(
      size: const Size(1280, 800),
      minimumSize: const Size(960, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: kIsWindowsDesktop
          ? TitleBarStyle.hidden // Windows：隐藏系统标题栏，由原生 C++ 控制条接管
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
      // 保留 WS_THICKFRAME 与 DWM 扩展区域，以启用 Windows 11 原生圆角与系统阴影，并保留窗口缩放手势
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // 2. 移动端 (Android, iOS) 沉浸式透明状态栏
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent, // 状态栏全透明
      statusBarIconBrightness: Brightness.dark, // 默认白色图标 (暗黑主题)
      statusBarBrightness: Brightness.light, // 适配 iOS
      systemNavigationBarColor: Colors.transparent, // 底部手势栏透明
    ),
  );

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => AppStateProvider())],
      child: const BlliiApp(),
    ),
  );
}

class BlliiApp extends StatelessWidget {
  const BlliiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, child) {
        // 同步明暗主题到 Windows 原生窗口控制条按钮配色
        final darkNow = appState.themeMode == ThemeMode.dark ||
            (appState.themeMode == ThemeMode.system &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);
        NativeWindow.setTheme(darkNow);
        return MaterialApp(
          title: 'bllii · More Stories, Together',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.themed(Brightness.light, appState.accentColor),
          darkTheme: AppTheme.themed(Brightness.dark, appState.accentColor),
          themeMode: appState.themeMode,
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            scrollbars: false,
          ),
          builder: (context, child) => VirtualWindowFrame(
            child: child ?? const SizedBox.shrink(),
          ),
          home: StartupScreen(openPlayerVideoId: _openPlayerVideoId),
        );
      },
    );
  }
}
