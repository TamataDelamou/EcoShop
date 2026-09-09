import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/planification_providers.dart';
import '../domain/conflit_emploi.dart';
import 'widgets/badge_signal_ia.dart';
import 'widgets/carte_seance.dart';

/// Conflits d'occupation (M11) — chevauchements horaires détectés par
/// `detecter_conflits_emploi` (salle, enseignant ou classe). Signal à
/// arbitrer humainement : aucune séance n'est déplacée automatiquement.
class EcranConflitsEmploi extends ConsumerWidget {
  const EcranConflitsEmploi({super.key, required this.etablissementId, required this.anneeId});

  final String etablissementId;
  final String anneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (etablissementId: etablissementId, anneeId: anneeId);
    final conflits = ref.watch(conflitsEmploiProvider(args));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conflits d\'occupation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraîchir la détection',
            onPressed: () => ref.invalidate(conflitsEmploiProvider(args)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(alignment: Alignment.centerLeft, child: BadgeSignalIa(texte: 'Signal IA — à arbitrer, jamais résolu automatiquement')),
          ),
          Expanded(
            child: conflits.when(
              loading: () => ListView(
                padding: const EdgeInsets.all(16),
                children: List.generate(3, (_) => const ShimmerCarteListe()),
              ),
              error: (erreur, _) => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Détection indisponible hors connexion pour le moment.'),
                ),
              ),
              data: (liste) => liste.isEmpty
                  ? const Center(child: Text('Aucun conflit détecté.'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: liste.length,
                      itemBuilder: (context, i) =>
                          EntreeAnimee(index: i, enfant: _CarteConflit(conflit: liste[i])),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteConflit extends StatelessWidget {
  const _CarteConflit({required this.conflit});

  final ConflitEmploi conflit;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(_icone(conflit.type), color: context.palette.erreur),
        title: Text('Conflit de ${_libelleType(conflit.type)}'),
        subtitle: Text(
          '${joursSemaine[conflit.jourSemaine - 1]} · ${conflit.heureDebut} – ${conflit.heureFin}',
        ),
      ),
    );
  }

  static IconData _icone(String type) => switch (type) {
        'salle' => Icons.meeting_room_outlined,
        'enseignant' => Icons.person_outline,
        _ => Icons.groups_outlined,
      };

  static String _libelleType(String type) => switch (type) {
        'salle' => 'salle',
        'enseignant' => 'enseignant',
        _ => 'classe',
      };
}
