import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/marketplace_providers.dart';
import '../domain/commande.dart';
import 'widgets/montant.dart';
import 'widgets/pastille_statut.dart';

/// Détail d'une commande — lignes (snapshot des prix) et paiements associés.
class EcranDetailCommande extends ConsumerWidget {
  const EcranDetailCommande({super.key, required this.commande});

  final Commande commande;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lignes = ref.watch(lignesCommandeProvider(commande.id));
    final paiements = ref.watch(paiementsCommandeProvider(commande.id));

    return Scaffold(
      appBar: AppBar(title: Text(commande.reference)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(commande.nomCommercant ?? 'Commerçant', style: Theme.of(context).textTheme.titleMedium),
              PastilleStatutCommande(statut: commande.statut),
            ],
          ),
          const SizedBox(height: 16),
          Text('Articles', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          lignes.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => const Text('Indisponible hors connexion.'),
            data: (liste) => Column(
              children: [
                for (final l in liste)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.libelleProduit ?? '—'),
                    subtitle: Text('${l.quantite} × ${formaterMontant(l.prixUnitaire, commande.devise)}'),
                    trailing: Text(formaterMontant(l.montantLigne, commande.devise)),
                  ),
              ],
            ),
          ),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total'),
              Text(
                formaterMontant(commande.montantTotal, commande.devise),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Paiements', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          paiements.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => const Text('Indisponible hors connexion.'),
            data: (liste) => liste.isEmpty
                ? const Text('Aucun paiement enregistré.')
                : Column(
                    children: [
                      for (final p in liste)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(p.fournisseur.libelle),
                          subtitle: Text(formaterMontant(p.montant, commande.devise)),
                          trailing: PastilleStatutPaiement(statut: p.statut),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
