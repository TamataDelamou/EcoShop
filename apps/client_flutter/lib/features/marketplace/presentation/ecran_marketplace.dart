import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/barre_actions.dart';

import '../../../core/auth/role_racine.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/profil.dart';
import 'ecran_anomalies_commandes.dart';
import 'ecran_catalogue.dart';
import 'ecran_mes_commandes.dart';
import 'ecran_panier.dart';
import 'ecran_sous_comptes_marchands.dart';
import '../../paiement_mobile/presentation/ecran_orange_money_etablissement.dart';

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
    void ouvrir(Widget ecran) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ecran));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace'),
        actions: [
          // Le panier reste une icône : c'est le repère universel des boutiques.
          IconButton(
            tooltip: 'Mon panier',
            icon: const Icon(Icons.shopping_cart_outlined),
            onPressed: () => ouvrir(const EcranPanier()),
          ),
        ],
        // Autres actions, avec leur libellé, sous le titre (REG-28).
        bottom: BarreActions(actions: [
          ActionEcran(
            cle: const Key('marketplace_commandes'),
            icone: Icons.receipt_long_outlined,
            libelle: 'Mes commandes',
            onPressed: profil == null ? null : () => ouvrir(EcranMesCommandes(profileId: profil!.id)),
          ),
          if (estDirection && etablissement != null) ...[
            ActionEcran(
              icone: Icons.account_tree_outlined,
              libelle: 'Sous-comptes marchands',
              onPressed: () => ouvrir(EcranSousComptesMarchands(etablissementId: etablissement.id)),
            ),
            ActionEcran(
              icone: Icons.phone_android_outlined,
              libelle: 'Orange Money',
              onPressed: () => ouvrir(EcranOrangeMoneyEtablissement(
                etablissementId: etablissement.id,
                devise: etablissement.deviseCode,
              )),
            ),
            ActionEcran(
              icone: Icons.report_problem_outlined,
              libelle: 'Anomalies de commandes',
              onPressed: () => ouvrir(EcranAnomaliesCommandes(etablissementId: etablissement.id)),
            ),
          ],
        ]),
      ),
      body: const EcranCatalogue(),
    );
  }
}
