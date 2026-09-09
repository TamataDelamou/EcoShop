import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';

import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/planification_providers.dart';
import '../domain/enums_planification.dart';
import '../domain/progression_pedagogique.dart';
import 'widgets/badge_signal_ia.dart';
import 'widgets/pastille_statut_progression.dart';

/// Progression pédagogique d'une classe (M11, vue personnel — la RLS ne
/// donne aucune visibilité aux élèves/parents sur cette table). Les séances
/// `proposee` sont des suggestions de rattrapage IA (`recommander_seances`),
/// jamais planifiées automatiquement.
class EcranProgressionPedagogique extends ConsumerWidget {
  const EcranProgressionPedagogique({super.key, required this.etablissementId, required this.classeId, required this.anneeId});

  final String etablissementId;
  final String classeId;
  final String anneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (classeId: classeId, anneeId: anneeId);
    final progression = ref.watch(progressionDeClasseProvider(args));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Progression pédagogique'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high_outlined),
            tooltip: 'Proposer des séances de rattrapage',
            onPressed: () async {
              await ref.read(planificationRepositoryProvider).recommanderSeances(etablissementId, anneeId);
              ref.invalidate(progressionDeClasseProvider(args));
            },
          ),
        ],
      ),
      body: progression.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(3, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Progression indisponible hors connexion pour le moment.'),
          ),
        ),
        data: (liste) => liste.isEmpty
            ? const Center(child: Text('Aucune séance enregistrée.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: liste.length,
                itemBuilder: (context, i) =>
                    EntreeAnimee(index: i, enfant: _CarteProgression(progression: liste[i])),
              ),
      ),
    );
  }
}

class _CarteProgression extends ConsumerWidget {
  const _CarteProgression({required this.progression});

  final ProgressionPedagogique progression;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(progression.seance, style: const TextStyle(fontWeight: FontWeight.w700))),
                PastilleStatutProgression(statut: progression.statut),
              ],
            ),
            if (progression.objectifs != null && progression.objectifs!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(progression.objectifs!, style: TextStyle(color: context.palette.encreSecondaire, fontSize: 13)),
            ],
            if (progression.statut == StatutProgression.proposee) ...[
              const SizedBox(height: 8),
              const BadgeSignalIa(texte: 'Signal IA — difficultés détectées (notes/assiduité)'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _statuer(ref, 'annulee'),
                    child: const Text('Ignorer'),
                  ),
                  FilledButton(
                    onPressed: () => _statuer(ref, 'planifiee'),
                    child: const Text('Planifier'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _statuer(WidgetRef ref, String statut) async {
    await ref.read(planificationRepositoryProvider).changerStatutProgression(progression.id, statut);
    ref.invalidate(progressionDeClasseProvider((classeId: progression.classeId, anneeId: progression.anneeScolaireId)));
  }
}
