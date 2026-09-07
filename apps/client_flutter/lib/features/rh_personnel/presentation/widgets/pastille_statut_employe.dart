import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/enums_rh.dart';

/// Pastille de statut employé (actif / en congé / suspendu / démissionnaire
/// / retraité).
class PastilleStatutEmploye extends StatelessWidget {
  const PastilleStatutEmploye({super.key, required this.statut});

  final StatutEmploye statut;

  @override
  Widget build(BuildContext context) {
    final (couleur, icone) = switch (statut) {
      StatutEmploye.actif => (AppColors.vertMenthe, Icons.check_circle_outline),
      StatutEmploye.enConge => (AppColors.bleuElectrique, Icons.beach_access_outlined),
      StatutEmploye.suspendu => (AppColors.orangePop, Icons.pause_circle_outline),
      StatutEmploye.demissionnaire => (AppColors.encreSecondaire, Icons.logout),
      StatutEmploye.retraite => (AppColors.encreSecondaire, Icons.elderly_outlined),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: couleur),
          const SizedBox(width: 4),
          Text(statut.libelle, style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
