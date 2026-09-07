import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/referentiel_providers.dart';
import '../domain/arborescence_pays.dart';
import '../domain/cycle_educatif.dart';
import '../domain/niveau_educatif.dart';
import '../domain/pays_pedagogique.dart';
import 'ecran_programme_niveau.dart';
import 'widgets/feuille_telechargement.dart';
import 'widgets/pastille.dart';

/// Cycles, niveaux et examens nationaux d'un pays (M4).
///
/// [gradeLevelNormalise] n'apparaît jamais ici : seule l'appellation locale
/// des niveaux est affichée (contrat M04 §5).
class EcranArborescencePays extends ConsumerWidget {
  const EcranArborescencePays({super.key, required this.pays});

  final PaysPedagogique pays;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arbo = ref.watch(arborescencePaysProvider(pays.codeIso));

    return Scaffold(
      appBar: AppBar(
        title: Text(pays.nom),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_for_offline_outlined),
            tooltip: 'Télécharger pour usage hors-ligne',
            onPressed: () => afficherFeuilleTelechargement(context, pays),
          ),
        ],
      ),
      body: arbo.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(4, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: AppColors.encreSecondaire),
                const SizedBox(height: 16),
                const Text(
                  'Ce pays n\'a pas encore été consulté : une connexion est '
                  'nécessaire au premier chargement.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () =>
                      ref.invalidate(arborescencePaysProvider(pays.codeIso)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (arborescence) => _Contenu(pays: pays, arborescence: arborescence),
      ),
    );
  }
}

class _Contenu extends StatelessWidget {
  const _Contenu({required this.pays, required this.arborescence});

  final PaysPedagogique pays;
  final ArborescencePays arborescence;

  @override
  Widget build(BuildContext context) {
    final cycles = arborescence.cyclesTries;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Cycles & niveaux', style: Theme.of(context).textTheme.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < cycles.length; i++)
          EntreeAnimee(
            index: i,
            enfant: _CarteCycle(
              cycle: cycles[i],
              niveaux: arborescence.niveauxDuCycle(cycles[i].id),
              paysNom: pays.nom,
            ),
          ),
        if (arborescence.examens.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Examens nationaux', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final examen in arborescence.examens)
                Pastille(
                  texte: examen.nom,
                  couleur: AppColors.orangePop,
                  icone: Icons.workspace_premium_outlined,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CarteCycle extends StatelessWidget {
  const _CarteCycle({
    required this.cycle,
    required this.niveaux,
    required this.paysNom,
  });

  final CycleEducatif cycle;
  final List<NiveauEducatif> niveaux;
  final String paysNom;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: cycle.ordre == 1,
        leading: const Icon(Icons.account_tree_outlined, color: AppColors.bleuElectrique),
        title: Text(cycle.nom, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            if (cycle.dureeAnnees != null) '${cycle.dureeAnnees} ans',
            'ISCED ${cycle.iscedMin}-${cycle.iscedMax}',
          ].join(' · '),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: niveaux.isEmpty
                ? const Text('Aucun niveau publié pour ce cycle.')
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final niveau in niveaux)
                        ActionChip(
                          label: Text(niveau.nom),
                          avatar: const Icon(Icons.menu_book_outlined, size: 16),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EcranProgrammeNiveau(
                                niveau: niveau,
                                paysNom: paysNom,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
