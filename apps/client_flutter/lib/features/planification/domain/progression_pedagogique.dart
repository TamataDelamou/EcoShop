import 'enums_planification.dart';

/// Projection cliente de `public.progression_pedagogique` (M11) — séance de
/// cours liée au programme (M4) et, le cas échéant, à une évaluation (M6).
/// Un statut `proposee` désigne une séance de rattrapage suggérée par
/// `recommander_seances` (IA) — au plus une par classe et par année tant
/// qu'elle n'a pas été traitée (index partiel serveur), jamais une décision
/// automatisée.
class ProgressionPedagogique {
  const ProgressionPedagogique({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    required this.classeId,
    this.programmeMatiereId,
    required this.enseignantProfileId,
    required this.seance,
    this.objectifs,
    this.contenu,
    this.evaluationId,
    this.statut = StatutProgression.planifiee,
    this.datePrevue,
    this.dateRealisee,
    this.modifieLe,
    this.deviceId,
  });

  factory ProgressionPedagogique.depuisJson(Map<String, dynamic> json) => ProgressionPedagogique(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        anneeScolaireId: json['annee_scolaire_id'] as String,
        classeId: json['classe_id'] as String,
        programmeMatiereId: json['programme_matiere_id'] as String?,
        enseignantProfileId: json['enseignant_profile_id'] as String,
        seance: json['seance'] as String,
        objectifs: json['objectifs'] as String?,
        contenu: json['contenu'] as String?,
        evaluationId: json['evaluation_id'] as String?,
        statut: StatutProgression.depuisCode(json['statut'] as String?),
        datePrevue: json['date_prevue'] == null ? null : DateTime.parse(json['date_prevue'] as String),
        dateRealisee: json['date_realisee'] == null ? null : DateTime.parse(json['date_realisee'] as String),
        modifieLe: json['modifie_le'] == null ? null : DateTime.parse(json['modifie_le'] as String),
        deviceId: json['device_id'] as String?,
      );

  factory ProgressionPedagogique.depuisJsonCache(Map<String, dynamic> json) =>
      ProgressionPedagogique.depuisJson(json);

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'classe_id': classeId,
        'programme_matiere_id': programmeMatiereId,
        'enseignant_profile_id': enseignantProfileId,
        'seance': seance,
        'objectifs': objectifs,
        'contenu': contenu,
        'evaluation_id': evaluationId,
        'statut': statut.code,
        'date_prevue': datePrevue == null ? null : _dateIso(datePrevue!),
        'date_realisee': dateRealisee == null ? null : _dateIso(dateRealisee!),
        'modifie_le': modifieLe?.toIso8601String(),
        'device_id': deviceId,
      };

  /// Colonnes réelles de `public.progression_pedagogique` — pour l'upsert
  /// (pas de contrainte unique métier hors le cas `proposee` : upsert par
  /// `id`, généré côté client).
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'classe_id': classeId,
        'programme_matiere_id': programmeMatiereId,
        'enseignant_profile_id': enseignantProfileId,
        'seance': seance,
        'objectifs': objectifs,
        'contenu': contenu,
        'evaluation_id': evaluationId,
        'statut': statut.code,
        'date_prevue': datePrevue == null ? null : _dateIso(datePrevue!),
        'date_realisee': dateRealisee == null ? null : _dateIso(dateRealisee!),
        'modifie_le': (modifieLe ?? DateTime.now()).toIso8601String(),
        'device_id': deviceId,
      };

  factory ProgressionPedagogique.depuisJsonEcriture(Map<String, dynamic> json) =>
      ProgressionPedagogique.depuisJson(json);

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String classeId;
  final String? programmeMatiereId;
  final String enseignantProfileId;
  final String seance;
  final String? objectifs;
  final String? contenu;
  final String? evaluationId;
  final StatutProgression statut;
  final DateTime? datePrevue;
  final DateTime? dateRealisee;
  final DateTime? modifieLe;
  final String? deviceId;

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
