import 'package:flutter/material.dart';

/// Petite pastille d'information neutre (libellé court, fond teinté léger).
///
/// Réservée aux libellés informatifs (langue, ISCED, coefficient…) — jamais
/// utilisée pour un état de succès/échec, qui reste porté par les couleurs de
/// feedback dédiées de la charte.
class Pastille extends StatelessWidget {
  const Pastille({
    super.key,
    required this.texte,
    required this.couleur,
    this.icone,
  });

  final String texte;
  final Color couleur;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 13, color: couleur),
            const SizedBox(width: 4),
          ],
          Text(
            texte,
            style: TextStyle(
              color: couleur,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
