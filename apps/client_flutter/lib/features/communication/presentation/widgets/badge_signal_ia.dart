import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

/// Marque tout contenu produit par une fonction IA (canal recommandé, heure
/// suggérée, sentiment, variante A/B) — jamais un envoi automatisé sans
/// validation, toujours un signal d'aide à la décision (M9 : `choisir_canal`,
/// `suggere_heure_envoi`, `analyser_feedback`, `selectionner_variante`).
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
