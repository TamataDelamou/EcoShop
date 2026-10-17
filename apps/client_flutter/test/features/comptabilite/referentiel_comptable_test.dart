import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/comptabilite/application/referentiel_comptable_providers.dart';
import 'package:ecoshop_client/features/comptabilite/domain/enums_comptabilite.dart';
import 'package:ecoshop_client/features/comptabilite/domain/plan_comptable.dart';
import 'package:ecoshop_client/features/comptabilite/domain/referentiel_comptable.dart';
import 'package:ecoshop_client/features/comptabilite/presentation/ecran_referentiel_comptable.dart';

/// Faux port — la recommandation, les droits, le chargement du plan et les
/// verrous sont vérifiés côté base (tests/rls/63).
class _FauxDepot implements ReferentielComptableRepository {
  ParametresComptables actuel = ParametresComptables.parDefaut;
  final List<({ReferentielComptable referentiel, FormeJuridique? forme, double? ca})> choix = [];
  ({FormeJuridique forme, double? ca, String devise, bool souhait})? derniereQuestion;
  String? erreurAuChoix;

  @override
  Future<ParametresComptables> parametres(String etablissementId) async => actuel;

  @override
  Future<RecommandationReferentiel> recommander({
    required FormeJuridique formeJuridique,
    double? chiffreAffaires,
    required String devise,
    required bool souhaitReglementaire,
  }) async {
    derniereQuestion = (forme: formeJuridique, ca: chiffreAffaires, devise: devise, souhait: souhaitReglementaire);
    return switch (formeJuridique) {
      FormeJuridique.confessionnelle => const RecommandationReferentiel(
          referentiel: ReferentielComptable.sycebnl,
          raison: 'Les organisations confessionnelles relèvent du SYCEBNL.',
          alternatives: [ReferentielComptable.simplifie],
          seuilSmt: 450000000,
          seuilDevise: 'GNF',
        ),
      _ => const RecommandationReferentiel(
          referentiel: ReferentielComptable.syscohadaSmt,
          raison: 'Sous le seuil du SMT.',
          alternatives: [ReferentielComptable.syscohadaNormal, ReferentielComptable.simplifie],
          seuilSmt: 450000000,
          seuilDevise: 'GNF',
        ),
    };
  }

  @override
  Future<ResultatChoixReferentiel> choisir({
    required String etablissementId,
    required ReferentielComptable referentiel,
    FormeJuridique? formeJuridique,
    double? chiffreAffaires,
  }) async {
    if (erreurAuChoix != null) throw ErreurReferentielComptable(erreurAuChoix!);
    choix.add((referentiel: referentiel, forme: formeJuridique, ca: chiffreAffaires));
    actuel = ParametresComptables(referentiel: referentiel, formeJuridique: formeJuridique, choisiLe: DateTime(2026, 10, 17));
    return ResultatChoixReferentiel(referentiel: referentiel, comptesCharges: 88);
  }
}

Future<void> _monter(WidgetTester tester, _FauxDepot depot) async {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [referentielComptableRepositoryProvider.overrideWithValue(depot)],
      child: const MaterialApp(home: EcranReferentielComptable(etablissementId: 'e1', devise: 'GNF')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('domaine', () {
    test('codes serveur ↔ référentiels, simplifié par défaut', () {
      expect(ReferentielComptable.depuisCode('syscohada_smt'), ReferentielComptable.syscohadaSmt);
      expect(ReferentielComptable.depuisCode('sycebnl'), ReferentielComptable.sycebnl);
      expect(ReferentielComptable.depuisCode(null), ReferentielComptable.simplifie);
      expect(ReferentielComptable.simplifie.estReglementaire, isFalse);
      expect(ReferentielComptable.syscohadaNormal.estReglementaire, isTrue);
    });

    test('recommandation lue depuis la réponse du serveur', () {
      final r = RecommandationReferentiel.depuisJson({
        'referentiel': 'sycebnl',
        'raison': 'R',
        'alternatives': ['simplifie'],
        'seuil_smt': 450000000,
        'seuil_devise': 'GNF',
        'seuil_a_confirmer': true,
      });
      expect(r.referentiel, ReferentielComptable.sycebnl);
      expect(r.alternatives, [ReferentielComptable.simplifie]);
      expect(r.seuilAConfirmer, isTrue);
    });

    test('compte réglementaire relu depuis la base et conservé en cache', () {
      final compte = PlanComptable.depuisJson({
        'id': 'c1',
        'etablissement_id': 'e1',
        'code': '571',
        'intitule': 'Caisse siège',
        'type': 'caisse',
        'reglementaire': true,
      });
      expect(compte.reglementaire, isTrue);
      expect(PlanComptable.depuisJsonCache(compte.versJsonCache()).reglementaire, isTrue);
      // Jamais transmis à l'écriture : seul le serveur crée un compte réglementaire.
      expect(compte.versJsonEcriture().containsKey('reglementaire'), isFalse);
    });

    test('les natures actif / passif / capitaux ne retombent plus sur « autre »', () {
      expect(TypeCompte.depuisCode('actif'), TypeCompte.actif);
      expect(TypeCompte.depuisCode('passif'), TypeCompte.passif);
      expect(TypeCompte.depuisCode('capitaux'), TypeCompte.capitaux);
    });
  });

  testWidgets('école confessionnelle : SYCEBNL recommandé puis adopté par la Direction', (tester) async {
    final depot = _FauxDepot();
    await _monter(tester, depot);

    expect(find.text('Comptabilité simplifiée'), findsOneWidget);
    expect(find.text('Référentiel actuel (par défaut)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('forme_confessionnelle')));
    await tester.enterText(find.byKey(const Key('chiffre_affaires')), '300000000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('bouton_recommander')));
    await tester.pumpAndSettle();

    expect(depot.derniereQuestion?.ca, 300000000);
    expect(depot.derniereQuestion?.devise, 'GNF');
    expect(find.textContaining('Recommandé : SYCEBNL'), findsOneWidget);
    expect(find.textContaining('à confirmer par un expert-comptable'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bouton_adopter')));
    await tester.pumpAndSettle();
    expect(find.textContaining('plan de comptes réglementaire sera installé'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmer_referentiel')));
    await tester.pumpAndSettle();

    expect(depot.choix.single.referentiel, ReferentielComptable.sycebnl);
    expect(depot.choix.single.forme, FormeJuridique.confessionnelle);
    expect(find.textContaining('88 comptes installés'), findsOneWidget);
    expect(find.text('SYCEBNL — Entités à but non lucratif'), findsOneWidget);
  });

  testWidgets('la Direction peut retenir une alternative à la recommandation', (tester) async {
    final depot = _FauxDepot();
    await _monter(tester, depot);

    await tester.tap(find.byKey(const Key('forme_societe')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('bouton_recommander')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('option_syscohada_normal')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('bouton_adopter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmer_referentiel')));
    await tester.pumpAndSettle();

    expect(depot.choix.single.referentiel, ReferentielComptable.syscohadaNormal);
  });

  testWidgets('refus du serveur (écritures existantes) expliqué simplement', (tester) async {
    final depot = _FauxDepot()..erreurAuChoix = 'ECRITURES_EXISTANTES';
    await _monter(tester, depot);

    await tester.tap(find.byKey(const Key('forme_societe')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('bouton_recommander')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bouton_adopter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmer_referentiel')));
    await tester.pumpAndSettle();

    expect(find.textContaining('ouverture du prochain exercice'), findsOneWidget);
  });
}
