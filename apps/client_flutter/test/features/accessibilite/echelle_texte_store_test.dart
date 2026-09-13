import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/features/accessibilite/data/echelle_texte_store.dart';
import 'package:ecoshop_client/features/accessibilite/domain/echelle_texte.dart';

void main() {
  late AppDatabase db;
  late EchelleTexteStore store;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    store = EchelleTexteStore(CacheDocumentStore(db, 'preferences'));
  });

  tearDown(() => db.close());

  test('sans préférence enregistrée, lit EchelleTexte.normal par défaut', () async {
    expect(await store.lire(), EchelleTexte.normal);
  });

  test('persiste puis relit chaque échelle', () async {
    for (final echelle in EchelleTexte.values) {
      await store.ecrire(echelle);
      expect(await store.lire(), echelle);
    }
  });

  test('une seconde instance de store sur la même base relit la préférence écrite', () async {
    await store.ecrire(EchelleTexte.tresGrand);

    final autreStore = EchelleTexteStore(CacheDocumentStore(db, 'preferences'));
    expect(await autreStore.lire(), EchelleTexte.tresGrand);
  });
}
