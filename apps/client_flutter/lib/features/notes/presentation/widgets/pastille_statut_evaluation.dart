import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../domain/enums_notes.dart';

/// Pastille de statut d'une évaluation (brouillon / publiée / clôturée).
class PastilleStatutEvaluation extends StatelessWidget {
  const PastilleStatutEvaluation({super.key, required this.statut});

  final StatutEvaluation statut;

  @override
  Widget build(BuildContext context) {
    final (couleur, libelle) = switch (statut) {
      StatutEvaluation.brouillon => (context.palette.encreSecondaire, 'Brouillon'),
      StatutEvaluation.publiee => (context.palette.succes, 'Publiée'),
      StatutEvaluation.cloturee => (context.palette.primaire, 'Clôturée'),
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
