import '../../../core/format/coefficient.dart';

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
    this.nature = 'tronc_commun',
  });

  factory ProgrammeMatiere.depuisJson(Map<String, dynamic> json) {
    return ProgrammeMatiere(
      id: json['id'] as String,
      programmeId: json['programme_id'] as String,
      code: json['code'] as String,
      nom: json['nom'] as String,
      ordre: json['ordre'] as int? ?? 0,
      coefficient: lireCoefficient(json['coefficient']),
      volumeHoraireAnnuel: json['volume_horaire_annuel'] as int?,
      nature: json['nature'] as String? ?? 'tronc_commun',
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
        'nature': nature,
      };

  final String id;
  final String programmeId;
  final String code;
  final String nom;
  final int ordre;
  final double? coefficient;
  final int? volumeHoraireAnnuel;

  /// REG-33 : `tronc_commun`, `specialite` (propre à la série) ou `option`.
  final String nature;

  static const natures = {'tronc_commun': 'Tronc commun', 'specialite': 'Spécialité de la série', 'option': 'Option'};
}
