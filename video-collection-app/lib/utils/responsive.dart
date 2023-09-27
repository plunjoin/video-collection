import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class Responsive {
  /// 是否为桌面端原生系统 (Windows, macOS, Linux)
  static bool get isDesktopPlatform {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// 是否为移动端原生系统 (Android, iOS)
  static bool get isMobilePlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// 当前是否处于桌面级宽屏交互模式 (宽度 >= 840 或 桌面端且 >= 720)
  static bool isDesktop(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (isDesktopPlatform) {
      return width >= 720;
    }
    return width >= 900;
  }

  /// 是否为平板尺寸
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 900;
  }

  /// 是否为手机竖屏微端尺寸
  static bool isMobile(BuildContext context) {
    return !isDesktop(context) && !isTablet(context);
  }

  /// 动态计算海报网格的列数 (自适应 3 ~ 8 列)
  static int gridColumns(
    BuildContext context, {
    double itemMinWidth = 120,
    int min = 3,
    int max = 8,
  }) {
    final width = MediaQuery.of(context).size.width;
    // 扣除侧边栏或内边距的大致可用宽度
    final columns = (width / itemMinWidth).floor();
    return columns.clamp(min, max);
  }

  /// 响应式取值辅助器
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    required T desktop,
  }) {
    if (isDesktop(context)) return desktop;
    if (isTablet(context)) return tablet ?? mobile;
    return mobile;
  }
}
