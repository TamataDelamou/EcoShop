import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/role_racine.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/profil.dart';
import 'ecran_anomalies_commandes.dart';
import 'ecran_catalogue.dart';
import 'ecran_mes_commandes.dart';
import 'ecran_panier.dart';
import 'ecran_sous_comptes_marchands.dart';

/// Point d'entrée de l'onglet Boutique (M13) — catalogue public, accès au
/// panier et à l'historique de commandes, et, pour la direction, à la
/// configuration des sous-comptes marchands et aux anomalies IA.
class EcranMarketplace extends ConsumerWidget {
  const EcranMarketplace({super.key, required this.profil});

  final Profil? profil;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etablissement = ref.watch(etablissementActifProvider);
    final estDirection = profil?.roleRacine == RoleRacine.direction;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace'),
        actions: [
          IconButton(
            tooltip: 'Mes commandes',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: profil == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => EcranMesCommandes(profileId: profil!.id)),
                    ),
          ),
          IconButton(
            tooltip: 'Mon panier',
            icon: const Icon(Icons.shopping_cart_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EcranPanier())),
          ),
          if (estDirection && etablissement != null)
            PopupMenuButton<String>(
              onSelected: (valeur) {
                final route = switch (valeur) {
                  'sous_comptes' => MaterialPageRoute(
                      builder: (_) => EcranSousComptesMarchands(etablissementId: etablissement.id),
                    ),
                  _ => MaterialPageRoute(
                      builder: (_) => EcranAnomaliesCommandes(etablissementId: etablissement.id),
                    ),
                };
                Navigator.of(context).push(route);
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'sous_comptes', child: Text('Sous-comptes marchands')),
                PopupMenuItem(value: 'anomalies', child: Text('Anomalies de commandes')),
              ],
            ),
        ],
      ),
      body: const EcranCatalogue(),
    );
  }
}
