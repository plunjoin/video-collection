import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import './fonts.dart';

/// 构建全局 Material 3 主题 (明暗 + 强调色)，对齐 Web 端高质感调色板。
ThemeData buildAppTheme(
  Brightness brightness, [
  Color accent = AppColors.brandSolid,
]) {
  final dark = brightness == Brightness.dark;
  final ink = dark ? AppColors.darkTextPrimary : AppColors.ink;
  final muted = dark ? AppColors.darkTextSecondary : AppColors.muted;
  final surface = dark ? AppColors.darkCard : Colors.white;
  final canvas = dark ? AppColors.darkBg : AppColors.lightBg;
  final line = dark ? AppColors.darkBorder : AppColors.line;
  final fill = dark ? const Color(0xFF1E2433) : const Color(0xFFF1F5F9);

  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
    borderSide: BorderSide(color: line),
  );
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.pill),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: AppFonts.family,
    fontFamilyFallback: AppFonts.fallback,
    scaffoldBackgroundColor: canvas,
    primaryColor: accent,
    dividerColor: line,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    ).copyWith(
      primary: accent,
      secondary: AppColors.brandPurple,
      surface: surface,
      onSurface: ink,
      onPrimary: Colors.white,
      outline: line,
      surfaceTint: Colors.transparent,
    ),
    textTheme: TextTheme(
      titleLarge: AppFonts.style(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: .4,
      ),
      titleMedium: AppFonts.style(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: AppFonts.style(fontSize: 14, height: 1.6, color: ink),
      bodyMedium: AppFonts.style(fontSize: 13, height: 1.5, color: ink),
      bodySmall: AppFonts.style(fontSize: 11, height: 1.6, color: muted),
      labelLarge: AppFonts.style(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: line),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: muted, size: 21),
      titleTextStyle: AppFonts.style(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fill,
      border: outline,
      enabledBorder: outline,
      focusedBorder: outline.copyWith(
        borderSide: BorderSide(
          color: accent,
          width: 1.5,
        ),
      ),
      errorBorder: outline.copyWith(
        borderSide: const BorderSide(color: AppColors.rose),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 13,
      ),
      labelStyle: AppFonts.style(fontSize: 13, color: muted),
      hintStyle: AppFonts.style(fontSize: 13, color: muted),
      floatingLabelStyle: AppFonts.style(
        fontSize: 13,
        color: accent,
      ),
      prefixIconColor: muted,
      suffixIconColor: muted,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        shape: buttonShape,
        minimumSize: const Size(40, 36),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        textStyle: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: buttonShape,
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        textStyle: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: buttonShape,
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        textStyle: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: line),
        shape: buttonShape,
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        textStyle: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: muted,
        iconSize: 20,
        minimumSize: const Size(36, 36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xxl)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? AppColors.darkCard : const Color(0xFF1E293B),
      behavior: SnackBarBehavior.floating,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      contentTextStyle: AppFonts.style(fontSize: 13, color: Colors.white),
    ),
    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
  );
}
