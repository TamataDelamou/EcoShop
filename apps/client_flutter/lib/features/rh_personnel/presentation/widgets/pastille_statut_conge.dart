import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/enums_rh.dart';

/// Pastille de statut d'une demande de congé (demandé / validé / refusé).
class PastilleStatutConge extends StatelessWidget {
  const PastilleStatutConge({super.key, required this.statut});

  final StatutConge statut;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (statut) {
      StatutConge.demande => AppColors.dore,
      StatutConge.valide => AppColors.vertMenthe,
      StatutConge.refuse => AppColors.erreur,
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
