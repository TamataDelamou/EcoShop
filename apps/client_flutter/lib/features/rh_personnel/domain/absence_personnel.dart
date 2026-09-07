import 'enums_rh.dart';

/// Projection cliente de `public.absences_personnel` (M8) — pointage RH,
/// alimente le score de risque de turn-over (`calculer_score_turnover`).
///
/// Saisie hors connexion via la même file `sync_queue` que le pointage de
/// présence des élèves (M7) : une absence de dernière minute doit pouvoir
/// être enregistrée même sans réseau (ex. salle des professeurs mal
/// couverte), voir `RhRepository.pointerAbsence`.
class AbsencePersonnel {
  const AbsencePersonnel({
    required this.id,
    required this.etablissementId,
    required this.employeId,
    required this.dateAbsence,
    this.type = TypeAbsencePersonnel.injustifiee,
    this.justifie = false,
    this.motif,
  });

  factory AbsencePersonnel.depuisJson(Map<String, dynamic> json) => AbsencePersonnel(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        employeId: json['employe_id'] as String,
        dateAbsence: DateTime.parse(json['date_absence'] as String),
        type: TypeAbsencePersonnel.depuisCode(json['type'] as String?),
        justifie: json['justifie'] as bool? ?? false,
        motif: json['motif'] as String?,
      );

  factory AbsencePersonnel.depuisJsonCache(Map<String, dynamic> json) => AbsencePersonnel(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        employeId: json['employe_id'] as String,
        dateAbsence: DateTime.parse(json['date_absence'] as String),
        type: TypeAbsencePersonnel.depuisCode(json['type'] as String?),
        justifie: json['justifie'] as bool? ?? false,
        motif: json['motif'] as String?,
      );

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'employe_id': employeId,
        'date_absence': _dateIso(dateAbsence),
        'type': type.code,
        'justifie': justifie,
        'motif': motif,
      };

  /// Colonnes réelles de `public.absences_personnel` — pour l'upsert.
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'employe_id': employeId,
        'date_absence': _dateIso(dateAbsence),
        'type': type.code,
        'justifie': justifie,
        'motif': motif,
      };

  factory AbsencePersonnel.depuisJsonEcriture(Map<String, dynamic> json) => AbsencePersonnel(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        employeId: json['employe_id'] as String,
        dateAbsence: DateTime.parse(json['date_absence'] as String),
        type: TypeAbsencePersonnel.depuisCode(json['type'] as String?),
        justifie: json['justifie'] as bool? ?? false,
        motif: json['motif'] as String?,
      );

  final String id;
  final String etablissementId;
  final String employeId;
  final DateTime dateAbsence;
  final TypeAbsencePersonnel type;
  final bool justifie;
  final String? motif;

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
