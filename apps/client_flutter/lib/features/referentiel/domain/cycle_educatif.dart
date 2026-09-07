/// Projection cliente de `public.cycles_educatifs` (M4) — ex. primaire, collège.
class CycleEducatif {
  const CycleEducatif({
    required this.id,
    required this.paysCode,
    required this.code,
    required this.nom,
    required this.ordre,
    required this.iscedMin,
    required this.iscedMax,
    this.ageMin,
    this.ageMax,
    this.dureeAnnees,
  });

  factory CycleEducatif.depuisJson(Map<String, dynamic> json) {
    return CycleEducatif(
      id: json['id'] as String,
      paysCode: json['pays_code'] as String,
      code: json['code'] as String,
      nom: json['nom'] as String,
      ordre: json['ordre'] as int,
      iscedMin: json['isced_min'] as int,
      iscedMax: json['isced_max'] as int,
      ageMin: json['age_min'] as int?,
      ageMax: json['age_max'] as int?,
      dureeAnnees: json['duree_annees'] as int?,
    );
  }

  Map<String, dynamic> versJson() => {
        'id': id,
        'pays_code': paysCode,
        'code': code,
        'nom': nom,
        'ordre': ordre,
        'isced_min': iscedMin,
        'isced_max': iscedMax,
        'age_min': ageMin,
        'age_max': ageMax,
        'duree_annees': dureeAnnees,
      };

  final String id;
  final String paysCode;
  final String code;
  final String nom;
  final int ordre;
  final int iscedMin;
  final int iscedMax;
  final int? ageMin;
  final int? ageMax;
  final int? dureeAnnees;
}
