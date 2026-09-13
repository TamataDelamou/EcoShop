import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/features/accessibilite/data/contraste_eleve_store.dart';

void main() {
  late AppDatabase db;
  late ContrasteEleveStore store;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    store = ContrasteEleveStore(CacheDocumentStore(db, 'preferences'));
  });

  tearDown(() => db.close());

  test('sans préférence enregistrée, lit false par défaut', () async {
    expect(await store.lire(), isFalse);
  });

  test('persiste puis relit chaque valeur', () async {
    await store.ecrire(true);
    expect(await store.lire(), isTrue);

    await store.ecrire(false);
    expect(await store.lire(), isFalse);
  });

  test('une seconde instance de store sur la même base relit la préférence écrite', () async {
    await store.ecrire(true);

    final autreStore = ContrasteEleveStore(CacheDocumentStore(db, 'preferences'));
    expect(await autreStore.lire(), isTrue);
  });
}
