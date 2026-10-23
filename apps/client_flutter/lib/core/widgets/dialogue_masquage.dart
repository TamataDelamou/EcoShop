import 'package:flutter/material.dart';

/// Raison du masquage (modération). Renvoie la raison, ou null si annulé.
class DialogueMasquage extends StatefulWidget {
  const DialogueMasquage({super.key, this.texte = 'Les familles ne la verront plus. Elle reste dans votre liste, '
      'et l’action est inscrite au journal (vous, la date, la raison).'});

  final String texte;

  @override
  State<DialogueMasquage> createState() => _DialogueMasquageState();
}

class _DialogueMasquageState extends State<DialogueMasquage> {
  final _motif = TextEditingController();

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Masquer ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.texte),
          const SizedBox(height: 12),
          TextField(
            key: const Key('champ_motif_masquage'),
            controller: _motif,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Raison'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_motif.text), child: const Text('Masquer')),
      ],
    );
  }
}
