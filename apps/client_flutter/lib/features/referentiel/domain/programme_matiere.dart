/// Projection cliente de `public.programmes_matieres` (M4).
class ProgrammeMatiere {
  const ProgrammeMatiere({
    required this.id,
    required this.programmeId,
    required this.code,
    required this.nom,
    required this.ordre,
    this.coefficient,
    this.volumeHoraireAnnuel,
  });

  factory ProgrammeMatiere.depuisJson(Map<String, dynamic> json) {
    return ProgrammeMatiere(
      id: json['id'] as String,
      programmeId: json['programme_id'] as String,
      code: json['code'] as String,
      nom: json['nom'] as String,
      ordre: json['ordre'] as int? ?? 0,
      coefficient: json['coefficient'] as int?,
      volumeHoraireAnnuel: json['volume_horaire_annuel'] as int?,
    );
  }

  Map<String, dynamic> versJson() => {
        'id': id,
        'programme_id': programmeId,
        'code': code,
        'nom': nom,
        'ordre': ordre,
        'coefficient': coefficient,
        'volume_horaire_annuel': volumeHoraireAnnuel,
      };

  final String id;
  final String programmeId;
  final String code;
  final String nom;
  final int ordre;
  final int? coefficient;
  final int? volumeHoraireAnnuel;
}
