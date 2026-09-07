/// Panier en brouillon **avant** connaissance de l'établissement (M13) — le
/// DDL réel exige `paniers.etablissement_id NOT NULL`, or un compte
/// authentifié sans rattachement (ex. un "Parent" auto-inscrit qui ne suit la
/// scolarité d'aucun enfant, simple client Marketplace) ne peut pas lister les
/// établissements pour en choisir un : la RLS `etablissements_select_member`
/// est réservée aux membres/admin, et aucune RPC de résolution par code
/// n'existe. Le panier vit donc uniquement en local (Drift) tant que
/// l'identifiant d'établissement n'a pas été saisi au checkout ; il n'est
/// transcrit vers `public.paniers`/`lignes_paniers` (via `sync_queue`,
/// tolérant hors-ligne) qu'à cet instant.
///
/// Ce n'est **pas** une projection d'une table serveur : pas de `depuisJson`
/// réseau, seulement une sérialisation locale pour `CacheDocumentStore`.
class PanierBrouillonLocal {
  const PanierBrouillonLocal({this.commercantId, this.quantites = const {}});

  factory PanierBrouillonLocal.depuisJsonCache(Map<String, dynamic> json) => PanierBrouillonLocal(
        commercantId: json['commercant_id'] as String?,
        quantites: (json['quantites'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v as int)) ?? const {},
      );

  Map<String, dynamic> versJsonCache() => {
        'commercant_id': commercantId,
        'quantites': quantites,
      };

  final String? commercantId;

  /// `catalogueProduitId -> quantité`.
  final Map<String, int> quantites;

  bool get estVide => quantites.isEmpty;

  int get nombreArticles => quantites.values.fold(0, (a, b) => a + b);

  /// Ajoute (ou incrémente) une ligne. Rejette un produit d'un autre
  /// commerçant tant que le panier n'est pas vidé — même garde-fou
  /// mono-vendeur que le trigger serveur `lignes_paniers_verifie_commercant`.
  PanierBrouillonLocal ajouter({required String commercantId, required String catalogueProduitId, int quantite = 1}) {
    if (this.commercantId != null && this.commercantId != commercantId) {
      throw const PanierBrouillonMonoVendeurException();
    }
    final nouvelles = Map<String, int>.of(quantites);
    nouvelles[catalogueProduitId] = (nouvelles[catalogueProduitId] ?? 0) + quantite;
    return PanierBrouillonLocal(commercantId: commercantId, quantites: nouvelles);
  }

  PanierBrouillonLocal definirQuantite(String catalogueProduitId, int quantite) {
    final nouvelles = Map<String, int>.of(quantites);
    if (quantite <= 0) {
      nouvelles.remove(catalogueProduitId);
    } else {
      nouvelles[catalogueProduitId] = quantite;
    }
    return PanierBrouillonLocal(commercantId: nouvelles.isEmpty ? null : commercantId, quantites: nouvelles);
  }

  static const vide = PanierBrouillonLocal();
}

/// Levée quand l'acheteur tente d'ajouter un produit d'un autre commerçant
/// sans avoir vidé son panier — panier mono-vendeur (cahier v4.1, ch. 27).
class PanierBrouillonMonoVendeurException implements Exception {
  const PanierBrouillonMonoVendeurException();
}
