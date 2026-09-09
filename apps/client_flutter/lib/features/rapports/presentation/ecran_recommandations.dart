import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../application/rapports_providers.dart';
import '../domain/enums_rapports.dart';
import '../domain/recommandation_strategique.dart';
import 'widgets/badge_signal_ia.dart';
import 'widgets/pastilles_rapports.dart';

/// Recommandations stratégiques (M10) — actions correctives (tutorat,
/// renforcement) proposées par `recommander_actions` pour les classes à
/// risque, validées par la direction. Signal IA, jamais une décision
/// automatisée.
class EcranRecommandations extends ConsumerWidget {
  const EcranRecommandations({super.key, required this.etablissementId, required this.anneeId});

  final String etablissementId;
  final String anneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommandations =
        ref.watch(recommandationsEtablissementProvider((etablissementId: etablissementId, anneeId: anneeId)));
    final peutValider = ref.watch(profilProvider).value?.roleRacine == RoleRacine.direction;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recommandations stratégiques'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high_outlined),
            tooltip: 'Générer les recommandations',
            onPressed: () async {
              await ref.read(rapportsRepositoryProvider).genererRecommandations(etablissementId, anneeId);
              ref.invalidate(recommandationsEtablissementProvider((etablissementId: etablissementId, anneeId: anneeId)));
            },
          ),
        ],
      ),
      body: recommandations.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: List.generate(3, (_) => const ShimmerCarteListe()),
        ),
        error: (erreur, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('Recommandations indisponibles hors connexion pour le moment.'),
          ),
        ),
        data: (liste) => liste.isEmpty
            ? const Center(child: Text('Aucune recommandation proposée.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: liste.length,
                itemBuilder: (context, i) => EntreeAnimee(
                  index: i,
                  enfant: _CarteRecommandation(recommandation: liste[i], peutValider: peutValider),
                ),
              ),
      ),
    );
  }
}

class _CarteRecommandation extends ConsumerWidget {
  const _CarteRecommandation({required this.recommandation, required this.peutValider});

  final RecommandationStrategique recommandation;
  final bool peutValider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(recommandation.titre, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                PastillePriorite(priorite: recommandation.priorite),
              ],
            ),
            const SizedBox(height: 6),
            Text(recommandation.description),
            const SizedBox(height: 8),
            Row(
              children: [
                PastilleStatutRecommandation(statut: recommandation.statut),
                const SizedBox(width: 8),
                const BadgeSignalIa(texte: 'Signal IA — décision RH/direction'),
              ],
            ),
            if (peutValider && recommandation.statut == StatutRecommandation.proposee) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _statuer(ref, 'rejetee'),
                    child: const Text('Rejeter'),
                  ),
                  FilledButton(
                    onPressed: () => _statuer(ref, 'validee'),
                    child: const Text('Valider'),
                  ),
                ],
              ),
            ],
            if (peutValider && recommandation.statut == StatutRecommandation.validee) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => _statuer(ref, 'mise_en_oeuvre'),
                icon: Icon(Icons.check_circle_outline, color: context.palette.succes),
                label: const Text('Marquer mise en œuvre'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _statuer(WidgetRef ref, String statut) async {
    final profil = ref.read(profilProvider).value;
    if (profil == null) return;
    await ref.read(rapportsRepositoryProvider).statuerRecommandation(recommandation.id, statut, valideePar: profil.id);
    ref.invalidate(recommandationsEtablissementProvider(
      (etablissementId: recommandation.etablissementId, anneeId: recommandation.anneeScolaireId),
    ));
  }
}
