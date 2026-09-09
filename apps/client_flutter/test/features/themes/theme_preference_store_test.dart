import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/features/themes/data/theme_preference_store.dart';

void main() {
  late AppDatabase db;
  late ThemePreferenceStore store;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    store = ThemePreferenceStore(CacheDocumentStore(db, 'preferences'));
  });

  tearDown(() => db.close());

  test('sans préférence enregistrée, lit ThemeMode.system par défaut', () async {
    expect(await store.lire(), ThemeMode.system);
  });

  test('persiste puis relit chaque mode (survit à un nouvel accès au store)', () async {
    await store.ecrire(ThemeMode.dark);
    expect(await store.lire(), ThemeMode.dark);

    await store.ecrire(ThemeMode.light);
    expect(await store.lire(), ThemeMode.light);

    await store.ecrire(ThemeMode.system);
    expect(await store.lire(), ThemeMode.system);
  });

  test('une seconde instance de store sur la même base relit la préférence écrite (persistance réelle, pas juste en mémoire)', () async {
    await store.ecrire(ThemeMode.dark);

    final autreStore = ThemePreferenceStore(CacheDocumentStore(db, 'preferences'));
    expect(await autreStore.lire(), ThemeMode.dark);
  });

  test('un domaine de cache différent ne voit pas la préférence (isolation par domaine)', () async {
    await store.ecrire(ThemeMode.dark);

    final autreDomaine = ThemePreferenceStore(CacheDocumentStore(db, 'autre_domaine'));
    expect(await autreDomaine.lire(), ThemeMode.system);
  });
}
