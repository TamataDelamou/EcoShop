import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../domain/enums_comm.dart';

/// Pastille de statut de notification (en attente / envoyée / lue / échouée
/// / annulée).
class PastilleStatutNotification extends StatelessWidget {
  const PastilleStatutNotification({super.key, required this.statut});

  final StatutNotification statut;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (statut) {
      StatutNotification.enAttente => context.palette.premium,
      StatutNotification.envoyee => context.palette.primaire,
      StatutNotification.lue => context.palette.succes,
      StatutNotification.echouee => context.palette.erreur,
      StatutNotification.annulee => context.palette.encreSecondaire,
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
