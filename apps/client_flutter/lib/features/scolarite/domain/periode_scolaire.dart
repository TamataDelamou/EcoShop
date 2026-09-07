import 'enums_scolarite.dart';

/// Projection cliente de `public.periodes_scolaires` (M5).
class PeriodeScolaire {
  const PeriodeScolaire({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    required this.code,
    required this.libelle,
    required this.ordre,
    required this.dateDebut,
    required this.dateFin,
    this.type = TypePeriode.trimestre,
  });

  factory PeriodeScolaire.depuisJson(Map<String, dynamic> json) {
    return PeriodeScolaire(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      code: json['code'] as String,
      libelle: json['libelle'] as String,
      ordre: json['ordre'] as int,
      dateDebut: DateTime.parse(json['date_debut'] as String),
      dateFin: DateTime.parse(json['date_fin'] as String),
      type: TypePeriode.depuisCode(json['type'] as String?),
    );
  }

  Map<String, dynamic> versJson() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'code': code,
        'libelle': libelle,
        'ordre': ordre,
        'date_debut': dateDebut.toIso8601String(),
        'date_fin': dateFin.toIso8601String(),
        'type': type.code,
      };

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String code;
  final String libelle;
  final int ordre;
  final DateTime dateDebut;
  final DateTime dateFin;
  final TypePeriode type;
}
