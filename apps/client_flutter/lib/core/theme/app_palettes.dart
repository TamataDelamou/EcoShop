import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'ambiance_visuelle.dart';
import 'app_theme_variant.dart';
import 'couleur_identite.dart';

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

  /// Arabophone mixte (REG-07) — sarcelle profonde et cuivre sur fond sable.
  static const arabophoneMixteLight = AppPalette(
    fond: Color(0xFFF9F7F2),
    surface: Colors.white,
    bordure: Color(0xFFE7E1D3),
    encre: Color(0xFF1F1A12),
    encreSecondaire: Color(0xFF5C5446),
    primaire: Color(0xFF0E6B5C),
    accent: Color(0xFF9A4A0B),
    succes: Color(0xFF0F7A52),
    premium: Color(0xFF7A5B10),
    erreur: Color(0xFFB42318),
  );

  static const arabophoneMixteDark = AppPalette(
    fond: Color(0xFF12100C),
    surface: Color(0xFF1D1A14),
    bordure: Color(0xFF3A3428),
    encre: Color(0xFFF3EEE4),
    encreSecondaire: Color(0xFFB8AE9B),
    primaire: Color(0xFF4CC2A9),
    accent: Color(0xFFE39A5B),
    succes: Color(0xFF40C98F),
    premium: Color(0xFFE2B652),
    erreur: Color(0xFFFF7B6B),
  );

  // -------------------------------------------------------------------------
  // Ambiances personnelles (REG-07 C) — choisies par l'utilisateur.
  // -------------------------------------------------------------------------

  static const oceanLight = AppPalette(
    fond: Color(0xFFF5F9FB),
    surface: Colors.white,
    bordure: Color(0xFFD6E4EC),
    encre: Color(0xFF0B2230),
    encreSecondaire: Color(0xFF46606F),
    primaire: Color(0xFF0B6E99),
    accent: Color(0xFFB4432F),
    succes: Color(0xFF117A52),
    premium: Color(0xFF7A5C12),
    erreur: Color(0xFFB3261E),
  );

  static const oceanDark = AppPalette(
    fond: Color(0xFF07161E),
    surface: Color(0xFF0F2430),
    bordure: Color(0xFF22404F),
    encre: Color(0xFFE6F2F7),
    encreSecondaire: Color(0xFF9DB7C4),
    primaire: Color(0xFF4FC0E8),
    accent: Color(0xFFF08A73),
    succes: Color(0xFF3FCB93),
    premium: Color(0xFFE3BE5A),
    erreur: Color(0xFFFF7A70),
  );

  static const savaneLight = AppPalette(
    fond: Color(0xFFFBF7F0),
    surface: Colors.white,
    bordure: Color(0xFFEADFCB),
    encre: Color(0xFF2A1D0E),
    encreSecondaire: Color(0xFF66553C),
    primaire: Color(0xFF9A4D06),
    accent: Color(0xFF1F6E5A),
    succes: Color(0xFF2E7D32),
    premium: Color(0xFF7A5B10),
    erreur: Color(0xFFB42318),
  );

  static const savaneDark = AppPalette(
    fond: Color(0xFF16110A),
    surface: Color(0xFF231B11),
    bordure: Color(0xFF41331F),
    encre: Color(0xFFF5ECDD),
    encreSecondaire: Color(0xFFC2B193),
    primaire: Color(0xFFF0A04B),
    accent: Color(0xFF5FC9A8),
    succes: Color(0xFF6FCF7A),
    premium: Color(0xFFE7C15E),
    erreur: Color(0xFFFF8070),
  );

  static const graphiteLight = AppPalette(
    fond: Color(0xFFF6F7F8),
    surface: Colors.white,
    bordure: Color(0xFFDDE1E5),
    encre: Color(0xFF15181C),
    encreSecondaire: Color(0xFF50565E),
    primaire: Color(0xFF2F3A48),
    accent: Color(0xFF0F62C9),
    succes: Color(0xFF157F4E),
    premium: Color(0xFF7A5C12),
    erreur: Color(0xFFB3261E),
  );

  static const graphiteDark = AppPalette(
    fond: Color(0xFF0F1114),
    surface: Color(0xFF1A1D22),
    bordure: Color(0xFF30353C),
    encre: Color(0xFFEDEFF2),
    encreSecondaire: Color(0xFFA3AAB4),
    primaire: Color(0xFFB9C3D0),
    accent: Color(0xFF7CB2FF),
    succes: Color(0xFF4CD08F),
    premium: Color(0xFFE0BC5C),
    erreur: Color(0xFFFF7C74),
  );

  static AppPalette pour(AppThemeVariant variante, Brightness brightness) {
    final sombre = brightness == Brightness.dark;
    return switch (variante) {
      AppThemeVariant.francophoneCfa =>
        sombre ? francophoneCfaDark : francophoneCfaLight,
      AppThemeVariant.anglophoneWaec =>
        sombre ? anglophoneWaecDark : anglophoneWaecLight,
      AppThemeVariant.lusophone => sombre ? lusophoneDark : lusophoneLight,
      AppThemeVariant.arabophoneMixte => sombre ? arabophoneMixteDark : arabophoneMixteLight,
    };
  }

  /// Palette d'une ambiance personnelle (null pour [AmbianceVisuelle.etablissement]).
  static AppPalette? pourAmbiance(AmbianceVisuelle ambiance, Brightness brightness) {
    final sombre = brightness == Brightness.dark;
    return switch (ambiance) {
      AmbianceVisuelle.etablissement => null,
      AmbianceVisuelle.ocean => sombre ? oceanDark : oceanLight,
      AmbianceVisuelle.savane => sombre ? savaneDark : savaneLight,
      AmbianceVisuelle.graphite => sombre ? graphiteDark : graphiteLight,
    };
  }

  /// Palette effective, par ordre de priorité :
  ///   1. contraste élevé (accessibilité) ;
  ///   2. ambiance personnelle choisie par l'utilisateur ;
  ///   3. charte de l'établissement (variante du pays), avec sa couleur
  ///      d'identité si la Direction en a défini une — toujours ajustée pour
  ///      rester lisible (voir [CouleurIdentite]).
  static AppPalette resoudre(
    AppThemeVariant variante,
    Brightness brightness, {
    bool contrasteEleve = false,
    AmbianceVisuelle ambiance = AmbianceVisuelle.etablissement,
    Color? couleurEtablissement,
  }) {
    if (contrasteEleve) return hauteVisibilite(brightness);
    final personnelle = pourAmbiance(ambiance, brightness);
    if (personnelle != null) return personnelle;
    final base = pour(variante, brightness);
    if (couleurEtablissement == null) return base;
    final primaire = brightness == Brightness.dark
        ? CouleurIdentite.pourModeSombre(couleurEtablissement, base.fond, base.surface)
        : CouleurIdentite.pourModeClair(couleurEtablissement, base.fond);
    return base.copyWith(primaire: primaire);
  }

  /// Palette « contraste élevé » (D4, §34.9) — une seule paire clair/sombre,
  /// dédiée et indépendante des 3 variantes d'établissement (le but ici est
  /// la lisibilité maximale, pas l'identité de marque). Ratios WCAG mesurés
  /// (`app_palettes_test.dart`) : tous les couples texte/fond dépassent
  /// largement le seuil AA de 4,5:1 (la plupart ≥ 7:1, souvent proche de
  /// 21:1 pour `encre`/`fond`), avec une marge volontairement large plutôt
  /// que des teintes en limite basse.
  static const hauteVisibiliteLight = AppPalette(
    fond: Colors.white,
    surface: Color(0xFFF0F0F0),
    bordure: Colors.black,
    encre: Colors.black,
    encreSecondaire: Color(0xFF262626),
    primaire: Color(0xFF0000CC),
    accent: Color(0xFF8A3800),
    succes: Color(0xFF006400),
    premium: Color(0xFF7A5C00),
    erreur: Color(0xFFB00020),
  );

  static const hauteVisibiliteDark = AppPalette(
    fond: Colors.black,
    surface: Color(0xFF1A1A1A),
    bordure: Colors.white,
    encre: Colors.white,
    encreSecondaire: Color(0xFFD9D9D9),
    primaire: Color(0xFF66B2FF),
    accent: Color(0xFFFFB870),
    succes: Color(0xFF6FE38A),
    premium: Color(0xFFFFD966),
    erreur: Color(0xFFFF8A80),
  );

  static AppPalette hauteVisibilite(Brightness brightness) =>
      brightness == Brightness.dark ? hauteVisibiliteDark : hauteVisibiliteLight;
}
