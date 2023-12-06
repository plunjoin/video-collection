import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/app_state_provider.dart';
import 'screens/main_scaffold.dart';
import 'theme/app_theme.dart';
import 'utils/responsive.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 MediaKit 流媒体硬解内核 (原生全面支持 HLS/m3u8, mp4, ts 切片)
  MediaKit.ensureInitialized();

  // 1. 桌面端 (Windows, macOS, Linux) 无边框沉浸式窗口定制
  if (!kIsWeb && Responsive.isDesktopPlatform) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(960, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden, // 隐藏原生系统白框标题栏
      title: 'bllii · More Stories, Together',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
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
        return MaterialApp(
          title: 'bllii · More Stories, Together',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: appState.themeMode,
          home: const MainScaffold(),
        );
      },
    );
  }
}
