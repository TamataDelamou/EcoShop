/// Cahier de texte, travail à faire et devoirs numériques (REG-40).
library;

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v');

String jourIso(DateTime d) {
  String deux(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${deux(d.month)}-${deux(d.day)}';
}

DateTime jour(DateTime d) => DateTime(d.year, d.month, d.day);

/// Type de travail (Pronote, Google Classroom) ; « devoir numérique » :
/// questions de la banque, corrigées par le serveur.
enum TypeTravail {
  lecon('lecon', 'Leçon à apprendre'),
  exercices('exercices', 'Exercices'),
  redaction('redaction', 'Rédaction'),
  expose('expose', 'Exposé'),
  revision('revision', 'Révision'),
  devoirNumerique('devoir_numerique', 'Devoir numérique'),
  evaluation('evaluation', 'Évaluation annoncée');

  const TypeTravail(this.code, this.libelle);

  final String code;
  final String libelle;

  static TypeTravail depuisCode(String? code) =>
      TypeTravail.values.firstWhere((t) => t.code == code, orElse: () => TypeTravail.exercices);
}

/// Pièce jointe (bucket privé `cahier-texte`).
class PieceJointe {
  const PieceJointe({required this.chemin, required this.nom});

  factory PieceJointe.depuisJson(Map<String, dynamic> j) =>
      PieceJointe(chemin: '${j['chemin']}', nom: '${j['nom'] ?? 'Fichier'}');

  static List<PieceJointe> liste(Object? j) => [
        for (final x in (j as List?) ?? const []) PieceJointe.depuisJson((x as Map).cast<String, dynamic>()),
      ];

  Map<String, dynamic> versJson() => {'chemin': chemin, 'nom': nom};

  final String chemin;
  final String nom;
}

/// Une séance du cahier de texte.
class Seance {
  const Seance({
    required this.id,
    required this.etablissementId,
    required this.anneeId,
    required this.classeId,
    required this.date,
    required this.titre,
    this.contenu,
    this.matiereId,
    this.matiere,
    this.chapitreId,
    this.chapitre,
    this.enseignant,
    this.piecesJointes = const [],
    this.enAttente = false,
  });

  factory Seance.depuisJson(Map<String, dynamic> j) => Seance(
        id: '${j['id']}',
        etablissementId: '${j['etablissement_id'] ?? ''}',
        anneeId: '${j['annee_scolaire_id'] ?? ''}',
        classeId: '${j['classe_id'] ?? ''}',
        date: _date(j['date_seance']) ?? DateTime.now(),
        titre: '${j['titre'] ?? ''}',
        contenu: j['contenu'] as String?,
        matiereId: (j['programme_matiere_id'] ?? j['matiere_id']) as String?,
        matiere: (j['matiere'] ?? (j['programmes_matieres'] as Map?)?['nom']) as String?,
        chapitreId: j['chapitre_id'] as String?,
        chapitre: (j['chapitre'] ?? (j['chapitres_matiere'] as Map?)?['titre']) as String?,
        enseignant: j['enseignant'] as String?,
        piecesJointes: PieceJointe.liste(j['pieces_jointes']),
        enAttente: j['_en_attente'] == true,
      );

  /// Colonnes de `cahier_texte` (écriture).
  Map<String, dynamic> versLigne() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeId,
        'classe_id': classeId,
        'programme_matiere_id': matiereId,
        'chapitre_id': chapitreId,
        'date_seance': jourIso(date),
        'titre': titre.trim(),
        'contenu': (contenu ?? '').trim().isEmpty ? null : contenu!.trim(),
        'pieces_jointes': [for (final p in piecesJointes) p.versJson()],
      };

  final String id;
  final String etablissementId;
  final String anneeId;
  final String classeId;
  final DateTime date;
  final String titre;
  final String? contenu;
  final String? matiereId;
  final String? matiere;
  final String? chapitreId;
  final String? chapitre;
  final String? enseignant;
  final List<PieceJointe> piecesJointes;

  /// Écrite sans réseau, pas encore envoyée.
  final bool enAttente;
}

/// Travail à faire, vu par l'enseignant (ligne de `travaux`).
class Travail {
  const Travail({
    required this.id,
    required this.etablissementId,
    required this.anneeId,
    required this.classeId,
    required this.type,
    required this.titre,
    required this.pourLe,
    this.donneLe,
    this.consigne,
    this.matiereId,
    this.matiere,
    this.chapitreId,
    this.seanceId,
    this.tempsEstimeMin = 20,
    this.piecesJointes = const [],
    this.questions = const [],
    this.dureeMin,
    this.correctionApresEcheance = false,
    this.enAttente = false,
  });

  factory Travail.depuisJson(Map<String, dynamic> j) => Travail(
        id: '${j['id']}',
        etablissementId: '${j['etablissement_id'] ?? ''}',
        anneeId: '${j['annee_scolaire_id'] ?? ''}',
        classeId: '${j['classe_id'] ?? ''}',
        type: TypeTravail.depuisCode(j['type'] as String?),
        titre: '${j['titre'] ?? ''}',
        pourLe: _date(j['pour_le']) ?? DateTime.now(),
        donneLe: _date(j['donne_le']),
        consigne: j['consigne'] as String?,
        matiereId: j['programme_matiere_id'] as String?,
        matiere: (j['matiere'] ?? (j['programmes_matieres'] as Map?)?['nom']) as String?,
        chapitreId: j['chapitre_id'] as String?,
        seanceId: j['seance_id'] as String?,
        tempsEstimeMin: (j['temps_estime_min'] as num?)?.toInt() ?? 20,
        piecesJointes: PieceJointe.liste(j['pieces_jointes']),
        questions: [for (final q in (j['questions'] as List?) ?? const []) '$q'],
        dureeMin: (j['duree_min'] as num?)?.toInt(),
        correctionApresEcheance: j['correction_apres_echeance'] == true,
        enAttente: j['_en_attente'] == true,
      );

  Map<String, dynamic> versLigne() => {
        'id': id,
        'etablissement_id': etablissementId,
        'annee_scolaire_id': anneeId,
        'classe_id': classeId,
        'programme_matiere_id': matiereId,
        'chapitre_id': chapitreId,
        'seance_id': seanceId,
        'type': type.code,
        'titre': titre.trim(),
        'consigne': (consigne ?? '').trim().isEmpty ? null : consigne!.trim(),
        'donne_le': jourIso(donneLe ?? DateTime.now()),
        'pour_le': jourIso(pourLe),
        'temps_estime_min': tempsEstimeMin,
        'pieces_jointes': [for (final p in piecesJointes) p.versJson()],
        'questions': type == TypeTravail.devoirNumerique ? questions : <String>[],
        'duree_min': type == TypeTravail.devoirNumerique ? dureeMin : null,
        'correction_apres_echeance': correctionApresEcheance,
      };

  final String id;
  final String etablissementId;
  final String anneeId;
  final String classeId;
  final TypeTravail type;
  final String titre;
  final DateTime pourLe;
  final DateTime? donneLe;
  final String? consigne;
  final String? matiereId;
  final String? matiere;
  final String? chapitreId;
  final String? seanceId;
  final int tempsEstimeMin;
  final List<PieceJointe> piecesJointes;
  final List<String> questions;
  final int? dureeMin;
  final bool correctionApresEcheance;
  final bool enAttente;
}

/// Travail vu par l'élève ou le parent, avec son suivi.
class TravailEleve {
  const TravailEleve({
    required this.id,
    required this.type,
    required this.titre,
    required this.pourLe,
    this.consigne,
    this.matiere,
    this.chapitre,
    this.enseignant,
    this.tempsEstimeMin = 20,
    this.piecesJointes = const [],
    this.nbQuestions = 0,
    this.dureeMin,
    this.faitLe,
    this.remisLe,
    this.score,
    this.enRetard = false,
  });

  factory TravailEleve.depuisJson(Map<String, dynamic> j) => TravailEleve(
        id: '${j['id']}',
        type: TypeTravail.depuisCode(j['type'] as String?),
        titre: '${j['titre'] ?? ''}',
        pourLe: _date(j['pour_le']) ?? DateTime.now(),
        consigne: j['consigne'] as String?,
        matiere: j['matiere'] as String?,
        chapitre: j['chapitre'] as String?,
        enseignant: j['enseignant'] as String?,
        tempsEstimeMin: (j['temps_estime_min'] as num?)?.toInt() ?? 20,
        piecesJointes: PieceJointe.liste(j['pieces_jointes']),
        nbQuestions: (j['nb_questions'] as num?)?.toInt() ?? 0,
        dureeMin: (j['duree_min'] as num?)?.toInt(),
        faitLe: _date(j['fait_le']),
        remisLe: _date(j['remis_le']),
        score: (j['score'] as num?)?.toDouble(),
        enRetard: j['en_retard'] == true,
      );

  static List<TravailEleve> liste(Object? j) => [
        for (final x in (j as List?) ?? const []) TravailEleve.depuisJson((x as Map).cast<String, dynamic>()),
      ];

  TravailEleve avecFait(DateTime? quand) => TravailEleve(
        id: id,
        type: type,
        titre: titre,
        pourLe: pourLe,
        consigne: consigne,
        matiere: matiere,
        chapitre: chapitre,
        enseignant: enseignant,
        tempsEstimeMin: tempsEstimeMin,
        piecesJointes: piecesJointes,
        nbQuestions: nbQuestions,
        dureeMin: dureeMin,
        faitLe: quand,
        remisLe: remisLe,
        score: score,
        enRetard: quand != null && jour(quand).isAfter(jour(pourLe)),
      );

  final String id;
  final TypeTravail type;
  final String titre;
  final DateTime pourLe;
  final String? consigne;
  final String? matiere;
  final String? chapitre;
  final String? enseignant;
  final int tempsEstimeMin;
  final List<PieceJointe> piecesJointes;
  final int nbQuestions;
  final int? dureeMin;
  final DateTime? faitLe;
  final DateTime? remisLe;
  final double? score;
  final bool enRetard;

  bool get estDevoir => type == TypeTravail.devoirNumerique;
  bool get termine => faitLe != null || remisLe != null;

  /// En retard : échéance passée et rien de fait.
  bool enRetardLe(DateTime maintenant) => !termine && jour(maintenant).isAfter(jour(pourLe));
}

/// Suivi d'un élève pour un travail (vue de l'enseignant).
class SuiviEleve {
  const SuiviEleve({
    required this.ficheId,
    required this.nom,
    this.faitLe,
    this.commenceLe,
    this.remisLe,
    this.score,
    this.nbQuestions,
    this.enRetard = false,
  });

  factory SuiviEleve.depuisJson(Map<String, dynamic> j) => SuiviEleve(
        ficheId: '${j['fiche_id']}',
        nom: '${j['nom'] ?? ''}',
        faitLe: _date(j['fait_le']),
        commenceLe: _date(j['commence_le']),
        remisLe: _date(j['remis_le']),
        score: (j['score'] as num?)?.toDouble(),
        nbQuestions: (j['nb_questions'] as num?)?.toInt(),
        enRetard: j['en_retard'] == true,
      );

  final String ficheId;
  final String nom;
  final DateTime? faitLe;
  final DateTime? commenceLe;
  final DateTime? remisLe;
  final double? score;
  final int? nbQuestions;
  final bool enRetard;

  bool get termine => faitLe != null || remisLe != null;

  /// Note sur 20 d'un devoir numérique.
  double? get surVingt => score == null || (nbQuestions ?? 0) == 0 ? null : score! * 20 / nbQuestions!;
}

/// Question d'un devoir, du moins au mieux réussie (Kolibri, Quizizz).
class QuestionSuivie {
  const QuestionSuivie({
    required this.questionId,
    required this.ordre,
    required this.enonce,
    this.competence,
    this.reponses = 0,
    this.reussite,
    this.aAider = const [],
  });

  factory QuestionSuivie.depuisJson(Map<String, dynamic> j) => QuestionSuivie(
        questionId: '${j['question_id']}',
        ordre: (j['ordre'] as num?)?.toInt() ?? 0,
        enonce: '${j['enonce'] ?? ''}',
        competence: j['competence'] as String?,
        reponses: (j['reponses'] as num?)?.toInt() ?? 0,
        reussite: (j['reussite'] as num?)?.toDouble(),
        aAider: [for (final n in (j['a_aider'] as List?) ?? const []) '$n'],
      );

  final String questionId;
  final int ordre;
  final String enonce;
  final String? competence;
  final int reponses;

  /// Part moyenne de réussite (0 à 1) ; nulle tant que personne n'a remis.
  final double? reussite;
  final List<String> aAider;
}

class SuiviTravail {
  const SuiviTravail({this.eleves = const [], this.questions = const []});

  factory SuiviTravail.depuisJson(Map<String, dynamic> j) => SuiviTravail(
        eleves: [for (final e in (j['eleves'] as List?) ?? const []) SuiviEleve.depuisJson((e as Map).cast<String, dynamic>())],
        questions: [
          for (final q in (j['questions'] as List?) ?? const []) QuestionSuivie.depuisJson((q as Map).cast<String, dynamic>()),
        ],
      );

  final List<SuiviEleve> eleves;
  final List<QuestionSuivie> questions;

  int get termines => eleves.where((e) => e.termine).length;
  int get enRetard => eleves.where((e) => e.enRetard).length;

  /// Moyenne sur 20 des devoirs remis.
  double? get moyenne {
    final notes = [for (final e in eleves) if (e.surVingt != null) e.surVingt!];
    if (notes.isEmpty) return null;
    return notes.reduce((a, b) => a + b) / notes.length;
  }
}

/// Question proposée pour composer un devoir.
class QuestionProposeeDevoir {
  const QuestionProposeeDevoir({
    required this.id,
    required this.enonce,
    required this.type,
    required this.difficulte,
    this.chapitreId,
    this.chapitre,
    this.competence,
    this.tempsS = 60,
  });

  factory QuestionProposeeDevoir.depuisJson(Map<String, dynamic> j) => QuestionProposeeDevoir(
        id: '${j['id']}',
        enonce: '${j['enonce'] ?? ''}',
        type: '${j['type'] ?? ''}',
        difficulte: '${j['difficulte'] ?? ''}',
        chapitreId: j['chapitre_id'] as String?,
        chapitre: j['chapitre'] as String?,
        competence: j['competence'] as String?,
        tempsS: (j['temps_s'] as num?)?.toInt() ?? 60,
      );

  final String id;
  final String enonce;
  final String type;
  final String difficulte;
  final String? chapitreId;
  final String? chapitre;
  final String? competence;
  final int tempsS;
}

/// Ligne de l'avancement du cahier (direction).
class AvancementCahier {
  const AvancementCahier({
    required this.classe,
    required this.matiere,
    required this.prevues,
    required this.renseignees,
    this.enseignant,
    this.derniere,
    this.travaux = 0,
  });

  factory AvancementCahier.depuisJson(Map<String, dynamic> j) => AvancementCahier(
        classe: '${j['classe'] ?? ''}',
        matiere: '${j['matiere'] ?? ''}',
        enseignant: j['enseignant'] as String?,
        prevues: (j['prevues'] as num?)?.toInt() ?? 0,
        renseignees: (j['renseignees'] as num?)?.toInt() ?? 0,
        derniere: _date(j['derniere']),
        travaux: (j['travaux'] as num?)?.toInt() ?? 0,
      );

  final String classe;
  final String matiere;
  final String? enseignant;
  final int prevues;
  final int renseignees;
  final DateTime? derniere;
  final int travaux;

  double get taux => prevues == 0 ? 1 : (renseignees / prevues).clamp(0, 1).toDouble();
}

/// Charge de travail par jour (minutes estimées), pour alerter l'enseignant
/// au-delà de [seuilChargeJour] (recherche : au-delà, le gain diminue).
const seuilChargeJour = 90;

Map<DateTime, int> chargeParJour(Iterable<({DateTime pourLe, int minutes})> travaux) {
  final m = <DateTime, int>{};
  for (final t in travaux) {
    final j = jour(t.pourLe);
    m[j] = (m[j] ?? 0) + t.minutes;
  }
  return m;
}

/// Prochain cours d'une matière d'après les jours de l'emploi du temps
/// (1 = lundi … 7 = dimanche), après [depuis] ; à défaut, dans 2 jours
/// (hors dimanche). Pronote : l'échéance par défaut est le prochain cours.
DateTime prochainCours(Iterable<int> joursDuCours, DateTime depuis) {
  final jours = joursDuCours.toSet();
  final base = jour(depuis);
  if (jours.isNotEmpty) {
    for (var i = 1; i <= 7; i++) {
      final d = base.add(Duration(days: i));
      if (jours.contains(d.weekday)) return d;
    }
  }
  var d = base.add(const Duration(days: 2));
  if (d.weekday == DateTime.sunday) d = d.add(const Duration(days: 1));
  return d;
}
