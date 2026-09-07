/// Projection cliente de `public.programmes_officiels` (M4) — curriculum versionné.
class ProgrammeOfficiel {
  const ProgrammeOfficiel({
    required this.id,
    required this.paysCode,
    required this.niveauId,
    required this.code,
    required this.nom,
    required this.version,
    this.filiereId,
    this.anneeScolaire,
  });

  factory ProgrammeOfficiel.depuisJson(Map<String, dynamic> json) {
    return ProgrammeOfficiel(
      id: json['id'] as String,
      paysCode: json['pays_code'] as String,
      niveauId: json['niveau_id'] as String,
      code: json['code'] as String,
      nom: json['nom'] as String,
      version: json['version'] as int,
      filiereId: json['filiere_id'] as String?,
      anneeScolaire: json['annee_scolaire'] as String?,
    );
  }

  Map<String, dynamic> versJson() => {
        'id': id,
        'pays_code': paysCode,
        'niveau_id': niveauId,
        'code': code,
        'nom': nom,
        'version': version,
        'filiere_id': filiereId,
        'annee_scolaire': anneeScolaire,
      };

  final String id;
  final String paysCode;
  final String niveauId;
  final String code;
  final String nom;
  final int version;
  final String? filiereId;
  final String? anneeScolaire;
}
