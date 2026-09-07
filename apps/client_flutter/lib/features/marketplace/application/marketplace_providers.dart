import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/cached_marketplace_repository.dart';
import '../data/supabase_marketplace_repository.dart';
import '../domain/anomalie_commande.dart';
import '../domain/catalogue_produit.dart';
import '../domain/commande.dart';
import '../domain/commercant.dart';
import '../domain/enums_marketplace.dart';
import '../domain/ligne_commande.dart';
import '../domain/ligne_panier.dart';
import '../domain/marketplace_repository.dart';
import '../domain/paiement.dart';
import '../domain/panier.dart';
import '../domain/panier_brouillon_local.dart';
import '../domain/sous_compte_marchand.dart';

/// Port réseau seul — utilisé par le rejeu de la file `sync_queue`, qui doit
/// toujours viser le serveur directement (même convention que M6-M11).
final _marketplaceReseauProvider = Provider<MarketplaceRepository>((ref) {
  return SupabaseMarketplaceRepository(ref.watch(supabaseClientProvider));
});

/// Port Marketplace — réseau d'abord, repli cache Drift, écriture tolérante
/// hors-ligne pour `paniers`/`lignes_paniers` via `sync_queue` (domaine
/// `marketplace`).
final marketplaceRepositoryProvider = Provider<MarketplaceRepository>((ref) {
  final cache = CacheDocumentStore(ref.watch(databaseProvider), 'marketplace');
  return CachedMarketplaceRepository(
    ref.watch(_marketplaceReseauProvider),
    cache,
    ref.watch(syncRepositoryProvider),
  );
});

/// Fonctions de rejeu — branchées sur le moteur de synchronisation composé à
/// la racine applicative (`features/coquille/application/sync_composition.dart`).
final paniersRejeuProvider = Provider<Future<void> Function(SyncEntree)>((ref) {
  final reseau = ref.watch(_marketplaceReseauProvider);
  return (entree) async {
    final json = jsonDecode(entree.payload) as Map<String, dynamic>;
    await reseau.enregistrerPanier(Panier.depuisJsonEcriture(json));
  };
});

final lignesPaniersRejeuProvider = Provider<Future<void> Function(SyncEntree)>((ref) {
  final reseau = ref.watch(_marketplaceReseauProvider);
  return (entree) async {
    final json = jsonDecode(entree.payload) as Map<String, dynamic>;
    await reseau.enregistrerLignePanier(LignePanier.depuisJsonEcriture(json));
  };
});

/// Catalogue — commerçants actifs, public (lecture possible même sans
/// session ouverte : RLS `using (true)`).
final commercantsProvider = FutureProvider<List<Commercant>>((ref) {
  return ref.watch(marketplaceRepositoryProvider).commercants();
});

/// Produits d'un commerçant (ou tout le catalogue si `commercantId` est nul).
final produitsProvider = FutureProvider.family<List<CatalogueProduit>, String?>((ref, commercantId) {
  return ref.watch(marketplaceRepositoryProvider).produits(commercantId: commercantId);
});

/// Panier actif de l'acheteur authentifié pour un établissement donné.
final panierActifProvider =
    FutureProvider.family<Panier?, ({String profileId, String etablissementId})>((ref, args) {
  return ref.watch(marketplaceRepositoryProvider).panierActifPourProfil(args.profileId, args.etablissementId);
});

/// Lignes d'un panier.
final lignesPanierProvider = FutureProvider.family<List<LignePanier>, String>((ref, panierId) {
  return ref.watch(marketplaceRepositoryProvider).lignesDuPanier(panierId);
});

/// Commandes de l'acheteur authentifié.
final mesCommandesProvider = FutureProvider.family<List<Commande>, String>((ref, profileId) {
  return ref.watch(marketplaceRepositoryProvider).mesCommandes(profileId);
});

/// Lignes (snapshot) d'une commande.
final lignesCommandeProvider = FutureProvider.family<List<LigneCommande>, String>((ref, commandeId) {
  return ref.watch(marketplaceRepositoryProvider).lignesDeCommande(commandeId);
});

/// Paiements d'une commande.
final paiementsCommandeProvider = FutureProvider.family<List<Paiement>, String>((ref, commandeId) {
  return ref.watch(marketplaceRepositoryProvider).paiementsDeCommande(commandeId);
});

/// Sous-comptes marchands d'un établissement (configuration direction).
final sousComptesEtablissementProvider = FutureProvider.family<List<SousCompteMarchand>, String>((ref, etabId) {
  return ref.watch(marketplaceRepositoryProvider).sousComptesEtablissement(etabId);
});

/// Anomalies de commandes (IA descriptive, personnel).
final anomaliesCommandesProvider = FutureProvider.family<List<AnomalieCommande>, String>((ref, etabId) {
  return ref.watch(marketplaceRepositoryProvider).detecterAnomalies(etabId);
});

// ---------------------------------------------------------------------------
// Panier en brouillon (M13) — acheteur authentifié sans établissement résolu,
// voir [PanierBrouillonLocal]. Persisté en cache Drift, promu vers
// `paniers`/`lignes_paniers` une fois l'établissement connu (checkout).
// ---------------------------------------------------------------------------

const _cacheBrouillon = 'marketplace_brouillon';

class PanierBrouillonLocalController extends AsyncNotifier<PanierBrouillonLocal> {
  CacheDocumentStore get _cache => CacheDocumentStore(ref.watch(databaseProvider), _cacheBrouillon);

  @override
  Future<PanierBrouillonLocal> build() async {
    final document = await _cache.lireDocument('panier', CacheDocumentStore.cleUnique);
    return document == null ? PanierBrouillonLocal.vide : PanierBrouillonLocal.depuisJsonCache(document);
  }

  Future<void> ajouter({required String commercantId, required String catalogueProduitId, int quantite = 1}) async {
    final courant = state.value ?? PanierBrouillonLocal.vide;
    final nouveau =
        courant.ajouter(commercantId: commercantId, catalogueProduitId: catalogueProduitId, quantite: quantite);
    await _persister(nouveau);
  }

  Future<void> definirQuantite(String catalogueProduitId, int quantite) async {
    final courant = state.value ?? PanierBrouillonLocal.vide;
    await _persister(courant.definirQuantite(catalogueProduitId, quantite));
  }

  Future<void> vider() => _persister(PanierBrouillonLocal.vide);

  Future<void> _persister(PanierBrouillonLocal panier) async {
    state = AsyncData(panier);
    await _cache.ecrireDocument('panier', CacheDocumentStore.cleUnique, panier.versJsonCache());
  }
}

final panierBrouillonLocalProvider = AsyncNotifierProvider<PanierBrouillonLocalController, PanierBrouillonLocal>(
  PanierBrouillonLocalController.new,
);

// ---------------------------------------------------------------------------
// Constructeurs — id client généré (uuid v4), horodatage/dispositif pour LWW.
// ---------------------------------------------------------------------------

Panier construirePanier({
  String? id,
  required String etablissementId,
  required String profileId,
  String? commercantId,
  required String deviceId,
}) =>
    Panier(
      id: id ?? const Uuid().v4(),
      etablissementId: etablissementId,
      profileId: profileId,
      commercantId: commercantId,
      saisiHorsLigne: true,
      deviceId: deviceId,
      clientTs: DateTime.now(),
    );

LignePanier construireLignePanier({
  String? id,
  required String panierId,
  required String catalogueProduitId,
  required int quantite,
}) =>
    LignePanier(id: id ?? const Uuid().v4(), panierId: panierId, catalogueProduitId: catalogueProduitId, quantite: quantite);

/// Référence de commande lisible, unique côté client (contrainte serveur
/// `commandes.reference` UNIQUE).
String genererReferenceCommande() =>
    'CMD-${DateTime.now().toUtc().millisecondsSinceEpoch}-${const Uuid().v4().substring(0, 4).toUpperCase()}';

Commande construireCommande({
  required String etablissementId,
  required String commercantId,
  required String profileId,
  String? panierId,
  required double montantTotal,
  double montantFrais = 0,
  String devise = 'XOF',
}) =>
    Commande(
      id: const Uuid().v4(),
      etablissementId: etablissementId,
      commercantId: commercantId,
      profileId: profileId,
      panierId: panierId,
      reference: genererReferenceCommande(),
      montantTotal: montantTotal,
      montantFrais: montantFrais,
      devise: devise,
    );

Paiement construirePaiement({
  required String etablissementId,
  required String commandeId,
  String? sousCompteId,
  required TypeFournisseurPaiement fournisseur,
  required double montant,
}) =>
    Paiement(
      id: const Uuid().v4(),
      etablissementId: etablissementId,
      commandeId: commandeId,
      sousCompteId: sousCompteId,
      fournisseur: fournisseur,
      montant: montant,
    );
