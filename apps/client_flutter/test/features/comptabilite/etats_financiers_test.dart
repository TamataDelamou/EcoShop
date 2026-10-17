import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/theme/app_theme_variant.dart';
import 'package:ecoshop_client/features/comptabilite/application/etats_financiers_providers.dart';
import 'package:ecoshop_client/features/comptabilite/application/pieces_comptables_providers.dart';
import 'package:ecoshop_client/features/comptabilite/domain/etats_financiers.dart';
import 'package:ecoshop_client/features/comptabilite/domain/pieces_comptables.dart';
import 'package:ecoshop_client/features/comptabilite/presentation/ecran_etats_financiers.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/export_pdf/data/etats_financiers_pdf_builder.dart';

/// Réponse serveur reproduisant le scénario de tests/rls/66 (SYSCOHADA).
final _json = <String, dynamic>{
  'referentiel': 'syscohada_normal',
  'plan': 'syscohada',
  'provisoire': true,
  'exercice': {
    'id': 'x2026',
    'libelle': 'Exercice 2026',
    'date_debut': '2026-01-01',
    'date_fin': '2026-12-31',
    'cloture': false,
    'situation_au': '2026-10-17',
  },
  'exercice_precedent': null,
  'lignes': [
    {'etat': 'resultat', 'reference': 'TA', 'libelle': 'Ventes de marchandises', 'total': false, 'montant': 0},
    {'etat': 'resultat', 'reference': 'TC', 'libelle': 'Travaux, services vendus', 'total': false, 'montant': 3030000},
    {'etat': 'resultat', 'reference': 'RK', 'libelle': 'Charges de personnel', 'total': false, 'montant': 400000},
    {'etat': 'resultat', 'reference': 'XI', 'libelle': 'RÉSULTAT NET', 'total': true, 'montant': 2580000},
    {'etat': 'actif', 'reference': 'AM', 'libelle': 'Matériel, mobilier et actifs biologiques', 'total': false, 'montant': 550000, 'brut': 600000, 'amortissements': 50000},
    {'etat': 'actif', 'reference': 'BS', 'libelle': 'Banques, chèques postaux, caisse et assimilés', 'total': false, 'montant': 3030000},
    {'etat': 'actif', 'reference': 'BZ', 'libelle': 'TOTAL GÉNÉRAL', 'total': true, 'montant': 3580000},
    {'etat': 'passif', 'reference': 'CA', 'libelle': 'Capital', 'total': false, 'montant': 1000000},
    {'etat': 'passif', 'reference': 'CH', 'libelle': 'Report à nouveau (+ ou −)', 'total': false, 'montant': 0},
    {'etat': 'passif', 'reference': 'CJ', 'libelle': 'Résultat net de l\'exercice', 'total': false, 'montant': 2580000},
    {'etat': 'passif', 'reference': 'DZ', 'libelle': 'TOTAL GÉNÉRAL', 'total': true, 'montant': 3580000},
  ],
  'equilibre': true,
  'resultat': 2580000,
  'non_classes': [],
  'tresorerie': {'solde_debut': 0, 'encaissements': 4030000, 'decaissements': 1000000, 'solde_fin': 3030000},
};

class _FauxEtats implements EtatsFinanciersRepository {
  int pcaPasses = 0;

  @override
  Future<EtatFinancier> etat(String etablissementId, String exerciceId) async => EtatFinancier.depuisJson(_json);

  @override
  Future<ApercuPca> apercuPca(String exerciceId) async => ApercuPca(
        dejaPasses: pcaPasses > 0,
        total: 1810000,
        lignes: const [LignePca(code: '70611', intitule: 'Frais de scolarité', encaisse: 3030000, montant: 1810000)],
      );

  @override
  Future<double> passerPca(String exerciceId) async {
    pcaPasses++;
    return 1810000;
  }
}

class _FauxPieces implements PiecesComptablesRepository {
  @override
  Future<List<ExerciceComptable>> exercices(String etablissementId) async => [
        ExerciceComptable(
          id: 'x2026',
          libelle: 'Exercice 2026',
          dateDebut: DateTime(2026, 1, 1),
          dateFin: DateTime(2026, 12, 31),
          cloture: false,
        ),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('lecture : lignes vides masquées, totaux gardés, libellé du résultat', () {
    final e = EtatFinancier.depuisJson(_json);
    expect(e.partie(PartieEtat.resultat).map((l) => l.reference), ['TC', 'RK', 'XI']);
    expect(e.partie(PartieEtat.passif).map((l) => l.reference), ['CA', 'CJ', 'DZ']);
    expect(e.libelleResultat, 'Bénéfice');
    expect(e.titreReferentiel, contains('Système normal'));
  });

  test('PDF des états financiers : document valide, sans caractère hors Latin-1', () async {
    final octets = await construireEtatsFinanciersPdf(
      etat: EtatFinancier.depuisJson(_json),
      etablissement: const Etablissement(id: 'e1', nom: 'Lycée Privé C4', slug: 'lycee-c4'),
      variante: AppThemeVariant.francophoneCfa,
    );
    expect(String.fromCharCodes(octets.take(4)), '%PDF');
    expect(textePdf('Report à nouveau (+ ou −) — test…'), 'Report à nouveau (+ ou -) - test...');
  });

  testWidgets('écran : résultat, bilan équilibré, passage des produits constatés d\'avance', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final etats = _FauxEtats();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        etatsFinanciersRepositoryProvider.overrideWithValue(etats),
        piecesComptablesRepositoryProvider.overrideWithValue(_FauxPieces()),
      ],
      child: const MaterialApp(home: EcranEtatsFinanciers(etablissementId: 'e1')),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Bénéfice'), findsOneWidget);
    expect(find.text('Bilan équilibré'), findsOneWidget);
    expect(find.byKey(const Key('ligne_actif_AM')), findsOneWidget);
    expect(find.textContaining('amort.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('passer_pca')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmer_pca')));
    await tester.pumpAndSettle();

    expect(etats.pcaPasses, 1);
    expect(find.text('Produits constatés d\'avance passés'), findsOneWidget);
  });
}
