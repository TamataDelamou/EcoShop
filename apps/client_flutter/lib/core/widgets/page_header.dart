import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

/// En-tête de page (titre + descriptif, D1) — appliqué pour l'instant
/// uniquement aux 5 onglets racine de la coquille (`coquille_app.dart`) ;
/// les écrans poussés existants l'adopteront au fil de l'eau, quand ils
/// seront eux-mêmes retouchés pour d'autres raisons, jamais dans ce
/// sous-livrable.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.titre, required this.descriptif});

  final String titre;
  final String descriptif;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titre,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: palette.encre),
          ),
          const SizedBox(height: 4),
          Text(descriptif, style: TextStyle(fontSize: 13, color: palette.encreSecondaire)),
        ],
      ),
    );
  }
}
