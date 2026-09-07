import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/shimmer.dart';
import '../application/marketplace_providers.dart';
import '../domain/commande.dart';
import 'ecran_detail_commande.dart';
import 'widgets/montant.dart';
import 'widgets/pastille_statut.dart';

/// Historique des commandes de l'acheteur authentifié (M13).
class EcranMesCommandes extends ConsumerWidget {
  const EcranMesCommandes({super.key, required this.profileId});

  final String profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commandes = ref.watch(mesCommandesProvider(profileId));

    return Scaffold(
      appBar: AppBar(title: const Text('Mes commandes')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(mesCommandesProvider(profileId).future),
        child: commandes.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: List.generate(4, (_) => const ShimmerCarteListe()),
          ),
          error: (e, _) => ListView(
            children: const [
              Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Commandes indisponibles hors connexion pour le moment.')),
              ),
            ],
          ),
          data: (liste) {
            if (liste.isEmpty) {
              return ListView(
                children: const [
                  Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucune commande pour le moment.'))),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: liste.length,
              itemBuilder: (context, i) => _CarteCommande(commande: liste[i]),
            );
          },
        ),
      ),
    );
  }
}

class _CarteCommande extends StatelessWidget {
  const _CarteCommande({required this.commande});

  final Commande commande;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(commande.reference),
        subtitle: Text('${commande.nomCommercant ?? 'Commerçant'} — ${formaterMontant(commande.montantTotal, commande.devise)}'),
        trailing: PastilleStatutCommande(statut: commande.statut),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EcranDetailCommande(commande: commande)),
        ),
      ),
    );
  }
}
