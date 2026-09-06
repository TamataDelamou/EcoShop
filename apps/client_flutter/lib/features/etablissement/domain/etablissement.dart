/// Projection cliente de `public.etablissements` (racine multi-tenant, ch. 27).
class Etablissement {
  const Etablissement({
    required this.id,
    required this.nom,
    required this.slug,
    this.paysCode,
    this.ville,
    this.deviseCode = 'GNF',
    this.langueCode = 'fr',
    this.fuseauHoraire = 'Africa/Conakry',
  });

  factory Etablissement.depuisJson(Map<String, dynamic> json) {
    return Etablissement(
      id: json['id'] as String,
      nom: json['nom'] as String,
      slug: json['slug'] as String,
      paysCode: json['pays_code'] as String?,
      ville: json['ville'] as String?,
      deviseCode: json['devise_code'] as String? ?? 'GNF',
      langueCode: json['langue_code'] as String? ?? 'fr',
      fuseauHoraire: json['fuseau_horaire'] as String? ?? 'Africa/Conakry',
    );
  }

  final String id;
  final String nom;
  final String slug;
  final String? paysCode;
  final String? ville;

  /// Devise, langue et fuseau proviennent du référentiel : ils ne sont jamais
  /// déduits côté client (conventions — pas de configuration en dur).
  final String deviseCode;
  final String langueCode;
  final String fuseauHoraire;

  /// Libellé secondaire affiché sous le nom dans les listes.
  String get localisation =>
      [ville, paysCode].where((v) => v != null && v.isNotEmpty).join(' · ');
}
