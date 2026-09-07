import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../application/marketplace_providers.dart';
import 'widgets/badge_signal_ia.dart';
import 'widgets/montant.dart';

/// Anomalies de commandes (M13) — signal IA descriptif (`detecter_anomalies_commandes`),
/// jamais une décision automatique : montants élevés ou paiements multiples en
/// attente, à trier humainement par la direction.
class EcranAnomaliesCommandes extends ConsumerWidget {
  const EcranAnomaliesCommandes({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anomalies = ref.watch(anomaliesCommandesProvider(etablissementId));

    return Scaffold(
      appBar: AppBar(title: const Text('Anomalies de commandes')),
      body: anomalies.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Indisponible hors connexion pour le moment.')),
        data: (liste) {
          if (liste.isEmpty) {
            return const Center(child: Text('Aucune anomalie détectée.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: liste.length,
            itemBuilder: (context, i) {
              final a = liste[i];
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
                          Text(a.reference, style: Theme.of(context).textTheme.titleSmall),
                          const BadgeSignalIa(),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(a.libelle, style: const TextStyle(color: AppColors.orangePop, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('${formaterMontant(a.montantTotal, 'XOF')} — ${a.paiementsEnAttente} paiement(s) en attente'),
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
