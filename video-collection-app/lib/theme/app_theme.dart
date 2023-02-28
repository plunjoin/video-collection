import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme => _build(Brightness.light);
  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData themed(Brightness brightness, Color accent) =>
      _build(brightness, accent);

  static ThemeData _build(
    Brightness brightness, [
    Color accent = AppColors.primary600,
  ]) {
    final dark = brightness == Brightness.dark;
    final ink = dark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final surface = dark ? AppColors.darkCard : Colors.white;
    final canvas = dark ? AppColors.darkBg : AppColors.lightBg;
    final line = dark ? AppColors.darkBorder : AppColors.lightBorder;
    final fill = dark ? const Color(0xFF243049) : const Color(0xFFF4F6FE);
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(15),
      borderSide: BorderSide(color: line),
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: canvas,
      primaryColor: accent,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: AppColors.purple.withValues(alpha: .05),
      dividerColor: line,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: accent,
            brightness: brightness,
          ).copyWith(
            primary: accent,
            secondary: accent,
            surface: surface,
            onSurface: ink,
            onPrimary: Colors.white,
            outline: line,
            surfaceTint: Colors.transparent,
          ),
      textTheme: TextTheme(
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: .4,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyLarge: TextStyle(fontSize: 14, height: 1.6, color: ink),
        bodyMedium: TextStyle(fontSize: 13, height: 1.5, color: ink),
        bodySmall: TextStyle(fontSize: 11, height: 1.6, color: muted),
        labelLarge: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.all(0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: line),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: muted, size: 21),
        titleTextStyle: TextStyle(
          fontSize: 19,
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
            color: AppColors.purple.withValues(alpha: .6),
            width: 1.2,
          ),
        ),
        errorBorder: outline.copyWith(
          borderSide: const BorderSide(color: AppColors.rose),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: TextStyle(fontSize: 12, color: muted),
        hintStyle: TextStyle(fontSize: 12, color: muted),
        floatingLabelStyle: const TextStyle(
          fontSize: 12,
          color: AppColors.purple,
        ),
        prefixIconColor: muted,
        suffixIconColor: muted,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: buttonShape,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: buttonShape,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: dark
              ? AppColors.primary200
              : const Color(0xFF7E79B6),
          backgroundColor: fill,
          side: BorderSide(color: line),
          shape: buttonShape,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 12),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: muted,
          iconSize: 21,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: const Color(0x227580B8),
        textStyle: TextStyle(fontSize: 12, color: ink),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.purple,
        textColor: ink,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? AppColors.darkCard : const Color(0xFF555F83),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentTextStyle: const TextStyle(fontSize: 12, color: Colors.white),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.purple,
        inactiveTrackColor: line,
        thumbColor: AppColors.rose,
        trackHeight: 3,
        overlayColor: AppColors.purple.withValues(alpha: .1),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.purple,
        linearMinHeight: 3,
      ),
      dividerTheme: DividerThemeData(color: line, thickness: .7, space: 1),
    );
  }
}
