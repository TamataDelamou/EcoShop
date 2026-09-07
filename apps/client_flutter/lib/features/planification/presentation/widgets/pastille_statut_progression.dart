import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/enums_planification.dart';

/// Pastille de statut d'une séance de progression pédagogique.
class PastilleStatutProgression extends StatelessWidget {
  const PastilleStatutProgression({super.key, required this.statut});

  final StatutProgression statut;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (statut) {
      StatutProgression.planifiee => AppColors.bleuElectrique,
      StatutProgression.realisee => AppColors.vertMenthe,
      StatutProgression.reportee => AppColors.orangePop,
      StatutProgression.annulee => AppColors.encreSecondaire,
      StatutProgression.proposee => AppColors.dore,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(statut.libelle, style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
