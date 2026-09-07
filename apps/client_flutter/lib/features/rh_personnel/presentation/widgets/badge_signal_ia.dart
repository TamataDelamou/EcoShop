import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Marque tout contenu produit par une fonction IA (score, recommandation) —
/// jamais un verdict, toujours un signal à validation humaine (M8 : risque
/// de turn-over, recommandation de formation, suggestion de remplacement).
/// À poser systématiquement à côté de tout affichage issu de
/// `calculer_score_turnover`, `recommander_formation` ou
/// `optimiser_remplacements`.
class BadgeSignalIa extends StatelessWidget {
  const BadgeSignalIa({super.key, this.texte = 'Signal IA — validation humaine requise'});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.dore.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.dore.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_outlined, size: 13, color: AppColors.dore),
          const SizedBox(width: 5),
          Text(texte, style: const TextStyle(color: AppColors.dore, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
