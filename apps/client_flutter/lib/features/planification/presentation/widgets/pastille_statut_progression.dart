import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

import '../../domain/enums_planification.dart';

/// Pastille de statut d'une séance de progression pédagogique.
class PastilleStatutProgression extends StatelessWidget {
  const PastilleStatutProgression({super.key, required this.statut});

  final StatutProgression statut;

  @override
  Widget build(BuildContext context) {
    final couleur = switch (statut) {
      StatutProgression.planifiee => context.palette.primaire,
      StatutProgression.realisee => context.palette.succes,
      StatutProgression.reportee => context.palette.accent,
      StatutProgression.annulee => context.palette.encreSecondaire,
      StatutProgression.proposee => context.palette.premium,
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
