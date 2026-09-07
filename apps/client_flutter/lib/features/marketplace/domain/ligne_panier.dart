/// Projection cliente de `public.lignes_paniers` (M13). Contrainte serveur
/// `lignes_paniers_unique (panier_id, catalogue_produit_id)` : l'upsert cible
/// ce couple, ce qui rend l'ajout au panier idempotent (rejouer la même
/// opération hors-ligne ne duplique jamais la ligne).
class LignePanier {
  const LignePanier({
    required this.id,
    required this.panierId,
    required this.catalogueProduitId,
    this.quantite = 1,
    this.libelleProduit,
    this.prixUnitaire,
  });

  factory LignePanier.depuisJson(Map<String, dynamic> json) {
    final produit = json['catalogues_produits'] as Map<String, dynamic>?;
    return LignePanier(
      id: json['id'] as String,
      panierId: json['panier_id'] as String,
      catalogueProduitId: json['catalogue_produit_id'] as String,
      quantite: json['quantite'] as int? ?? 1,
      libelleProduit: produit?['libelle'] as String?,
      prixUnitaire: produit?['prix'] == null ? null : (produit!['prix'] as num).toDouble(),
    );
  }

  factory LignePanier.depuisJsonCache(Map<String, dynamic> json) => LignePanier(
        id: json['id'] as String,
        panierId: json['panier_id'] as String,
        catalogueProduitId: json['catalogue_produit_id'] as String,
        quantite: json['quantite'] as int? ?? 1,
        libelleProduit: json['libelle_produit'] as String?,
        prixUnitaire: json['prix_unitaire'] == null ? null : (json['prix_unitaire'] as num).toDouble(),
      );

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'panier_id': panierId,
        'catalogue_produit_id': catalogueProduitId,
        'quantite': quantite,
        'libelle_produit': libelleProduit,
        'prix_unitaire': prixUnitaire,
      };

  /// Colonnes réelles de `public.lignes_paniers` — pour l'upsert.
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'panier_id': panierId,
        'catalogue_produit_id': catalogueProduitId,
        'quantite': quantite,
      };

  factory LignePanier.depuisJsonEcriture(Map<String, dynamic> json) => LignePanier(
        id: json['id'] as String,
        panierId: json['panier_id'] as String,
        catalogueProduitId: json['catalogue_produit_id'] as String,
        quantite: json['quantite'] as int? ?? 1,
      );

  LignePanier copierAvec({int? quantite}) => LignePanier(
        id: id,
        panierId: panierId,
        catalogueProduitId: catalogueProduitId,
        quantite: quantite ?? this.quantite,
        libelleProduit: libelleProduit,
        prixUnitaire: prixUnitaire,
      );

  final String id;
  final String panierId;
  final String catalogueProduitId;
  final int quantite;

  /// Peuplés via l'embed PostgREST — affichage uniquement.
  final String? libelleProduit;
  final double? prixUnitaire;
}
