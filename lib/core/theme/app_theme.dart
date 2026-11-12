import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  /// Cream-led theme (used by the customer app).
  static ThemeData light() => _build(
        ColorScheme(
          brightness: Brightness.light,
          primary: AppColors.fuchsia,
          onPrimary: AppColors.cream,
          secondary: AppColors.charcoal,
          onSecondary: AppColors.cream,
          surface: AppColors.cream,
          onSurface: AppColors.charcoal,
          surfaceContainerHighest: AppColors.beige,
          outline: AppColors.beige,
          error: const Color(0xFFB3261E),
          onError: AppColors.cream,
        ),
      );

  /// Dark-grey-led theme (used by the driver app).
  static ThemeData dark() => _build(
        ColorScheme(
          brightness: Brightness.dark,
          primary: AppColors.fuchsia,
          onPrimary: AppColors.cream,
          secondary: AppColors.beige,
          onSecondary: AppColors.black,
          surface: AppColors.charcoal,
          onSurface: AppColors.cream,
          surfaceContainerHighest: AppColors.graphite,
          outline: AppColors.graphite,
          error: const Color(0xFFFF8A80),
          onError: AppColors.black,
        ),
      );

  static ThemeData _build(ColorScheme scheme) {
    final fill = scheme.brightness == Brightness.light ? Colors.white : AppColors.graphite;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        border: border(scheme.outline),
        enabledBorder: border(scheme.outline),
        focusedBorder: border(scheme.primary, 2),
        errorBorder: border(scheme.error),
        focusedErrorBorder: border(scheme.error, 2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.brightness == Brightness.light ? Colors.white : AppColors.graphite,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, color: scheme.onSurface)),
      ),
    );
  }
}
