import 'evaluation.dart';

/// Projection cliente de `public.notes` (M6) — score d'un élève à une
/// évaluation. `absent` et [valeur] sont mutuellement exclusifs (contrat M06).
///
/// [deviceId] et [clientTs] portent le facteur Last-Write-Wins d'une saisie
/// hors-ligne ; [saisiHorsLigne] trace l'origine pour l'audit. La moyenne
/// n'est **jamais** dérivée de ces lignes côté client — toujours du RPC
/// serveur `calculer_moyenne_eleve` (contrat M06 §5).
class Note {
  const Note({
    required this.id,
    required this.etablissementId,
    required this.evaluationId,
    required this.ficheEleveId,
    required this.saisiPar,
    this.valeur,
    this.absent = false,
    this.commentaire,
    this.saisiHorsLigne = false,
    this.deviceId,
    this.clientTs,
    this.nomEleve,
    this.evaluation,
  });

  factory Note.depuisJson(Map<String, dynamic> json) {
    final fiche = json['fiches_eleves'] as Map<String, dynamic>?;
    final evaluationJson = json['evaluations'] as Map<String, dynamic>?;
    return Note(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      evaluationId: json['evaluation_id'] as String,
      ficheEleveId: json['fiche_eleve_id'] as String,
      saisiPar: json['saisi_par'] as String,
      valeur: (json['valeur'] as num?)?.toDouble(),
      absent: json['absent'] as bool? ?? false,
      commentaire: json['commentaire'] as String?,
      saisiHorsLigne: json['saisi_hors_ligne'] as bool? ?? false,
      deviceId: json['device_id'] as String?,
      clientTs: json['client_ts'] == null ? null : DateTime.parse(json['client_ts'] as String),
      nomEleve: fiche == null ? null : '${fiche['prenom']} ${fiche['nom']}',
      evaluation: evaluationJson == null ? null : Evaluation.depuisJson(evaluationJson),
    );
  }

  /// Sérialisation complète — utilisée à la fois pour le cache local et pour
  /// le payload de la file `sync_queue` (upsert Supabase à la reconnexion).
  Map<String, dynamic> versJson() => {
        'id': id,
        'etablissement_id': etablissementId,
        'evaluation_id': evaluationId,
        'fiche_eleve_id': ficheEleveId,
        'saisi_par': saisiPar,
        'valeur': valeur,
        'absent': absent,
        'commentaire': commentaire,
        'saisi_hors_ligne': saisiHorsLigne,
        'device_id': deviceId,
        'client_ts': clientTs?.toIso8601String(),
        'nom_eleve': nomEleve,
        'evaluation': evaluation?.versJsonCache(),
      };

  /// Parse le payload d'écriture (`versJsonEcriture`) tel que stocké dans
  /// `sync_queue` — sans les champs d'affichage, à compléter via [avecAffichage].
  factory Note.depuisJsonEcriture(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      evaluationId: json['evaluation_id'] as String,
      ficheEleveId: json['fiche_eleve_id'] as String,
      saisiPar: json['saisi_par'] as String,
      valeur: (json['valeur'] as num?)?.toDouble(),
      absent: json['absent'] as bool? ?? false,
      commentaire: json['commentaire'] as String?,
      saisiHorsLigne: json['saisi_hors_ligne'] as bool? ?? false,
      deviceId: json['device_id'] as String?,
      clientTs: json['client_ts'] == null ? null : DateTime.parse(json['client_ts'] as String),
    );
  }

  /// Complète les champs d'affichage manquants à partir d'une autre note
  /// représentant le même élève (ex. la dernière lecture serveur connue).
  Note avecAffichage(Note? source) {
    return Note(
      id: id,
      etablissementId: etablissementId,
      evaluationId: evaluationId,
      ficheEleveId: ficheEleveId,
      saisiPar: saisiPar,
      valeur: valeur,
      absent: absent,
      commentaire: commentaire,
      saisiHorsLigne: saisiHorsLigne,
      deviceId: deviceId,
      clientTs: clientTs,
      nomEleve: nomEleve ?? source?.nomEleve,
      evaluation: evaluation ?? source?.evaluation,
    );
  }

  factory Note.depuisJsonCache(Map<String, dynamic> json) {
    final evaluationJson = json['evaluation'] as Map<String, dynamic>?;
    return Note(
      id: json['id'] as String,
      etablissementId: json['etablissement_id'] as String,
      evaluationId: json['evaluation_id'] as String,
      ficheEleveId: json['fiche_eleve_id'] as String,
      saisiPar: json['saisi_par'] as String,
      valeur: (json['valeur'] as num?)?.toDouble(),
      absent: json['absent'] as bool? ?? false,
      commentaire: json['commentaire'] as String?,
      saisiHorsLigne: json['saisi_hors_ligne'] as bool? ?? false,
      deviceId: json['device_id'] as String?,
      clientTs: json['client_ts'] == null ? null : DateTime.parse(json['client_ts'] as String),
      nomEleve: json['nom_eleve'] as String?,
      evaluation: evaluationJson == null ? null : Evaluation.depuisJsonCache(evaluationJson),
    );
  }

  /// Colonnes réelles de `public.notes` — utilisée pour l'upsert Supabase (à
  /// la différence de [versJson], qui inclut des champs d'affichage dérivés).
  Map<String, dynamic> versJsonEcriture() => {
        'id': id,
        'etablissement_id': etablissementId,
        'evaluation_id': evaluationId,
        'fiche_eleve_id': ficheEleveId,
        'saisi_par': saisiPar,
        'valeur': valeur,
        'absent': absent,
        'commentaire': commentaire,
        'saisi_hors_ligne': saisiHorsLigne,
        'device_id': deviceId,
        'client_ts': clientTs?.toIso8601String(),
      };

  Note copierAvec({double? valeur, bool? absent, String? commentaire, bool videValeur = false}) {
    return Note(
      id: id,
      etablissementId: etablissementId,
      evaluationId: evaluationId,
      ficheEleveId: ficheEleveId,
      saisiPar: saisiPar,
      valeur: videValeur ? null : (valeur ?? this.valeur),
      absent: absent ?? this.absent,
      commentaire: commentaire ?? this.commentaire,
      saisiHorsLigne: saisiHorsLigne,
      deviceId: deviceId,
      clientTs: clientTs,
      nomEleve: nomEleve,
      evaluation: evaluation,
    );
  }

  final String id;
  final String etablissementId;
  final String evaluationId;
  final String ficheEleveId;
  final String saisiPar;
  final double? valeur;
  final bool absent;
  final String? commentaire;
  final bool saisiHorsLigne;
  final String? deviceId;
  final DateTime? clientTs;

  /// Peuplé via l'embed `fiches_eleves(prenom, nom)` — affichage uniquement.
  final String? nomEleve;

  /// Peuplée via l'embed `evaluations(*, programmes_matieres(nom))` — lecture
  /// côté élève/parent (regroupement par matière à l'affichage uniquement,
  /// aucun calcul de moyenne ici).
  final Evaluation? evaluation;
}
