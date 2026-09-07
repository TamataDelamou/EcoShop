import 'anomalie_commande.dart';
import 'catalogue_produit.dart';
import 'commande.dart';
import 'commercant.dart';
import 'ligne_commande.dart';
import 'ligne_panier.dart';
import 'paiement.dart';
import 'panier.dart';
import 'sous_compte_marchand.dart';

/// Erreur métier ou réseau du port [MarketplaceRepository]. [code] porte soit
/// un code de contrainte serveur authentique (ex. `PANIER_MONO_VENDEUR`,
/// `PAIEMENT_FOURNISSEUR_INCOHERENT`), soit `ERREUR_RESEAU` en cas de panne.
class ErreurMarketplace implements Exception {
  const ErreurMarketplace(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurMarketplace($code${detail != null ? ': $detail' : ''})';
}

/// Port Marketplace AssoShop (M13). Catalogue public (lecture sans session) ;
/// panier/commande/paiement exigent un compte authentifié (`profileId`),
/// sans notion de rattachement établissement obligatoire (cf.
/// `marketplace_providers.dart` pour la résolution d'établissement au
/// checkout d'un compte non rattaché).
abstract interface class MarketplaceRepository {
  // ---------------------------------------------------------------------
  // Catalogue — lecture publique (fonctionne même sans session ouverte).
  // ---------------------------------------------------------------------
  Future<List<Commercant>> commercants();
  Future<List<CatalogueProduit>> produits({String? commercantId});

  // ---------------------------------------------------------------------
  // Panier — mono-vendeur, tolérant hors-ligne (LWW via device_id/client_ts).
  // ---------------------------------------------------------------------
  Future<Panier?> panierActifPourProfil(String profileId, String etablissementId);
  Future<bool> enregistrerPanier(Panier panier);
  Future<List<LignePanier>> lignesDuPanier(String panierId);
  Future<bool> enregistrerLignePanier(LignePanier ligne);
  Future<void> supprimerLignePanier(String ligneId);

  // ---------------------------------------------------------------------
  // Commande & lignes — actes transactionnels, en ligne uniquement.
  // ---------------------------------------------------------------------
  Future<Commande> creerCommande(Commande commande);
  Future<void> enregistrerLignesCommande(List<LigneCommande> lignes);
  Future<List<Commande>> mesCommandes(String profileId);
  Future<List<LigneCommande>> lignesDeCommande(String commandeId);

  // ---------------------------------------------------------------------
  // Sous-comptes marchands — configuration établissement, en ligne uniquement.
  // ---------------------------------------------------------------------
  Future<List<SousCompteMarchand>> sousComptesEtablissement(String etablissementId);
  Future<bool> enregistrerSousCompte(SousCompteMarchand sousCompte);

  // ---------------------------------------------------------------------
  // Paiement — port agnostique, initiation seule (exécution = M14).
  // ---------------------------------------------------------------------
  Future<Paiement> initierPaiement(Paiement paiement);
  Future<List<Paiement>> paiementsDeCommande(String commandeId);

  // ---------------------------------------------------------------------
  // IA descriptive.
  // ---------------------------------------------------------------------
  Future<List<AnomalieCommande>> detecterAnomalies(String etablissementId);
}
