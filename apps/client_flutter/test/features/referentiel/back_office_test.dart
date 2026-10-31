import 'package:ecoshop_client/features/referentiel/back_office/ecran_back_office_referentiel.dart';
import 'package:ecoshop_client/features/referentiel/back_office/referentiel_back_office.dart';
import 'package:ecoshop_client/features/referentiel/back_office/referentiel_back_office_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> referentielTogo({String? points = 'Le BAC I est-il maintenu ?', bool bloquant = true}) => {
      'pays': {
        'code_iso': 'TG',
        'nom': 'Togo',
        'type_systeme': 'francophone_cfa',
        'langue_enseignement_principale': 'fr',
        'organisme_examinateur': 'DECC',
        'devise_code': 'XOF',
        'zone': 'cedeao',
        'sources': 'Calendrier officiel 2023-2024',
        'points_a_verifier': points,
        'statut_deploiement': 'brouillon',
      },
      'controle': [
        if (bloquant) {'bloquant': true, 'message': 'Des points restent à vérifier sur les textes officiels.'},
        {'bloquant': false, 'message': 'Aucun programme national.'},
      ],
      'cycles': [
        {
          'id': 'c1',
          'code': 'primaire',
          'nom': 'Primaire',
          'ordre': 1,
          'isced_min': 1,
          'isced_max': 1,
          'statut': 'brouillon',
          'niveaux': [
            {'id': 'n1', 'code': 'CP1', 'nom': 'CP1', 'grade': 1, 'isced': 1, 'ordre': 1, 'statut': 'brouillon', 'programmes': []},
            {
              'id': 'n6',
              'code': 'CM2',
              'nom': 'CM2',
              'grade': 6,
              'isced': 1,
              'ordre': 6,
              'examinateur': true,
              'statut': 'brouillon',
              'programmes': [
                {
                  'id': 'p1',
                  'nom': 'Programme national · CM2',
                  'statut': 'brouillon',
                  'matieres': [
                    {'id': 'm1', 'code': 'MATH', 'nom': 'Mathématiques', 'questions': 3},
                  ],
                },
              ],
            },
          ],
        },
      ],
      'examens': [
        {'id': 'e1', 'code': 'CEPD', 'nom': 'Certificat d’Études du Premier Degré', 'mois': 6, 'cycle_id': 'c1', 'statut': 'brouillon'},
      ],
      'series': [],
    };

void main() {
  group('domaine', () {
    test('lecture d’un pays, rang proposé, brouillons, publication bloquée', () {
      final r = ReferentielPays.depuisJson(referentielTogo());
      expect(r.pays.zone, ZonePays.cedeao);
      expect(r.niveaux.length, 2);
      expect(r.prochainRang, 7);
      expect(r.brouillons, 4, reason: '1 cycle, 2 niveaux, 1 examen');
      expect(r.publiable, isFalse);
      expect(r.nomCycle('c1'), 'Primaire');
      expect(r.niveaux.last.programmes.single.matieres.single.questions, 3);
      expect(ReferentielPays.depuisJson(referentielTogo(points: null, bloquant: false)).publiable, isTrue);
    });

    test('liste des pays : zones et compteurs', () {
      final l = PaysBackOffice.liste([
        {'code': 'ML', 'nom': 'Mali', 'zone': 'aes', 'statut': 'brouillon', 'a_verifier': true, 'niveaux': 12},
        {'code': 'GN', 'nom': 'Guinée', 'zone': 'cedeao', 'statut': 'deploye', 'niveaux': 16},
      ]);
      expect(l.first.zone, ZonePays.aes);
      expect(l.first.aVerifier, isTrue);
      expect(l.last.publie, isTrue);
    });
  });

  group('écrans', () {
    testWidgets('pays en brouillon : points à vérifier, publication bloquée', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          referentielPaysProvider('TG').overrideWith((ref) async => ReferentielPays.depuisJson(referentielTogo())),
        ],
        child: const MaterialApp(home: EcranPaysBackOffice(code: 'TG')),
      ));
      await tester.pump();
      expect(find.byKey(const Key('bo_points_a_verifier')), findsOneWidget);
      expect(find.textContaining('BAC I est-il maintenu'), findsOneWidget);
      final bouton = tester.widget<ButtonStyleButton>(
        find.descendant(of: find.byKey(const Key('bo_publier_pays')), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
      );
      expect(bouton.onPressed, isNull);
      expect(find.text('CEPD · Certificat d’Études du Premier Degré'), findsOneWidget);
    });

    testWidgets('points levés : le pays se publie', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          referentielPaysProvider('TG')
              .overrideWith((ref) async => ReferentielPays.depuisJson(referentielTogo(points: null, bloquant: false))),
        ],
        child: const MaterialApp(home: EcranPaysBackOffice(code: 'TG')),
      ));
      await tester.pump();
      final bouton = tester.widget<ButtonStyleButton>(
        find.descendant(of: find.byKey(const Key('bo_publier_pays')), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
      );
      expect(bouton.onPressed, isNotNull);
    });

    testWidgets('liste rangée par zone', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          paysBackOfficeProvider.overrideWith((ref) async => PaysBackOffice.liste([
                {'code': 'GN', 'nom': 'Guinée', 'zone': 'cedeao', 'statut': 'deploye'},
                {'code': 'ML', 'nom': 'Mali', 'zone': 'aes', 'statut': 'brouillon', 'a_verifier': true},
              ])),
        ],
        child: const MaterialApp(home: EcranBackOfficeReferentiel()),
      ));
      await tester.pump();
      expect(find.text('CEDEAO'), findsOneWidget);
      expect(find.text('AES (MALI, BURKINA FASO, NIGER)'), findsOneWidget);
      expect(find.text('À vérifier'), findsOneWidget);
    });

    testWidgets('programme national : matières et banque', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          referentielPaysProvider('TG').overrideWith((ref) async => ReferentielPays.depuisJson(referentielTogo())),
        ],
        child: const MaterialApp(home: EcranProgrammeNational(pays: 'TG', niveauId: 'n6')),
      ));
      await tester.pump();
      expect(find.text('MATH · Mathématiques'), findsOneWidget);
      expect(find.textContaining('Publiez d’abord le pays'), findsOneWidget);
    });
  });
}
