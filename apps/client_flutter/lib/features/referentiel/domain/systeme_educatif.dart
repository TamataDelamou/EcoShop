/// Projection cliente de `public.systemes_educatifs` (M4, 4 familles CEDEAO).
class SystemeEducatif {
  const SystemeEducatif({
    required this.code,
    required this.nom,
    this.description,
  });

  factory SystemeEducatif.depuisJson(Map<String, dynamic> json) {
    return SystemeEducatif(
      code: json['code'] as String,
      nom: json['nom'] as String,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> versJson() => {
        'code': code,
        'nom': nom,
        'description': description,
      };

  final String code;
  final String nom;
  final String? description;
}
