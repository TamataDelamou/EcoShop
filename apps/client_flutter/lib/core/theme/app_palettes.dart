import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_theme_variant.dart';

/// Catalogue des 6 palettes (3 variantes × clair/sombre).
///
/// Chaque couleur de texte/icône a été vérifiée au ratio de contraste WCAG AA
/// contre son fond usuel (4.5:1 texte normal, 3:1 grands textes/UI) — voir
/// `docs/contrats/M15bis_themes_dark_mode.md` §3 pour le détail des mesures.
/// `francophoneCfaLight` reprend telle quelle la charte « Innovation &
/// Énergie » déjà approuvée (cahier v4.1 ch. 2) : ses teintes ne sont pas
/// modifiées par ce module.
abstract final class AppPalettes {
  static const francophoneCfaLight = AppPalette(
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

  static const francophoneCfaDark = AppPalette(
    fond: Color(0xFF0F172A),
    surface: Color(0xFF1E293B),
    bordure: Color(0xFF334155),
    encre: Color(0xFFF1F5F9),
    encreSecondaire: Color(0xFF94A3B8),
    primaire: Color(0xFF60A5FA),
    accent: Color(0xFFFF8A3D),
    succes: Color(0xFF34D399),
    premium: Color(0xFFFBBF24),
    erreur: Color(0xFFF87171),
  );

  /// Anglophone WAEC — bleu marine et or, esthétique « conseil d'examen ».
  static const anglophoneWaecLight = AppPalette(
    fond: Color(0xFFF7F8FA),
    surface: Colors.white,
    bordure: Color(0xFFDDE3EA),
    encre: Color(0xFF12203A),
    encreSecondaire: Color(0xFF51607A),
    primaire: Color(0xFF1E3A8A),
    accent: Color(0xFF8C2F39),
    succes: Color(0xFF157F5A),
    premium: Color(0xFF7A5E15),
    erreur: Color(0xFFB3261E),
  );

  static const anglophoneWaecDark = AppPalette(
    fond: Color(0xFF0B1220),
    surface: Color(0xFF16213A),
    bordure: Color(0xFF2A3B5C),
    encre: Color(0xFFE8ECF4),
    encreSecondaire: Color(0xFFA9B4C9),
    primaire: Color(0xFF7C9EFA),
    accent: Color(0xFFD97B87),
    succes: Color(0xFF34C28F),
    premium: Color(0xFFE3C05B),
    erreur: Color(0xFFFF6B6B),
  );

  /// Lusophone — vert et terre cuite, palette Afrique lusophone.
  static const lusophoneLight = AppPalette(
    fond: Color(0xFFF8FAF7),
    surface: Colors.white,
    bordure: Color(0xFFDCE7DC),
    encre: Color(0xFF16241B),
    encreSecondaire: Color(0xFF4B5D4E),
    primaire: Color(0xFF0F7A4B),
    accent: Color(0xFFA8531A),
    succes: Color(0xFF0F7A52),
    premium: Color(0xFF7C5B18),
    erreur: Color(0xFFC1362A),
  );

  static const lusophoneDark = AppPalette(
    fond: Color(0xFF0D1710),
    surface: Color(0xFF16261B),
    bordure: Color(0xFF2A3D2E),
    encre: Color(0xFFE9F1EA),
    encreSecondaire: Color(0xFFA9BDAC),
    primaire: Color(0xFF4FBE86),
    accent: Color(0xFFE7975A),
    succes: Color(0xFF3FCB93),
    premium: Color(0xFFE0B24E),
    erreur: Color(0xFFFF8577),
  );

  static AppPalette pour(AppThemeVariant variante, Brightness brightness) {
    final sombre = brightness == Brightness.dark;
    return switch (variante) {
      AppThemeVariant.francophoneCfa =>
        sombre ? francophoneCfaDark : francophoneCfaLight,
      AppThemeVariant.anglophoneWaec =>
        sombre ? anglophoneWaecDark : anglophoneWaecLight,
      AppThemeVariant.lusophone => sombre ? lusophoneDark : lusophoneLight,
    };
  }
}
