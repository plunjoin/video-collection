/// bllii 统一 UI 组件库出口。
///
/// 直接放行 Flutter 官方 Material 原生组件，并注入项目全局设计令牌 (AppColors, AppRadius, AppSpacing, AppFonts)
/// 与基础主题构建函数。
library;

// ---- Flutter 官方 Material 原生组件库 ----
export 'package:flutter/material.dart';

// ---- 项目设计令牌与基础扩展 ----
export '../theme/app_colors.dart';
export '../theme/app_radius.dart';
export './fonts.dart';
export './spacing.dart';
export './theme.dart';
export './app.dart';
