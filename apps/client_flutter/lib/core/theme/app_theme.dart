import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Thème Material 3 aligné sur la charte « Innovation & Énergie ».
ThemeData appTheme() {
  final base = ThemeData(useMaterial3: true);

  return base.copyWith(
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.bleuElectrique)
        .copyWith(
          primary: AppColors.bleuElectrique,
          secondary: AppColors.orangePop,
          surface: AppColors.surface,
          error: AppColors.erreur,
        ),
    scaffoldBackgroundColor: AppColors.fond,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.encre,
      elevation: 0,
    ),
    cardTheme: base.cardTheme.copyWith(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.bordure),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.bleuElectrique,
        foregroundColor: Colors.white,
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.encre,
      displayColor: AppColors.encre,
    ),
  );
}
