import 'package:flutter/painting.dart';

/// 应用字体配置:San Francisco,中文缺字回退苹方/微软雅黑。
abstract final class AppFonts {
  static const family = 'SF Pro Text';
  static const fallback = <String>[
    'SF Pro Display',
    '.SF Pro Text',
    '.SF Pro Display',
    '.AppleSystemUIFont',
    'PingFang SC',
    'Segoe UI',
    'Microsoft YaHei UI',
    'Microsoft YaHei',
  ];

  static TextStyle style({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: family,
      fontFamilyFallback: fallback,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }
}
