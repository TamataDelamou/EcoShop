import 'package:flutter/material.dart';

import 'app_palettes.dart';
import 'app_theme_variant.dart';

/// Construit le thème Material 3 d'une variante d'établissement pour une
/// luminosité donnée (M15bis — thèmes internationaux & mode sombre).
///
/// Remplace l'ancienne fonction `appTheme()` à thème unique : chaque écran lit
/// désormais ses couleurs via `context.palette` plutôt que la constante
/// statique `AppColors`, ce qui permet au thème de changer réellement à
/// l'exécution (variante d'établissement, bascule clair/sombre) sans redémarrer
/// l'application.
ThemeData construireThemeData(AppThemeVariant variante, Brightness brightness) {
  final palette = AppPalettes.pour(variante, brightness);
  final base = ThemeData(useMaterial3: true, brightness: brightness);
  // Sur fond sombre, une couleur d'action assombrie perd son contraste : le
  // bouton reste dans la teinte de la palette (déjà éclaircie pour le mode
  // sombre) mais le texte passe au ton `fond` (le plus sombre de la palette,
  // pas `encre` qui lui est clair en mode sombre) plutôt qu'au blanc — c'est
  // ce choix qui fait passer les boutons de ~2:1 à plus de 7:1 de contraste
  // (mesures dans `docs/contrats/M15bis_themes_dark_mode.md` §3).
  final texteSurBoutonPrimaire =
      brightness == Brightness.dark ? palette.fond : Colors.white;

  return base.copyWith(
    extensions: [palette],
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette.primaire,
      brightness: brightness,
    ).copyWith(
      primary: palette.primaire,
      secondary: palette.accent,
      surface: palette.surface,
      error: palette.erreur,
    ),
    scaffoldBackgroundColor: palette.fond,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.surface,
      foregroundColor: palette.encre,
      elevation: 0,
    ),
    cardTheme: base.cardTheme.copyWith(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.bordure),
      ),
    ),
    dividerTheme: DividerThemeData(color: palette.bordure, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.primaire,
        foregroundColor: texteSurBoutonPrimaire,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.bordure),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.bordure),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.primaire, width: 1.5),
      ),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: palette.encre,
      displayColor: palette.encre,
    ),
  );
}
