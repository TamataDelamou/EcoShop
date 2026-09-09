import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/shimmer.dart';
import '../../scolarite/application/scolarite_providers.dart';
import '../application/rapports_providers.dart';
import '../domain/indicateur_cle.dart';
import 'ecran_anomalies.dart';
import 'ecran_recommandations.dart';
import 'ecran_rapports.dart';
import 'widgets/badge_signal_ia.dart';

/// Tableau de bord Rapports & Statistiques (M10, vue personnel) —
/// consolidation M6×M7×M8×M9 : indicateurs clés, accès aux anomalies,
/// recommandations et rapports générés, résumé exécutif NLG.
class EcranTableauBordRapports extends ConsumerWidget {
  const EcranTableauBordRapports({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final structure = ref.watch(structureEtablissementProvider(null));

    return Scaffold(
      appBar: AppBar(title: const Text('Rapports & statistiques')),
      body: structure.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (erreur, _) => const Center(child: Text('Structure indisponible.')),
        data: (donnees) {
          final anneeId = donnees?.anneeCourante?.id;
          if (anneeId == null) {
            return const Center(child: Text('Aucune année scolaire active.'));
          }
          return _Contenu(etablissementId: etablissementId, anneeId: anneeId);
        },
      ),
    );
  }
}

class _Contenu extends ConsumerWidget {
  const _Contenu({required this.etablissementId, required this.anneeId});

  final String etablissementId;
  final String anneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indicateurs = ref.watch(indicateursEtablissementProvider((etablissementId: etablissementId, anneeId: anneeId)));

    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(indicateursEtablissementProvider((etablissementId: etablissementId, anneeId: anneeId))),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: Text('Indicateurs clés', style: Theme.of(context).textTheme.titleLarge)),
              TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Recalculer'),
                onPressed: () async {
                  await ref.read(rapportsRepositoryProvider).consoliderIndicateurs(etablissementId, anneeId);
                  ref.invalidate(indicateursEtablissementProvider((etablissementId: etablissementId, anneeId: anneeId)));
                },
              ),
            ],
          ),
          indicateurs.when(
            loading: () => const ShimmerCarteListe(),
            error: (erreur, _) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Indicateurs indisponibles hors connexion pour le moment.'),
            ),
            data: (liste) => liste.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Aucun indicateur calculé — utilisez « Recalculer ».'),
                  )
                : GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.5,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    children: [
                      for (var i = 0; i < liste.length; i++)
                        EntreeAnimee(index: i, enfant: _CarteIndicateur(indicateur: liste[i])),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: Icon(Icons.warning_amber_outlined, color: context.palette.accent),
              title: const Text('Anomalies statistiques'),
              subtitle: const Text('Notes aberrantes, absentéisme excessif'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EcranAnomalies(etablissementId: etablissementId, anneeId: anneeId),
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.lightbulb_outline, color: context.palette.primaire),
              title: const Text('Recommandations stratégiques'),
              subtitle: const Text('Tutorat, renforcement — classes à risque'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EcranRecommandations(etablissementId: etablissementId, anneeId: anneeId),
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.description_outlined, color: context.palette.succes),
              title: const Text('Rapports générés'),
              subtitle: const Text('Bulletins, relevés, statistiques, exports'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EcranRapports(etablissementId: etablissementId, anneeId: anneeId),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.summarize_outlined),
            label: const Text('Générer le résumé exécutif'),
            onPressed: () => _afficherResume(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _afficherResume(BuildContext context, WidgetRef ref) async {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Résumé exécutif'),
        content: FutureBuilder<String>(
          future: ref.read(rapportsRepositoryProvider).resumeExecutif(etablissementId, anneeId),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError) {
              return const Text('Résumé indisponible pour le moment.');
            }
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BadgeSignalIa(texte: 'Résumé généré automatiquement — à relire avant diffusion'),
                  const SizedBox(height: 12),
                  Text(snapshot.data ?? ''),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer')),
        ],
      ),
    );
  }
}

class _CarteIndicateur extends StatelessWidget {
  const _CarteIndicateur({required this.indicateur});

  final IndicateurCle indicateur;

  @override
  Widget build(BuildContext context) {
    final valeur = indicateur.valeurNumeric;
    final texte = valeur == null
        ? (indicateur.valeurTexte ?? '—')
        : (indicateur.estUnTaux ? '${(valeur * 100).toStringAsFixed(1)} %' : valeur.toStringAsFixed(0));

    return GlassCard(
      padding: const EdgeInsets.all(12),
      enfant: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(indicateur.libelle, style: TextStyle(color: context.palette.encreSecondaire, fontSize: 12)),
          const SizedBox(height: 6),
          Text(texte, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: context.palette.primaire)),
        ],
      ),
    );
  }
}
