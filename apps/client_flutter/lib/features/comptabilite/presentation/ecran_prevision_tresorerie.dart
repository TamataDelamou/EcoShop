import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/comptabilite_providers.dart';
import 'widgets/badge_signal_ia.dart';
import 'widgets/montant.dart';

/// Prévision de trésorerie à 30 jours (M14) — méthode directe, IA
/// prédictive (`predire_tresorerie`), simple projection linéaire à valider
/// humainement, jamais une décision de trésorerie automatique.
class EcranPrevisionTresorerie extends ConsumerWidget {
  const EcranPrevisionTresorerie({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projection = ref.watch(previsionTresorerieProvider(etablissementId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prévision de trésorerie'),
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: Center(child: BadgeSignalIa()))],
      ),
      body: projection.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Indisponible hors connexion pour le moment.')),
        data: (liste) {
          if (liste.isEmpty) return const Center(child: Text('Trésorerie insuffisante pour projeter.'));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: liste.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = liste[i];
              final date = '${p.jour.day.toString().padLeft(2, '0')}/${p.jour.month.toString().padLeft(2, '0')}/${p.jour.year}';
              return ListTile(
                title: Text(date),
                trailing: Text(
                  '${formaterMontant(p.soldeProjete)} GNF',
                  style: TextStyle(fontWeight: FontWeight.w700, color: p.soldeProjete < 0 ? Theme.of(context).colorScheme.error : null),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
