import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/core/sync/journal_rejets.dart';
import 'package:ecoshop_client/core/sync/sync_engine.dart';

void main() {
  late AppDatabase db;
  late DriftSyncRepository file;
  late JournalRejets journal;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    file = DriftSyncRepository(db);
    journal = JournalRejets(CacheDocumentStore(db, 'sync_rejets'), file);
  });

  tearDown(() => db.close());

  SyncEngine moteur(Future<void> Function(SyncEntree) rejouer) => SyncEngine(
        repository: file,
        estConnecte: () async => true,
        rejouer: rejouer,
        surRejet: (entree, rejet) => journal.enregistrer(entree, rejet, 'Don de 250 000'),
      );

  test('refus du serveur : rejetée, plus rejouée, expliquée à l\'utilisateur', () async {
    await file.enfiler(const SyncEntree(id: 'd1', entite: 'dons', operation: 'upsert', payload: '{}'));
    var appels = 0;
    final m = moteur((_) async {
      appels++;
      throw const RejetDefinitif('PERIODE_CLOTUREE', 'Cette période est clôturée.');
    });

    await m.synchroniser();
    await m.synchroniser();

    expect(appels, 1, reason: 'un refus définitif ne se réessaie pas');
    expect(await file.entreesEnAttente(), isEmpty);
    expect((await file.entreesRejetees()).single.id, 'd1');
    final rejets = await journal.lister();
    expect(rejets.single.libelle, 'Don de 250 000');
    expect(rejets.single.message, 'Cette période est clôturée.');
    expect(await file.suivre().first, (enAttente: 0, rejetees: 1));

    await journal.retirer('d1');
    expect(await journal.lister(), isEmpty);
    expect(await file.entreesRejetees(), isEmpty);
  });

  test('panne de réseau : reste en file pour un nouvel essai', () async {
    await file.enfiler(const SyncEntree(id: 'd2', entite: 'dons', operation: 'upsert', payload: '{}'));
    var appels = 0;
    final m = moteur((_) async {
      appels++;
      if (appels == 1) throw Exception('SocketException');
    });

    await m.synchroniser();
    expect((await file.entreesEnAttente()).single.statut, SyncStatut.echec);
    await m.synchroniser();
    expect(appels, 2);
    expect(await file.suivre().first, (enAttente: 0, rejetees: 0));
  });
}
