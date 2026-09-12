import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

/// Bandeau permanent du chat IA — même discipline que `BadgeSignalIa`
/// (M10/M16) : jamais une décision automatisée, toujours un signal à
/// validation humaine. Affiché une seule fois en haut de l'écran plutôt que
/// répété sur chaque bulle, pour ne pas noyer la conversation.
class BadgeSignalIaChat extends StatelessWidget {
  const BadgeSignalIaChat({super.key});

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
          Text(
            'Réponses générées par IA — validation humaine requise',
            style: TextStyle(color: context.palette.premium, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
