import 'package:drift/native.dart';
import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/cgu/application/cgu_providers.dart';
import 'package:ecoshop_client/features/cgu/domain/cgu_statut.dart';
import 'package:ecoshop_client/features/communication/prototype/application/visibilite_prototypes.dart';
import 'package:ecoshop_client/features/coquille/presentation/garde_session.dart';
import 'package:ecoshop_client/features/regionalisation/application/regionalisation_providers.dart';
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

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.pourTests(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> monter(WidgetTester tester, {required bool prototypes, RoleRacine role = RoleRacine.vendeur}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        // Vendeur, enseignant : leur liste « Mon profil » ne lit pas la scolarité (Supabase).
        authRepositoryProvider.overrideWithValue(FauxAuthRepository(profil: profilTest(role: role))),
        sessionOuverteProvider.overrideWithValue(true),
        databaseProvider.overrideWithValue(db),
        onboardingRegionalisationVuProvider.overrideWith(_RegionalisationVue.new),
        cguStatutProvider.overrideWith(_CguRienAAccepter.new),
        prototypesCommunicationVisiblesProvider.overrideWithValue(prototypes),
      ],
      child: const MaterialApp(home: RacineApp()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('accueil : texte d’aide engageant, sans jargon de développement', (tester) async {
    await monter(tester, prototypes: false, role: RoleRacine.enseignant);
    expect(find.text('Retrouvez l’essentiel de votre journée'), findsOneWidget);
    expect(find.textContaining('module M'), findsNothing);
  });

  testWidgets('version publiée : cahier de liaison (prototype local) masqué', (tester) async {
    await monter(tester, prototypes: false, role: RoleRacine.enseignant);
    await tester.tap(find.byKey(const Key('raccourci_profil')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Se déconnecter'), 300, scrollable: find.byType(Scrollable).last);

    expect(find.byKey(const Key('menu_cahier_liaison_prototype')), findsNothing);
    expect(find.textContaining('Prototype local'), findsNothing);
  });

  testWidgets('version d’essai : cahier de liaison visible, avec la mention du prototype', (tester) async {
    await monter(tester, prototypes: true, role: RoleRacine.enseignant);
    await tester.tap(find.byKey(const Key('raccourci_profil')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('menu_cahier_liaison_prototype')), 300,
        scrollable: find.byType(Scrollable).last);

    expect(find.text('Prototype local — non synchronisé'), findsOneWidget);
  });
}
