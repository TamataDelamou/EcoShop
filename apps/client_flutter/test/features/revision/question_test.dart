import 'package:ecoshop_client/features/revision/data/banque_questions_repository.dart';
import 'package:ecoshop_client/features/revision/domain/question.dart';
import 'package:flutter_test/flutter_test.dart';

ContenuQuestion q(TypeQuestion type, {Map<String, dynamic> contenu = const {}, required Map<String, dynamic> reponse, String enonce = 'Énoncé'}) =>
    ContenuQuestion(
      type: type,
      difficulte: Difficulte.moyen,
      competenceId: 'c1',
      enonce: enonce,
      contenu: contenu,
      reponse: reponse,
      explication: 'Parce que.',
    );

const choix3 = {
  'choix': [
    {'id': 'a', 'texte': '1/2'},
    {'id': 'b', 'texte': '2/2'},
    {'id': 'c', 'texte': '1/4'},
  ],
};

void main() {
  group('Correction (lot R1, utilisée hors connexion au lot R2)', () {
    test('QCM simple et multiple', () {
      final simple = q(TypeQuestion.qcmSimple, contenu: choix3, reponse: {'bonnes': ['a']});
      expect(simple.corriger({'a'}).juste, isTrue);
      expect(simple.corriger(['b']).juste, isFalse);
      final multiple = q(TypeQuestion.qcmMultiple, contenu: choix3, reponse: {'bonnes': ['a', 'c']});
      expect(multiple.corriger({'c', 'a'}).juste, isTrue);
      expect(multiple.corriger({'a'}).juste, isFalse, reason: 'il manque une bonne réponse');
      expect(multiple.corriger({'a', 'b', 'c'}).juste, isFalse, reason: 'une réponse en trop');
      expect(multiple.bonneReponseLisible(), '1/2 ; 1/4');
    });

    test('vrai ou faux', () {
      final v = q(TypeQuestion.vraiFaux, reponse: {'valeur': false});
      expect(v.corriger(false).juste, isTrue);
      expect(v.corriger(true).juste, isFalse);
      expect(v.corriger(null).juste, isFalse);
    });

    test('réponse courte : sans accents, majuscules ni point final', () {
      final c = q(TypeQuestion.reponseCourte, reponse: {'acceptees': ['Conakry', 'Konakry']});
      expect(c.corriger('  conakry. ').juste, isTrue);
      expect(c.corriger('KONAKRY').juste, isTrue);
      expect(c.corriger('Kindia').juste, isFalse);
      expect(c.corriger('').juste, isFalse);
      expect(q(TypeQuestion.reponseCourte, reponse: {'acceptees': ['Élève']}).corriger('eleve').juste, isTrue);
    });

    test('texte à trous : score partiel', () {
      final t = q(TypeQuestion.texteATrous,
          enonce: 'La capitale de la Guinée est [[1]] et celle du Mali est [[2]].',
          reponse: {
            'trous': {'1': ['Conakry'], '2': ['Bamako']},
          });
      expect(t.trous, ['1', '2']);
      expect(t.corriger({'1': 'conakry', '2': 'Bamako'}).juste, isTrue);
      expect(t.corriger({'1': 'conakry', '2': 'Dakar'}).score, 0.5);
      expect(t.bonneReponseLisible(), 'La capitale de la Guinée est Conakry et celle du Mali est Bamako.');
    });

    test('association et classement', () {
      final a = q(TypeQuestion.association, contenu: {
        'gauche': [
          {'id': 'g1', 'texte': 'Guinée'},
          {'id': 'g2', 'texte': 'Sénégal'},
        ],
        'droite': [
          {'id': 'd1', 'texte': 'Conakry'},
          {'id': 'd2', 'texte': 'Dakar'},
        ],
      }, reponse: {
        'paires': {'g1': 'd1', 'g2': 'd2'},
      });
      expect(a.corriger({'g1': 'd1', 'g2': 'd2'}).juste, isTrue);
      expect(a.corriger({'g1': 'd2', 'g2': 'd2'}).score, 0.5);
      expect(a.bonneReponseLisible(), 'Guinée → Conakry ; Sénégal → Dakar');

      final c = q(TypeQuestion.classement, contenu: {
        'elements': [
          {'id': 'x', 'texte': '1/4'},
          {'id': 'y', 'texte': '1/2'},
          {'id': 'z', 'texte': '3/4'},
        ],
      }, reponse: {
        'ordre': ['x', 'y', 'z'],
      });
      expect(c.corriger(['x', 'y', 'z']).juste, isTrue);
      expect(c.corriger(['y', 'x', 'z']).score, closeTo(1 / 3, 1e-9));
      expect(c.corriger(['x']).juste, isFalse);
      expect(c.bonneReponseLisible(), '1/4 < 1/2 < 3/4');
    });

    test('calcul : virgule, espaces et écart toléré', () {
      final c = q(TypeQuestion.calcul, reponse: {'valeur': 3.14, 'tolerance': 0.01, 'unite': 'm'});
      expect(c.corriger('3,14').juste, isTrue);
      expect(c.corriger('3.15').juste, isTrue);
      expect(c.corriger('3,2').juste, isFalse);
      expect(c.corriger('trois').juste, isFalse);
      expect(q(TypeQuestion.calcul, reponse: {'valeur': 1200}).corriger('1 200').juste, isTrue);
      expect(c.bonneReponseLisible(), '3.14 m');
    });
  });

  group('Contrôles avant enregistrement (cahier 10.3)', () {
    test('compétence, explication et énoncé obligatoires', () {
      expect(
        const ContenuQuestion(
          type: TypeQuestion.vraiFaux,
          difficulte: Difficulte.facile,
          competenceId: null,
          enonce: 'E',
          contenu: {},
          reponse: {'valeur': true},
          explication: 'X',
        ).erreur(),
        'COMPETENCE_REQUISE',
      );
      expect(q(TypeQuestion.vraiFaux, reponse: {'valeur': true}).erreur(), isNull);
    });

    test('formes refusées, comme le serveur', () {
      expect(q(TypeQuestion.qcmSimple, contenu: choix3, reponse: {'bonnes': ['a', 'b']}).erreur(), 'REPONSE_INVALIDE');
      expect(q(TypeQuestion.qcmSimple, contenu: choix3, reponse: {'bonnes': ['z']}).erreur(), 'REPONSE_INVALIDE');
      expect(q(TypeQuestion.qcmMultiple, reponse: {'bonnes': ['a']}).erreur(), 'CHOIX_INVALIDES');
      expect(
        q(TypeQuestion.texteATrous, enonce: 'Il y a [[1]].', reponse: {
          'trous': {'2': ['x']},
        }).erreur(),
        'TROU_ABSENT_ENONCE',
      );
      expect(q(TypeQuestion.calcul, reponse: {'valeur': 'douze'}).erreur(), 'REPONSE_INVALIDE');
      expect(q(TypeQuestion.reponseCourte, reponse: {'acceptees': <String>[]}).erreur(), 'REPONSE_INVALIDE');
    });

    test('petites classes : types adaptés, trois choix au plus', () {
      expect(q(TypeQuestion.reponseCourte, reponse: {'acceptees': ['A']}).erreur(petitesClasses: true),
          'TYPE_NON_ADAPTE_PETITES_CLASSES');
      final quatre = {
        'choix': [
          for (final id in ['a', 'b', 'c', 'd']) {'id': id, 'texte': id.toUpperCase()},
        ],
      };
      expect(q(TypeQuestion.qcmSimple, contenu: quatre, reponse: {'bonnes': ['a']}).erreur(petitesClasses: true),
          'TROP_DE_CHOIX_PETITES_CLASSES');
      expect(q(TypeQuestion.qcmSimple, contenu: choix3, reponse: {'bonnes': ['a']}).erreur(petitesClasses: true), isNull);
    });
  });

  group('Lecture du serveur et brouillons', () {
    test('la version de travail est celle montrée à l’éditeur', () {
      final question = Question.depuisJson({
        'id': 'q1',
        'matiere_id': 'm1',
        'statut': 'brouillon',
        'version_travail': 2,
        'version_publiee': 1,
        'questions_versions': [
          {'version': 1, 'type': 'vrai_faux', 'enonce': 'Ancienne', 'reponse': {'valeur': true}, 'explication': 'E'},
          {'version': 2, 'type': 'vrai_faux', 'enonce': 'Nouvelle', 'reponse': {'valeur': true}, 'explication': 'E'},
        ],
        'signalements_questions': [
          {'traite': false},
          {'traite': true},
        ],
      });
      expect(question.travail.enonce, 'Nouvelle');
      expect(question.diffuseePendantModification, isTrue);
      expect(question.signalements, 1);
    });

    test('un brouillon gardé sur l’appareil se relit', () {
      final c = q(TypeQuestion.qcmSimple, contenu: choix3, reponse: {'bonnes': ['a']});
      final p = {'p_id': 'q9', 'p_matiere': 'm1', ...c.versParametres()};
      final relu = BanqueQuestionsRepository.questionDepuisParametres(p);
      expect(relu.enAttenteEnvoi, isTrue);
      expect(relu.travail.choix.length, 3);
      expect(relu.travail.corriger({'a'}).juste, isTrue);
    });
  });
}
