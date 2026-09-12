import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../domain/detail_eleve_pseudonymise.dart';
import '../../domain/message_chat_ia.dart';

/// Une bulle de message — alignée à droite (utilisateur) ou à gauche
/// (assistant). Si [detailEleves] n'est pas vide, affiche le mapping
/// pseudonyme → identité réelle sous la bulle assistant — reçu de
/// `envoyer_message_ia`, jamais construit côté client, jamais envoyé à
/// Anthropic (voir `DetailElevePseudonymise`). Repliable par défaut : le
/// texte de l'IA n'emploie que des pseudonymes, ce tableau est une
/// commodité de lecture pour la direction, pas une donnée renvoyée au
/// modèle.
class BulleMessageIa extends StatefulWidget {
  const BulleMessageIa({super.key, required this.entree, this.detailEleves = const []});

  final MessageChatIa entree;
  final List<DetailElevePseudonymise> detailEleves;

  @override
  State<BulleMessageIa> createState() => _BulleMessageIaState();
}

class _BulleMessageIaState extends State<BulleMessageIa> {
  bool _detailOuvert = false;

  @override
  Widget build(BuildContext context) {
    final estAssistant = widget.entree.estAssistant;
    final palette = context.palette;

    return Align(
      alignment: estAssistant ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          crossAxisAlignment: estAssistant ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: estAssistant ? palette.surface : palette.primaire,
                borderRadius: BorderRadius.circular(16),
                border: estAssistant ? Border.all(color: palette.bordure) : null,
              ),
              child: Text(
                widget.entree.content,
                style: TextStyle(color: estAssistant ? palette.encre : Colors.white),
              ),
            ),
            if (widget.detailEleves.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: TextButton.icon(
                  onPressed: () => setState(() => _detailOuvert = !_detailOuvert),
                  icon: Icon(_detailOuvert ? Icons.expand_less : Icons.expand_more, size: 16),
                  label: Text('${widget.detailEleves.length} élève(s) — voir les identités'),
                ),
              ),
            if (widget.detailEleves.isNotEmpty && _detailOuvert)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: palette.bordure),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final d in widget.detailEleves)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${d.pseudonyme} → ${d.prenom} ${d.nom} (${d.matricule})',
                          style: TextStyle(fontSize: 12, color: palette.encreSecondaire),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
