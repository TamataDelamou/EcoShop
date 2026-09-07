/// Projection cliente de `public.lignes_commandes` (M13) — snapshot du prix
/// au moment de la commande (`prixUnitaire`/`montantLigne` figés, jamais
/// recalculés depuis `catalogues_produits`).
class LigneCommande {
  const LigneCommande({
    required this.id,
    required this.commandeId,
    required this.catalogueProduitId,
    required this.quantite,
    required this.prixUnitaire,
    required this.montantLigne,
    this.libelleProduit,
  });

  factory LigneCommande.depuisJson(Map<String, dynamic> json) {
    final produit = json['catalogues_produits'] as Map<String, dynamic>?;
    return LigneCommande(
      id: json['id'] as String,
      commandeId: json['commande_id'] as String,
      catalogueProduitId: json['catalogue_produit_id'] as String,
      quantite: json['quantite'] as int,
      prixUnitaire: (json['prix_unitaire'] as num).toDouble(),
      montantLigne: (json['montant_ligne'] as num).toDouble(),
      libelleProduit: produit?['libelle'] as String?,
    );
  }

  /// Colonnes réelles de `public.lignes_commandes` — pour l'insert.
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'commande_id': commandeId,
        'catalogue_produit_id': catalogueProduitId,
        'quantite': quantite,
        'prix_unitaire': prixUnitaire,
        'montant_ligne': montantLigne,
      };

  final String id;
  final String commandeId;
  final String catalogueProduitId;
  final int quantite;
  final double prixUnitaire;
  final double montantLigne;

  /// Peuplé via l'embed PostgREST — affichage uniquement.
  final String? libelleProduit;
}
