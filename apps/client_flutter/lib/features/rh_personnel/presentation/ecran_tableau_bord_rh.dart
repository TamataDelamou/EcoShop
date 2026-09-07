import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/rh_providers.dart';
import '../domain/effectif_categorie.dart';
import '../domain/enums_rh.dart';
import '../domain/remplacement_suggere.dart';
import 'widgets/badge_signal_ia.dart';

/// Tableau de bord RH (M8, vue direction) — effectifs par catégorie (IA
/// descriptive, RPC `analyser_effectifs`) et remplacements suggérés du jour
/// pour les enseignants absents (IA prescriptive, RPC
/// `optimiser_remplacements`). Signaux d'aide à la décision uniquement :
/// aucune affectation n'est déclenchée automatiquement.
class EcranTableauBordRh extends ConsumerWidget {
  const EcranTableauBordRh({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aujourdHui = DateTime.now();
    final date = DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day);
    final effectifs = ref.watch(analyserEffectifsProvider(etablissementId));
    final remplacements = ref.watch(
      optimiserRemplacementsProvider((etablissementId: etablissementId, date: date)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Tableau de bord RH')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(analyserEffectifsProvider(etablissementId));
          ref.invalidate(optimiserRemplacementsProvider((etablissementId: etablissementId, date: date)));
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Effectifs', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            effectifs.when(
              loading: () => const ShimmerCarteListe(),
              error: (erreur, _) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Tableau de bord indisponible hors connexion pour le moment.'),
              ),
              data: (liste) => liste.isEmpty
                  ? const Text('Aucun employé enregistré.')
                  : Column(
                      children: [
                        for (var i = 0; i < liste.length; i++)
                          EntreeAnimee(index: i, enfant: _CarteEffectif(effectif: liste[i])),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: Text('Remplacements suggérés', style: Theme.of(context).textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 4),
            const BadgeSignalIa(texte: "Signal IA — l'affectation reste une décision RH"),
            const SizedBox(height: 8),
            remplacements.when(
              loading: () => const ShimmerCarteListe(),
              error: (erreur, _) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Suggestions indisponibles pour le moment.'),
              ),
              data: (liste) => liste.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text("Aucun enseignant absent aujourd'hui."),
                    )
                  : Column(children: [for (final r in liste) _CarteRemplacement(remplacement: r)]),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarteEffectif extends StatelessWidget {
  const _CarteEffectif({required this.effectif});

  final EffectifCategorie effectif;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      enfant: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  CategorieEmploye.depuisCode(effectif.categorie).libelle,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Ancienneté moyenne : ${effectif.ancienneteMoyenneJours.toStringAsFixed(0)} j',
                  style: const TextStyle(color: AppColors.encreSecondaire, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${effectif.effectif}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.bleuElectrique)),
              Text(
                'Masse : ${effectif.masseSalarialeBase.toStringAsFixed(0)}',
                style: const TextStyle(color: AppColors.encreSecondaire, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CarteRemplacement extends StatelessWidget {
  const _CarteRemplacement({required this.remplacement});

  final RemplacementSuggere remplacement;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.swap_horiz, color: AppColors.orangePop),
        title: Text('${remplacement.absentMatricule} → ${remplacement.remplacantMatricule}'),
        subtitle: const Text('Enseignant absent → remplaçant le moins chargé'),
      ),
    );
  }
}
