import 'enums_notes.dart';

/// Projection cliente de `public.evaluations` (M6) — devoir, contrôle,
/// composition… l'unité de notation.
class Evaluation {
  const Evaluation({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    required this.classeId,
    required this.enseignantProfileId,
    required this.libelle,
    required this.dateEvaluation,
    this.periodeId,
    this.programmeMatiereId,
    this.type = TypeEvaluation.controle,
    this.coefficient = 1,
    this.bareme = 20,
    this.statut = StatutEvaluation.brouillon,
    this.nomMatiere,
  });

  factory Evaluation.depuisJson(Map<String, dynamic> json) {
    final matiere = json['programmes_matieres'] as Map<String, dynamic>?;
    return Evaluation(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      classeId: json['classe_id'] as String,
      enseignantProfileId: json['enseignant_profile_id'] as String,
      libelle: json['libelle'] as String,
      dateEvaluation: DateTime.parse(json['date_evaluation'] as String),
      periodeId: json['periode_id'] as String?,
      programmeMatiereId: json['programme_matiere_id'] as String?,
      type: TypeEvaluation.depuisCode(json['type'] as String?),
      coefficient: (json['coefficient'] as num?)?.toDouble() ?? 1,
      bareme: (json['bareme'] as num?)?.toDouble() ?? 20,
      statut: StatutEvaluation.depuisCode(json['statut'] as String?),
      nomMatiere: matiere?['nom'] as String?,
    );
  }

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'classe_id': classeId,
        'enseignant_profile_id': enseignantProfileId,
        'libelle': libelle,
        'date_evaluation': _dateIso(dateEvaluation),
        'periode_id': periodeId,
        'programme_matiere_id': programmeMatiereId,
        'type': type.code,
        'coefficient': coefficient,
        'bareme': bareme,
        'statut': statut.code,
        'nom_matiere': nomMatiere,
      };

  factory Evaluation.depuisJsonCache(Map<String, dynamic> json) {
    return Evaluation(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      classeId: json['classe_id'] as String,
      enseignantProfileId: json['enseignant_profile_id'] as String,
      libelle: json['libelle'] as String,
      dateEvaluation: DateTime.parse(json['date_evaluation'] as String),
      periodeId: json['periode_id'] as String?,
      programmeMatiereId: json['programme_matiere_id'] as String?,
      type: TypeEvaluation.depuisCode(json['type'] as String?),
      coefficient: (json['coefficient'] as num?)?.toDouble() ?? 1,
      bareme: (json['bareme'] as num?)?.toDouble() ?? 20,
      statut: StatutEvaluation.depuisCode(json['statut'] as String?),
      nomMatiere: json['nom_matiere'] as String?,
    );
  }

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String classeId;
  final String enseignantProfileId;
  final String libelle;
  final DateTime dateEvaluation;
  final String? periodeId;
  final String? programmeMatiereId;
  final TypeEvaluation type;
  final double coefficient;
  final double bareme;
  final StatutEvaluation statut;

  /// Peuplé via l'embed `programmes_matieres(nom)` — affichage uniquement.
  final String? nomMatiere;

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
