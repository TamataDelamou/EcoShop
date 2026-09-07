/// Ligne d'achat affichable — vue unifiée d'une [LignePanier] (panier
/// serveur) ou d'une entrée de [PanierBrouillonLocal] (panier brouillon),
/// utilisée par l'écran panier et le checkout pour ne pas dupliquer la
/// logique d'affichage/total selon la provenance.
typedef LigneAchat = ({String catalogueProduitId, String nom, double prix, int quantite});
