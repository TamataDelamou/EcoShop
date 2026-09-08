import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/comptabilite_providers.dart';
import 'widgets/badge_signal_ia.dart';
import 'widgets/montant.dart';

/// Écritures récurrentes recommandées (M14) — IA descriptive
/// (`recommander_ecritures`, ≥ 2 mois distincts) : une suggestion de
/// ressaisie à valider, jamais une écriture générée automatiquement.
class EcranEcrituresRecommandees extends ConsumerWidget {
  const EcranEcrituresRecommandees({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommandations = ref.watch(ecrituresRecommandeesProvider(etablissementId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Écritures récurrentes'),
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: Center(child: BadgeSignalIa()))],
      ),
      body: recommandations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Indisponible hors connexion pour le moment.')),
        data: (liste) {
          if (liste.isEmpty) return const Center(child: Text('Aucune écriture récurrente détectée.'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: liste.length,
            itemBuilder: (context, i) {
              final r = liste[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(r.libelle),
                  subtitle: Text('${r.compteDebit} → ${r.compteCredit} · ${r.moisDistincts} mois distincts'),
                  trailing: Text(formaterMontant(r.montant), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
