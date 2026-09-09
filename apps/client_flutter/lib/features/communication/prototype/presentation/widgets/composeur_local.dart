import 'package:flutter/material.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../domain/moderation_locale.dart';

/// Zone de composition du prototype local (M9) — détecte les termes
/// inappropriés via un lexique local avant l'envoi (`contientTermeInapproprie`)
/// et affiche un avertissement **non bloquant** : l'envoi reste toujours
/// possible, cohérent avec la règle éthique du projet (signal, jamais un
/// blocage automatisé).
class ComposeurLocal extends StatefulWidget {
  const ComposeurLocal({
    super.key,
    required this.onEnvoyer,
    this.champsSupplementaires = const [],
    this.hintText = 'Écrire un message…',
  });

  final void Function(String contenu, {required bool signalee}) onEnvoyer;
  final List<Widget> champsSupplementaires;
  final String hintText;

  @override
  State<ComposeurLocal> createState() => _ComposeurLocalState();
}

class _ComposeurLocalState extends State<ComposeurLocal> {
  final _controleur = TextEditingController();
  bool _signalee = false;

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  void _envoyer() {
    final texte = _controleur.text.trim();
    if (texte.isEmpty) return;
    widget.onEnvoyer(texte, signalee: contientTermeInapproprie(texte));
    _controleur.clear();
    setState(() => _signalee = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(top: BorderSide(color: context.palette.bordure)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...widget.champsSupplementaires,
          if (_signalee)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Terme potentiellement inapproprié détecté — signalé pour modération humaine, envoi non bloqué.',
                style: TextStyle(color: context.palette.accent, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controleur,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.hintText,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (texte) => setState(() => _signalee = contientTermeInapproprie(texte)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.send_outlined),
                onPressed: _envoyer,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
