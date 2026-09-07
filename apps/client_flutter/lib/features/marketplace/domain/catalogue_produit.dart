/// Projection cliente de `public.catalogues_produits` (M13) — produit porté
/// par un commerçant. Pas de colonne « catégorie » côté DDL réel : le
/// filtrage catalogue se limite au commerçant et à une recherche texte sur
/// [libelle]/[description], pas à une taxonomie de catégories.
class CatalogueProduit {
  const CatalogueProduit({
    required this.id,
    required this.commercantId,
    required this.libelle,
    this.description,
    required this.prix,
    this.devise = 'XOF',
    this.actif = true,
    this.nomCommercant,
  });

  factory CatalogueProduit.depuisJson(Map<String, dynamic> json) {
    final commercant = json['commercants'] as Map<String, dynamic>?;
    return CatalogueProduit(
      id: json['id'] as String,
      commercantId: json['commercant_id'] as String,
      libelle: json['libelle'] as String,
      description: json['description'] as String?,
      prix: (json['prix'] as num).toDouble(),
      devise: json['devise'] as String? ?? 'XOF',
      actif: json['actif'] as bool? ?? true,
      nomCommercant: commercant?['nom'] as String?,
    );
  }

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'commercant_id': commercantId,
        'libelle': libelle,
        'description': description,
        'prix': prix,
        'devise': devise,
        'actif': actif,
        'nom_commercant': nomCommercant,
      };

  factory CatalogueProduit.depuisJsonCache(Map<String, dynamic> json) => CatalogueProduit(
        id: json['id'] as String,
        commercantId: json['commercant_id'] as String,
        libelle: json['libelle'] as String,
        description: json['description'] as String?,
        prix: (json['prix'] as num).toDouble(),
        devise: json['devise'] as String? ?? 'XOF',
        actif: json['actif'] as bool? ?? true,
        nomCommercant: json['nom_commercant'] as String?,
      );

  final String id;
  final String commercantId;
  final String libelle;
  final String? description;
  final double prix;
  final String devise;
  final bool actif;

  /// Peuplé via l'embed PostgREST — affichage uniquement.
  final String? nomCommercant;
}
