/// Projection cliente de `public.niveaux_educatifs` (M4) — ex. CP1, 6e, JHS1.
///
/// [gradeLevelNormalise] est la clé de comparaison inter-pays : elle ne doit
/// **jamais** être affichée à l'utilisateur (seul [nom], l'appellation locale,
/// l'est — cf. contrat M04 §5).
class NiveauEducatif {
  const NiveauEducatif({
    required this.id,
    required this.cycleId,
    required this.paysCode,
    required this.code,
    required this.nom,
    required this.gradeLevelNormalise,
    required this.isced,
    required this.ordre,
  });

  factory NiveauEducatif.depuisJson(Map<String, dynamic> json) {
    return NiveauEducatif(
      id: json['id'] as String,
      cycleId: json['cycle_id'] as String,
      paysCode: json['pays_code'] as String,
      code: json['code'] as String,
      nom: json['nom'] as String,
      gradeLevelNormalise: json['grade_level_normalise'] as int,
      isced: json['isced'] as int,
      ordre: json['ordre'] as int,
    );
  }

  Map<String, dynamic> versJson() => {
        'id': id,
        'cycle_id': cycleId,
        'pays_code': paysCode,
        'code': code,
        'nom': nom,
        'grade_level_normalise': gradeLevelNormalise,
        'isced': isced,
        'ordre': ordre,
      };

  final String id;
  final String cycleId;
  final String paysCode;
  final String code;
  final String nom;
  final int gradeLevelNormalise;
  final int isced;
  final int ordre;
}
