import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/accessibilite/application/accessibilite_providers.dart';
import 'package:ecoshop_client/features/accessibilite/domain/echelle_texte.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.pourTests(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('contrasteEleveProvider', () {
    test('démarre à false puis reflète immédiatement definir(), persisté', () async {
      final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);

      expect(await container.read(contrasteEleveProvider.future), isFalse);

      await container.read(contrasteEleveProvider.notifier).definir(true);
      expect(container.read(contrasteEleveProvider).value, isTrue);

      final autreContainer = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
      addTearDown(autreContainer.dispose);
      expect(await autreContainer.read(contrasteEleveProvider.future), isTrue);
    });
  });

  group('echelleTexteProvider', () {
    test('démarre à normal puis reflète immédiatement definir(), persisté', () async {
      final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);

      expect(await container.read(echelleTexteProvider.future), EchelleTexte.normal);

      await container.read(echelleTexteProvider.notifier).definir(EchelleTexte.tresGrand);
      expect(container.read(echelleTexteProvider).value, EchelleTexte.tresGrand);

      final autreContainer = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
      addTearDown(autreContainer.dispose);
      expect(await autreContainer.read(echelleTexteProvider.future), EchelleTexte.tresGrand);
    });
  });
}
