import 'dart:math';

import 'package:ecoshop_client/core/audio/lecteur_vocal.dart';
import 'package:ecoshop_client/features/revision/application/revision_providers.dart';
import 'package:ecoshop_client/features/revision/data/revision_repository.dart';
import 'package:ecoshop_client/features/revision/domain/classement.dart';
import 'package:ecoshop_client/features/revision/domain/examen.dart';
import 'package:ecoshop_client/features/revision/domain/question.dart';
import 'package:ecoshop_client/features/revision/domain/quiz.dart';
import 'package:ecoshop_client/features/revision/presentation/champ_reponse.dart';
import 'package:ecoshop_client/features/revision/presentation/ecran_examen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

QuestionQuiz vf(String id, {bool valeur = true, String competence = 'k1', int temps = 60}) => QuestionQuiz.depuisJson({
      'id': id,
      'matiere_id': 'm1',
      'version': 1,
      'type': 'vrai_faux',
      'difficulte': 'moyen',
      'competence_id': competence,
      'enonce': 'Affirmation $id',
      'contenu': const <String, dynamic>{},
      'reponse': {'valeur': valeur},
      'explication': 'Parce que $id.',
      'temps_recommande_s': temps,
    });

class _FauxDepot extends Fake implements RevisionRepository {
  final examens = <SessionExamen>[];

  @override
  Future<bool> enregistrerExamen(SessionExamen e) async {
    examens.add(e);
    return true;
  }
}

class _FauxLecteur implements LecteurVocal {
  final lus = <String>[];

  @override
  Future<bool> lire(String texte) async {
    lus.add(texte);
    return true;
  }

  @override
  Future<void> arreter() async {}
}

void main() {
  final debut = DateTime(2026, 10, 30, 9);

  group('examen blanc (cahier 11.2)', () {
    test('durée conseillée : temps recommandés arrondis aux 5 minutes', () {
      expect(dureeConseilleeS([vf('a', temps: 90), vf('b', temps: 90), vf('c', temps: 90)]), 5 * 60);
      expect(dureeConseilleeS([for (var i = 0; i < 20; i++) vf('q$i', temps: 50)]), 20 * 60);
    });

    test('correction seulement à la remise ; note sur 20, points forts et à renforcer', () {
      final e = SessionExamen(
        id: 'x1',
        ficheId: 'f1',
        dureeLimiteS: 600,
        commenceLe: debut,
        questions: [vf('a'), vf('b'), vf('c', competence: 'k2'), vf('d', competence: 'k2')],
      );
      e.repondre(0, true, complete: true);
      e.repondre(1, true, complete: true);
      e.repondre(2, false, complete: true);
      expect(() => e.corrections, throwsStateError, reason: 'pas de correction pendant l’examen');
      e.repondre(2, true, complete: true); // retour en arrière : la réponse change
      e.remettre(debut.add(const Duration(minutes: 7)));
      e.repondre(3, true, complete: true); // trop tard : ignoré
      expect(e.justes, 3);
      expect(e.noteSur20, 15);
      expect(e.dureeS, 420);
      expect(e.pointsForts().map((b) => b.competenceId), ['k1']);
      expect(e.aRenforcer(), isEmpty);
      final t = e.versTentative();
      expect(t['mode'], 'examen');
      expect((t['reponses'] as List).length, 4, reason: 'une question sans réponse compte zéro');
    });

    test('temps écoulé : remise automatique', () {
      final e = SessionExamen(id: 'x2', ficheId: 'f1', dureeLimiteS: 60, commenceLe: debut, questions: [vf('a')]);
      expect(e.tempsEcoule(debut.add(const Duration(seconds: 59))), isFalse);
      expect(e.tempsEcoule(debut.add(const Duration(seconds: 60))), isTrue);
      expect(chrono(3725), '1:02:05');
      expect(chrono(65), '01:05');
    });
  });

  group('classement de la semaine', () {
    test('encouragement : écart à combler, jamais de honte', () {
      final c = ClassementRevision.depuisJson({
        'actif': true,
        'lignes': [
          {'rang': 1, 'nom': 'Moussa D.', 'points': 180},
          {'rang': 2, 'nom': 'Awa B.', 'points': 70, 'moi': true},
        ],
        'mon_rang': 2,
        'participants': 2,
        'mes_points': 70,
      });
      expect(c.encouragement(), 'Encore 110 points pour rattraper Moussa D. : un quiz terminé en rapporte 50.');
      expect(const ClassementRevision(actif: true, monRang: 1).encouragement(), contains('en tête'));
      expect(const ClassementRevision(actif: true, visible: false).encouragement(), contains('comptent quand même'));
    });
  });

  group('lecture à voix haute', () {
    test('texte prononçable', () {
      expect(texteALire('La moitié de 8 est [[1]].'), 'La moitié de 8 est blanc .');
      expect(texteALire('« Fractions » : 40 %'), 'Fractions : 40 pour cent');
      final c = ContenuQuestion.depuisJson({
        'type': 'qcm_simple',
        'enonce': 'Capitale ?',
        'contenu': {
          'choix': [
            {'id': 'a', 'texte': 'Conakry'},
            {'id': 'b', 'texte': 'Kindia'},
          ],
        },
        'reponse': {
          'bonnes': ['a'],
        },
      });
      expect(texteQuestionALire(c), 'Capitale ?. Conakry. Kindia');
    });
  });

  testWidgets('écran d’examen : chrono, retour en arrière, remise, correction', (tester) async {
    final depot = _FauxDepot();
    var maintenant = debut;
    final examen = SessionExamen(
      id: 'x3',
      ficheId: 'f1',
      dureeLimiteS: 300,
      commenceLe: debut,
      questions: [vf('a'), vf('b', valeur: false)],
    );
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        revisionRepositoryProvider.overrideWithValue(depot),
        lecteurVocalProvider.overrideWithValue(_FauxLecteur()),
      ],
      child: MaterialApp(
        home: EcranExamen(
          examen: examen,
          competences: const {'k1': 'Logique'},
          maintenant: () => maintenant,
          hasard: Random(1),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('05:00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('vf_true')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('examen_suivante')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('vf_true'))); // fausse
    await tester.pump();
    // Retour en arrière : la première réponse est gardée, rien n'est corrigé.
    await tester.tap(find.byKey(const Key('examen_precedente')));
    await tester.pump();
    expect(find.textContaining('Bonne réponse'), findsNothing);

    maintenant = debut.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('03:00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('examen_suivante')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('examen_remettre')));
    // Le chronomètre tourne encore : pas de pumpAndSettle avant la remise.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('examen_confirmer_remise')));
    await tester.pumpAndSettle();

    expect(find.text('10 / 20'), findsOneWidget);
    expect(find.textContaining('Bonne réponse : Faux'), findsOneWidget);
    expect(depot.examens.single.justes, 1);
  });

  testWidgets('temps écoulé : copie remise automatiquement', (tester) async {
    final depot = _FauxDepot();
    var maintenant = debut;
    await tester.pumpWidget(ProviderScope(
      overrides: [revisionRepositoryProvider.overrideWithValue(depot)],
      child: MaterialApp(
        home: EcranExamen(
          examen: SessionExamen(id: 'x4', ficheId: 'f1', dureeLimiteS: 60, commenceLe: debut, questions: [vf('a')]),
          maintenant: () => maintenant,
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('vf_true')));
    await tester.pump();
    maintenant = debut.add(const Duration(seconds: 61));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('examen_remise_auto')), findsOneWidget);
    expect(find.text('20 / 20'), findsOneWidget);
    expect(depot.examens.single.remiseAutomatique, isTrue);
  });
}
