import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Couleur d'identité d'un établissement — outils de lisibilité.
///
/// La Direction choisit librement sa couleur ; l'application l'AJUSTE
/// automatiquement (même teinte, luminosité corrigée) pour qu'elle reste
/// lisible selon la norme WCAG AA (4,5:1) dans les deux modes :
///   • mode clair  : texte blanc sur un bouton de cette couleur, et cette
///                   couleur utilisée comme texte sur le fond de page ;
///   • mode sombre : texte sombre (`fond`) sur le bouton, et cette couleur
///                   utilisée comme texte sur le fond et les surfaces.
/// Une couleur trop claire est donc foncée en mode clair, une couleur trop
/// foncée éclaircie en mode sombre — jamais refusée.
abstract final class CouleurIdentite {
  static const seuilWcag = 4.5;

  /// Ratio de contraste WCAG entre deux couleurs.
  static double contraste(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// Couleur lisible en mode clair (sur [fond], avec du texte blanc dessus).
  static Color pourModeClair(Color couleur, Color fond) {
    return _ajuster(couleur, (c) => contraste(Colors.white, c) >= seuilWcag && contraste(c, fond) >= seuilWcag,
        sens: -1);
  }

  /// Couleur lisible en mode sombre (sur [fond] et [surface]).
  static Color pourModeSombre(Color couleur, Color fond, Color surface) {
    return _ajuster(couleur, (c) => contraste(fond, c) >= seuilWcag && contraste(c, surface) >= seuilWcag,
        sens: 1);
  }

  static Color _ajuster(Color couleur, bool Function(Color) lisible, {required int sens}) {
    if (lisible(couleur)) return couleur;
    var hsl = HSLColor.fromColor(couleur);
    for (var i = 0; i < 60; i++) {
      final l = (hsl.lightness + sens * 0.02).clamp(0.0, 1.0);
      hsl = hsl.withLightness(l);
      final candidate = hsl.toColor();
      if (lisible(candidate)) return candidate;
      if (l == 0.0 || l == 1.0) break;
    }
    // Repli extrême (ne devrait pas arriver) : noir ou blanc, toujours lisibles.
    return sens < 0 ? const Color(0xFF111111) : const Color(0xFFF5F5F5);
  }

  /// `#RRGGBB` -> couleur ; null si absent ou mal formé.
  static Color? depuisHex(String? hex) {
    if (hex == null) return null;
    final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(hex.trim());
    if (m == null) return null;
    return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
  }

  /// Couleur -> `#RRGGBB` (majuscules), format stocké en base.
  static String versHex(Color couleur) {
    String canal(double v) => (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${canal(couleur.r)}${canal(couleur.g)}${canal(couleur.b)}'.toUpperCase();
  }
}
