import 'package:drift/native.dart';
import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/cgu/application/cgu_providers.dart';
import 'package:ecoshop_client/features/cgu/domain/cgu_statut.dart';
import 'package:ecoshop_client/features/coquille/presentation/garde_session.dart';
import 'package:ecoshop_client/features/regionalisation/application/regionalisation_providers.dart';
import 'package:ecoshop_client/features/themes/application/theme_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth_repository.dart';

class _RegionalisationVue extends OnboardingRegionalisationNotifier {
  @override
  Future<bool> build() async => true;
}

class _CguRienAAccepter extends CguStatutNotifier {
  @override
  Future<CguStatut?> build() async => null;
}

/// Apparence dans la barre du haut : 3 icônes au plus (Material 3), choix
/// « Automatique / Clair / Sombre », automatique par défaut, seul endroit.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.pourTests(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> monter(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FauxAuthRepository(profil: profilTest(role: RoleRacine.vendeur))),
        sessionOuverteProvider.overrideWithValue(true),
        databaseProvider.overrideWithValue(db),
        onboardingRegionalisationVuProvider.overrideWith(_RegionalisationVue.new),
        cguStatutProvider.overrideWith(_CguRienAAccepter.new),
      ],
      child: const MaterialApp(home: RacineApp()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('barre du haut : notifications, apparence, profil tout à droite — pas plus de 3', (tester) async {
    await monter(tester);
    final actions = tester.widget<AppBar>(find.byType(AppBar).first).actions!;
    expect(actions, hasLength(3));
    final x = [
      tester.getCenter(find.byTooltip('Notifications')).dx,
      tester.getCenter(find.byKey(const Key('bouton_apparence'))).dx,
      tester.getCenter(find.byKey(const Key('raccourci_profil'))).dx,
    ];
    expect(x[0] < x[1] && x[1] < x[2], isTrue, reason: 'convention Google : le profil tout à droite');
  });

  testWidgets('choix Automatique / Clair / Sombre, automatique par défaut, gardé sur le téléphone', (tester) async {
    await monter(tester);
    expect(find.byIcon(Icons.brightness_auto_outlined), findsOneWidget, reason: 'automatique par défaut');

    await tester.tap(find.byKey(const Key('bouton_apparence')));
    await tester.pumpAndSettle();
    expect(find.text('Automatique (comme le téléphone)'), findsOneWidget);
    expect(find.text('Clair'), findsOneWidget);
    expect(find.text('Sombre'), findsOneWidget);

    await tester.tap(find.byKey(const Key('apparence_dark')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget, reason: 'l’icône montre le choix en cours');

    final autre = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(autre.dispose);
    expect(await autre.read(themeModeProvider.future), ThemeMode.dark, reason: 'gardé au prochain lancement');
  });

  testWidgets('un seul endroit : plus d’entrée « Apparence » dans le profil', (tester) async {
    await monter(tester);
    await tester.tap(find.byKey(const Key('raccourci_profil')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Se déconnecter'), 300, scrollable: find.byType(Scrollable).last);

    expect(find.text('Apparence'), findsNothing);
    expect(find.text('Clair, sombre, système'), findsNothing);
  });
}
