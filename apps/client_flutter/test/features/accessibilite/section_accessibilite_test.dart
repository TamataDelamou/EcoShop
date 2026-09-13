import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/accessibilite/application/accessibilite_providers.dart';
import 'package:ecoshop_client/features/accessibilite/domain/echelle_texte.dart';
import 'package:ecoshop_client/features/accessibilite/presentation/section_accessibilite.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.pourTests(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> monter(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: SectionAccessibilite())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('affiche le contraste désactivé et l’échelle Normal sélectionnée par défaut', (tester) async {
    await monter(tester);

    final interrupteur = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(interrupteur.value, isFalse);

    final chipsNormal = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Normal'));
    expect(chipsNormal.selected, isTrue);
  });

  testWidgets('activer le contraste élevé persiste immédiatement', (tester) async {
    await monter(tester);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    expect(await container.read(contrasteEleveProvider.future), isTrue);
  });

  testWidgets('choisir « Très grand » persiste immédiatement', (tester) async {
    await monter(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Très grand'));
    await tester.pumpAndSettle();

    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    expect(await container.read(echelleTexteProvider.future), EchelleTexte.tresGrand);
  });
}
