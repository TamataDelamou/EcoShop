import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/enums_vie_scolaire.dart';

/// Pastille de statut de présence (présent / absent / retard / exclu / dispensé).
class PastilleStatutPresence extends StatelessWidget {
  const PastilleStatutPresence({super.key, required this.statut});

  final StatutPresence statut;

  @override
  Widget build(BuildContext context) {
    final (couleur, icone) = switch (statut) {
      StatutPresence.present => (AppColors.vertMenthe, Icons.check_circle_outline),
      StatutPresence.absent => (AppColors.erreur, Icons.cancel_outlined),
      StatutPresence.retard => (AppColors.orangePop, Icons.schedule_outlined),
      StatutPresence.exclu => (AppColors.encreSecondaire, Icons.block_outlined),
      StatutPresence.dispense => (AppColors.bleuElectrique, Icons.event_busy_outlined),
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
