/// Mode examen (REG-37 lot R3, cahier 11.2) : chronomètre, navigation libre
/// et retour en arrière, remise automatique à la fin du temps, correction
/// seulement après la clôture, note sur 20, points forts et à renforcer.
/// Résultat d'entraînement : jamais dans la moyenne ni le bulletin (12.6).
library;

import 'dart:math';

import 'question.dart';
import 'quiz.dart';

/// Durée conseillée : somme des temps recommandés, arrondie aux 5 minutes
/// supérieures, entre 5 et 180 minutes.
int dureeConseilleeS(List<QuestionQuiz> questions) {
  final total = questions.fold(0, (s, q) => s + q.contenu.tempsRecommandeS);
  final minutes = max(5, min(180, ((total / 60) / 5).ceil() * 5));
  return minutes * 60;
}

class BilanCompetence {
  const BilanCompetence({required this.competenceId, required this.questions, required this.points});

  final String competenceId;
  final int questions;
  final double points;

  double get reussite => questions == 0 ? 0 : points / questions;
}

class SessionExamen {
  SessionExamen({
    required this.id,
    required this.ficheId,
    required this.questions,
    required this.dureeLimiteS,
    this.matiereId,
    DateTime? commenceLe,
  }) : commenceLe = commenceLe ?? DateTime.now();

  final String id;
  final String ficheId;
  final String? matiereId;
  final List<QuestionQuiz> questions;
  final int dureeLimiteS;
  final DateTime commenceLe;

  /// Réponse par question (index) ; modifiable tant que l'examen n'est pas
  /// remis.
  final Map<int, Object?> reponses = {};
  final Set<int> completes = {};
  DateTime? remisLe;
  bool remiseAutomatique = false;
  List<Correction>? _corrections;

  bool get remis => remisLe != null;

  int restantS(DateTime maintenant) => max(0, dureeLimiteS - maintenant.difference(commenceLe).inSeconds);

  bool tempsEcoule(DateTime maintenant) => restantS(maintenant) == 0;

  void repondre(int index, Object? donnee, {required bool complete}) {
    if (remis) return; // plus rien ne change après la remise
    reponses[index] = donnee;
    complete ? completes.add(index) : completes.remove(index);
  }

  int get nonRepondues => questions.length - completes.length;

  /// Remet l'examen (par l'élève ou à la fin du temps) avec les réponses
  /// saisies à cet instant (11.2).
  void remettre(DateTime quand, {bool automatique = false}) {
    if (remis) return;
    remisLe = quand;
    remiseAutomatique = automatique;
    _corrections = [
      for (var i = 0; i < questions.length; i++)
        completes.contains(i) ? questions[i].contenu.corriger(reponses[i]) : const Correction(0),
    ];
  }

  List<Correction> get corrections => _corrections ?? (throw StateError('Examen pas encore remis'));

  double get points => corrections.fold(0.0, (s, c) => s + c.score);
  int get justes => corrections.where((c) => c.juste).length;
  int get fausses => questions.length - justes;

  /// Note sur 20, au quart de point.
  double get noteSur20 => questions.isEmpty ? 0 : (points / questions.length * 20 * 4).round() / 4;

  int get dureeS => min(dureeLimiteS, max(0, (remisLe ?? DateTime.now()).difference(commenceLe).inSeconds));

  List<BilanCompetence> parCompetence() {
    final m = <String, ({int n, double p})>{};
    for (var i = 0; i < questions.length; i++) {
      final k = questions[i].contenu.competenceId ?? '-';
      final a = m[k];
      m[k] = (n: (a?.n ?? 0) + 1, p: (a?.p ?? 0) + corrections[i].score);
    }
    return [for (final e in m.entries) BilanCompetence(competenceId: e.key, questions: e.value.n, points: e.value.p)];
  }

  /// Points forts : 75 % ou plus ; à renforcer : moins de 50 %.
  List<BilanCompetence> pointsForts() => [for (final b in parCompetence()) if (b.reussite >= 0.75) b]
    ..sort((a, b) => b.reussite.compareTo(a.reussite));

  List<BilanCompetence> aRenforcer() => [for (final b in parCompetence()) if (b.reussite < 0.5) b]
    ..sort((a, b) => a.reussite.compareTo(b.reussite));

  Map<String, dynamic> versTentative() => {
        'id': id,
        'fiche_eleve_id': ficheId,
        'mode': ModeQuiz.examen.code,
        'matiere_id': matiereId,
        'nb_questions': questions.length,
        'duree_s': dureeS,
        'termine': true,
        'commence_le': commenceLe.toUtc().toIso8601String(),
        'termine_le': remisLe?.toUtc().toIso8601String(),
        'reponses': [
          for (var i = 0; i < questions.length; i++)
            {
              'question_id': questions[i].id,
              'version': questions[i].version,
              'ordre': i,
              'score': double.parse(corrections[i].score.toStringAsFixed(3)),
              'duree_s': 0,
              'reponse': _json(reponses[i]),
            },
        ],
      };

  static Object? _json(Object? d) {
    if (d is Set) return d.toList();
    if (d is Map) return d.map((k, v) => MapEntry('$k', v));
    return d;
  }
}

/// « 18:05 » ou « 1:02:30 ».
String chrono(int s) {
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String d(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${d(m)}:${d(sec)}' : '${d(m)}:${d(sec)}';
}
