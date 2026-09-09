import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

/// Marque tout contenu produit par une fonction IA (score, recommandation,
/// alerte) — jamais un verdict, toujours un signal à validation humaine
/// (contrat M07 §5, éthique IA). À poser systématiquement à côté de tout
/// affichage issu de `calculer_score_decrochage`, `recommander_sanction_educative`
/// ou d'une sanction `origine = ia`.
class BadgeSignalIa extends StatelessWidget {
  const BadgeSignalIa({super.key, this.texte = 'Signal IA — validation humaine requise'});

  final String texte;

  @override
  Widget build(BuildContext context) {
    final couleur = context.palette.premium;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: couleur.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 13, color: couleur),
          const SizedBox(width: 5),
          Text(texte, style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
