import 'package:drift/native.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/securite/chiffrement_file.dart';
import 'package:ecoshop_client/core/securite/coffre_fort.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/core/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// REG-18 : file d'envoi chiffrée par compte. Un compte ne lit et n'envoie
/// que ses propres opérations ; celles d'un autre compte restent intactes
/// sur le téléphone et partent quand il se reconnecte.
void main() {
  late AppDatabase db;
  late ChiffreurFile chiffreur;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    // Même coffre pour tout le test : c'est le Keystore du téléphone.
    chiffreur = ChiffreurFile(CoffreFortMemoire());
  });

  tearDown(() => db.close());

  DriftSyncRepository fileDe(String? compte) => DriftSyncRepository(db, chiffreur: chiffreur, compte: compte);

  const encaissement = SyncEntree(
    id: 'op-1',
    entite: 'encaissements',
    operation: 'insert',
    payload: '{"montant":250000,"eleve":"Awa Bah"}',
  );

  test('le contenu n’est jamais lisible dans la base du téléphone', () async {
    await fileDe('awa').enfiler(encaissement);

    final brut = await db.select(db.syncQueueEntries).getSingle();
    expect(brut.payload, startsWith(ChiffreurFile.prefixe));
    expect(brut.payload, isNot(contains('Awa Bah')));
    expect(brut.payload, isNot(contains('250000')));
  });

  test('le compte qui a enfilé relit l’opération en clair', () async {
    await fileDe('awa').enfiler(encaissement);

    final entrees = await fileDe('awa').entreesEnAttente();
    expect(entrees.single.payload, encaissement.payload);
  });

  test('un autre compte ne voit ni n’envoie l’opération, qui reste intacte pour son auteur', () async {
    await fileDe('awa').enfiler(encaissement);

    // Awa se déconnecte, Mamadou se connecte sur la même tablette.
    final mamadou = fileDe('mamadou');
    expect(await mamadou.entreesEnAttente(), isEmpty);
    expect(await mamadou.entreesRejetees(), isEmpty);
    expect((await mamadou.suivre().first).enAttente, 0, reason: 'le bandeau ne compte pas les envois d’Awa');

    // Awa revient : l'opération part en son nom.
    final retour = await fileDe('awa').entreesEnAttente();
    expect(retour.single.payload, encaissement.payload);
    expect((await fileDe('awa').suivre().first).enAttente, 1);
  });

  test('sans session : rien n’est rendu, rien n’est perdu', () async {
    await fileDe('awa').enfiler(encaissement);

    expect(await fileDe(null).entreesEnAttente(), isEmpty);
    expect(await fileDe('awa').entreesEnAttente(), hasLength(1));
  });

  test('statut et tentatives mis à jour sans toucher au contenu chiffré', () async {
    final awa = fileDe('awa');
    await awa.enfiler(encaissement);
    final entree = (await awa.entreesEnAttente()).single;

    await awa.marquer(entree.copierAvec(statut: SyncStatut.echec, tentatives: 2));

    final relue = (await awa.entreesEnAttente()).single;
    expect(relue.tentatives, 2);
    expect(relue.payload, encaissement.payload);
  });

  test('opérations en clair d’avant REG-18 : toujours envoyées', () async {
    await DriftSyncRepository(db).enfiler(encaissement);

    expect((await fileDe('awa').entreesEnAttente()).single.payload, encaissement.payload);
  });
}
