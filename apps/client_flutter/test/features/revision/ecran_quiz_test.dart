import 'dart:math';

import 'package:ecoshop_client/features/revision/application/revision_providers.dart';
import 'package:ecoshop_client/features/revision/data/revision_repository.dart';
import 'package:ecoshop_client/features/revision/domain/quiz.dart';
import 'package:ecoshop_client/features/revision/presentation/ecran_quiz.dart';
import 'package:ecoshop_client/features/revision/presentation/ecran_revision.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FauxDepot extends Fake implements RevisionRepository {
  final enregistrees = <({String id, bool termine, int reponses})>[];
  final signalements = <String>[];

  @override
  Future<bool> enregistrer(SessionQuiz s, {required bool termine}) async {
    enregistrees.add((id: s.id, termine: termine, reponses: s.reponses.length));
    return false; // sans réseau : gardé sur l'appareil
  }

  @override
  Future<void> signaler(String questionId, String motif, {String? commentaire}) async =>
      signalements.add('$questionId:$motif');
}

QuestionQuiz _q(String id, Map<String, dynamic> champs) => QuestionQuiz.depuisJson({
      'id': id,
      'matiere_id': 'm1',
      'version': 1,
      'difficulte': 'facile',
      'competence_id': 'k1',
      'explication': 'Explication de $id.',
      'contenu': const <String, dynamic>{},
      ...champs,
    });

final _questions = [
  _q('q1', {'type': 'vrai_faux', 'enonce': '2 + 2 = 4', 'reponse': {'valeur': true}}),
  _q('q2', {
    'type': 'qcm_simple',
    'enonce': 'Capitale de la Guinée ?',
    'contenu': {
      'choix': [
        {'id': 'a', 'texte': 'Conakry'},
        {'id': 'b', 'texte': 'Kindia'},
      ],
    },
    'reponse': {
      'bonnes': ['a'],
    },
  }),
  _q('q3', {'type': 'calcul', 'enonce': '3 × 4 ?', 'reponse': {'valeur': 12}}),
];

void main() {
  Future<_FauxDepot> monter(WidgetTester tester, {bool petites = false}) async {
    final depot = _FauxDepot();
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        revisionRepositoryProvider.overrideWithValue(depot),
        espaceRevisionProvider('f1').overrideWith((ref) async => throw UnimplementedError()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => EcranQuiz(
                    session: SessionQuiz(
                      id: 't1',
                      ficheId: 'f1',
                      config: const ConfigQuiz(mode: ModeQuiz.rapide),
                      questions: _questions,
                    ),
                    petitesClasses: petites,
                    prenom: 'Awa',
                    hasard: Random(2),
                  ),
                )),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    return depot;
  }

  testWidgets('un quiz complet : correction immédiate, explication, résultat, envoi', (tester) async {
    final depot = await monter(tester);
    expect(find.text('Avec Awa'), findsOneWidget);
    expect(find.text('Question 1 sur 3'), findsOneWidget);

    // Q1 : juste.
    await tester.tap(find.byKey(const Key('vf_true')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('quiz_valider')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quiz_bonne_reponse')), findsNothing);
    expect(find.text('Explication de q1.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quiz_suivant')));
    await tester.pumpAndSettle();

    // Q2 : fausse → bonne réponse et explication montrées ; signalement.
    await tester.tap(find.byKey(const Key('choix_b')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('quiz_valider')));
    await tester.pumpAndSettle();
    expect(find.text('Bonne réponse : Conakry'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quiz_signaler')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('motif_faute')));
    await tester.pumpAndSettle();
    expect(depot.signalements, ['q2:faute']);
    await tester.tap(find.byKey(const Key('quiz_suivant')));
    await tester.pumpAndSettle();

    // Q3 : calcul avec virgule et espaces.
    await tester.enterText(find.byKey(const Key('quiz_texte')), ' 12,0 ');
    await tester.pump();
    await tester.tap(find.byKey(const Key('quiz_valider')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quiz_suivant')));
    await tester.pumpAndSettle();

    expect(find.text('2 sur 3'), findsOneWidget);
    expect(find.textContaining('envoyé au retour du réseau'), findsOneWidget);
    expect(depot.enregistrees.single, (id: 't1', termine: true, reponses: 3));
    expect(find.byKey(const Key('quiz_refaire_erreurs')), findsOneWidget);
  });

  testWidgets('arrêter en cours : le temps est gardé, le quiz ne compte pas comme fini', (tester) async {
    final depot = await monter(tester);
    await tester.tap(find.byKey(const Key('vf_false')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('quiz_valider')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quiz_fermer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quiz_arreter')));
    await tester.pumpAndSettle();
    expect(depot.enregistrees.single, (id: 't1', termine: false, reponses: 1));
    expect(find.text('ouvrir'), findsOneWidget);
  });

  testWidgets('petites classes : une erreur reçoit un encouragement', (tester) async {
    await monter(tester, petites: true);
    await tester.tap(find.byKey(const Key('vf_false')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('quiz_valider')));
    await tester.pumpAndSettle();
    final message = tester.widget<Text>(find.byKey(const Key('quiz_message'))).data!;
    expect(message, anyOf(contains('apprends'), contains('arriver')));
  });

  testWidgets('écran des révisions : sans classe, message clair', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        espaceRevisionProvider('f9').overrideWith((ref) async => throw const ErreurRevision('SANS_CLASSE')),
      ],
      child: const MaterialApp(home: EcranRevision(ficheId: 'f9', prenom: 'Awa', parent: true)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Révisions de Awa'), findsOneWidget);
    expect(find.textContaining('pas encore inscrit dans une classe'), findsOneWidget);
  });
}
