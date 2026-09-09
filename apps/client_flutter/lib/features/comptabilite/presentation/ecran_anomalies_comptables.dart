import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ecoshop_client/core/theme/app_palette.dart';
import '../application/comptabilite_providers.dart';
import 'widgets/badge_signal_ia.dart';
import 'widgets/montant.dart';

/// Anomalies comptables (M14) — signal IA descriptif
/// (`detecter_anomalies_comptables`) : montants élevés ou doubles saisies
/// suspectées, jamais une correction automatique.
class EcranAnomaliesComptables extends ConsumerWidget {
  const EcranAnomaliesComptables({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anomalies = ref.watch(anomaliesComptablesProvider(etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Anomalies comptables')),
      body: anomalies.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Indisponible hors connexion pour le moment.')),
        data: (liste) {
          if (liste.isEmpty) return const Center(child: Text('Aucune anomalie détectée.'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: liste.length,
            itemBuilder: (context, i) {
              final a = liste[i];
              final date = '${a.dateEcriture.day.toString().padLeft(2, '0')}/${a.dateEcriture.month.toString().padLeft(2, '0')}/${a.dateEcriture.year}';
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(a.libelle, style: Theme.of(context).textTheme.titleSmall)),
                          const BadgeSignalIa(),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(a.libelleAnomalie, style: TextStyle(color: context.palette.accent, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('$date — ${formaterMontant(a.montant)}'),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
