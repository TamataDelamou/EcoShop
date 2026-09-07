import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../../auth/application/auth_providers.dart';
import '../application/rapports_providers.dart';
import '../domain/anomalie_statistique.dart';
import '../domain/enums_rapports.dart';
import 'widgets/badge_signal_ia.dart';
import 'widgets/pastilles_rapports.dart';

/// Anomalies statistiques (M10) — données aberrantes détectées par
/// `detecter_anomalies` (notes incohérentes, absentéisme excessif…), soumises
/// à validation humaine. Le traitement (confirmer/rejeter/traiter) est
/// restreint à la direction côté ergonomie ; la RLS (`rapports.administrer`)
/// reste la seule autorité réelle.
class EcranAnomalies extends ConsumerWidget {
  const EcranAnomalies({super.key, required this.etablissementId, required this.anneeId});

  final String etablissementId;
  final String anneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anomalies = ref.watch(anomaliesEtablissementProvider((etablissementId: etablissementId, anneeId: anneeId)));
    final peutTraiter = ref.watch(profilProvider).value?.roleRacine == RoleRacine.direction;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anomalies statistiques'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Détecter les anomalies',
            onPressed: () async {
              await ref.read(rapportsRepositoryProvider).detecterAnomalies(etablissementId, anneeId);
              ref.invalidate(anomaliesEtablissementProvider((etablissementId: etablissementId, anneeId: anneeId)));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.dore.withValues(alpha: 0.08),
            padding: const EdgeInsets.all(16),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.dore, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Signal statistique — à examiner, jamais une conclusion automatique.',
                    style: TextStyle(fontSize: 12, color: AppColors.dore),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: anomalies.when(
              loading: () => ListView(
                padding: const EdgeInsets.all(16),
                children: List.generate(4, (_) => const ShimmerCarteListe()),
              ),
              error: (erreur, _) => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('Anomalies indisponibles hors connexion pour le moment.'),
                ),
              ),
              data: (liste) => liste.isEmpty
                  ? const Center(child: Text('Aucune anomalie ouverte.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: liste.length,
                      itemBuilder: (context, i) => EntreeAnimee(
                        index: i,
                        enfant: _CarteAnomalie(anomalie: liste[i], peutTraiter: peutTraiter),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteAnomalie extends ConsumerWidget {
  const _CarteAnomalie({required this.anomalie, required this.peutTraiter});

  final AnomalieStatistique anomalie;
  final bool peutTraiter;

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
                  child: Text(anomalie.type, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                PastilleSeverite(severite: anomalie.severite),
                const SizedBox(width: 6),
                PastilleStatutAnomalie(statut: anomalie.statut),
              ],
            ),
            const SizedBox(height: 6),
            Text(anomalie.description),
            if (anomalie.valeurObservee != null) ...[
              const SizedBox(height: 4),
              Text(
                'Observé : ${anomalie.valeurObservee} · Attendu : ${anomalie.valeurAttendue ?? '—'}',
                style: const TextStyle(color: AppColors.encreSecondaire, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            const BadgeSignalIa(),
            if (peutTraiter && anomalie.statut == StatutAnomalie.ouverte) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _traiter(ref, 'rejetee'),
                    child: const Text('Rejeter'),
                  ),
                  FilledButton(
                    onPressed: () => _traiter(ref, 'confirmee'),
                    child: const Text('Confirmer'),
                  ),
                ],
              ),
            ],
            if (peutTraiter && anomalie.statut == StatutAnomalie.confirmee) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => _traiter(ref, 'traitee'),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Marquer comme traitée'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _traiter(WidgetRef ref, String statut) async {
    final profil = ref.read(profilProvider).value;
    if (profil == null) return;
    await ref.read(rapportsRepositoryProvider).traiterAnomalie(anomalie.id, statut, traiteePar: profil.id);
    ref.invalidate(anomaliesEtablissementProvider((etablissementId: anomalie.etablissementId, anneeId: anomalie.anneeScolaireId)));
  }
}
