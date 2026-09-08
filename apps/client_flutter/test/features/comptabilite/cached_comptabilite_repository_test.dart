import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/features/comptabilite/data/cached_comptabilite_repository.dart';
import 'package:ecoshop_client/features/comptabilite/domain/comptabilite_repository.dart';
import 'package:ecoshop_client/features/comptabilite/domain/ecriture_comptable.dart';
import 'package:ecoshop_client/features/comptabilite/domain/journal.dart';
import 'package:ecoshop_client/features/comptabilite/domain/ligne_balance.dart';
import 'package:ecoshop_client/features/comptabilite/domain/ligne_journal.dart';
import 'package:ecoshop_client/features/comptabilite/domain/mouvement_grand_livre.dart';
import 'package:ecoshop_client/features/comptabilite/domain/plan_comptable.dart';
import 'package:ecoshop_client/features/comptabilite/domain/signaux_ia_comptables.dart';

EcritureComptable _ecriture({String id = 'e1'}) => EcritureComptable(
      id: id,
      etablissementId: 'et1',
      journalId: 'j1',
      dateEcriture: DateTime(2026, 9, 15),
      libelle: 'Scolarité',
      compteDebitId: 'c1',
      compteCreditId: 'c2',
      montant: 500000,
    );

class _FauxDistant implements ComptabiliteRepository {
  bool horsLigne = false;
  String? codeErreur;

  @override
  Future<List<PlanComptable>> planComptable(String etablissementId) async {
    if (horsLigne) throw const ErreurComptabilite('ERREUR_RESEAU');
    return const [PlanComptable(id: 'c1', etablissementId: 'et1', code: '520', intitule: 'Banque')];
  }

  @override
  Future<bool> enregistrerCompte(PlanComptable compte) async => true;

  @override
  Future<List<Journal>> journaux(String etablissementId) async {
    if (horsLigne) throw const ErreurComptabilite('ERREUR_RESEAU');
    return const [Journal(id: 'j1', etablissementId: 'et1', code: 'BQ', intitule: 'Banque')];
  }

  @override
  Future<bool> enregistrerJournal(Journal journal) async => true;

  @override
  Future<List<EcritureComptable>> ecrituresRecentes(String etablissementId, {int limite = 100}) async {
    if (horsLigne) throw const ErreurComptabilite('ERREUR_RESEAU');
    return [_ecriture()];
  }

  @override
  Future<bool> enregistrerEcriture(EcritureComptable ecriture) async {
    final code = codeErreur;
    if (code != null) throw ErreurComptabilite(code);
    return true;
  }

  @override
  Future<List<LigneJournal>> journalComptable(
          String etablissementId, String journalId, DateTime debut, DateTime fin) async =>
      const [];

  @override
  Future<List<MouvementGrandLivre>> grandLivre(
          String etablissementId, String compteId, DateTime debut, DateTime fin) async =>
      const [];

  @override
  Future<List<LigneBalance>> balanceComptable(String etablissementId, DateTime date) async => const [];

  @override
  Future<List<Balance>> genererBalance(String etablissementId, DateTime date) async => const [];

  @override
  Future<List<AnomalieComptable>> detecterAnomalies(String etablissementId) async => const [];

  @override
  Future<List<ProjectionTresorerie>> predireTresorerie(String etablissementId, {int jours = 30}) async => const [];

  @override
  Future<List<EcritureRecommandee>> recommanderEcritures(String etablissementId) async => const [];

  @override
  Future<List<TendanceMensuelle>> analyserTendances(String etablissementId, {int mois = 12}) async => const [];
}

void main() {
  late AppDatabase db;
  late _FauxDistant distant;
  late CachedComptabiliteRepository repository;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    distant = _FauxDistant();
    repository = CachedComptabiliteRepository(distant, CacheDocumentStore(db, 'comptabilite'), DriftSyncRepository(db));
  });

  tearDown(() => db.close());

  group('lecture', () {
    test('planComptable retombe sur le cache hors ligne', () async {
      await repository.planComptable('et1');
      distant.horsLigne = true;

      final liste = await repository.planComptable('et1');
      expect(liste.single.code, '520');
    });

    test('ecrituresRecentes retombe sur le cache hors ligne', () async {
      await repository.ecrituresRecentes('et1');
      distant.horsLigne = true;

      final liste = await repository.ecrituresRecentes('et1');
      expect(liste.single.libelle, 'Scolarité');
    });
  });

  group('enregistrerEcriture', () {
    test('renvoie true sans rien enfiler quand le réseau réussit', () async {
      final synchronisee = await repository.enregistrerEcriture(_ecriture());

      expect(synchronisee, isTrue);
      expect(await DriftSyncRepository(db).entreesEnAttente(), isEmpty);
    });

    test('enfile l\'écriture et renvoie false sur une panne réseau non métier', () async {
      distant.codeErreur = 'ERREUR_RESEAU';

      final synchronisee = await repository.enregistrerEcriture(_ecriture());

      expect(synchronisee, isFalse);
      final enAttente = await DriftSyncRepository(db).entreesEnAttente();
      expect(enAttente, hasLength(1));
      expect(enAttente.single.entite, 'ecritures_comptables');
    });

    test('remonte une erreur métier authentique sans l\'enfiler', () async {
      distant.codeErreur = 'ECRITURE_COMPTES_IDENTIQUES';

      await expectLater(
        repository.enregistrerEcriture(_ecriture()),
        throwsA(isA<ErreurComptabilite>().having((e) => e.code, 'code', 'ECRITURE_COMPTES_IDENTIQUES')),
      );
      expect(await DriftSyncRepository(db).entreesEnAttente(), isEmpty);
    });
  });

  group('ecrituresRecentes — superposition de la file d\'attente', () {
    test('une écriture en attente apparaît immédiatement dans la liste', () async {
      distant.codeErreur = 'ERREUR_RESEAU';
      await repository.enregistrerEcriture(_ecriture(id: 'e2'));
      distant.codeErreur = null;

      final liste = await repository.ecrituresRecentes('et1');
      expect(liste.any((e) => e.id == 'e2'), isTrue);
    });
  });
}
