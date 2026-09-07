import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/enums_comm.dart';

/// Pastille de statut de notification (en attente / envoyée / lue / échouée
/// / annulée).
class PastilleStatutNotification extends StatelessWidget {
  const PastilleStatutNotification({super.key, required this.statut});

  final StatutNotification statut;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (statut) {
      StatutNotification.enAttente => AppColors.dore,
      StatutNotification.envoyee => AppColors.bleuElectrique,
      StatutNotification.lue => AppColors.vertMenthe,
      StatutNotification.echouee => AppColors.erreur,
      StatutNotification.annulee => AppColors.encreSecondaire,
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
