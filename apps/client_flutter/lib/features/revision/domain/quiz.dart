/// Quiz et entraînement (REG-37 lot R2, cahier 11.1). Tout ce fichier
/// fonctionne sans réseau : choix des questions, déroulé, correction,
/// résultat et messages.
library;

import 'dart:math';

import 'question.dart';

enum ModeQuiz {
  rapide('rapide', 'Quiz rapide', 5),
  standard('standard', 'Quiz standard', 10),
  intensif('intensif', 'Quiz intensif', 20),
  chapitre('chapitre', 'Par chapitre', 10),
  matiere('matiere', 'Par matière', 10),
  melange('melange', 'Révision mêlée', 10),
  personnalise('personnalise', 'Personnalisé', 10),
  erreurs('erreurs', 'Refaire mes erreurs', 10);

  const ModeQuiz(this.code, this.libelle, this.nombreParDefaut);

  final String code;
  final String libelle;
  final int nombreParDefaut;
}

/// Question telle que l'élève la reçoit (version publiée du paquet).
class QuestionQuiz {
  const QuestionQuiz({required this.id, required this.matiereId, required this.contenu});

  final String id;
  final String matiereId;
  final ContenuQuestion contenu;

  int get version => contenu.version;

  factory QuestionQuiz.depuisJson(Map<String, dynamic> j) => QuestionQuiz(
        id: j['id'] as String,
        matiereId: j['matiere_id'] as String,
        contenu: ContenuQuestion.depuisJson(j),
      );
}

class MatiereRevision {
  const MatiereRevision({required this.id, required this.nom, this.code = ''});

  final String id;
  final String nom;
  final String code;
}

class ChapitreRevision {
  const ChapitreRevision({required this.id, required this.matiereId, required this.titre, this.ordre = 0});

  final String id;
  final String matiereId;
  final String titre;
  final int ordre;
}

class CompetenceRevision {
  const CompetenceRevision({required this.id, required this.matiereId, required this.libelle, this.code = ''});

  final String id;
  final String matiereId;
  final String libelle;
  final String code;
}

/// Contenu de révision d'un niveau, gardé sur l'appareil.
class PaquetRevision {
  const PaquetRevision({
    this.empreinte,
    this.matieres = const [],
    this.chapitres = const [],
    this.competences = const [],
    this.questions = const [],
  });

  final String? empreinte;
  final List<MatiereRevision> matieres;
  final List<ChapitreRevision> chapitres;
  final List<CompetenceRevision> competences;
  final List<QuestionQuiz> questions;

  bool get vide => questions.isEmpty;

  factory PaquetRevision.depuisJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> l(String cle) =>
        [for (final x in (j[cle] as List?) ?? const []) (x as Map).cast<String, dynamic>()];
    return PaquetRevision(
      empreinte: j['empreinte'] as String?,
      matieres: [for (final m in l('matieres')) MatiereRevision(id: m['id'] as String, nom: m['nom'] as String, code: '${m['code'] ?? ''}')],
      chapitres: [
        for (final c in l('chapitres'))
          ChapitreRevision(
            id: c['id'] as String,
            matiereId: c['matiere_id'] as String,
            titre: c['titre'] as String,
            ordre: (c['ordre'] as num?)?.toInt() ?? 0,
          ),
      ]..sort((a, b) => a.ordre.compareTo(b.ordre)),
      competences: [
        for (final k in l('competences'))
          CompetenceRevision(
            id: k['id'] as String,
            matiereId: k['matiere_id'] as String,
            libelle: k['libelle'] as String,
            code: '${k['code'] ?? ''}',
          ),
      ],
      questions: [for (final q in l('questions')) QuestionQuiz.depuisJson(q)],
    );
  }

  int questionsDe(String matiereId, {String? chapitreId}) => questions
      .where((q) => q.matiereId == matiereId && (chapitreId == null || q.contenu.chapitreId == chapitreId))
      .length;
}

/// Ce que l'appareil retient de chaque question déjà jouée, pour choisir les
/// suivantes (jamais vues et ratées d'abord, pas de répétition immédiate).
class TraceQuestion {
  const TraceQuestion({required this.vues, required this.dernierScore, required this.derniereFois});

  final int vues;
  final double dernierScore;
  final DateTime derniereFois;

  Map<String, dynamic> versJson() =>
      {'v': vues, 's': dernierScore, 't': derniereFois.toUtc().toIso8601String()};

  factory TraceQuestion.depuisJson(Map<String, dynamic> j) => TraceQuestion(
        vues: (j['v'] as num?)?.toInt() ?? 0,
        dernierScore: (j['s'] as num?)?.toDouble() ?? 0,
        derniereFois: DateTime.tryParse('${j['t']}') ?? DateTime(2000),
      );
}

/// Réglage d'un quiz.
class ConfigQuiz {
  const ConfigQuiz({
    required this.mode,
    this.matiereId,
    this.chapitreId,
    this.difficultes = const {},
    int? nombre,
    this.petitesClasses = false,
  }) : _nombre = nombre;

  final ModeQuiz mode;
  final String? matiereId;
  final String? chapitreId;
  final Set<Difficulte> difficultes;
  final int? _nombre;

  /// CP1 à CE2 : 5 questions au plus (cahier 11.1).
  final bool petitesClasses;

  int get nombre {
    final n = (_nombre ?? mode.nombreParDefaut).clamp(1, 50);
    return petitesClasses ? min(n, 5) : n;
  }
}

/// Choisit les questions d'un quiz. Ordre de priorité : jamais vues, puis
/// ratées (les plus anciennes d'abord), puis réussies il y a longtemps ;
/// jamais une question jouée dans l'heure si d'autres restent. Le mode
/// « mêlée » répartit entre les chapitres (pratique entrelacée).
List<QuestionQuiz> choisirQuestions(
  PaquetRevision paquet,
  ConfigQuiz config, {
  Map<String, TraceQuestion> traces = const {},
  DateTime? maintenant,
  Random? hasard,
}) {
  final now = maintenant ?? DateTime.now();
  final rnd = hasard ?? Random();
  var candidates = paquet.questions.where((q) {
    if (config.matiereId != null && q.matiereId != config.matiereId) return false;
    if (config.chapitreId != null && q.contenu.chapitreId != config.chapitreId) return false;
    if (config.difficultes.isNotEmpty && !config.difficultes.contains(q.contenu.difficulte)) return false;
    if (config.petitesClasses && !q.contenu.type.petitesClasses) return false;
    return true;
  }).toList();
  if (config.mode == ModeQuiz.erreurs) {
    candidates = candidates.where((q) => (traces[q.id]?.dernierScore ?? 1) < 1).toList();
  }
  if (candidates.isEmpty) return const [];

  double priorite(QuestionQuiz q) {
    final t = traces[q.id];
    if (t == null) return 3 + rnd.nextDouble();                       // jamais vue
    final heures = now.difference(t.derniereFois).inMinutes / 60;
    if (heures < 1) return rnd.nextDouble() * 0.1;                    // jouée à l'instant
    final rate = t.dernierScore < 1 ? 2.0 : 0.0;
    return rate + min(1.0, heures / (24 * 7)) + rnd.nextDouble() * 0.5;
  }

  final classees = [...candidates]..sort((a, b) => priorite(b).compareTo(priorite(a)));
  if (config.mode != ModeQuiz.melange) return classees.take(config.nombre).toList();

  // Mêlée : tour à tour dans chaque chapitre, puis mélange de l'ordre.
  final parChapitre = <String, List<QuestionQuiz>>{};
  for (final q in classees) {
    (parChapitre[q.contenu.chapitreId ?? '-'] ??= []).add(q);
  }
  final files = parChapitre.values.toList();
  final choisies = <QuestionQuiz>[];
  var i = 0;
  while (choisies.length < config.nombre && files.any((f) => f.isNotEmpty)) {
    final f = files[i % files.length];
    if (f.isNotEmpty) choisies.add(f.removeAt(0));
    i++;
  }
  return choisies..shuffle(rnd);
}

/// Mélange l'ordre d'affichage (choix d'un QCM, termes de droite d'une
/// association, éléments d'un classement) sans jamais montrer la bonne
/// réponse déjà en place pour un classement.
List<T> melanger<T>(List<T> elements, Random hasard, {bool eviterIdentite = false}) {
  final l = [...elements]..shuffle(hasard);
  if (eviterIdentite && l.length > 1) {
    var essais = 0;
    while (essais++ < 5 && _identique(l, elements)) {
      l.shuffle(hasard);
    }
    if (_identique(l, elements)) l.insert(0, l.removeLast());
  }
  return l;
}

bool _identique<T>(List<T> a, List<T> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Réponse donnée à une question.
class ReponseQuiz {
  const ReponseQuiz({required this.question, required this.donnee, required this.correction, required this.dureeS});

  final QuestionQuiz question;
  final Object? donnee;
  final Correction correction;
  final int dureeS;
}

/// Un quiz en cours puis terminé.
class SessionQuiz {
  SessionQuiz({
    required this.id,
    required this.ficheId,
    required this.config,
    required this.questions,
    DateTime? commenceLe,
  }) : commenceLe = commenceLe ?? DateTime.now();

  final String id;
  final String ficheId;
  final ConfigQuiz config;
  final List<QuestionQuiz> questions;
  final DateTime commenceLe;
  final List<ReponseQuiz> reponses = [];
  DateTime? termineLe;

  int get index => reponses.length;
  bool get fini => reponses.length >= questions.length;
  QuestionQuiz? get courante => fini ? null : questions[index];

  ReponseQuiz repondre(Object? donnee, {required int dureeS}) {
    final q = courante!;
    final r = ReponseQuiz(question: q, donnee: donnee, correction: q.contenu.corriger(donnee), dureeS: dureeS);
    reponses.add(r);
    if (fini) termineLe = DateTime.now();
    return r;
  }

  double get points => reponses.fold(0.0, (s, r) => s + r.correction.score);
  int get justes => reponses.where((r) => r.correction.juste).length;

  /// Part de réussite (0 à 1) sur les questions répondues.
  double get reussite => reponses.isEmpty ? 0 : points / reponses.length;

  int dureeTotaleS(DateTime fin) => max(0, fin.difference(commenceLe).inSeconds);

  /// Enregistrement envoyé au serveur (`enregistrer_tentative_revision`).
  Map<String, dynamic> versTentative({required bool termine, DateTime? fin}) {
    final f = fin ?? termineLe ?? DateTime.now();
    return {
      'id': id,
      'fiche_eleve_id': ficheId,
      'mode': config.mode.code,
      'matiere_id': config.matiereId,
      'chapitre_id': config.chapitreId,
      'nb_questions': questions.length,
      'duree_s': dureeTotaleS(f),
      'termine': termine,
      'commence_le': commenceLe.toUtc().toIso8601String(),
      'termine_le': termine ? f.toUtc().toIso8601String() : null,
      'reponses': [
        for (final (i, r) in reponses.indexed)
          {
            'question_id': r.question.id,
            'version': r.question.version,
            'ordre': i,
            'score': double.parse(r.correction.score.toStringAsFixed(3)),
            'duree_s': r.dureeS,
            'reponse': _json(r.donnee),
          },
      ],
    };
  }

  static Object? _json(Object? d) {
    if (d is Set) return d.toList();
    if (d is Map) return d.map((k, v) => MapEntry('$k', v));
    return d;
  }
}

// ---------------------------------------------------------------- messages

/// Message après une réponse : on félicite le travail et la méthode, jamais
/// « l'intelligence » ; du CP1 au CE2, une erreur reçoit toujours un
/// encouragement (cahier 11.1, Mueller et Dweck 1998).
String messageApresReponse(Correction c, {required bool petitesClasses, required int serie, Random? hasard}) {
  final r = hasard ?? Random();
  String un(List<String> l) => l[r.nextInt(l.length)];
  if (c.juste) {
    if (serie >= 3) return un(['Trois de suite, belle concentration !', 'Tu enchaînes, continue comme ça !']);
    return un(['Bonne réponse !', 'Exact, bien raisonné.', 'C’est juste !']);
  }
  if (c.score > 0) return un(['Presque : une partie est juste. Regarde la correction.', 'Tu y es presque !']);
  if (petitesClasses) {
    return un(['Pas encore, mais tu apprends ! Regarde bien la réponse.', 'Essaie de retenir celle-ci, tu vas y arriver !']);
  }
  return un(['Pas cette fois. Lis l’explication : c’est comme ça qu’on progresse.', 'Erreur utile : retiens l’explication.']);
}

/// Message de fin, selon la réussite.
String messageFin(double reussite, {required bool petitesClasses}) {
  if (reussite >= 0.9) return 'Excellent travail ! Tu peux passer à un quiz plus difficile.';
  if (reussite >= 0.7) return 'Bon travail ! Refais tes erreurs demain pour bien les retenir.';
  if (reussite >= 0.4) return 'Tu progresses. Relis les explications et refais tes erreurs.';
  return petitesClasses
      ? 'Bravo d’avoir essayé jusqu’au bout ! On recommence ensemble bientôt.'
      : 'Courage : ces questions reviendront, et tu les connaîtras mieux. Commence par refaire tes erreurs.';
}

// -------------------------------------------------------- niveau par compétence

enum NiveauCompetence {
  aRevoir('À revoir'),
  enProgres('En progrès'),
  solide('Solide');

  const NiveauCompetence(this.libelle);

  final String libelle;
}

/// Étiquette sur les cinq dernières réponses (la plus récente en tête) :
/// solide si 4 sur 5 (modèle « M sur N » de Kolibri), à revoir si moins de
/// la moitié, en progrès sinon ; null s'il y a moins de 3 réponses.
NiveauCompetence? niveauCompetence(List<double> derniersScores) {
  final s = derniersScores.take(5).toList();
  if (s.length < 3) return null;
  final total = s.fold(0.0, (a, b) => a + b);
  if (s.length == 5 && total >= 4) return NiveauCompetence.solide;
  if (total / s.length < 0.5) return NiveauCompetence.aRevoir;
  return NiveauCompetence.enProgres;
}

/// Résumé des révisions d'un élève (serveur, plus les quiz pas encore
/// envoyés depuis cet appareil).
class ResumeRevision {
  const ResumeRevision({
    this.jours = 30,
    this.tempsS = 0,
    this.quizTermines = 0,
    this.questions = 0,
    this.points = 0,
    this.derniereActivite,
    this.parMatiere = const {},
    this.competences = const {},
  });

  final int jours;
  final int tempsS;
  final int quizTermines;
  final int questions;
  final double points;
  final DateTime? derniereActivite;

  /// Matière → (réponses, points).
  final Map<String, ({int reponses, double points})> parMatiere;

  /// Compétence → cinq derniers scores, le plus récent en tête.
  final Map<String, List<double>> competences;

  double? get reussite => questions == 0 ? null : points / questions;

  factory ResumeRevision.depuisJson(Map<String, dynamic> j) => ResumeRevision(
        jours: (j['jours'] as num?)?.toInt() ?? 30,
        tempsS: (j['temps_s'] as num?)?.toInt() ?? 0,
        quizTermines: (j['quiz_termines'] as num?)?.toInt() ?? 0,
        questions: (j['questions'] as num?)?.toInt() ?? 0,
        points: (j['points'] as num?)?.toDouble() ?? 0,
        derniereActivite: j['derniere_activite'] == null ? null : DateTime.tryParse('${j['derniere_activite']}'),
        parMatiere: {
          for (final m in (j['par_matiere'] as List?) ?? const [])
            '${(m as Map)['matiere_id']}': (
              reponses: (m['reponses'] as num?)?.toInt() ?? 0,
              points: (m['points'] as num?)?.toDouble() ?? 0,
            ),
        },
        competences: {
          for (final c in (j['competences'] as List?) ?? const [])
            '${(c as Map)['competence_id']}': [for (final s in (c['scores'] as List?) ?? const []) (s as num).toDouble()],
        },
      );

  /// Ajoute les quiz faits sur cet appareil et pas encore reçus.
  ResumeRevision avecEnAttente(List<Map<String, dynamic>> tentatives, Map<String, QuestionQuiz> questionsParId) {
    if (tentatives.isEmpty) return this;
    var temps = tempsS, quiz = quizTermines, nbQ = questions;
    var pts = points;
    final parM = {...parMatiere};
    final comp = {for (final e in competences.entries) e.key: [...e.value]};
    DateTime? derniere = derniereActivite;
    for (final t in tentatives) {
      temps += (t['duree_s'] as num?)?.toInt() ?? 0;
      final debut = DateTime.tryParse('${t['commence_le']}');
      if (debut != null && (derniere == null || debut.isAfter(derniere))) derniere = debut;
      if (t['termine'] != true) continue;
      quiz++;
      for (final r in (t['reponses'] as List?) ?? const []) {
        final score = ((r as Map)['score'] as num?)?.toDouble() ?? 0;
        nbQ++;
        pts += score;
        final q = questionsParId['${r['question_id']}'];
        if (q == null) continue;
        final m = parM[q.matiereId];
        parM[q.matiereId] = (reponses: (m?.reponses ?? 0) + 1, points: (m?.points ?? 0) + score);
        final k = q.contenu.competenceId;
        if (k != null) comp[k] = [score, ...?comp[k]].take(5).toList();
      }
    }
    return ResumeRevision(
      jours: jours,
      tempsS: temps,
      quizTermines: quiz,
      questions: nbQ,
      points: pts,
      derniereActivite: derniere,
      parMatiere: parM,
      competences: comp,
    );
  }

  /// Compétences « à revoir », les plus faibles d'abord.
  List<String> competencesARevoir() {
    final l = [
      for (final e in competences.entries)
        if (niveauCompetence(e.value) == NiveauCompetence.aRevoir) e.key,
    ];
    double moyenne(String k) => competences[k]!.fold(0.0, (a, b) => a + b) / competences[k]!.length;
    return l..sort((a, b) => moyenne(a).compareTo(moyenne(b)));
  }
}

/// Durée lisible : « 1 h 05 », « 12 min », « 40 s ».
String dureeLisible(int s) {
  if (s < 60) return '$s s';
  final m = s ~/ 60;
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
}
