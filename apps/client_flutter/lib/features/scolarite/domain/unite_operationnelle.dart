/// Projection cliente de `public.unites_operationnelles` (M1) — campus, annexes.
class UniteOperationnelle {
  const UniteOperationnelle({
    required this.id,
    required this.etablissementId,
    required this.code,
    required this.nom,
    this.parentId,
    this.adresse,
    this.actif = true,
  });

  factory UniteOperationnelle.depuisJson(Map<String, dynamic> json) {
    return UniteOperationnelle(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      code: json['code'] as String,
      nom: json['nom'] as String,
      parentId: json['parent_id'] as String?,
      adresse: json['adresse'] as String?,
      actif: json['actif'] as bool? ?? true,
    );
  }

  Map<String, dynamic> versJson() => {
        'id': id,
        'etablissement_id': etablissementId,
        'code': code,
        'nom': nom,
        'parent_id': parentId,
        'adresse': adresse,
        'actif': actif,
      };

  final String id;
  final String etablissementId;
  final String code;
  final String nom;
  final String? parentId;
  final String? adresse;
  final bool actif;
}
