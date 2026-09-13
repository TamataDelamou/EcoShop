import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/regionalisation/application/regionalisation_providers.dart';
import 'package:ecoshop_client/features/regionalisation/presentation/ecran_onboarding_regionalisation.dart';

Profil _profilTest() => Profil(
      id: 'p1',
      identifiantCanonique: '+224600000001',
      statutCompte: StatutCompte.actif,
      roleRacine: RoleRacine.parent,
    );

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.pourTests(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Monte l'écran et attend que `profilProvider` soit résolu avant de
  /// rendre la main au test — en production, cet écran n'est jamais atteint
  /// avant que `destinationProvider` ait déjà confirmé `profil` chargé
  /// (`GardeSession.resoudre` ne route ici qu'après ce point). Sans ce
  /// pré-chauffage explicite, un tap déclenchant la toute première lecture
  /// de `profilProvider` (ici en dehors de ce chemin de garde) fait
  /// diverger `pumpAndSettle`.
  Future<ProviderContainer> monter(WidgetTester tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          profilProvider.overrideWith((ref) async => _profilTest()),
          etablissementActifProvider.overrideWithValue(
            const Etablissement(
              id: 'e1',
              nom: 'École test',
              slug: 'test',
              paysCode: 'GN',
              deviseCode: 'GNF',
            ),
          ),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: EcranOnboardingRegionalisation());
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await container.read(profilProvider.future);
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('affiche Langue (Français sélectionné) et Région (pays/devise lecture seule)', (tester) async {
    await monter(tester);

    expect(find.text('Langue'), findsOneWidget);
    final radioFrancais = tester.widget<RadioListTile<String>>(
      find.widgetWithText(RadioListTile<String>, 'Français'),
    );
    expect(radioFrancais.value, 'fr');

    expect(find.text('Région'), findsOneWidget);
    expect(find.text('GN'), findsOneWidget);
    expect(find.text('GNF'), findsOneWidget);
    expect(find.text('Continuer'), findsOneWidget);
  });

  testWidgets('« Continuer » marque l’étape vue pour ce profil', (tester) async {
    final container = await monter(tester);

    expect(await container.read(onboardingRegionalisationVuProvider.future), isFalse);

    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    expect(await container.read(onboardingRegionalisationVuProvider.future), isTrue);
  });
}
