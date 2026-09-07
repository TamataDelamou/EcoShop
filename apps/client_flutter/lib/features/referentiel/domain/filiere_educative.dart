/// Projection cliente de `public.filieres_educatives` (M4) — séries du lycée.
class FiliereEducative {
  const FiliereEducative({
    required this.id,
    required this.paysCode,
    required this.code,
    required this.nom,
    this.niveauId,
    this.description,
  });

  factory FiliereEducative.depuisJson(Map<String, dynamic> json) {
    return FiliereEducative(
      id: json['id'] as String,
      paysCode: json['pays_code'] as String,
      code: json['code'] as String,
      nom: json['nom'] as String,
      niveauId: json['niveau_id'] as String?,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> versJson() => {
        'id': id,
        'pays_code': paysCode,
        'code': code,
        'nom': nom,
        'niveau_id': niveauId,
        'description': description,
      };

  final String id;
  final String paysCode;
  final String code;
  final String nom;
  final String? niveauId;
  final String? description;
}
