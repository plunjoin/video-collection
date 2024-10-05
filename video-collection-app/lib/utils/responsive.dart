import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 把内容区的 [MediaQuery] 宽度收成「窗口减去侧栏」，网格和横幅按剩余空间排。
class DesktopInset extends StatelessWidget {
  final double sidebarWidth;
  final Widget child;

  const DesktopInset({
    super.key,
    required this.sidebarWidth,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = (media.size.width - sidebarWidth).clamp(
      0.0,
      media.size.width,
    );
    return MediaQuery(
      data: media.copyWith(size: Size(width, media.size.height)),
      child: child,
    );
  }
}

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

  /// 当前是否处于桌面级宽屏交互模式。
  /// 原生桌面看窗口本身，不看侧栏扣掉之后的内容宽度，避免主框架被收成手机布局。
  static bool isDesktop(BuildContext context) {
    if (isDesktopPlatform) {
      final view = View.of(context);
      final windowWidth = view.physicalSize.width / view.devicePixelRatio;
      return windowWidth >= 720;
    }
    return MediaQuery.sizeOf(context).width >= 900;
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

  /// 当前内容区宽度。桌面主框架里已经扣掉侧栏。
  static double contentWidth(BuildContext context) {
    return MediaQuery.sizeOf(context).width;
  }

  static int gridColumns(
    BuildContext context, {
    double? width,
    double itemMinWidth = 120,
    int min = 3,
    int max = 8,
  }) {
    final available = width ?? contentWidth(context);
    final columns = (available / itemMinWidth).floor();
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
