/// 移动端入口 (Android / iOS)。打包/运行:
/// `flutter build apk -t lib/main_mobile.dart`
/// `flutter run -t lib/main_mobile.dart`
library;
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'mobile/mobile_app.dart';
import 'shared/app_bootstrap.dart';
import 'shared/ui/kit.dart';

Future<void> main(List<String> args) => mobileMain(args);

Future<void> mobileMain(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final launchArgs = AppLaunchArgs.parse(args);
  // 初始化 MediaKit 流媒体硬解内核 (原生全面支持 HLS/m3u8, mp4, ts 切片)
  MediaKit.ensureInitialized();

  // 移动端 (Android, iOS) 沉浸式透明状态栏
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent, // 状态栏全透明
      statusBarIconBrightness: Brightness.dark, // 默认白色图标 (暗黑主题)
      statusBarBrightness: Brightness.light, // 适配 iOS
      systemNavigationBarColor: Colors.transparent, // 底部手势栏透明
    ),
  );

  runApp(buildAppProviders(child: MobileBlliiApp(launchArgs: launchArgs)));
}
