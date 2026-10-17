import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/comptabilite/application/comptabilite_providers.dart';
import 'package:ecoshop_client/features/comptabilite/application/pieces_comptables_providers.dart';
import 'package:ecoshop_client/features/comptabilite/domain/enums_comptabilite.dart';
import 'package:ecoshop_client/features/comptabilite/domain/journal.dart';
import 'package:ecoshop_client/features/comptabilite/domain/pieces_comptables.dart';
import 'package:ecoshop_client/features/comptabilite/domain/plan_comptable.dart';
import 'package:ecoshop_client/features/comptabilite/presentation/ecran_exercices_comptables.dart';
import 'package:ecoshop_client/features/comptabilite/presentation/ecran_pieces_comptables.dart';
import 'package:ecoshop_client/features/comptabilite/presentation/ecran_saisie_piece.dart';

/// Faux port — équilibre, numérotation, irréversibilité, contre-passation
/// et clôtures sont garantis côté base (tests/rls/64).
class _FauxDepot implements PiecesComptablesRepository {
  final List<SaisiePiece> enregistrees = [];
  final List<String> validees = [];
  final List<({String id, String motif})> contrepassees = [];
  final List<({DateTime debut, DateTime fin})> ouverts = [];
  List<ExerciceComptable> liste = [];
  PieceComptable? detailPiece;

  @override
  Future<List<ExerciceComptable>> exercices(String etablissementId) async => liste;

  @override
  Future<String> ouvrirExercice(String etablissementId, DateTime debut, DateTime fin) async {
    ouverts.add((debut: debut, fin: fin));
    return 'x-new';
  }

  @override
  Future<void> cloturerPeriode(String etablissementId, DateTime jusquAu) async {}

  @override
  Future<ResultatClotureExercice> cloturerExercice(String exerciceId) async =>
      const ResultatClotureExercice(resultat: 600000);

  @override
  Future<List<PieceComptable>> pieces(String etablissementId, String exerciceId) async => const [];

  @override
  Future<PieceComptable> detail(String pieceId) async => detailPiece!;

  @override
  Future<String> enregistrer(SaisiePiece saisie) async {
    enregistrees.add(saisie);
    return 'p1';
  }

  @override
  Future<String> valider(String pieceId) async {
    validees.add(pieceId);
    return 'CAI-2026-000001';
  }

  @override
  Future<void> supprimerBrouillard(String pieceId) async {}

  @override
  Future<String> contrepasser(String pieceId, String motif, DateTime date) async {
    contrepassees.add((id: pieceId, motif: motif));
    return 'p2';
  }
}

const _caisse = PlanComptable(id: 'c571', etablissementId: 'e1', code: '571', intitule: 'Caisse siège', type: TypeCompte.caisse, reglementaire: true);
const _regroupement = PlanComptable(id: 'c57', etablissementId: 'e1', code: '57', intitule: 'Caisse', type: TypeCompte.caisse, reglementaire: true);
const _scolarite = PlanComptable(id: 'c70521', etablissementId: 'e1', code: '70521', intitule: 'Frais de scolarité', type: TypeCompte.produit, reglementaire: true);
const _cantine = PlanComptable(id: 'c70523', etablissementId: 'e1', code: '70523', intitule: 'Cantine scolaire', type: TypeCompte.produit, reglementaire: true);
const _caisseFille = PlanComptable(id: 'c571', etablissementId: 'e1', code: '571', intitule: 'Caisse siège', type: TypeCompte.caisse, parentId: 'c57', reglementaire: true);
const _journal = Journal(id: 'j1', etablissementId: 'e1', code: 'CAI', intitule: 'Caisse', type: TypeJournal.caisse);

Future<void> _monter(WidgetTester tester, _FauxDepot depot, Widget ecran) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        piecesComptablesRepositoryProvider.overrideWithValue(depot),
        planComptableProvider.overrideWith((ref, etab) async => const [_regroupement, _caisseFille, _scolarite, _cantine]),
        journauxProvider.overrideWith((ref, etab) async => const [_journal]),
      ],
      child: MaterialApp(home: ecran),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _choisir(WidgetTester tester, Key cle, String texte) async {
  await tester.tap(find.byKey(cle));
  await tester.pumpAndSettle();
  await tester.tap(find.text(texte).last);
  await tester.pumpAndSettle();
}

void main() {
  group('domaine', () {
    test('équilibre de la saisie', () {
      final s = SaisiePiece(
        etablissementId: 'e1',
        journalId: 'j1',
        datePiece: DateTime(2026, 10, 5),
        libelle: 'L',
        lignes: const [
          LignePiece(compteId: 'a', debit: 600000),
          LignePiece(compteId: 'b', credit: 500000),
          LignePiece(compteId: 'c', credit: 100000),
        ],
      );
      expect(s.equilibree, isTrue);
      expect(s.lignes.first.versJsonSaisie(), {'compte_id': 'a', 'debit': 600000.0});
    });

    test('pièce validée, annulée, non contre-passable', () {
      final p = PieceComptable.depuisJson({
        'id': 'p',
        'exercice_id': 'x',
        'journal_id': 'j',
        'date_piece': '2026-10-05',
        'libelle': 'L',
        'statut': 'validee',
        'reference': 'CAI-2026-000001',
        'origine': 'saisie',
        'annulee_par_piece_id': 'p2',
        'lignes': [
          {'compte_id': 'a', 'compte_code': '571', 'debit': 1000, 'credit': 0},
          {'compte_id': 'b', 'compte_code': '70521', 'debit': 0, 'credit': 1000},
        ],
      });
      expect(p.estValidee, isTrue);
      expect(p.estAnnulee, isTrue);
      expect(p.contrepassable, isFalse);
      expect(p.totalDebit, 1000);
    });

    test('montants lisibles', () {
      expect(formaterMontant(600000), '600 000');
      expect(formaterMontant(-200000), '−200 000');
      expect(formaterMontant(12.5), '12,50');
    });
  });

  testWidgets('saisie : comptes de regroupement exclus, validation seulement si équilibrée', (tester) async {
    final depot = _FauxDepot();
    await _monter(tester, depot, const EcranSaisiePiece(etablissementId: 'e1'));

    await _choisir(tester, const Key('piece_journal'), 'CAI — Caisse');
    await tester.enterText(find.byKey(const Key('piece_libelle')), 'Encaissements du 5 octobre');

    // Le compte « 57 » regroupe « 571 » : il n'est pas proposé.
    await tester.tap(find.byKey(const Key('ligne_0_compte')));
    await tester.pumpAndSettle();
    expect(find.text('57 — Caisse'), findsNothing);
    await tester.tap(find.text('571 — Caisse siège').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ligne_0_debit')), '600000');

    await _choisir(tester, const Key('ligne_1_compte'), '70521 — Frais de scolarité');
    await tester.enterText(find.byKey(const Key('ligne_1_credit')), '500000');
    await tester.pump();

    expect(find.textContaining('écart 100 000'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('enregistrer_et_valider'))).onPressed, isNull);

    await tester.tap(find.byKey(const Key('ajouter_ligne')));
    await tester.pumpAndSettle();
    await _choisir(tester, const Key('ligne_2_compte'), '70523 — Cantine scolaire');
    await tester.enterText(find.byKey(const Key('ligne_2_credit')), '100000');
    await tester.pump();

    expect(find.textContaining('équilibrée'), findsOneWidget);
    await tester.tap(find.byKey(const Key('enregistrer_et_valider')));
    await tester.pumpAndSettle();

    final s = depot.enregistrees.single;
    expect(s.lignes.length, 3);
    expect(s.totalDebit, 600000);
    expect(s.totalCredit, 600000);
    expect(depot.validees, ['p1']);
  });

  testWidgets('pièce validée : contre-passation motivée', (tester) async {
    final depot = _FauxDepot()
      ..detailPiece = PieceComptable(
        id: 'p1',
        exerciceId: 'x',
        journalId: 'j1',
        datePiece: DateTime(2026, 10, 5),
        libelle: 'Inscriptions',
        statut: StatutPiece.validee,
        reference: 'CAI-2026-000002',
        journalCode: 'CAI',
        lignes: const [
          LignePiece(compteId: 'c571', compteCode: '571', compteIntitule: 'Caisse siège', debit: 200000),
          LignePiece(compteId: 'c70522', compteCode: '70522', compteIntitule: 'Inscriptions', credit: 200000),
        ],
      );
    await _monter(tester, depot, const EcranDetailPiece(etablissementId: 'e1', pieceId: 'p1'));

    expect(find.textContaining('CAI-2026-000002'), findsOneWidget);
    expect(find.byKey(const Key('valider_piece')), findsNothing);
    await tester.tap(find.byKey(const Key('contrepasser_piece')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('motif_contrepassation')), 'Double saisie');
    await tester.tap(find.byKey(const Key('confirmer_contrepassation')));
    await tester.pumpAndSettle();

    expect(depot.contrepassees.single.motif, 'Double saisie');
  });

  testWidgets('exercices : ouverture proposée sur l\'année civile', (tester) async {
    final depot = _FauxDepot();
    await _monter(tester, depot, const EcranExercicesComptables(etablissementId: 'e1'));

    expect(find.textContaining('Aucun exercice'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ouvrir_exercice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmer_ouverture')));
    await tester.pumpAndSettle();

    final o = depot.ouverts.single;
    expect(o.debut, DateTime(DateTime.now().year, 1, 1));
    expect(o.fin, DateTime(DateTime.now().year, 12, 31));
  });
}
