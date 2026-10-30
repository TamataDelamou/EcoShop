import 'dart:math';

import 'package:ecoshop_client/features/revision/domain/conseils.dart';
import 'package:ecoshop_client/features/revision/domain/question.dart';
import 'package:ecoshop_client/features/revision/domain/quiz.dart';
import 'package:flutter_test/flutter_test.dart';

QuestionQuiz vf(String id, {String matiere = 'm1', String? chapitre, String competence = 'k1', String type = 'vrai_faux', String difficulte = 'facile'}) =>
    QuestionQuiz.depuisJson({
      'id': id,
      'matiere_id': matiere,
      'version': 1,
      'type': type,
      'difficulte': difficulte,
      'chapitre_id': chapitre,
      'competence_id': competence,
      'enonce': 'Question $id',
      'contenu': const <String, dynamic>{},
      'reponse': type == 'vrai_faux' ? {'valeur': true} : {'acceptees': ['oui']},
      'explication': 'Explication $id',
    });

PaquetRevision paquet(List<QuestionQuiz> q) => PaquetRevision(
      empreinte: 'e1',
      matieres: const [MatiereRevision(id: 'm1', nom: 'Maths'), MatiereRevision(id: 'm2', nom: 'Français')],
      competences: const [CompetenceRevision(id: 'k1', matiereId: 'm1', libelle: 'Fractions')],
      questions: q,
    );

void main() {
  final maintenant = DateTime(2026, 10, 30, 18);

  group('choix des questions', () {
    test('jamais vues d’abord, puis ratées ; pas une question jouée à l’instant', () {
      final p = paquet([vf('a'), vf('b'), vf('c'), vf('d')]);
      final traces = {
        'a': TraceQuestion(vues: 1, dernierScore: 1, derniereFois: maintenant.subtract(const Duration(minutes: 5))),
        'b': TraceQuestion(vues: 2, dernierScore: 0, derniereFois: maintenant.subtract(const Duration(days: 2))),
        'c': TraceQuestion(vues: 1, dernierScore: 1, derniereFois: maintenant.subtract(const Duration(days: 3))),
      };
      final choisies = choisirQuestions(p, const ConfigQuiz(mode: ModeQuiz.rapide, nombre: 3),
          traces: traces, maintenant: maintenant, hasard: Random(1));
      expect(choisies.map((q) => q.id), ['d', 'b', 'c']);
    });

    test('filtres : matière, chapitre, difficulté ; erreurs seulement', () {
      final p = paquet([
        vf('a', chapitre: 'ch1'),
        vf('b', chapitre: 'ch2', difficulte: 'difficile'),
        vf('c', matiere: 'm2'),
      ]);
      expect(choisirQuestions(p, const ConfigQuiz(mode: ModeQuiz.chapitre, matiereId: 'm1', chapitreId: 'ch2'))
          .map((q) => q.id), ['b']);
      expect(choisirQuestions(p, const ConfigQuiz(mode: ModeQuiz.personnalise, difficultes: {Difficulte.facile}))
          .map((q) => q.id).toSet(), {'a', 'c'});
      final traces = {'c': TraceQuestion(vues: 1, dernierScore: 0, derniereFois: DateTime(2026))};
      expect(choisirQuestions(p, const ConfigQuiz(mode: ModeQuiz.erreurs), traces: traces).map((q) => q.id), ['c']);
    });

    test('petites classes : 5 questions au plus, types adaptés seulement', () {
      final p = paquet([for (var i = 0; i < 8; i++) vf('v$i'), vf('court', type: 'reponse_courte')]);
      final choisies = choisirQuestions(p, const ConfigQuiz(mode: ModeQuiz.standard, petitesClasses: true));
      expect(choisies.length, 5);
      expect(choisies.any((q) => q.id == 'court'), isFalse);
    });

    test('révision mêlée : un peu de chaque chapitre', () {
      final p = paquet([
        for (var i = 0; i < 5; i++) vf('x$i', chapitre: 'ch1'),
        for (var i = 0; i < 5; i++) vf('y$i', chapitre: 'ch2'),
      ]);
      final choisies = choisirQuestions(p, const ConfigQuiz(mode: ModeQuiz.melange, nombre: 4), hasard: Random(3));
      expect(choisies.where((q) => q.contenu.chapitreId == 'ch1').length, 2);
      expect(choisies.where((q) => q.contenu.chapitreId == 'ch2').length, 2);
    });

    test('un classement n’est jamais montré déjà dans le bon ordre', () {
      final r = Random(0);
      for (var i = 0; i < 30; i++) {
        expect(melanger([1, 2, 3], r, eviterIdentite: true), isNot([1, 2, 3]));
      }
    });
  });

  group('session et tentative', () {
    test('réponses, points et enregistrement envoyé au serveur', () {
      final s = SessionQuiz(
        id: 't1',
        ficheId: 'f1',
        config: const ConfigQuiz(mode: ModeQuiz.rapide),
        questions: [vf('a'), vf('b')],
        commenceLe: DateTime.utc(2026, 10, 30, 10),
      );
      expect(s.repondre(true, dureeS: 12).correction.juste, isTrue);
      expect(s.repondre(false, dureeS: 8).correction.juste, isFalse);
      expect(s.fini, isTrue);
      expect(s.reussite, 0.5);
      final t = s.versTentative(termine: true, fin: DateTime.utc(2026, 10, 30, 10, 1));
      expect(t['duree_s'], 60);
      expect(t['mode'], 'rapide');
      expect((t['reponses'] as List).map((r) => r['score']), [1.0, 0.0]);
    });
  });

  group('messages et niveaux', () {
    test('on félicite le travail ; en petites classes, on encourage toujours', () {
      final r = Random(0);
      for (var i = 0; i < 10; i++) {
        final m = messageApresReponse(const Correction(0), petitesClasses: true, serie: 0, hasard: r);
        expect(m, anyOf(contains('apprends'), contains('arriver')));
      }
      expect(messageFin(0.2, petitesClasses: true), contains('Bravo d’avoir essayé'));
      expect(messageFin(0.95, petitesClasses: false), contains('Excellent travail'));
    });

    test('compétence : solide, en progrès, à revoir (5 dernières réponses)', () {
      expect(niveauCompetence([1, 1, 1, 1, 0]), NiveauCompetence.solide);
      expect(niveauCompetence([1, 0, 1, 0, 1]), NiveauCompetence.enProgres);
      expect(niveauCompetence([0, 0, 1]), NiveauCompetence.aRevoir);
      expect(niveauCompetence([1, 1]), isNull, reason: 'trop tôt pour juger');
    });

    test('dureeLisible', () {
      expect(dureeLisible(40), '40 s');
      expect(dureeLisible(720), '12 min');
      expect(dureeLisible(3900), '1 h 05');
    });
  });

  group('résumé et conseils au parent', () {
    test('les quiz de cet appareil pas encore envoyés comptent', () {
      final q = vf('a');
      final r = const ResumeRevision(tempsS: 100, quizTermines: 1, questions: 2, points: 1).avecEnAttente([
        {
          'fiche_eleve_id': 'f1',
          'duree_s': 50,
          'termine': true,
          'commence_le': '2026-10-30T10:00:00Z',
          'reponses': [
            {'question_id': 'a', 'score': 0},
            {'question_id': 'a', 'score': 0},
            {'question_id': 'a', 'score': 0},
          ],
        },
        {'duree_s': 30, 'termine': false, 'reponses': []},
      ], {'a': q});
      expect(r.tempsS, 180, reason: 'un quiz abandonné compte dans le temps');
      expect(r.quizTermines, 2);
      expect(r.reussite, closeTo(1 / 5, 1e-9));
      expect(r.competencesARevoir(), ['k1']);
    });

    test('conseils concrets : reprendre, travailler une compétence, féliciter l’effort', () {
      final p = paquet([vf('a')]);
      final aucun = conseilsParent(prenom: 'Awa', resume: const ResumeRevision(), paquet: p, maintenant: maintenant);
      expect(aucun.single.texte, contains('premier quiz rapide'));

      final r = ResumeRevision(
        quizTermines: 3,
        questions: 10,
        points: 5,
        derniereActivite: maintenant.subtract(const Duration(days: 6)),
        competences: const {'k1': [0, 0, 1]},
      );
      final c = conseilsParent(prenom: 'Awa', resume: r, paquet: p, maintenant: maintenant);
      expect(c.map((x) => x.texte).join('\n'), allOf(contains('depuis 6 jours'), contains('« Fractions »'), contains('félicitez')));
      expect(c.firstWhere((x) => x.competenceId != null).matiereId, 'm1');
      expect(conseilsParent(prenom: 'Awa', resume: r, paquet: paquet(const []), maintenant: maintenant), isEmpty);
    });
  });
}
