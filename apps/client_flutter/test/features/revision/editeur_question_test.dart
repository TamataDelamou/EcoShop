import 'dart:typed_data';

import 'package:ecoshop_client/features/revision/application/banque_providers.dart';
import 'package:ecoshop_client/features/revision/data/banque_questions_repository.dart';
import 'package:ecoshop_client/features/revision/domain/question.dart';
import 'package:ecoshop_client/features/revision/presentation/ecran_editeur_question.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FausseBanque extends Fake implements BanqueQuestionsRepository {
  final enregistrees = <String, ContenuQuestion>{};
  final actions = <String>[];
  StatutContenu statut = StatutContenu.brouillon;
  bool horsLigne = false;

  @override
  Future<bool> enregistrer(String id, String matiereId, ContenuQuestion c, {bool petitesClasses = false}) async {
    final erreur = c.erreur(petitesClasses: petitesClasses);
    if (erreur != null) throw ErreurBanque(erreur);
    enregistrees[id] = c;
    return !horsLigne;
  }

  @override
  Future<List<Question>> questions(String matiereId) async => [
        for (final e in enregistrees.entries)
          Question(id: e.key, matiereId: matiereId, statut: statut, versionTravail: 1, travail: e.value),
      ];

  @override
  Future<void> changerStatut(String id, String action, {String? remarque}) async {
    actions.add(action);
    statut = switch (action) {
      'soumettre' => StatutContenu.revision,
      'valider' => StatutContenu.validee,
      'publier' => StatutContenu.publiee,
      _ => StatutContenu.brouillon,
    };
  }

  @override
  Future<String> envoyerMedia(String questionId, Uint8List octets, String extension) async => 'x.$extension';
}

const _structure = StructureMatiere(
  competences: [Competence(id: 'k1', code: 'FRAC-1', libelle: 'Simplifier une fraction')],
  chapitres: [ChapitreMatiere(id: 'ch1', titre: 'Fractions', ordre: 1)],
);

void main() {
  Future<void> monter(WidgetTester tester, _FausseBanque banque, {bool petitesClasses = false}) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        banqueQuestionsRepositoryProvider.overrideWithValue(banque),
        structureMatiereProvider('m1').overrideWith((ref) async => _structure),
        questionsMatiereProvider('m1').overrideWith((ref) async => const []),
        questionsATraiterProvider.overrideWith((ref) async => const []),
        questionsSignaleesProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(
        home: EcranEditeurQuestion(matiereId: 'm1', titreMatiere: 'Guinée · 7e · Maths', petitesClasses: petitesClasses),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> choisirCompetence(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('question_competence')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FRAC-1 — Simplifier une fraction').last);
    await tester.pumpAndSettle();
  }

  testWidgets('QCM : saisie, aperçu de la bonne réponse, enregistrement puis circuit', (tester) async {
    final banque = _FausseBanque();
    await monter(tester, banque);

    await choisirCompetence(tester);
    await tester.enterText(find.byKey(const Key('question_enonce')), 'Simplifier 2/4');
    await tester.enterText(find.byKey(const ValueKey('choix_c1')), '1/2');
    await tester.enterText(find.byKey(const ValueKey('choix_c2')), '2/2');
    await tester.enterText(find.byKey(const ValueKey('choix_c3')), '1/4');
    await tester.enterText(find.byKey(const Key('question_explication')), 'On divise haut et bas par 2.');
    await tester.pump();
    expect(find.text('Bonne réponse : 1/2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('question_enregistrer')));
    await tester.pumpAndSettle();
    final q = banque.enregistrees.values.single;
    expect(q.reponse, {'bonnes': ['c1']});
    expect(q.competenceId, 'k1');

    await tester.tap(find.byKey(const Key('question_soumettre')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('question_valider')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('question_publier')));
    await tester.pumpAndSettle();
    expect(banque.actions, ['soumettre', 'valider', 'publier']);
    expect(find.textContaining('nouvelle version'), findsOneWidget);
  });

  testWidgets('sans compétence : message clair, rien n’est envoyé', (tester) async {
    final banque = _FausseBanque();
    await monter(tester, banque);
    await tester.enterText(find.byKey(const Key('question_enonce')), 'Q');
    await tester.tap(find.byKey(const Key('question_enregistrer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('question_erreur')), findsOneWidget);
    expect(banque.enregistrees, isEmpty);
  });

  testWidgets('texte à trous : un champ par trou inséré', (tester) async {
    final banque = _FausseBanque()..horsLigne = true;
    await monter(tester, banque);
    await tester.tap(find.byKey(const Key('question_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Texte à trous').last);
    await tester.pumpAndSettle();
    await choisirCompetence(tester);
    await tester.enterText(find.byKey(const Key('question_enonce')), 'La moitié de 8 est ');
    await tester.tap(find.byKey(const Key('inserer_trou')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('trou_1')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('trou_1')), '4 / quatre');
    await tester.enterText(find.byKey(const Key('question_explication')), '8 divisé par 2.');
    await tester.tap(find.byKey(const Key('question_enregistrer')));
    await tester.pumpAndSettle();
    expect(banque.enregistrees.values.single.reponse, {
      'trous': {'1': ['4', 'quatre']},
    });
    expect(find.textContaining('gardé sur l’appareil'), findsOneWidget);
  });

  testWidgets('petites classes : seuls les types adaptés sont proposés', (tester) async {
    await monter(tester, _FausseBanque(), petitesClasses: true);
    await tester.tap(find.byKey(const Key('question_type')));
    await tester.pumpAndSettle();
    expect(find.text('Réponse courte'), findsNothing);
    expect(find.text('Classement'), findsWidgets);
  });
}
