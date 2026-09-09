import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

/// Marque tout contenu produit par une fonction IA (score de risque,
/// anomalie, recommandation, résumé exécutif) — jamais une décision
/// automatisée, toujours un signal à validation humaine (M10 : `detecter_anomalies`,
/// `risque_classe`, `recommander_actions`, `generer_resume_executif`).
class BadgeSignalIa extends StatelessWidget {
  const BadgeSignalIa({super.key, this.texte = 'Signal IA — validation humaine requise'});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.palette.premium.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.palette.premium.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 13, color: context.palette.premium),
          const SizedBox(width: 5),
          Text(texte, style: TextStyle(color: context.palette.premium, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
