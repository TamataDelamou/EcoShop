import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/justificatifs_providers.dart';
import '../domain/justificatif.dart';
import 'ecran_justifier_absence.dart';

/// Vie scolaire (REG-36) : justificatifs déposés par les familles, à
/// accepter ou refuser. Accepté : les absences et retards de la période
/// deviennent justifiés. Décision possible sans réseau (envoyée au retour).
class EcranJustificatifsEcole extends ConsumerWidget {
  const EcranJustificatifsEcole({super.key, required this.etablissementId});

  final String etablissementId;

  Future<void> _decider(BuildContext context, WidgetRef ref, Justificatif j, {required bool accepte}) async {
    String? motif;
    if (!accepte) {
      motif = await _demanderMotif(context);
      if (motif == null) return;
    }
    try {
      final applique = await ref.read(justificatifsRepositoryProvider).traiter(j.id, accepte: accepte, motifRefus: motif);
      ref.invalidate(justificatifsATraiterProvider(etablissementId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(applique
            ? (accepte ? 'Accepté : absences justifiées, la famille est informée.' : 'Refusé : la famille voit la raison.')
            : 'Pas de réseau : décision gardée, envoyée au retour du réseau.'),
      ));
    } on ErreurJustificatif catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<String?> _demanderMotif(BuildContext context) {
    final controleur = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (contexte) => AlertDialog(
        title: const Text('Refuser le justificatif'),
        content: TextField(
          key: const Key('motif_refus'),
          controller: controleur,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Raison, lue par la famille'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(contexte).pop(), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final texte = controleur.text.trim();
              if (texte.isNotEmpty) Navigator.of(contexte).pop(texte);
            },
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
  }

  Future<void> _ouvrirPiece(BuildContext context, WidgetRef ref, String chemin) async {
    try {
      final lien = await ref.read(justificatifsRepositoryProvider).lienPiece(chemin);
      await launchUrl(lien, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pièce indisponible sans réseau.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liste = ref.watch(justificatifsATraiterProvider(etablissementId));
    return Scaffold(
      appBar: AppBar(title: const Text('Justificatifs d’absence')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(justificatifsATraiterProvider(etablissementId)),
        child: liste.when(
          data: (justificatifs) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (justificatifs.isEmpty)
                const Text('Aucun justificatif en attente.', key: Key('justificatifs_ecole_vides')),
              for (final j in justificatifs)
                CarteJustificatif(
                  justificatif: j,
                  actions: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(spacing: 8, runSpacing: 4, children: [
                      if (j.pieceChemin != null)
                        TextButton.icon(
                          onPressed: () => _ouvrirPiece(context, ref, j.pieceChemin!),
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Voir la pièce'),
                        ),
                      FilledButton(
                        key: ValueKey('accepter_${j.id}'),
                        onPressed: () => _decider(context, ref, j, accepte: true),
                        child: const Text('Accepter'),
                      ),
                      OutlinedButton(
                        key: ValueKey('refuser_${j.id}'),
                        onPressed: () => _decider(context, ref, j, accepte: false),
                        child: const Text('Refuser'),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(children: const [
            Padding(padding: EdgeInsets.all(16), child: Text('Liste indisponible pour le moment. Tirez pour réessayer.')),
          ]),
        ),
      ),
    );
  }
}
