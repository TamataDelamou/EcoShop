import 'package:flutter/material.dart';

/// Charte graphique « Innovation & Énergie » (cahier v4.1, ch. 2).
///
/// Répartition : base 70 % (fond + bleu électrique), accent 20 % (orange pop),
/// touches premium 10 % (vert menthe + doré métallisé).
abstract final class AppColors {
  // Base dominante (70 %)
  static const Color fond = Color(0xFFF8FAFC); // blanc cassé / gris très clair
  static const Color bleuElectrique = Color(0xFF2563EB);
  static const Color encre = Color(0xFF0F172A); // texte principal
  static const Color encreSecondaire = Color(0xFF475569);

  // Accent (20 %)
  static const Color orangePop = Color(0xFFFF6B00);

  // Touches premium & dynamisme (10 %)
  static const Color vertMenthe = Color(0xFF10B981); // succès / validation
  static const Color dore = Color(0xFFE1A100); // haut de gamme (Pro, Premium)

  // États
  static const Color erreur = Color(0xFFDC2626);
  static const Color surface = Colors.white;
  static const Color bordure = Color(0xFFE2E8F0);
}
