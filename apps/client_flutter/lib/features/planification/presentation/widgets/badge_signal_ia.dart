import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

/// Marque tout contenu produit par une fonction IA (placement suggéré,
/// conflit détecté, charge de travail, séance de rattrapage) — jamais une
/// décision automatisée (M11 : `suggerer_placement_seance`,
/// `detecter_conflits_emploi`, `charger_travail_*`, `recommander_seances`).
class BadgeSignalIa extends StatelessWidget {
  const BadgeSignalIa({super.key, this.texte = 'Signal IA — validation humaine requise'});

  final String texte;

  @override
  Widget build(BuildContext context) {
    final premium = context.palette.premium;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: premium.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: premium.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 13, color: premium),
          const SizedBox(width: 5),
          Text(texte, style: TextStyle(color: premium, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
