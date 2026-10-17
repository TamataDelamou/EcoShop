import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/theme/app_theme_variant.dart';
import 'package:ecoshop_client/features/comptabilite/application/dons_providers.dart';
import 'package:ecoshop_client/features/comptabilite/domain/dons.dart';
import 'package:ecoshop_client/features/comptabilite/domain/montant_en_lettres.dart';
import 'package:ecoshop_client/features/comptabilite/presentation/ecran_dons.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/export_pdf/data/recu_don_pdf_builder.dart';

/// Réponse serveur reproduisant le scénario de tests/rls/68.
final _tableau = <String, dynamic>{
  'annee': 2026,
  'total': 2875000,
  'total_annee_precedente': 300000,
  'nombre_dons': 4,
  'nombre_donateurs': 3,
  'nouveaux_donateurs': 2,
  'donateurs_fideles': 1,
  'par_nature': [
    {'nature': 'mecenat', 'montant': 2000000, 'nombre': 1},
    {'nature': 'don', 'montant': 500000, 'nombre': 1},
  ],
  'affectations': [
    {
      'id': 'a1',
      'libelle': 'Bibliothèque',
      'type': 'projet',
      'active': true,
      'objectif': 10000000,
      'collecte': 2000000,
      'collecte_annee': 2000000,
      'emploie': 1500000,
      'disponible': 500000,
      'donateurs': 1,
    },
  ],
  'meilleurs_donateurs': [
    {'donateur_id': 'd3', 'nom': 'ONG Lumière', 'montant': 2000000, 'nombre': 1},
  ],
  'a_relancer': [
    {'donateur_id': 'd2', 'nom': 'Paroisse de Kaloum', 'telephone': '224620000002', 'montant_annee_precedente': 200000},
  ],
  'engagements': [
    {
      'id': 'e1',
      'donateur': 'SOW Mariama',
      'affectation': 'Parrainage d\'élèves',
      'eleve': 'Fatoumata DIALLO',
      'montant': 100000,
      'periodicite': 'mensuelle',
      'attendu': 1000000,
      'recu': 300000,
      'retard': 700000,
    },
  ],
};

class _FauxDons implements DonsRepository {
  final List<SaisieDon> saisies = [];
  final List<({String affectationId, double montant, String libelle})> emplois = [];

  @override
  Future<TableauBordDons> tableauBord(String etablissementId, int annee) async => TableauBordDons.depuisJson(_tableau);

  @override
  Future<List<Don>> dons(String etablissementId, int annee) async => [
        Don.depuisJson({
          'id': 'x1',
          'numero_recu': 'REC-2026-000001',
          'date_don': '2026-03-10',
          'montant': 500000,
          'nature': 'don',
          'moyen_paiement': 'especes',
          'statut': 'valide',
          'donateurs': {'nom': 'CAMARA', 'prenom': 'Ibrahima'},
        }),
      ];

  @override
  Future<List<Donateur>> donateurs(String etablissementId) async =>
      [const Donateur(id: 'd1', etablissementId: 'e1', nom: 'CAMARA', prenom: 'Ibrahima')];

  @override
  Future<List<AffectationDon>> affectations(String etablissementId) async =>
      [const AffectationDon(id: 'a1', etablissementId: 'e1', libelle: 'Bibliothèque', type: TypeAffectation.projet)];

  @override
  Future<ResultatDon> enregistrerDon(SaisieDon saisie) async {
    saisies.add(saisie);
    return const ResultatDon(id: 'x9', numeroRecu: 'REC-2026-000005', comptabilise: true);
  }

  @override
  Future<double> constaterEmploi({
    required String affectationId,
    required double montant,
    required String libelle,
    required DateTime date,
  }) async {
    emplois.add((affectationId: affectationId, montant: montant, libelle: libelle));
    return 500000 - montant;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<_FauxDons> _monter(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final depot = _FauxDons();
  await tester.pumpWidget(ProviderScope(
    overrides: [donsRepositoryProvider.overrideWithValue(depot)],
    child: const MaterialApp(home: EcranDons(etablissementId: 'e1', annee: 2026)),
  ));
  await tester.pumpAndSettle();
  return depot;
}

void main() {
  test('montant en lettres : règles du français', () {
    expect(montantEnLettres(0), 'zéro');
    expect(montantEnLettres(21), 'vingt et un');
    expect(montantEnLettres(71), 'soixante et onze');
    expect(montantEnLettres(77), 'soixante-dix-sept');
    expect(montantEnLettres(80), 'quatre-vingts');
    expect(montantEnLettres(81), 'quatre-vingt-un');
    expect(montantEnLettres(91), 'quatre-vingt-onze');
    expect(montantEnLettres(200), 'deux cents');
    expect(montantEnLettres(280), 'deux cent quatre-vingts');
    expect(montantEnLettres(1001), 'mille un');
    expect(montantEnLettres(80000), 'quatre-vingt mille');
    expect(montantEnLettres(200000), 'deux cent mille');
    expect(montantEnLettres(1250000), 'un million deux cent cinquante mille');
    expect(montantEnLettres(2000000), 'deux millions');
    expect(deviseEnLettres('GNF', 500000), 'francs guinéens');
  });

  test('lecture : synthèse, progression, retard, évolution', () {
    final t = TableauBordDons.depuisJson(_tableau);
    expect(t.affectations.single.progression, closeTo(0.2, 1e-9));
    expect(t.engagementsEnRetard.single.retard, 700000);
    expect(t.evolution, closeTo(8.5833, 1e-3));
    expect(Don.depuisJson({
      'id': 'q',
      'numero_recu': 'REC-2026-000002',
      'date_don': '2026-04-05',
      'montant': 75000,
      'nature': 'quete',
      'moyen_paiement': 'mobile_money',
      'statut': 'annule',
    }).donateurAffiche, 'Quête');
  });

  test('PDF : reçu (annulé compris) et relevé annuel valides', () async {
    const etab = Etablissement(id: 'e1', nom: 'École Bambino', slug: 'bambino');
    final recu = RecuDon.depuisJson({
      'numero_recu': 'REC-2026-000001',
      'date_don': '2026-03-10',
      'montant': 500000,
      'nature': 'don',
      'moyen_paiement': 'especes',
      'statut': 'annule',
      'motif_annulation': 'Saisi en double',
      'donateur': {'nom': 'CAMARA', 'prenom': 'Ibrahima', 'adresse': 'Kaloum — Conakry'},
    });
    final octets = await construireRecuDonPdf(recu: recu, etablissement: etab, variante: AppThemeVariant.francophoneCfa);
    expect(String.fromCharCodes(octets.take(4)), '%PDF');

    final releve = ReleveDonateur.depuisJson({
      'donateur': {'nom': 'CAMARA', 'prenom': 'Ibrahima'},
      'annee': 2026,
      'total': 500000,
      'dons': [
        {'numero_recu': 'REC-2026-000001', 'date_don': '2026-03-10', 'montant': 500000, 'nature': 'don'},
      ],
    });
    final octets2 =
        await construireReleveDonateurPdf(releve: releve, etablissement: etab, variante: AppThemeVariant.francophoneCfa);
    expect(String.fromCharCodes(octets2.take(4)), '%PDF');
  });

  testWidgets('synthèse : total, projet, relances, parrainage en retard ; emploi des fonds', (tester) async {
    final depot = await _monter(tester);

    expect(find.byKey(const Key('total_dons')), findsOneWidget);
    expect(find.textContaining('disponible'), findsWidgets);
    expect(find.byKey(const Key('relancer_Paroisse de Kaloum')), findsOneWidget);
    expect(find.byKey(const Key('engagement_SOW Mariama')), findsOneWidget);

    await tester.tap(find.byKey(const Key('employer_Bibliothèque')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('montant_emploi')), '600000');
    await tester.enterText(find.byKey(const Key('libelle_emploi')), 'Étagères');
    await tester.pump();
    // Au-delà du disponible : bouton inactif.
    expect(tester.widget<FilledButton>(find.byKey(const Key('valider_emploi'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('montant_emploi')), '400000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('valider_emploi')));
    await tester.pumpAndSettle();

    expect(depot.emplois.single.montant, 400000);
    expect(find.textContaining('Reste disponible'), findsOneWidget);
  });

  testWidgets('nouveau don : saisie, montant en lettres, reçu numéroté', (tester) async {
    final depot = await _monter(tester);

    await tester.tap(find.byKey(const Key('nouveau_don')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('montant_don')), '250000');
    await tester.pump();
    expect(find.textContaining('Deux cent cinquante mille'), findsOneWidget);

    await tester.tap(find.byKey(const Key('enregistrer_don')));
    await tester.pumpAndSettle();

    expect(depot.saisies.single.montant, 250000);
    expect(depot.saisies.single.nature, NatureDon.don);
    expect(find.textContaining('REC-2026-000005'), findsOneWidget);
  });
}
