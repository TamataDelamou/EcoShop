import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../application/comptabilite_providers.dart';
import 'widgets/badge_signal_ia.dart';
import 'widgets/montant.dart';

/// Tendances charges/produits (M14) — IA descriptive (`analyser_tendances`,
/// 12 mois glissants), lecture d'aide à la décision.
class EcranTendances extends ConsumerWidget {
  const EcranTendances({super.key, required this.etablissementId});

  final String etablissementId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tendances = ref.watch(tendancesComptablesProvider(etablissementId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tendances'),
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: Center(child: BadgeSignalIa()))],
      ),
      body: tendances.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('Indisponible hors connexion pour le moment.')),
        data: (liste) {
          if (liste.isEmpty) return const Center(child: Text('Pas assez de données pour dégager une tendance.'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: liste.length,
            itemBuilder: (context, i) {
              final t = liste[i];
              final mois = '${t.mois.month.toString().padLeft(2, '0')}/${t.mois.year}';
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mois, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Charges : ${formaterMontant(t.totalCharges)}', style: const TextStyle(color: AppColors.erreur)),
                          Text('Produits : ${formaterMontant(t.totalProduits)}', style: const TextStyle(color: AppColors.vertMenthe)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Solde net : ${formaterMontant(t.soldeNet)}',
                        style: TextStyle(fontWeight: FontWeight.w700, color: t.soldeNet >= 0 ? AppColors.vertMenthe : AppColors.erreur),
                      ),
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
