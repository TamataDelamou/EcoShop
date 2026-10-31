import 'package:ecoshop_client/features/revision/application/concours_providers.dart';
import 'package:ecoshop_client/features/revision/data/concours_repository.dart';
import 'package:ecoshop_client/features/revision/domain/concours.dart';
import 'package:ecoshop_client/features/revision/domain/quiz.dart';
import 'package:ecoshop_client/features/revision/presentation/ecran_concours.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime.utc(2026, 11, 2, 10);

Map<String, dynamic> question(String id) => {
      'id': id,
      'matiere_id': 'math',
      'version': 1,
      'type': 'vrai_faux',
      'difficulte': 'moyen',
      'competence_id': 'k',
      'enonce': 'Énoncé $id',
      'contenu': const <String, dynamic>{},
      'reponse': const <String, dynamic>{},
      'explication': '',
    };

Map<String, dynamic> concoursJson({bool inscrit = true, bool remise = false, String? certificat}) => {
      'id': 'c1',
      'titre': 'Olympiade ouest-africaine',
      'type': 'olympiade',
      'organisateur': 'Global Service Groupe',
      'international': true,
      'pays_code': null,
      'statut': 'ouvert',
      'inscription_jusquau': null,
      'inscrit': inscrit,
      'certificat': certificat,
      'manches': [
        {
          'id': 'm1',
          'ordre': 1,
          'titre': 'Première manche',
          'ouverture': t0.subtract(const Duration(hours: 1)).toIso8601String(),
          'fermeture': t0.add(const Duration(days: 1)).toIso8601String(),
          'duree_min': 30,
          'questions': 2,
          'commencee': false,
          'remise': remise,
          'score': remise ? 2 : null,
          'hors_delai': false,
        },
      ],
    };

class _FauxDepot implements ConcoursRepository {
  _FauxDepot({this.horsLigne = false});

  final bool horsLigne;
  Map<String, Object?>? remis;

  @override
  Future<SujetManche> commencer(String mancheId, String ficheId) async {
    if (horsLigne) throw const ErreurConcours('HORS_LIGNE');
    return SujetManche.depuisJson({
      'commence_le': t0.toIso8601String(),
      'limite': t0.add(const Duration(minutes: 30)).toIso8601String(),
      'questions': [question('q1'), question('q2')],
    });
  }

  @override
  Future<ResultatManche> remettre(String mancheId, String ficheId, Map<String, Object?> reponses, int nb) async {
    remis = reponses;
    return ResultatManche.depuisJson({
      'score': 1,
      'questions': 2,
      'correction': [
        {'question_id': 'q1', 'score': 1, 'reponse': {'valeur': true}, 'explication': 'Bravo'},
        {'question_id': 'q2', 'score': 0, 'reponse': {'valeur': false}, 'explication': 'C’était faux.'},
      ],
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('domaine des concours', () {
    test('manche à jouer : ouverte et pas encore remise', () {
      final c = Concours.depuisJson(concoursJson());
      expect(c.international, isTrue);
      expect(c.type, TypeConcours.olympiade);
      expect(c.mancheAJouer(t0)?.id, 'm1');
      expect(c.mancheAJouer(t0.add(const Duration(days: 2))), isNull, reason: 'manche fermée');
      expect(Concours.depuisJson(concoursJson(remise: true)).mancheAJouer(t0), isNull);
    });

    test('variantes : chaque groupe de questions forme un emplacement', () {
      final e = emplacementsDepuis(['a', 'b', 'c', 'd', 'e'], variantes: 2);
      expect([for (final x in e) x['emplacement']], [1, 1, 2, 2, 3]);
      expect(emplacementsDepuis(['a'], variantes: 9).single['emplacement'], 1);
    });

    test('la correction du serveur rend la bonne réponse affichable', () {
      final r = ResultatManche.depuisJson({
        'score': 0,
        'questions': 1,
        'correction': [
          {'question_id': 'q1', 'score': 0, 'reponse': {'valeur': true}, 'explication': 'Voilà.'},
        ],
      });
      final c = r.contenuCorrige(QuestionQuiz.depuisJson(question('q1')))!;
      expect(c.explication, 'Voilà.');
      expect(c.reponse, {'valeur': true});
    });

    test('classement : pays et école de l’élève pour les filtres', () {
      final c = ClassementConcours.depuisJson({
        'participants': 2,
        'mon_pays': 'SN',
        'mon_etablissement': 'e1',
        'lignes': [
          {'rang': 1, 'nom': 'Awa B.', 'score': 2, 'pays': 'GN', 'moi': false},
          {'rang': 2, 'nom': 'Fatou N.', 'score': 0, 'pays': 'SN', 'moi': true},
        ],
      });
      expect(c.monPays, 'SN');
      expect(c.lignes.last.moi, isTrue);
    });

    test('erreurs en mots simples', () {
      expect(const ErreurConcours('NON_INSCRIT').message, contains('Inscris-toi'));
      expect(const ErreurConcours('INCONNU').message, contains('Réessayez'));
    });
  });

  group('écrans', () {
    testWidgets('la carte annonce une manche à jouer', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [concoursEleveProvider('f1').overrideWith((ref) async => [Concours.depuisJson(concoursJson())])],
        child: MaterialApp(
          home: Scaffold(body: CarteConcours(ficheId: 'f1', prenom: 'Awa', parent: false, maintenant: () => t0)),
        ),
      ));
      await tester.pump();
      expect(find.text('1 manche à jouer maintenant'), findsOneWidget);
    });

    testWidgets('le certificat se montre avec son code vérifiable', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          concoursEleveProvider('f1')
              .overrideWith((ref) async => [Concours.depuisJson(concoursJson(remise: true, certificat: 'GSG-AB12-CD34-EF56'))]),
        ],
        child: MaterialApp(home: EcranConcours(ficheId: 'f1', prenom: 'Awa', parent: false, maintenant: () => t0)),
      ));
      await tester.pump();
      expect(find.text('GSG-AB12-CD34-EF56'), findsOneWidget);
      expect(find.byKey(const Key('concours_classement_c1')), findsOneWidget);
    });

    testWidgets('manche : remise, puis correction du serveur', (tester) async {
      final depot = _FauxDepot();
      final c = Concours.depuisJson(concoursJson());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          concoursRepositoryProvider.overrideWithValue(depot),
          concoursEleveProvider('f1').overrideWith((ref) async => [c]),
        ],
        child: MaterialApp(
          home: EcranMancheConcours(ficheId: 'f1', concours: c, manche: c.manches.single, maintenant: () => t0),
        ),
      ));
      await tester.pump();
      expect(find.text('30:00'), findsOneWidget);
      expect(find.text('Énoncé q1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('manche_suivante')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('manche_remettre')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('manche_confirmer')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(depot.remis, isNotNull);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.textContaining('C’était faux.'), findsOneWidget);
    });

    testWidgets('manche : copie ramassée à la fin du temps', (tester) async {
      final depot = _FauxDepot();
      final c = Concours.depuisJson(concoursJson());
      var maintenant = t0;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          concoursRepositoryProvider.overrideWithValue(depot),
          concoursEleveProvider('f1').overrideWith((ref) async => [c]),
        ],
        child: MaterialApp(
          home: EcranMancheConcours(ficheId: 'f1', concours: c, manche: c.manches.single, maintenant: () => maintenant),
        ),
      ));
      await tester.pump();
      maintenant = t0.add(const Duration(minutes: 31));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(depot.remis, isNotNull);
      expect(find.byKey(const Key('manche_score')), findsOneWidget);
    });

    testWidgets('manche sans réseau : message et nouvel essai', (tester) async {
      final c = Concours.depuisJson(concoursJson());
      await tester.pumpWidget(ProviderScope(
        overrides: [concoursRepositoryProvider.overrideWithValue(_FauxDepot(horsLigne: true))],
        child: MaterialApp(home: EcranMancheConcours(ficheId: 'f1', concours: c, manche: c.manches.single)),
      ));
      await tester.pump();
      expect(find.byKey(const Key('manche_erreur')), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });
  });
}
