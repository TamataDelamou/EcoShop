import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/comptabilite/application/comptabilite_providers.dart';
import 'package:ecoshop_client/features/comptabilite/application/referentiel_comptable_providers.dart';
import 'package:ecoshop_client/features/comptabilite/domain/changement_plan.dart';
import 'package:ecoshop_client/features/comptabilite/domain/plan_comptable.dart';
import 'package:ecoshop_client/features/comptabilite/domain/referentiel_comptable.dart';
import 'package:ecoshop_client/features/comptabilite/presentation/ecran_changement_plan.dart';

/// Réponse serveur reproduisant tests/rls/70 (SYSCOHADA → SYCEBNL au 1/1/2027).
Map<String, dynamic> _json({String cible5711 = '571', String origine5711 = 'rattachement', bool verifier5711 = true}) => {
      'id': 'ch1',
      'statut': 'brouillon',
      'ancien_referentiel': 'syscohada_normal',
      'nouveau_referentiel': 'sycebnl',
      'date_effet': '2027-01-01',
      'exercice': 'Exercice 2027',
      'a_completer': 0,
      'a_verifier': verifier5711 ? 3 : 2,
      'lignes': [
        {'ancien_compte_id': 'a101', 'ancien_code': '101', 'ancien_intitule': 'Capital social', 'solde': -1000000,
         'code_cible': '101', 'intitule_cible': 'Dotation non consomptible sans droit de reprise', 'origine': 'meme_numero', 'a_verifier': true},
        {'ancien_compte_id': 'a5711', 'ancien_code': '5711', 'ancien_intitule': 'Caisse secrétariat', 'solde': 100000,
         'code_cible': cible5711, 'intitule_cible': cible5711 == '571' ? 'Caisse siège' : 'Caisse secrétariat',
         'origine': origine5711, 'a_verifier': verifier5711},
        {'ancien_compte_id': 'a70611', 'ancien_code': '70611', 'ancien_intitule': 'Frais de scolarité', 'solde': 0,
         'code_cible': '70521', 'intitule_cible': 'Frais de scolarité', 'origine': 'table', 'a_verifier': true},
        {'ancien_compte_id': 'a422', 'ancien_code': '422', 'ancien_intitule': 'Personnel, rémunérations dues', 'solde': 0,
         'code_cible': '422', 'intitule_cible': 'Personnel, rémunérations dues', 'origine': 'identique', 'a_verifier': false},
      ],
    };

class _FauxChangement implements ChangementPlanRepository {
  final List<({String compte, String? code})> definitions = [];
  int applications = 0;

  @override
  Future<ChangementPlan> proposer(String etablissementId, ReferentielComptable cible, FormeJuridique? forme) async =>
      ChangementPlan.depuisJson(_json());

  @override
  Future<ChangementPlan> definir(String changementId, String ancienCompteId, String? codeCible) async {
    definitions.add((compte: ancienCompteId, code: codeCible));
    return ChangementPlan.depuisJson(_json(cible5711: codeCible ?? '571', origine5711: 'manuel', verifier5711: false));
  }

  @override
  Future<ResultatChangementPlan> appliquer(String changementId) async {
    applications++;
    return const ResultatChangementPlan(comptesCharges: 105, comptesRetires: 117, exercicesArchives: 1);
  }

  @override
  Future<void> abandonner(String changementId) async {}

  @override
  Future<List<CompteCible>> comptesCibles(ReferentielComptable referentiel) async => const [
        CompteCible(code: '571', intitule: 'Caisse siège'),
        CompteCible(code: '5521', intitule: 'Orange Money'),
      ];
}

Future<_FauxChangement> _monter(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final depot = _FauxChangement();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      changementPlanRepositoryProvider.overrideWithValue(depot),
      planComptableProvider.overrideWith((ref, etab) async => const <PlanComptable>[]),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(
                builder: (_) => const EcranChangementPlan(etablissementId: 'e1', cible: ReferentielComptable.sycebnl),
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

void main() {
  test('lecture : origine, lignes à vérifier, applicable', () {
    final c = ChangementPlan.depuisJson(_json());
    expect(c.nouveau, ReferentielComptable.sycebnl);
    expect(c.lignes.first.origine, OrigineCorrespondance.memeNumero);
    expect(c.applicable, isTrue);
    expect(const ErreurChangementPlan('EXERCICE_VIERGE_REQUIS').messageUtilisateur, contains('premier jour'));
  });

  testWidgets('table de correspondance : sous-compte gardé, puis application confirmée', (tester) async {
    final depot = await _monter(tester);

    expect(find.byKey(const Key('date_effet_changement')), findsOneWidget);
    expect(find.text('3 à vérifier'), findsOneWidget);
    expect(find.textContaining('→ 70521'), findsOneWidget);

    await tester.tap(find.byKey(const Key('correspondance_5711')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('recherche_cible')), '5711');
    await tester.pump();
    await tester.tap(find.byKey(const Key('cible_sous_compte')));
    await tester.pumpAndSettle();

    expect(depot.definitions.single, (compte: 'a5711', code: '5711'));
    expect(find.text('2 à vérifier'), findsOneWidget);

    await tester.tap(find.byKey(const Key('appliquer_changement_plan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmer_changement_plan')));
    await tester.pumpAndSettle();

    expect(depot.applications, 1);
    expect(find.textContaining('105 comptes installés'), findsOneWidget);
  });
}
