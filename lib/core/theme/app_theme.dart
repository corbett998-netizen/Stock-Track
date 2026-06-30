import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Single dark [ThemeData] for the app — the product is dark by design (no
/// light theme for the MVP).
ThemeData buildStockTrackTheme() {
  final base = ThemeData.dark(useMaterial3: true);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primaryBlue,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.primaryBlue,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    error: AppColors.lowOrange,
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bgDark,
    colorScheme: colorScheme,
    canvasColor: AppColors.bgDark,
    dividerColor: AppColors.surfaceBorder,
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
      fontFamily: null,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bgDark,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.textPrimary,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      margin: EdgeInsets.zero,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.primaryBlue.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)
            .copyWith(color: AppColors.textSecondary),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.primaryBlue : AppColors.textSecondary,
        );
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceAlt,
      hintStyle: const TextStyle(color: AppColors.textFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.surfaceBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.surfaceBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryBlue),
      ),
    ),
  );
}
