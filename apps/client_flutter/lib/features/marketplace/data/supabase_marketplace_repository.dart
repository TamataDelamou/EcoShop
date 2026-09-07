import 'package:supabase_flutter/supabase_flutter.dart';

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

const _embedProduit = '*, commercants(nom)';
const _embedLignePanier = '*, catalogues_produits(libelle, prix)';
const _embedCommande = '*, commercants(nom)';
const _embedLigneCommande = '*, catalogues_produits(libelle)';

/// Implémentation Supabase du port [MarketplaceRepository] (M13).
class SupabaseMarketplaceRepository implements MarketplaceRepository {
  const SupabaseMarketplaceRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Commercant>> commercants() {
    return _executer(() async {
      final lignes = await _client.from('commercants').select().eq('actif', true).order('nom');
      return lignes.map((l) => Commercant.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<CatalogueProduit>> produits({String? commercantId}) {
    return _executer(() async {
      var requete = _client.from('catalogues_produits').select(_embedProduit).eq('actif', true);
      if (commercantId != null) requete = requete.eq('commercant_id', commercantId);
      final lignes = await requete.order('libelle');
      return lignes.map((l) => CatalogueProduit.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<Panier?> panierActifPourProfil(String profileId, String etablissementId) {
    return _executer(() async {
      final ligne = await _client
          .from('paniers')
          .select()
          .eq('profile_id', profileId)
          .eq('etablissement_id', etablissementId)
          .eq('statut', 'actif')
          .maybeSingle();
      return ligne == null ? null : Panier.depuisJson(ligne);
    });
  }

  @override
  Future<bool> enregistrerPanier(Panier panier) {
    return _executer(() async {
      await _client.from('paniers').upsert(panier.versJsonEcriture(), onConflict: 'id');
      return true;
    });
  }

  @override
  Future<List<LignePanier>> lignesDuPanier(String panierId) {
    return _executer(() async {
      final lignes = await _client
          .from('lignes_paniers')
          .select(_embedLignePanier)
          .eq('panier_id', panierId)
          .order('created_at');
      return lignes.map((l) => LignePanier.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<bool> enregistrerLignePanier(LignePanier ligne) {
    return _executer(() async {
      await _client
          .from('lignes_paniers')
          .upsert(ligne.versJsonEcriture(), onConflict: 'panier_id,catalogue_produit_id');
      return true;
    });
  }

  @override
  Future<void> supprimerLignePanier(String ligneId) {
    return _executer(() async {
      await _client.from('lignes_paniers').delete().eq('id', ligneId);
    });
  }

  @override
  Future<Commande> creerCommande(Commande commande) {
    return _executer(() async {
      final ligne = await _client.from('commandes').insert(commande.versJsonEcriture()).select(_embedCommande).single();
      return Commande.depuisJson(ligne);
    });
  }

  @override
  Future<void> enregistrerLignesCommande(List<LigneCommande> lignes) {
    return _executer(() async {
      if (lignes.isEmpty) return;
      await _client.from('lignes_commandes').insert(lignes.map((l) => l.versJsonEcriture()).toList(growable: false));
    });
  }

  @override
  Future<List<Commande>> mesCommandes(String profileId) {
    return _executer(() async {
      final lignes = await _client
          .from('commandes')
          .select(_embedCommande)
          .eq('profile_id', profileId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);
      return lignes.map((l) => Commande.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<LigneCommande>> lignesDeCommande(String commandeId) {
    return _executer(() async {
      final lignes = await _client
          .from('lignes_commandes')
          .select(_embedLigneCommande)
          .eq('commande_id', commandeId)
          .order('created_at');
      return lignes.map((l) => LigneCommande.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<SousCompteMarchand>> sousComptesEtablissement(String etablissementId) {
    return _executer(() async {
      final lignes = await _client
          .from('sous_comptes_marchands')
          .select()
          .eq('etablissement_id', etablissementId)
          .eq('actif', true)
          .isFilter('deleted_at', null)
          .order('libelle');
      return lignes.map((l) => SousCompteMarchand.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<bool> enregistrerSousCompte(SousCompteMarchand sousCompte) {
    return _executer(() async {
      await _client
          .from('sous_comptes_marchands')
          .upsert(sousCompte.versJsonEcriture(), onConflict: 'etablissement_id,fournisseur');
      return true;
    });
  }

  @override
  Future<Paiement> initierPaiement(Paiement paiement) {
    return _executer(() async {
      final ligne = await _client.from('paiements').insert(paiement.versJsonEcriture()).select().single();
      return Paiement.depuisJson(ligne);
    });
  }

  @override
  Future<List<Paiement>> paiementsDeCommande(String commandeId) {
    return _executer(() async {
      final lignes =
          await _client.from('paiements').select().eq('commande_id', commandeId).order('created_at', ascending: false);
      return lignes.map((l) => Paiement.depuisJson(l)).toList(growable: false);
    });
  }

  @override
  Future<List<AnomalieCommande>> detecterAnomalies(String etablissementId) {
    return _executer(() async {
      final resultat = await _client.rpc<List<dynamic>>(
        'detecter_anomalies_commandes',
        params: {'p_etablissement': etablissementId},
      );
      return resultat.map((l) => AnomalieCommande.depuisJson(l as Map<String, dynamic>)).toList(growable: false);
    });
  }

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw ErreurMarketplace(_codeDepuisMessage(e.message), e.message);
    }
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_RESEAU';
  }
}
