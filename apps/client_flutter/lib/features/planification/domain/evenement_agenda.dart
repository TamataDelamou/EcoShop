import 'enums_planification.dart';

/// Projection cliente de `public.evenements_agenda` (M11) — événement
/// d'établissement (examen, réunion, conseil de classe, sortie…),
/// complémentaire de `evenements_scolaires` (M7, qui porte l'impact sur les
/// présences attendues). Porte le même facteur LWW que `emplois_du_temps`.
class EvenementAgenda {
  const EvenementAgenda({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    this.classeId,
    required this.titre,
    this.type = TypeEvenementAgenda.reunion,
    required this.dateDebut,
    required this.dateFin,
    this.heureDebut,
    this.heureFin,
    this.lieu,
    this.participants = const {},
    this.rappel = false,
    this.modifieLe,
    this.deviceId,
  });

  factory EvenementAgenda.depuisJson(Map<String, dynamic> json) => EvenementAgenda(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        anneeScolaireId: json['annee_scolaire_id'] as String,
        classeId: json['classe_id'] as String?,
        titre: json['titre'] as String,
        type: TypeEvenementAgenda.depuisCode(json['type'] as String?),
        dateDebut: DateTime.parse(json['date_debut'] as String),
        dateFin: DateTime.parse(json['date_fin'] as String),
        heureDebut: _tronquerHeure(json['heure_debut'] as String?),
        heureFin: _tronquerHeure(json['heure_fin'] as String?),
        lieu: json['lieu'] as String?,
        participants: (json['participants'] as Map<String, dynamic>?) ?? const {},
        rappel: json['rappel'] as bool? ?? false,
        modifieLe: json['modifie_le'] == null ? null : DateTime.parse(json['modifie_le'] as String),
        deviceId: json['device_id'] as String?,
      );

  factory EvenementAgenda.depuisJsonCache(Map<String, dynamic> json) => EvenementAgenda(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        anneeScolaireId: json['annee_scolaire_id'] as String,
        classeId: json['classe_id'] as String?,
        titre: json['titre'] as String,
        type: TypeEvenementAgenda.depuisCode(json['type'] as String?),
        dateDebut: DateTime.parse(json['date_debut'] as String),
        dateFin: DateTime.parse(json['date_fin'] as String),
        heureDebut: json['heure_debut'] as String?,
        heureFin: json['heure_fin'] as String?,
        lieu: json['lieu'] as String?,
        participants: (json['participants'] as Map<String, dynamic>?) ?? const {},
        rappel: json['rappel'] as bool? ?? false,
        modifieLe: json['modifie_le'] == null ? null : DateTime.parse(json['modifie_le'] as String),
        deviceId: json['device_id'] as String?,
      );

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'classe_id': classeId,
        'titre': titre,
        'type': type.code,
        'date_debut': _dateIso(dateDebut),
        'date_fin': _dateIso(dateFin),
        'heure_debut': heureDebut,
        'heure_fin': heureFin,
        'lieu': lieu,
        'participants': participants,
        'rappel': rappel,
        'modifie_le': modifieLe?.toIso8601String(),
        'device_id': deviceId,
      };

  /// Colonnes réelles de `public.evenements_agenda` — pour l'upsert. Table
  /// sans contrainte unique métier : l'upsert cible `id` (généré côté
  /// client), seul moyen d'éviter les doublons de retry hors-ligne.
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'classe_id': classeId,
        'titre': titre,
        'type': type.code,
        'date_debut': _dateIso(dateDebut),
        'date_fin': _dateIso(dateFin),
        'heure_debut': heureDebut,
        'heure_fin': heureFin,
        'lieu': lieu,
        'participants': participants,
        'rappel': rappel,
        'modifie_le': (modifieLe ?? DateTime.now()).toIso8601String(),
        'device_id': deviceId,
      };

  factory EvenementAgenda.depuisJsonEcriture(Map<String, dynamic> json) => EvenementAgenda(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        anneeScolaireId: json['annee_scolaire_id'] as String,
        classeId: json['classe_id'] as String?,
        titre: json['titre'] as String,
        type: TypeEvenementAgenda.depuisCode(json['type'] as String?),
        dateDebut: DateTime.parse(json['date_debut'] as String),
        dateFin: DateTime.parse(json['date_fin'] as String),
        heureDebut: json['heure_debut'] as String?,
        heureFin: json['heure_fin'] as String?,
        lieu: json['lieu'] as String?,
        participants: (json['participants'] as Map<String, dynamic>?) ?? const {},
        rappel: json['rappel'] as bool? ?? false,
        modifieLe: json['modifie_le'] == null ? null : DateTime.parse(json['modifie_le'] as String),
        deviceId: json['device_id'] as String?,
      );

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String? classeId;
  final String titre;
  final TypeEvenementAgenda type;
  final DateTime dateDebut;
  final DateTime dateFin;

  /// Format `HH:mm`, nullable (événement d'une journée entière si absent).
  final String? heureDebut;
  final String? heureFin;
  final String? lieu;
  final Map<String, dynamic> participants;
  final bool rappel;
  final DateTime? modifieLe;
  final String? deviceId;

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String? _tronquerHeure(String? heure) =>
      heure == null ? null : (heure.length >= 5 ? heure.substring(0, 5) : heure);
}
