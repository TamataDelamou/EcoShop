import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/core/theme/app_theme_variant.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/referentiel/application/referentiel_providers.dart';
import 'package:ecoshop_client/features/referentiel/domain/pays_pedagogique.dart';
import 'package:ecoshop_client/features/themes/application/theme_providers.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.pourTests(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('themeModeProvider', () {
    test('démarre sur system puis reflète immédiatement definir(), persisté', () async {
      final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);

      expect(await container.read(themeModeProvider.future), ThemeMode.system);

      await container.read(themeModeProvider.notifier).definir(ThemeMode.dark);
      expect(container.read(themeModeProvider).value, ThemeMode.dark);

      // Persisté : un nouveau conteneur sur la même base relit la même valeur.
      final autreContainer = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
      addTearDown(autreContainer.dispose);
      expect(await autreContainer.read(themeModeProvider.future), ThemeMode.dark);
    });
  });

  group('themeVariantProvider', () {
    ProviderContainer construire({Etablissement? etablissement, List<PaysPedagogique> pays = const []}) {
      return ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        etablissementActifProvider.overrideWithValue(etablissement),
        paysPedagogiquesProvider.overrideWith((ref) async => pays),
      ]);
    }

    test('aucun établissement actif → repli francophone_cfa', () async {
      final container = construire(etablissement: null);
      addTearDown(container.dispose);
      expect(container.read(themeVariantProvider), AppThemeVariant.francophoneCfa);
    });

    test('établissement sans pays renseigné → repli francophone_cfa', () async {
      final container = construire(
        etablissement: const Etablissement(id: 'e1', nom: 'Test', slug: 'test'),
      );
      addTearDown(container.dispose);
      expect(container.read(themeVariantProvider), AppThemeVariant.francophoneCfa);
    });

    test('pays du référentiel pas encore chargé → repli francophone_cfa', () async {
      final container = construire(
        etablissement: const Etablissement(id: 'e1', nom: 'Test', slug: 'test', paysCode: 'GH'),
        pays: const [],
      );
      addTearDown(container.dispose);
      expect(container.read(themeVariantProvider), AppThemeVariant.francophoneCfa);
    });

    test('établissement au Ghana (anglophone_waec) → variante anglophone_waec', () async {
      final container = construire(
        etablissement: const Etablissement(id: 'e1', nom: 'Test', slug: 'test', paysCode: 'GH'),
        pays: const [
          PaysPedagogique(
            codeIso: 'GH',
            nom: 'Ghana',
            typeSysteme: 'anglophone_waec',
            langueEnseignementPrincipale: 'en',
          ),
        ],
      );
      addTearDown(container.dispose);
      // Le référentiel est un FutureProvider : on attend sa résolution avant de lire.
      await container.read(paysPedagogiquesProvider.future);
      expect(container.read(themeVariantProvider), AppThemeVariant.anglophoneWaec);
    });

    test('établissement en Guinée-Bissau (lusophone) → variante lusophone', () async {
      final container = construire(
        etablissement: const Etablissement(id: 'e1', nom: 'Test', slug: 'test', paysCode: 'GW'),
        pays: const [
          PaysPedagogique(
            codeIso: 'GW',
            nom: 'Guinée-Bissau',
            typeSysteme: 'lusophone',
            langueEnseignementPrincipale: 'pt',
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(paysPedagogiquesProvider.future);
      expect(container.read(themeVariantProvider), AppThemeVariant.lusophone);
    });
  });
}
