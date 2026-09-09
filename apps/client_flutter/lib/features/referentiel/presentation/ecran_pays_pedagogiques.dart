import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../../../core/widgets/entree_animee.dart';
import '../../../core/widgets/shimmer.dart';
import '../application/referentiel_providers.dart';
import '../domain/pays_pedagogique.dart';
import 'ecran_arborescence_pays.dart';
import 'widgets/pastille.dart';

/// Accueil du référentiel pédagogique CEDEAO (M4) — liste des pays déployés.
///
/// Écran de **consultation pure** : aucune session n'est requise (RLS ouvre
/// la lecture à `anon`), et la liste reste disponible hors connexion via le
/// cache Drift dès qu'elle a été chargée une première fois (contrat M04 §5).
class EcranPaysPedagogiques extends ConsumerWidget {
  const EcranPaysPedagogiques({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pays = ref.watch(paysPedagogiquesProvider);
    final systemes = ref.watch(systemesEducatifsProvider).valueOrNull ?? const [];
    final libelleSysteme = {for (final s in systemes) s.code: s.nom};

    return Scaffold(
      appBar: AppBar(title: const Text('Référentiel pédagogique CEDEAO')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(paysPedagogiquesProvider);
          ref.invalidate(systemesEducatifsProvider);
          await ref.read(paysPedagogiquesProvider.future);
        },
        child: pays.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: List.generate(6, (_) => const ShimmerCarteListe()),
          ),
          error: (erreur, _) => _EtatErreur(
            onReessayer: () => ref.invalidate(paysPedagogiquesProvider),
          ),
          data: (liste) => liste.isEmpty
              ? const _EtatVide()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: liste.length,
                  itemBuilder: (context, index) {
                    final p = liste[index];
                    return EntreeAnimee(
                      index: index,
                      enfant: _CartePays(
                        pays: p,
                        libelleSysteme: libelleSysteme[p.typeSysteme] ?? p.typeSysteme,
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _CartePays extends StatelessWidget {
  const _CartePays({required this.pays, required this.libelleSysteme});

  final PaysPedagogique pays;
  final String libelleSysteme;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EcranArborescencePays(pays: pays)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: context.palette.primaire.withValues(alpha: 0.1),
                child: Text(
                  pays.codeIso,
                  style: TextStyle(
                    color: context.palette.primaire,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pays.nom, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Pastille(
                          texte: libelleSysteme,
                          couleur: context.palette.primaire,
                          icone: Icons.public,
                        ),
                        Pastille(
                          texte: pays.langueEnseignementPrincipale,
                          couleur: context.palette.encreSecondaire,
                          icone: Icons.translate,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.palette.encreSecondaire),
            ],
          ),
        ),
      ),
    );
  }
}

class _EtatVide extends StatelessWidget {
  const _EtatVide();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.public_off, size: 48, color: context.palette.encreSecondaire),
            const SizedBox(height: 16),
            Text('Aucun pays publié pour le moment.',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _EtatErreur extends StatelessWidget {
  const _EtatErreur({required this.onReessayer});

  final VoidCallback onReessayer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: context.palette.encreSecondaire),
            const SizedBox(height: 16),
            const Text(
              'Impossible de charger le référentiel et aucune copie hors-ligne '
              "n'est disponible.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onReessayer,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
