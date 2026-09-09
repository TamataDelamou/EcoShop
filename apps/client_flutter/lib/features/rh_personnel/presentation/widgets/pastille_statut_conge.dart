import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../domain/enums_rh.dart';

/// Pastille de statut d'une demande de congé (demandé / validé / refusé).
class PastilleStatutConge extends StatelessWidget {
  const PastilleStatutConge({super.key, required this.statut});

  final StatutConge statut;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final couleur = switch (statut) {
      StatutConge.demande => palette.premium,
      StatutConge.valide => palette.succes,
      StatutConge.refuse => palette.erreur,
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
