import 'package:flutter/material.dart';

/// Jeu de couleurs sémantiques d'une charte graphique EcoShop, pour un
/// [AppThemeVariant] et une luminosité (clair/sombre) donnés.
///
/// Remplace les anciennes constantes statiques `AppColors.xxx` : les couleurs
/// ne sont plus figées à la compilation, elles dépendent du thème actif et se
/// lisent via `context.palette` (voir `app_palette_x.dart`), ce qui permet au
/// mode sombre et aux variantes d'établissement de s'appliquer à l'écran sans
/// reconstruire chaque widget à la main.
///
/// Chaque teinte est vérifiée au ratio de contraste WCAG AA (4.5:1 pour un
/// texte normal) contre [fond] — voir `docs/contrats/M15bis_themes_dark_mode.md`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.fond,
    required this.surface,
    required this.bordure,
    required this.encre,
    required this.encreSecondaire,
    required this.primaire,
    required this.accent,
    required this.succes,
    required this.premium,
    required this.erreur,
  });

  /// Fond général (scaffold).
  final Color fond;

  /// Fond des surfaces élevées (cartes, feuilles, champs).
  final Color surface;

  /// Bordures et séparateurs.
  final Color bordure;

  /// Texte principal.
  final Color encre;

  /// Texte secondaire / atténué.
  final Color encreSecondaire;

  /// Couleur d'action principale (navigation, CTA primaire).
  final Color primaire;

  /// Couleur d'accent (CTA secondaire, mise en avant).
  final Color accent;

  /// Succès / validation.
  final Color succes;

  /// Marqueur haut de gamme (Pro, Premium, signal IA).
  final Color premium;

  /// Erreur / alerte bloquante.
  final Color erreur;

  @override
  AppPalette copyWith({
    Color? fond,
    Color? surface,
    Color? bordure,
    Color? encre,
    Color? encreSecondaire,
    Color? primaire,
    Color? accent,
    Color? succes,
    Color? premium,
    Color? erreur,
  }) {
    return AppPalette(
      fond: fond ?? this.fond,
      surface: surface ?? this.surface,
      bordure: bordure ?? this.bordure,
      encre: encre ?? this.encre,
      encreSecondaire: encreSecondaire ?? this.encreSecondaire,
      primaire: primaire ?? this.primaire,
      accent: accent ?? this.accent,
      succes: succes ?? this.succes,
      premium: premium ?? this.premium,
      erreur: erreur ?? this.erreur,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      fond: Color.lerp(fond, other.fond, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      bordure: Color.lerp(bordure, other.bordure, t)!,
      encre: Color.lerp(encre, other.encre, t)!,
      encreSecondaire: Color.lerp(encreSecondaire, other.encreSecondaire, t)!,
      primaire: Color.lerp(primaire, other.primaire, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      succes: Color.lerp(succes, other.succes, t)!,
      premium: Color.lerp(premium, other.premium, t)!,
      erreur: Color.lerp(erreur, other.erreur, t)!,
    );
  }
}

/// Repli si aucun [AppPalette] n'est enregistré dans le thème ambiant — un
/// `MaterialApp` de test construit sans `construireThemeData` (widget tests
/// isolés), par exemple. Mêmes valeurs que `AppPalettes.francophoneCfaLight`,
/// dupliquées ici pour éviter un import circulaire avec `app_palettes.dart`.
const _paletteReplie = AppPalette(
  fond: Color(0xFFF8FAFC),
  surface: Colors.white,
  bordure: Color(0xFFE2E8F0),
  encre: Color(0xFF0F172A),
  encreSecondaire: Color(0xFF475569),
  primaire: Color(0xFF2563EB),
  accent: Color(0xFFFF6B00),
  succes: Color(0xFF10B981),
  premium: Color(0xFFE1A100),
  erreur: Color(0xFFDC2626),
);

/// Accès ergonomique à la palette du thème actif : `context.palette.primaire`.
extension AppPaletteContextX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? _paletteReplie;
}
