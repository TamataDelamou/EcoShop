import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

/// Badge de moyenne — vert menthe si réussite (≥ 10/20), orange pop sinon.
///
/// Couleur strictement indicative (seuil de réussite générique CFA) : elle
/// ne remplace aucune règle de passage propre à l'établissement, qui reste
/// du ressort du bulletin officiel signé (contrat M06).
class MoyenneBadge extends StatelessWidget {
  const MoyenneBadge({super.key, required this.moyenne, this.grande = false});

  final double? moyenne;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final valeur = moyenne;
    final couleur = valeur == null
        ? context.palette.encreSecondaire
        : (valeur >= 10 ? context.palette.succes : context.palette.accent);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: grande ? 16 : 10, vertical: grande ? 8 : 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        valeur == null ? '—' : '${valeur.toStringAsFixed(2)}/20',
        style: TextStyle(
          color: couleur,
          fontWeight: FontWeight.w700,
          fontSize: grande ? 20 : 13,
        ),
      ),
    );
  }
}
