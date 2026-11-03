/// 自动选端入口:web 与桌面平台走桌面装配,移动原生走移动装配。
///
/// 正式打包请显式指定端入口:
/// - 桌面: `flutter build windows -t lib/main_desktop.dart`
/// - 移动: `flutter build apk -t lib/main_mobile.dart`
library;
import 'package:flutter/foundation.dart';

import 'main_desktop.dart' as desktop;
import 'main_mobile.dart' as mobile;
import 'shared/utils/responsive.dart';

Future<void> main(List<String> args) {
  if (!kIsWeb && Responsive.isMobilePlatform) {
    return mobile.mobileMain(args);
  }
  return desktop.desktopMain(args);
}
