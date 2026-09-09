import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/referentiel/application/referentiel_providers.dart';
import 'package:ecoshop_client/features/referentiel/domain/pays_pedagogique.dart';
import 'package:ecoshop_client/features/themes/application/theme_providers.dart';
import 'package:ecoshop_client/features/themes/presentation/ecran_preferences_apparence.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.pourTests(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> monter(WidgetTester tester, {required List<Override> overrides}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), ...overrides],
        child: const MaterialApp(home: EcranPreferencesApparence()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('rendu initial : système sélectionné par défaut, charte francophone_cfa affichée', (tester) async {
    await monter(tester, overrides: [
      etablissementActifProvider.overrideWithValue(null),
      paysPedagogiquesProvider.overrideWith((ref) async => const []),
    ]);

    final radioSysteme = tester.widget<RadioListTile<ThemeMode>>(
      find.widgetWithText(RadioListTile<ThemeMode>, 'Système'),
    );
    expect(radioSysteme.value, ThemeMode.system);
    expect(find.textContaining('Francophone CFA'), findsOneWidget);
  });

  testWidgets('bascule vers Sombre : persiste le choix et redevient sélectionné après rechargement', (tester) async {
    await monter(tester, overrides: [
      etablissementActifProvider.overrideWithValue(null),
      paysPedagogiquesProvider.overrideWith((ref) async => const []),
    ]);

    await tester.tap(find.widgetWithText(RadioListTile<ThemeMode>, 'Sombre'));
    await tester.pumpAndSettle();

    // Persisté dans le store hors-ligne partagé (CacheEntries / domaine 'preferences').
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    expect(await container.read(themeModeProvider.future), ThemeMode.dark);
  });

  testWidgets('affiche la charte anglophone_waec quand l\'établissement est au Ghana', (tester) async {
    await monter(tester, overrides: [
      etablissementActifProvider.overrideWithValue(
        const Etablissement(id: 'e1', nom: 'École test', slug: 'test', paysCode: 'GH'),
      ),
      paysPedagogiquesProvider.overrideWith((ref) async => const [
            PaysPedagogique(
              codeIso: 'GH',
              nom: 'Ghana',
              typeSysteme: 'anglophone_waec',
              langueEnseignementPrincipale: 'en',
            ),
          ]),
    ]);

    expect(find.textContaining('Anglophone WAEC'), findsOneWidget);
  });
}
