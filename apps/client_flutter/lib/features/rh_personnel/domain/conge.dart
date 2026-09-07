import 'enums_rh.dart';

/// Projection cliente de `public.conges` (M8) — demande de congé par
/// l'employé, validation humaine RH/direction (trigger serveur
/// `conges_verifie_validation`, jamais une décision automatisée).
///
/// La **demande** (statut `demande`) est saisie hors connexion via la même
/// file `sync_queue` que les présences (M7) — un enseignant en zone
/// dépourvue de réseau doit pouvoir déposer sa demande sans attendre. La
/// **validation** RH reste une action de bureau, toujours en ligne (voir
/// `RhRepository.validerConge`).
class Conge {
  const Conge({
    required this.id,
    required this.etablissementId,
    required this.employeId,
    this.type = TypeConge.annuel,
    required this.dateDebut,
    required this.dateFin,
    required this.nbJours,
    this.statut = StatutConge.demande,
    this.motif,
    this.validePar,
    this.dateValidation,
  });

  factory Conge.depuisJson(Map<String, dynamic> json) => Conge(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        employeId: json['employe_id'] as String,
        type: TypeConge.depuisCode(json['type'] as String?),
        dateDebut: DateTime.parse(json['date_debut'] as String),
        dateFin: DateTime.parse(json['date_fin'] as String),
        nbJours: json['nb_jours'] as int,
        statut: StatutConge.depuisCode(json['statut'] as String?),
        motif: json['motif'] as String?,
        validePar: json['valide_par'] as String?,
        dateValidation: json['date_validation'] == null
            ? null
            : DateTime.parse(json['date_validation'] as String),
      );

  factory Conge.depuisJsonCache(Map<String, dynamic> json) => Conge(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        employeId: json['employe_id'] as String,
        type: TypeConge.depuisCode(json['type'] as String?),
        dateDebut: DateTime.parse(json['date_debut'] as String),
        dateFin: DateTime.parse(json['date_fin'] as String),
        nbJours: json['nb_jours'] as int,
        statut: StatutConge.depuisCode(json['statut'] as String?),
        motif: json['motif'] as String?,
        validePar: json['valide_par'] as String?,
        dateValidation: json['date_validation'] == null
            ? null
            : DateTime.parse(json['date_validation'] as String),
      );

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'employe_id': employeId,
        'type': type.code,
        'date_debut': _dateIso(dateDebut),
        'date_fin': _dateIso(dateFin),
        'nb_jours': nbJours,
        'statut': statut.code,
        'motif': motif,
        'valide_par': validePar,
        'date_validation': dateValidation?.toIso8601String(),
      };

  /// Colonnes réelles de `public.conges` — pour la demande (toujours au
  /// statut `demande` : la validation passe par `RhRepository.validerConge`).
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'employe_id': employeId,
        'type': type.code,
        'date_debut': _dateIso(dateDebut),
        'date_fin': _dateIso(dateFin),
        'nb_jours': nbJours,
        'statut': statut.code,
        'motif': motif,
      };

  factory Conge.depuisJsonEcriture(Map<String, dynamic> json) => Conge(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        employeId: json['employe_id'] as String,
        type: TypeConge.depuisCode(json['type'] as String?),
        dateDebut: DateTime.parse(json['date_debut'] as String),
        dateFin: DateTime.parse(json['date_fin'] as String),
        nbJours: json['nb_jours'] as int,
        statut: StatutConge.depuisCode(json['statut'] as String?),
        motif: json['motif'] as String?,
      );

  final String id;
  final String etablissementId;
  final String employeId;
  final TypeConge type;
  final DateTime dateDebut;
  final DateTime dateFin;
  final int nbJours;
  final StatutConge statut;
  final String? motif;
  final String? validePar;
  final DateTime? dateValidation;

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
