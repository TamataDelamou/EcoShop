/// Profil de maîtrise, recommandation du jour, répétition espacée et plan
/// (REG-37 lot R4, cahier ch. 14 et 15).
library;

import 'dart:math';

import 'question.dart';
import 'quiz.dart';

/// Seuil sous lequel une compétence est un point faible (14.1).
const seuilMaitrise = 0.5;

/// Seuil d'une compétence acquise.
const seuilAcquis = 0.8;

class CompetenceMaitrise {
  const CompetenceMaitrise({
    required this.competenceId,
    required this.maitrise,
    required this.reponses,
    this.derniere,
    this.echecsRepetes = false,
  });

  final String competenceId;

  /// 0 à 1, les réponses récentes pesant davantage (calcul du serveur).
  final double maitrise;
  final int reponses;
  final DateTime? derniere;

  /// Les trois dernières réponses ratées : retour à la leçon (14.2).
  final bool echecsRepetes;

  bool get faible => reponses >= 2 && maitrise < seuilMaitrise;
  bool get acquise => reponses >= 5 && maitrise >= seuilAcquis;

  factory CompetenceMaitrise.depuisJson(Map<String, dynamic> j) => CompetenceMaitrise(
        competenceId: j['competence_id'] as String,
        maitrise: (j['maitrise'] as num?)?.toDouble() ?? 0.5,
        reponses: (j['reponses'] as num?)?.toInt() ?? 0,
        derniere: j['derniere'] == null ? null : DateTime.tryParse('${j['derniere']}'),
        echecsRepetes: j['echecs_repetes'] == true,
      );
}

class ProfilMaitrise {
  const ProfilMaitrise([this.competences = const {}]);

  final Map<String, CompetenceMaitrise> competences;

  factory ProfilMaitrise.depuisJson(Object? json) => ProfilMaitrise({
        for (final c in (json as List?) ?? const [])
          (c as Map)['competence_id'] as String: CompetenceMaitrise.depuisJson(c.cast<String, dynamic>()),
      });

  /// Points faibles, les plus faibles d'abord.
  List<CompetenceMaitrise> faibles() =>
      [for (final c in competences.values) if (c.faible) c]..sort((a, b) => a.maitrise.compareTo(b.maitrise));

  /// Maîtrise moyenne d'une matière (compétences commencées).
  double? matiere(String matiereId, PaquetRevision paquet) {
    final ids = {for (final k in paquet.competences) if (k.matiereId == matiereId) k.id};
    final l = [for (final c in competences.values) if (ids.contains(c.competenceId)) c.maitrise];
    return l.isEmpty ? null : l.reduce((a, b) => a + b) / l.length;
  }
}

/// Cartes de répétition espacée à revoir aujourd'hui (15.1).
class RevisionsDuJour {
  const RevisionsDuJour({this.dues = 0, this.retenues = 0, this.suivies = 0, this.questionIds = const []});

  final int dues;
  final int retenues;
  final int suivies;
  final List<String> questionIds;

  factory RevisionsDuJour.depuisJson(Map<String, dynamic> j) => RevisionsDuJour(
        dues: (j['dues'] as num?)?.toInt() ?? 0,
        retenues: (j['retenues'] as num?)?.toInt() ?? 0,
        suivies: (j['suivies'] as num?)?.toInt() ?? 0,
        questionIds: [for (final c in (j['cartes'] as List?) ?? const []) '${(c as Map)['question_id']}'],
      );

  /// Sans les cartes déjà revues aujourd'hui sur cet appareil (pas encore
  /// reçues par le serveur).
  RevisionsDuJour sansDejaRevues(Map<String, TraceQuestion> traces, DateTime maintenant) {
    bool aujourdhui(DateTime d) => d.year == maintenant.year && d.month == maintenant.month && d.day == maintenant.day;
    final restantes = [
      for (final id in questionIds)
        if (!(traces[id] != null && aujourdhui(traces[id]!.derniereFois.toLocal()))) id,
    ];
    return RevisionsDuJour(
      dues: max(0, dues - (questionIds.length - restantes.length)),
      retenues: retenues,
      suivies: suivies,
      questionIds: restantes,
    );
  }
}

/// Plafond de la file du jour (15.1) : resserré du CP1 au CE2.
int plafondRevisions({required bool petitesClasses}) => petitesClasses ? 8 : 20;

enum TypeRecommandation { repetition, retourLecon, similaire, nouvelle, plusDifficile, decouverte }

/// La prochaine activité la plus utile (14.2).
class Recommandation {
  const Recommandation({required this.type, required this.titre, required this.raison, required this.config});

  final TypeRecommandation type;
  final String titre;
  final String raison;
  final ConfigQuiz config;
}

/// Règles de transition du cahier (14.2) : oubli → répétition espacée ;
/// échec répété → retour à la leçon ; erreur → exercice similaire ; bonne
/// maîtrise → nouvelle compétence, sinon difficulté supérieure.
Recommandation? recommandationDuJour({
  required PaquetRevision paquet,
  required ProfilMaitrise profil,
  required RevisionsDuJour revisions,
  required bool petitesClasses,
}) {
  if (paquet.vide) return null;
  String libelle(String id) => paquet.competences.where((k) => k.id == id).firstOrNull?.libelle ?? 'cette compétence';
  bool aDesQuestions(String competenceId) => paquet.questions.any((q) => q.contenu.competenceId == competenceId);

  if (revisions.questionIds.isNotEmpty) {
    return Recommandation(
      type: TypeRecommandation.repetition,
      titre: 'Tes révisions du jour',
      raison: '${revisions.questionIds.length} question${revisions.questionIds.length > 1 ? 's' : ''} à revoir '
          'avant de les oublier.',
      config: ConfigQuiz(
        mode: ModeQuiz.repetition,
        questionIds: revisions.questionIds,
        nombre: plafondRevisions(petitesClasses: petitesClasses),
        petitesClasses: petitesClasses,
      ),
    );
  }

  final faibles = [for (final c in profil.faibles()) if (aDesQuestions(c.competenceId)) c];
  final bloquee = faibles.where((c) => c.echecsRepetes).firstOrNull;
  if (bloquee != null) {
    final lecon = paquet.chapitres
        .where((ch) => paquet.questions.any((q) => q.contenu.competenceId == bloquee.competenceId && q.contenu.chapitreId == ch.id))
        .firstOrNull;
    return Recommandation(
      type: TypeRecommandation.retourLecon,
      titre: 'Revenir à la leçon : ${libelle(bloquee.competenceId)}',
      raison: 'Plusieurs erreurs de suite : relis ta leçon${lecon == null ? '' : ' « ${lecon.titre} »'} ou demande à ton '
          'enseignant, puis refais ces questions faciles.',
      config: ConfigQuiz(
        mode: ModeQuiz.competence,
        competenceId: bloquee.competenceId,
        difficultes: const {Difficulte.facile},
        petitesClasses: petitesClasses,
      ),
    );
  }
  if (faibles.isNotEmpty) {
    final k = faibles.first;
    return Recommandation(
      type: TypeRecommandation.similaire,
      titre: 'À renforcer : ${libelle(k.competenceId)}',
      raison: 'Des questions du même genre pour corriger tes erreurs.',
      config: ConfigQuiz(mode: ModeQuiz.competence, competenceId: k.competenceId, petitesClasses: petitesClasses),
    );
  }

  final acquises = [for (final c in profil.competences.values) if (c.acquise) c];
  for (final a in acquises) {
    final matiere = paquet.competences.where((k) => k.id == a.competenceId).firstOrNull?.matiereId;
    final nouvelle = paquet.competences
        .where((k) => k.matiereId == matiere && !profil.competences.containsKey(k.id) && aDesQuestions(k.id))
        .firstOrNull;
    if (nouvelle != null) {
      return Recommandation(
        type: TypeRecommandation.nouvelle,
        titre: 'Nouvelle compétence : ${nouvelle.libelle}',
        raison: 'Tu maîtrises « ${libelle(a.competenceId)} » : passe à la suite.',
        config: ConfigQuiz(mode: ModeQuiz.competence, competenceId: nouvelle.id, petitesClasses: petitesClasses),
      );
    }
  }
  if (acquises.isNotEmpty && !petitesClasses) {
    final a = acquises.first;
    return Recommandation(
      type: TypeRecommandation.plusDifficile,
      titre: 'Défi : ${libelle(a.competenceId)}',
      raison: 'Tu réussis bien : essaie des questions plus difficiles.',
      config: ConfigQuiz(
        mode: ModeQuiz.competence,
        competenceId: a.competenceId,
        difficultes: const {Difficulte.difficile, Difficulte.expert},
      ),
    );
  }
  return Recommandation(
    type: TypeRecommandation.decouverte,
    titre: 'Quiz rapide',
    raison: '5 questions pour faire le point et préparer tes prochaines recommandations.',
    config: ConfigQuiz(mode: ModeQuiz.rapide, petitesClasses: petitesClasses),
  );
}

// ------------------------------------------------------------------- plan

class PlanRevision {
  const PlanRevision({required this.titre, required this.echeance, required this.matieres, this.questionsParJour = 10});

  final String titre;
  final DateTime echeance;
  final List<String> matieres;
  final int questionsParJour;

  factory PlanRevision.depuisJson(Map<String, dynamic> j) => PlanRevision(
        titre: '${j['titre'] ?? 'Mon examen'}',
        echeance: DateTime.parse('${j['echeance']}'),
        matieres: [for (final m in (j['matieres'] as List?) ?? const []) '$m'],
        questionsParJour: (j['questions_par_jour'] as num?)?.toInt() ?? 10,
      );

  int joursRestants(DateTime maintenant) {
    final a = DateTime(maintenant.year, maintenant.month, maintenant.day);
    final b = DateTime(echeance.year, echeance.month, echeance.day);
    return b.difference(a).inDays;
  }
}

class MissionJour {
  const MissionJour({required this.jour, required this.matiereId, required this.nombre, this.examenBlanc = false});

  final DateTime jour;

  /// Null : examen blanc toutes matières du plan.
  final String? matiereId;
  final int nombre;
  final bool examenBlanc;
}

/// Missions de chaque jour jusqu'à l'échéance (15.2). Recalculé chaque jour
/// à partir d'aujourd'hui : un retard est réparti sur les jours restants,
/// rien n'est perdu. Temps alloué à chaque matière selon son coefficient et
/// ses points faibles ; un examen blanc chaque semaine et la veille.
List<MissionJour> missionsDuPlan({
  required PlanRevision plan,
  required DateTime maintenant,
  Map<String, num> coefficients = const {},
  Map<String, int> faiblesParMatiere = const {},
  int horizon = 14,
}) {
  final jours = plan.joursRestants(maintenant);
  if (jours <= 0 || plan.matieres.isEmpty) return const [];
  final poids = {
    for (final m in plan.matieres) m: (coefficients[m] ?? 1).toDouble() * (1 + 0.5 * (faiblesParMatiere[m] ?? 0)),
  };
  final total = poids.values.fold(0.0, (a, b) => a + b);
  final attribues = {for (final m in plan.matieres) m: 0};
  final aujourdhui = DateTime(maintenant.year, maintenant.month, maintenant.day);
  final missions = <MissionJour>[];
  for (var i = 0; i < min(jours, horizon); i++) {
    final jour = aujourdhui.add(Duration(days: i));
    final restants = jours - i;
    if (restants == 1 || (i > 0 && i % 7 == 6)) {
      missions.add(MissionJour(jour: jour, matiereId: null, nombre: max(10, plan.questionsParJour), examenBlanc: true));
      continue;
    }
    // Matière la plus en retard sur sa part (plus grand reste).
    final faits = attribues.values.fold(0, (a, b) => a + b) + 1;
    String choisie = plan.matieres.first;
    var ecart = double.negativeInfinity;
    for (final m in plan.matieres) {
      final e = poids[m]! / total * faits - attribues[m]!;
      if (e > ecart) {
        ecart = e;
        choisie = m;
      }
    }
    attribues[choisie] = attribues[choisie]! + 1;
    missions.add(MissionJour(jour: jour, matiereId: choisie, nombre: plan.questionsParJour));
  }
  return missions;
}

// ------------------------------------------------------- vue de la classe

class CompetenceClasse {
  const CompetenceClasse({
    required this.competenceId,
    required this.libelle,
    required this.eleves,
    required this.sousSeuil,
    required this.moyenne,
    this.elevesSousSeuil = const [],
  });

  final String competenceId;
  final String libelle;
  final int eleves;
  final int sousSeuil;
  final double moyenne;
  final List<String> elevesSousSeuil;

  /// Part de la classe sous le seuil.
  double get partSousSeuil => eleves == 0 ? 0 : sousSeuil / eleves;
}

/// Vue de l'enseignant (14.1) : compétences le plus souvent sous le seuil,
/// pour une reprise de cours ciblée.
class MaitriseClasse {
  const MaitriseClasse({this.eleves = 0, this.elevesActifs = 0, this.competences = const []});

  final int eleves;
  final int elevesActifs;
  final List<CompetenceClasse> competences;

  factory MaitriseClasse.depuisJson(Map<String, dynamic> j) => MaitriseClasse(
        eleves: (j['eleves'] as num?)?.toInt() ?? 0,
        elevesActifs: (j['eleves_actifs'] as num?)?.toInt() ?? 0,
        competences: [
          for (final c in (j['competences'] as List?) ?? const [])
            CompetenceClasse(
              competenceId: '${(c as Map)['competence_id']}',
              libelle: '${c['libelle'] ?? ''}',
              eleves: (c['eleves'] as num?)?.toInt() ?? 0,
              sousSeuil: (c['sous_seuil'] as num?)?.toInt() ?? 0,
              moyenne: (c['maitrise_moyenne'] as num?)?.toDouble() ?? 0,
              elevesSousSeuil: [for (final n in (c['eleves_sous_seuil'] as List?) ?? const []) '$n'],
            ),
        ],
      );

  /// À reprendre en classe : au moins un tiers des élèves sous le seuil.
  List<CompetenceClasse> aReprendre() => [for (final c in competences) if (c.sousSeuil > 0 && c.partSousSeuil >= 1 / 3) c];
}
