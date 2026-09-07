import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/device_id_provider.dart';
import '../../auth/application/auth_providers.dart';
import '../application/marketplace_providers.dart';
import '../domain/catalogue_produit.dart';
import '../domain/marketplace_repository.dart';
import '../domain/panier_brouillon_local.dart';

/// Ajoute un produit au panier — panier serveur (`paniers`/`lignes_paniers`)
/// si l'acheteur a un établissement résolu, sinon [PanierBrouillonLocal] en
/// attendant le checkout (voir `panier_brouillon_local.dart`).
Future<void> ajouterProduitAuPanier(BuildContext context, WidgetRef ref, CatalogueProduit produit) async {
  final messenger = ScaffoldMessenger.of(context);
  final profil = ref.read(profilProvider).value;
  final etablissement = ref.read(etablissementActifProvider);

  try {
    if (profil != null && etablissement != null) {
      final args = (profileId: profil.id, etablissementId: etablissement.id);
      final panierExistant = await ref.read(panierActifProvider(args).future);
      final deviceId = await ref.read(deviceIdProvider.future);
      final panier = panierExistant ??
          construirePanier(
            etablissementId: etablissement.id,
            profileId: profil.id,
            commercantId: produit.commercantId,
            deviceId: deviceId,
          );
      final depot = ref.read(marketplaceRepositoryProvider);
      if (panierExistant == null) {
        await depot.enregistrerPanier(panier);
      }
      final lignes = await ref.read(lignesPanierProvider(panier.id).future);
      final existante = lignes.where((l) => l.catalogueProduitId == produit.id);
      final quantite = (existante.isEmpty ? 0 : existante.first.quantite) + 1;
      await depot.enregistrerLignePanier(construireLignePanier(
        id: existante.isEmpty ? null : existante.first.id,
        panierId: panier.id,
        catalogueProduitId: produit.id,
        quantite: quantite,
      ));
      ref.invalidate(panierActifProvider(args));
      ref.invalidate(lignesPanierProvider(panier.id));
    } else {
      await ref
          .read(panierBrouillonLocalProvider.notifier)
          .ajouter(commercantId: produit.commercantId, catalogueProduitId: produit.id);
    }
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('${produit.libelle} ajouté au panier')));
  } on PanierBrouillonMonoVendeurException {
    messenger.showSnackBar(const SnackBar(
      content: Text("Panier mono-vendeur : videz-le avant d'ajouter un article d'un autre commerçant."),
    ));
  } on ErreurMarketplace catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(e.code == 'PANIER_MONO_VENDEUR'
          ? "Panier mono-vendeur : videz-le avant d'ajouter un article d'un autre commerçant."
          : 'Ajout impossible pour le moment.'),
    ));
  }
}
