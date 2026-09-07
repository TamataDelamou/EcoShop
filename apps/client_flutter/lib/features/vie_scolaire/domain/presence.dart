import 'enums_vie_scolaire.dart';

/// Projection cliente de `public.presences` (M7) — pointage quotidien, demi-
/// journée ou par cours.
///
/// [deviceId]/[clientTs] portent le facteur Last-Write-Wins d'un pointage
/// hors-ligne, sur le même modèle que `notes` (M6) — voir contrat M07 §5.
class Presence {
  const Presence({
    required this.id,
    required this.etablissementId,
    required this.anneeScolaireId,
    required this.classeId,
    required this.ficheEleveId,
    required this.datePresence,
    required this.saisiPar,
    this.typeSeance = TypeSeance.demiJournee,
    this.programmeMatiereId,
    this.statut = StatutPresence.present,
    this.justifie = false,
    this.motif,
    this.saisiHorsLigne = false,
    this.deviceId,
    this.clientTs,
    this.nomEleve,
  });

  factory Presence.depuisJson(Map<String, dynamic> json) {
    final fiche = json['fiches_eleves'] as Map<String, dynamic>?;
    return Presence(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      classeId: json['classe_id'] as String,
      ficheEleveId: json['fiche_eleve_id'] as String,
      datePresence: DateTime.parse(json['date_presence'] as String),
      saisiPar: json['saisi_par'] as String,
      typeSeance: TypeSeance.depuisCode(json['type_seance'] as String?),
      programmeMatiereId: json['programme_matiere_id'] as String?,
      statut: StatutPresence.depuisCode(json['statut'] as String?),
      justifie: json['justifie'] as bool? ?? false,
      motif: json['motif'] as String?,
      saisiHorsLigne: json['saisi_hors_ligne'] as bool? ?? false,
      deviceId: json['device_id'] as String?,
      clientTs: json['client_ts'] == null ? null : DateTime.parse(json['client_ts'] as String),
      nomEleve: fiche == null ? null : '${fiche['prenom']} ${fiche['nom']}',
    );
  }

  /// Sérialisation complète (cache local + payload `sync_queue`).
  Map<String, dynamic> versJson() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'classe_id': classeId,
        'fiche_eleve_id': ficheEleveId,
        'date_presence': _dateIso(datePresence),
        'saisi_par': saisiPar,
        'type_seance': typeSeance.code,
        'programme_matiere_id': programmeMatiereId,
        'statut': statut.code,
        'justifie': justifie,
        'motif': motif,
        'saisi_hors_ligne': saisiHorsLigne,
        'device_id': deviceId,
        'client_ts': clientTs?.toIso8601String(),
        'nom_eleve': nomEleve,
      };

  factory Presence.depuisJsonCache(Map<String, dynamic> json) {
    return Presence(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      classeId: json['classe_id'] as String,
      ficheEleveId: json['fiche_eleve_id'] as String,
      datePresence: DateTime.parse(json['date_presence'] as String),
      saisiPar: json['saisi_par'] as String,
      typeSeance: TypeSeance.depuisCode(json['type_seance'] as String?),
      programmeMatiereId: json['programme_matiere_id'] as String?,
      statut: StatutPresence.depuisCode(json['statut'] as String?),
      justifie: json['justifie'] as bool? ?? false,
      motif: json['motif'] as String?,
      saisiHorsLigne: json['saisi_hors_ligne'] as bool? ?? false,
      deviceId: json['device_id'] as String?,
      clientTs: json['client_ts'] == null ? null : DateTime.parse(json['client_ts'] as String),
      nomEleve: json['nom_eleve'] as String?,
    );
  }

  /// Colonnes réelles de `public.presences` — pour l'upsert Supabase.
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeScolaireId,
        'classe_id': classeId,
        'fiche_eleve_id': ficheEleveId,
        'date_presence': _dateIso(datePresence),
        'saisi_par': saisiPar,
        'type_seance': typeSeance.code,
        'programme_matiere_id': programmeMatiereId,
        'statut': statut.code,
        'justifie': justifie,
        'motif': motif,
        'saisi_hors_ligne': saisiHorsLigne,
        'device_id': deviceId,
        'client_ts': clientTs?.toIso8601String(),
      };

  factory Presence.depuisJsonEcriture(Map<String, dynamic> json) {
    return Presence(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      classeId: json['classe_id'] as String,
      ficheEleveId: json['fiche_eleve_id'] as String,
      datePresence: DateTime.parse(json['date_presence'] as String),
      saisiPar: json['saisi_par'] as String,
      typeSeance: TypeSeance.depuisCode(json['type_seance'] as String?),
      programmeMatiereId: json['programme_matiere_id'] as String?,
      statut: StatutPresence.depuisCode(json['statut'] as String?),
      justifie: json['justifie'] as bool? ?? false,
      motif: json['motif'] as String?,
      saisiHorsLigne: json['saisi_hors_ligne'] as bool? ?? false,
      deviceId: json['device_id'] as String?,
      clientTs: json['client_ts'] == null ? null : DateTime.parse(json['client_ts'] as String),
    );
  }

  /// Complète les champs d'affichage manquants depuis une autre lecture.
  Presence avecAffichage(Presence? source) {
    return Presence(
      id: id,
      etablissementId: etablissementId,
      anneeScolaireId: anneeScolaireId,
      classeId: classeId,
      ficheEleveId: ficheEleveId,
      datePresence: datePresence,
      saisiPar: saisiPar,
      typeSeance: typeSeance,
      programmeMatiereId: programmeMatiereId,
      statut: statut,
      justifie: justifie,
      motif: motif,
      saisiHorsLigne: saisiHorsLigne,
      deviceId: deviceId,
      clientTs: clientTs,
      nomEleve: nomEleve ?? source?.nomEleve,
    );
  }

  final String id;
  final String etablissementId;
  final String anneeScolaireId;
  final String classeId;
  final String ficheEleveId;
  final DateTime datePresence;
  final String saisiPar;
  final TypeSeance typeSeance;
  final String? programmeMatiereId;
  final StatutPresence statut;
  final bool justifie;
  final String? motif;
  final bool saisiHorsLigne;
  final String? deviceId;
  final DateTime? clientTs;

  /// Peuplé via l'embed `fiches_eleves(prenom, nom)` — affichage uniquement.
  final String? nomEleve;

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
