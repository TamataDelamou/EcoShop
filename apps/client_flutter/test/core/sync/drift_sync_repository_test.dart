import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/core/sync/sync_engine.dart';

void main() {
  late AppDatabase db;
  late DriftSyncRepository repo;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    repo = DriftSyncRepository(db);
  });

  tearDown(() => db.close());

  test('enfiler puis entreesEnAttente restitue les entrées non terminées', () async {
    await repo.enfiler(const SyncEntree(id: '1', entite: 'notes', operation: 'upsert', payload: '{}'));

    final entrees = await repo.entreesEnAttente();

    expect(entrees, hasLength(1));
    expect(entrees.single.statut, SyncStatut.enAttente);
  });

  test('marquer termine exclut l\'entrée des prochaines lectures', () async {
    await repo.enfiler(const SyncEntree(id: '1', entite: 'notes', operation: 'upsert', payload: '{}'));
    final entree = (await repo.entreesEnAttente()).single;

    await repo.marquer(entree.copierAvec(statut: SyncStatut.termine));

    expect(await repo.entreesEnAttente(), isEmpty);
  });

  test('réenfiler le même id repart avec un budget de tentatives neuf', () async {
    await repo.enfiler(const SyncEntree(id: '1', entite: 'notes', operation: 'upsert', payload: '{"v":1}'));
    var entree = (await repo.entreesEnAttente()).single;
    await repo.marquer(entree.copierAvec(tentatives: 5, statut: SyncStatut.echec));

    // La note est modifiée à nouveau avant reconnexion : on réenfile.
    await repo.enfiler(const SyncEntree(id: '1', entite: 'notes', operation: 'upsert', payload: '{"v":2}'));
    entree = (await repo.entreesEnAttente()).single;

    expect(entree.tentatives, 0);
    expect(entree.statut, SyncStatut.enAttente);
    expect(entree.payload, '{"v":2}');
  });

  test('les entrées échouées restent visibles pour rejeu tant qu\'elles ne sont pas terminées', () async {
    await repo.enfiler(const SyncEntree(id: '1', entite: 'notes', operation: 'upsert', payload: '{}'));
    final entree = (await repo.entreesEnAttente()).single;
    await repo.marquer(entree.copierAvec(statut: SyncStatut.echec, tentatives: 3));

    final entrees = await repo.entreesEnAttente();

    expect(entrees, hasLength(1));
    expect(entrees.single.statut, SyncStatut.echec);
  });
}
