import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/accueil_providers.dart';

/// Réglage de l'affichage de l'accueil (REG-25) : défilant ou fixe, deux
/// grandes pastilles ou trois par ligne. Gardé sur ce téléphone.
Future<void> afficherReglagesAccueil(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _ReglagesAffichage(),
    );

class _ReglagesAffichage extends ConsumerWidget {
  const _ReglagesAffichage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(affichageAccueilProvider).valueOrNull ?? const AffichageAccueil();
    void definir(AffichageAccueil n) => ref.read(affichageAccueilProvider.notifier).definir(n);
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Affichage de l’accueil', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Disposition', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              key: const Key('choix_disposition_accueil'),
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.view_agenda_outlined), label: Text('Défilante')),
                ButtonSegment(value: true, icon: Icon(Icons.view_carousel_outlined), label: Text('Fixe')),
              ],
              selected: {a.fixe},
              onSelectionChanged: (s) => definir(a.copier(fixe: s.first)),
            ),
            const SizedBox(height: 6),
            Text(
              a.fixe
                  ? 'Une ligne par thème : faites glisser la ligne de côté pour voir les autres pastilles.'
                  : 'Toutes les pastilles, de haut en bas : faites défiler la page.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Text('Taille des pastilles', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              key: const Key('choix_colonnes_accueil'),
              segments: const [
                ButtonSegment(value: 2, icon: Icon(Icons.grid_view_rounded), label: Text('2 par ligne')),
                ButtonSegment(value: 3, icon: Icon(Icons.apps_rounded), label: Text('3 par ligne')),
              ],
              selected: {a.colonnes},
              onSelectionChanged: (s) => definir(a.copier(colonnes: s.first)),
            ),
            const SizedBox(height: 6),
            Text(
              a.grandes ? 'Grandes pastilles, plus faciles à lire et à toucher.' : 'Pastilles plus petites : plus de fonctions à l’écran.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            _Apercu(affichage: a),
          ],
        ),
      ),
    );
  }
}

/// Miniature de l'accueil avec le réglage choisi.
class _Apercu extends StatelessWidget {
  const _Apercu({required this.affichage});

  final AffichageAccueil affichage;

  @override
  Widget build(BuildContext context) {
    final schema = Theme.of(context).colorScheme;
    Widget bloc() => Expanded(
          child: Container(
            height: affichage.grandes ? 44 : 32,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: schema.primaryContainer, borderRadius: BorderRadius.circular(8)),
          ),
        );
    Widget ligne(int n) => Row(children: [for (var i = 0; i < n; i++) bloc()]);
    final n = affichage.colonnes;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: schema.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final theme in const ['Vie de l’école', 'Finances']) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
              child: Text(theme.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
            ),
            if (affichage.fixe)
              Row(children: [for (var i = 0; i < n; i++) bloc(), const SizedBox(width: 18), const Icon(Icons.chevron_right, size: 16)])
            else ...[
              ligne(n),
              ligne(n),
            ],
          ],
        ],
      ),
    );
  }
}
