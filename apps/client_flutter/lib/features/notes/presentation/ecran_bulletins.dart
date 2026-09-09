import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../../scolarite/domain/fiche_eleve.dart';
import '../application/notes_providers.dart';
import '../domain/bulletin.dart';
import '../domain/enums_notes.dart';

/// Liste des bulletins publiés d'un élève (M6) — snapshots signés, intégrité
/// vérifiable côté back-office (contrat M06 §2).
class EcranBulletins extends ConsumerWidget {
  const EcranBulletins({super.key, required this.fiche});

  final FicheEleve fiche;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bulletins = ref.watch(bulletinsDeFicheProvider(fiche.id));

    return Scaffold(
      appBar: AppBar(title: Text('Bulletins — ${fiche.prenom}')),
      body: bulletins.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(3, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Bulletins indisponibles hors connexion pour le moment.'),
          ),
        ),
        data: (liste) => liste.isEmpty
            ? const Center(child: Text('Aucun bulletin publié pour le moment.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: liste.length,
                itemBuilder: (context, i) =>
                    EntreeAnimee(index: i, enfant: _CarteBulletin(bulletin: liste[i])),
              ),
      ),
    );
  }
}

class _CarteBulletin extends StatelessWidget {
  const _CarteBulletin({required this.bulletin});

  final Bulletin bulletin;

  @override
  Widget build(BuildContext context) {
    final libelleType = switch (bulletin.type) {
      TypeBulletin.trimestriel => 'Trimestre',
      TypeBulletin.semestriel => 'Semestre',
      TypeBulletin.annuel => 'Bulletin annuel',
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(Icons.receipt_long_outlined, color: context.palette.primaire),
        title: Text(libelleType),
        subtitle: bulletin.publieLe != null ? Text('Publié le ${_formatDate(bulletin.publieLe!)}') : null,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bulletin.contenu.isEmpty)
                  const Text('Contenu détaillé indisponible pour le moment.')
                else
                  for (final entree in bulletin.contenu.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('${entree.key} : ${entree.value}'),
                    ),
                if (bulletin.signatureSha256 != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.verified_outlined, size: 16, color: context.palette.succes),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Intégrité vérifiable — empreinte ${bulletin.signatureSha256!.substring(0, 12)}…',
                          style: TextStyle(fontSize: 12, color: context.palette.encreSecondaire),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}
