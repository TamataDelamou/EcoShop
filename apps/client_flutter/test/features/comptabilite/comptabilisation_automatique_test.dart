import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/comptabilite/application/comptabilite_providers.dart';
import 'package:ecoshop_client/features/comptabilite/application/pieces_comptables_providers.dart';
import 'package:ecoshop_client/features/comptabilite/domain/comptabilisation_automatique.dart';
import 'package:ecoshop_client/features/comptabilite/domain/enums_comptabilite.dart';
import 'package:ecoshop_client/features/comptabilite/domain/plan_comptable.dart';
import 'package:ecoshop_client/features/comptabilite/presentation/ecran_comptabilisation_automatique.dart';

/// Faux port — création des pièces, idempotence, contre-passation des
/// annulations et incidents sont vérifiés côté base (tests/rls/65 et 67).
class _FauxDepot implements ComptabilisationAutomatiqueRepository {
  _FauxDepot(this.etatCourant);

  EtatComptabilisationAutomatique etatCourant;
  int rattrapages = 0;
  final List<({String cle, String? compteId})> regles = [];

  @override
  Future<EtatComptabilisationAutomatique> etat(String etablissementId) async => etatCourant;

  @override
  Future<({int comptabilises, int enEchec})> rattraper(String etablissementId) async {
    rattrapages++;
    etatCourant = EtatComptabilisationAutomatique(
      active: true,
      nonComptabilises: 0,
      annulationsEnAttente: 0,
      regles: etatCourant.regles,
    );
    return (comptabilises: 2, enEchec: 0);
  }

  @override
  Future<void> definirRegle(String etablissementId, String cle, String? compteId) async {
    regles.add((cle: cle, compteId: compteId));
  }
}

final _etatEnRetard = EtatComptabilisationAutomatique.depuisJson({
  'active': true,
  'non_comptabilises': 2,
  'annulations_en_attente': 0,
  'incidents': [
    {'id': 'i1', 'source_id': 's1', 'operation': 'comptabilisation', 'code': 'AUCUN_EXERCICE_OUVERT', 'le': '2026-10-05T10:00:00Z'},
  ],
  'regles': [
    {'cle': 'tresorerie:especes', 'compte_id': 'c571', 'compte_code': '571', 'compte_intitule': 'Caisse siège', 'personnalisee': false},
    {'cle': 'tresorerie:mobile_money', 'compte_id': 'c5521', 'compte_code': '5521', 'compte_intitule': 'Orange Money', 'personnalisee': false},
    {'cle': 'produit:scolarite', 'compte_id': 'c70521', 'compte_code': '70521', 'compte_intitule': 'Frais de scolarité', 'personnalisee': false},
  ],
});

Future<void> _monter(WidgetTester tester, _FauxDepot depot) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      comptabilisationAutomatiqueRepositoryProvider.overrideWithValue(depot),
      planComptableProvider.overrideWith((ref, etab) async => const [
            PlanComptable(id: 'c57', etablissementId: 'e1', code: '57', intitule: 'Caisse', type: TypeCompte.caisse, reglementaire: true),
            PlanComptable(id: 'c571', etablissementId: 'e1', code: '571', intitule: 'Caisse siège', type: TypeCompte.caisse, parentId: 'c57', reglementaire: true),
            PlanComptable(id: 'c5711', etablissementId: 'e1', code: '5711', intitule: 'Caisse secrétariat', type: TypeCompte.caisse, parentId: 'c571'),
          ]),
    ],
    child: const MaterialApp(home: EcranComptabilisationAutomatique(etablissementId: 'e1')),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('incident expliqué simplement', () {
    expect(_etatEnRetard.incidents.single.explication, contains('ouvrez l\'exercice'));
    expect(_etatEnRetard.aJour, isFalse);
    expect(_etatEnRetard.regles[1].libelle, 'Orange Money');
  });

  testWidgets('paiements en attente : rattrapage puis état à jour', (tester) async {
    final depot = _FauxDepot(_etatEnRetard);
    await _monter(tester, depot);

    expect(find.text('2 paiement(s) non comptabilisé(s)'), findsOneWidget);
    expect(find.textContaining('Aucun exercice ouvert'), findsOneWidget);
    expect(find.text('5521 — Orange Money'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bouton_rattraper')));
    await tester.pumpAndSettle();

    expect(depot.rattrapages, 1);
    expect(find.text('Paiements et paie sont à jour en comptabilité.'), findsOneWidget);
  });

  testWidgets('l\'école choisit un compte de détail pour les espèces', (tester) async {
    final depot = _FauxDepot(_etatEnRetard);
    await _monter(tester, depot);

    await tester.tap(find.byKey(const Key('regle_tresorerie:especes')));
    await tester.pumpAndSettle();
    // « 57 » et « 571 » regroupent d'autres comptes : seul 5711 est proposé.
    expect(find.byKey(const Key('choix_compte_57')), findsNothing);
    expect(find.byKey(const Key('choix_compte_571')), findsNothing);
    await tester.tap(find.byKey(const Key('choix_compte_5711')));
    await tester.pumpAndSettle();

    expect(depot.regles.single, (cle: 'tresorerie:especes', compteId: 'c5711'));
  });

  testWidgets('paie : bulletins à reporter, incident expliqué, comptes de paie à part', (tester) async {
    final depot = _FauxDepot(EtatComptabilisationAutomatique.depuisJson({
      'active': true,
      'non_comptabilises': 0,
      'annulations_en_attente': 0,
      'paies_a_synchroniser': 3,
      'incidents': [
        {
          'id': 'i2',
          'source_id': 'b1',
          'source_type': 'paie_bulletin',
          'operation': 'comptabilisation',
          'code': 'AUCUN_EXERCICE_OUVERT',
          'le': '2026-10-05T10:00:00Z',
        },
      ],
      'regles': [
        {'cle': 'produit:scolarite', 'compte_id': 'c70521', 'compte_code': '70521', 'compte_intitule': 'Frais de scolarité'},
        {'cle': 'paie:charge', 'compte_id': 'c661', 'compte_code': '661', 'compte_intitule': 'Rémunérations directes'},
        {'cle': 'paie:retenues', 'compte_id': 'c447', 'compte_code': '447', 'compte_intitule': 'État, impôts retenus'},
      ],
    }));
    await _monter(tester, depot);

    expect(find.byKey(const Key('paies_a_synchroniser')), findsOneWidget);
    expect(find.textContaining('date du bulletin de paie'), findsOneWidget);
    expect(find.textContaining('Bulletin de paie ·'), findsOneWidget);
    expect(find.text('Comptes utilisés — paie'), findsOneWidget);
    expect(find.text('Salaires (charge)'), findsOneWidget);
    expect(find.text('661 — Rémunérations directes'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bouton_rattraper')));
    await tester.pumpAndSettle();
    expect(find.text('2 opération(s) comptabilisée(s).'), findsOneWidget);
  });
}
