/// Projection cliente de `public.retards` (M7).
class Retard {
  const Retard({
    required this.id,
    required this.etablissementId,
    required this.ficheEleveId,
    required this.anneeScolaireId,
    required this.dateRetard,
    required this.minutesRetard,
    required this.saisiPar,
    this.justifie = false,
    this.motif,
    this.saisiHorsLigne = false,
    this.deviceId,
    this.clientTs,
    this.nomEleve,
  });

  factory Retard.depuisJson(Map<String, dynamic> json) {
    final fiche = json['fiches_eleves'] as Map<String, dynamic>?;
    return Retard(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      ficheEleveId: json['fiche_eleve_id'] as String,
      anneeScolaireId: json['annee_scolaire_id'] as String,
      dateRetard: DateTime.parse(json['date_retard'] as String),
      minutesRetard: json['minutes_retard'] as int,
      saisiPar: json['saisi_par'] as String,
      justifie: json['justifie'] as bool? ?? false,
      motif: json['motif'] as String?,
      saisiHorsLigne: json['saisi_hors_ligne'] as bool? ?? false,
      deviceId: json['device_id'] as String?,
      clientTs: json['client_ts'] == null ? null : DateTime.parse(json['client_ts'] as String),
      nomEleve: fiche == null ? null : '${fiche['prenom']} ${fiche['nom']}',
    );
  }

  Map<String, dynamic> versJsonCache() => {
        'id': id,
        'etablissement_id': etablissementId,
        'fiche_eleve_id': ficheEleveId,
        'annee_scolaire_id': anneeScolaireId,
        'date_retard': _dateIso(dateRetard),
        'minutes_retard': minutesRetard,
        'saisi_par': saisiPar,
        'justifie': justifie,
        'motif': motif,
        'saisi_hors_ligne': saisiHorsLigne,
        'device_id': deviceId,
        'client_ts': clientTs?.toIso8601String(),
        'nom_eleve': nomEleve,
      };

  factory Retard.depuisJsonCache(Map<String, dynamic> json) => Retard(
        id: json['id'] as String,
        etablissementId: json['etablissement_id'] as String,
        ficheEleveId: json['fiche_eleve_id'] as String,
        anneeScolaireId: json['annee_scolaire_id'] as String,
        dateRetard: DateTime.parse(json['date_retard'] as String),
        minutesRetard: json['minutes_retard'] as int,
        saisiPar: json['saisi_par'] as String,
        justifie: json['justifie'] as bool? ?? false,
        motif: json['motif'] as String?,
        saisiHorsLigne: json['saisi_hors_ligne'] as bool? ?? false,
        deviceId: json['device_id'] as String?,
        clientTs: json['client_ts'] == null ? null : DateTime.parse(json['client_ts'] as String),
        nomEleve: json['nom_eleve'] as String?,
      );

  /// Colonnes réelles de `public.retards` — pour l'écriture Supabase.
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'fiche_eleve_id': ficheEleveId,
        'annee_scolaire_id': anneeScolaireId,
        'date_retard': _dateIso(dateRetard),
        'minutes_retard': minutesRetard,
        'saisi_par': saisiPar,
        'justifie': justifie,
        'motif': motif,
        'saisi_hors_ligne': saisiHorsLigne,
        'device_id': deviceId,
        'client_ts': clientTs?.toIso8601String(),
      };

  final String id;
  final String etablissementId;
  final String ficheEleveId;
  final String anneeScolaireId;
  final DateTime dateRetard;
  final int minutesRetard;
  final String saisiPar;
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
