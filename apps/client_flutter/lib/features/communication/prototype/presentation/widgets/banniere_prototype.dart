import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

/// Bandeau permanent rappelant qu'un écran appartient au **prototype local**
/// de M9 : aucune donnée n'est envoyée au serveur, rien n'est partagé entre
/// appareils ni entre utilisateurs, et le contenu sera remplacé quand une
/// migration backend dédiée (conversations/annonces/cahier de liaison) sera
/// livrée. À poser en tête de chaque écran du dossier `prototype/`.
class BanniereProtoype extends StatelessWidget {
  const BanniereProtoype({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: context.palette.accent.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.science_outlined, size: 16, color: context.palette.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Prototype local — non synchronisé, visible sur cet appareil uniquement.',
              style: TextStyle(color: context.palette.accent, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
