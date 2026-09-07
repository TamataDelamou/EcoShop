import 'dart:convert';

import '../../../core/db/cache_document_store.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/anomalie_commande.dart';
import '../domain/catalogue_produit.dart';
import '../domain/commande.dart';
import '../domain/commercant.dart';
import '../domain/ligne_commande.dart';
import '../domain/ligne_panier.dart';
import '../domain/marketplace_repository.dart';
import '../domain/paiement.dart';
import '../domain/panier.dart';
import '../domain/sous_compte_marchand.dart';

/// Décore un [MarketplaceRepository] réseau avec un repli SQLite/Drift.
///
/// Périmètre hors-ligne aligné sur le DDL réel : `paniers`/`lignes_paniers`
/// portent `device_id`/`client_ts` côté serveur et sont donc tolérants
/// hors-ligne via `sync_queue`, même pattern que les présences (M7) et
/// l'emploi du temps (M11). `commandes`/`lignes_commandes`/`paiements`/
/// `sous_comptes_marchands` n'ont **aucune** colonne de tolérance hors-ligne
/// côté serveur : ce sont des actes transactionnels, exécutés en ligne
/// uniquement (même scope que le CRUD RH en M8).
class CachedMarketplaceRepository implements MarketplaceRepository {
  const CachedMarketplaceRepository(this._distant, this._cache, this._syncRepo);

  final MarketplaceRepository _distant;
  final CacheDocumentStore _cache;
  final DriftSyncRepository _syncRepo;

  static const _typeCommercants = 'commercants';
  static const _typeProduits = 'produits';
  static const _typePanier = 'panier_actif';
  static const _typeLignesPanier = 'lignes_panier';
  static const _typeCommandes = 'mes_commandes';

  /// Codes métier authentiques des triggers M13 — jamais mis en file.
  static const _codesMetierBloquants = {
    'PANIER_MONO_VENDEUR',
    'COMMANDE_COMMERCANT_INCOHERENT',
    'COMMANDE_ETABLISSEMENT_INCOHERENT',
    'LIGNE_COMMANDE_COMMERCANT_INCOHERENT',
    'PAIEMENT_FOURNISSEUR_INCOHERENT',
  };

  @override
  Future<List<Commercant>> commercants() async {
    try {
      final liste = await _distant.commercants();
      await _cache.ecrireDocument(_typeCommercants, CacheDocumentStore.cleUnique, {
        'lignes': liste.map((c) => c.versJsonCache()).toList(growable: false),
      });
      return liste;
    } on ErreurMarketplace {
      final document = await _cache.lireDocument(_typeCommercants, CacheDocumentStore.cleUnique);
      if (document == null) rethrow;
      return (document['lignes'] as List<dynamic>)
          .map((l) => Commercant.depuisJson(l as Map<String, dynamic>))
          .toList(growable: false);
    }
  }

  @override
  Future<List<CatalogueProduit>> produits({String? commercantId}) async {
    final cle = commercantId ?? CacheDocumentStore.cleUnique;
    try {
      final liste = await _distant.produits(commercantId: commercantId);
      await _cache.ecrireDocument(_typeProduits, cle, {
        'lignes': liste.map((p) => p.versJsonCache()).toList(growable: false),
      });
      return liste;
    } on ErreurMarketplace {
      final document = await _cache.lireDocument(_typeProduits, cle);
      if (document == null) rethrow;
      return (document['lignes'] as List<dynamic>)
          .map((l) => CatalogueProduit.depuisJsonCache(l as Map<String, dynamic>))
          .toList(growable: false);
    }
  }

  @override
  Future<Panier?> panierActifPourProfil(String profileId, String etablissementId) async {
    final cle = '$profileId::$etablissementId';
    Panier? base;
    try {
      base = await _distant.panierActifPourProfil(profileId, etablissementId);
      if (base != null) await _cache.ecrireDocument(_typePanier, cle, base.versJsonCache());
    } on ErreurMarketplace {
      final document = await _cache.lireDocument(_typePanier, cle);
      base = document == null ? null : Panier.depuisJsonCache(document);
    }

    final enAttente = await _syncRepo.entreesEnAttente();
    for (final entree in enAttente) {
      if (entree.entite != 'paniers') continue;
      final enCours = Panier.depuisJsonEcriture(jsonDecode(entree.payload) as Map<String, dynamic>);
      if (enCours.statut == 'actif' && enCours.profileId == profileId && enCours.etablissementId == etablissementId) {
        base = enCours;
      }
    }
    return base;
  }

  @override
  Future<bool> enregistrerPanier(Panier panier) async {
    try {
      return await _distant.enregistrerPanier(panier);
    } catch (e) {
      if (e is ErreurMarketplace && _codesMetierBloquants.contains(e.code)) rethrow;
      await _syncRepo.enfiler(
        SyncEntree(
          id: panier.id,
          entite: 'paniers',
          operation: 'upsert',
          payload: jsonEncode(panier.versJsonEcriture()),
        ),
      );
      return false;
    }
  }

  @override
  Future<List<LignePanier>> lignesDuPanier(String panierId) async {
    List<LignePanier> base;
    try {
      base = await _distant.lignesDuPanier(panierId);
      await _cache.ecrireDocument(_typeLignesPanier, panierId, {
        'lignes': base.map((l) => l.versJsonCache()).toList(growable: false),
      });
    } on ErreurMarketplace {
      final document = await _cache.lireDocument(_typeLignesPanier, panierId);
      if (document == null) rethrow;
      base = (document['lignes'] as List<dynamic>)
          .map((l) => LignePanier.depuisJsonCache(l as Map<String, dynamic>))
          .toList(growable: false);
    }

    final enAttente = await _syncRepo.entreesEnAttente();
    final parId = {for (final l in base) l.id: l};
    for (final entree in enAttente) {
      if (entree.entite != 'lignes_paniers') continue;
      final enCours = LignePanier.depuisJsonEcriture(jsonDecode(entree.payload) as Map<String, dynamic>);
      if (enCours.panierId == panierId) parId[enCours.id] = enCours;
    }
    return parId.values.toList(growable: false);
  }

  @override
  Future<bool> enregistrerLignePanier(LignePanier ligne) async {
    try {
      return await _distant.enregistrerLignePanier(ligne);
    } catch (e) {
      if (e is ErreurMarketplace && _codesMetierBloquants.contains(e.code)) rethrow;
      await _syncRepo.enfiler(
        SyncEntree(
          id: ligne.id,
          entite: 'lignes_paniers',
          operation: 'upsert',
          payload: jsonEncode(ligne.versJsonEcriture()),
        ),
      );
      return false;
    }
  }

  @override
  Future<void> supprimerLignePanier(String ligneId) => _distant.supprimerLignePanier(ligneId);

  @override
  Future<Commande> creerCommande(Commande commande) => _distant.creerCommande(commande);

  @override
  Future<void> enregistrerLignesCommande(List<LigneCommande> lignes) => _distant.enregistrerLignesCommande(lignes);

  @override
  Future<List<Commande>> mesCommandes(String profileId) async {
    final cle = profileId;
    try {
      final liste = await _distant.mesCommandes(profileId);
      await _cache.ecrireDocument(_typeCommandes, cle, {
        'lignes': liste.map((c) => c.versJsonCache()).toList(growable: false),
      });
      return liste;
    } on ErreurMarketplace {
      final document = await _cache.lireDocument(_typeCommandes, cle);
      if (document == null) rethrow;
      return (document['lignes'] as List<dynamic>)
          .map((l) => Commande.depuisJsonCache(l as Map<String, dynamic>))
          .toList(growable: false);
    }
  }

  @override
  Future<List<LigneCommande>> lignesDeCommande(String commandeId) => _distant.lignesDeCommande(commandeId);

  @override
  Future<List<SousCompteMarchand>> sousComptesEtablissement(String etablissementId) =>
      _distant.sousComptesEtablissement(etablissementId);

  @override
  Future<bool> enregistrerSousCompte(SousCompteMarchand sousCompte) => _distant.enregistrerSousCompte(sousCompte);

  @override
  Future<Paiement> initierPaiement(Paiement paiement) => _distant.initierPaiement(paiement);

  @override
  Future<List<Paiement>> paiementsDeCommande(String commandeId) => _distant.paiementsDeCommande(commandeId);

  @override
  Future<List<AnomalieCommande>> detecterAnomalies(String etablissementId) => _distant.detecterAnomalies(etablissementId);
}
