import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/enums_notes.dart';

/// Pastille de statut d'une évaluation (brouillon / publiée / clôturée).
class PastilleStatutEvaluation extends StatelessWidget {
  const PastilleStatutEvaluation({super.key, required this.statut});

  final StatutEvaluation statut;

  @override
  Widget build(BuildContext context) {
    final (couleur, libelle) = switch (statut) {
      StatutEvaluation.brouillon => (AppColors.encreSecondaire, 'Brouillon'),
      StatutEvaluation.publiee => (AppColors.vertMenthe, 'Publiée'),
      StatutEvaluation.cloturee => (AppColors.bleuElectrique, 'Clôturée'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        libelle,
        style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
