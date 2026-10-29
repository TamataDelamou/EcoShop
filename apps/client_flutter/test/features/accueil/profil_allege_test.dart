import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/features/accueil/presentation/profil_allege.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:ecoshop_client/features/invitations/application/invitations_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// REG-21, étape 3 : « Mon profil » ne garde que le personnel.
void main() {
  Future<void> monter(WidgetTester tester, RoleRacine role) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [mesInvitationsProvider.overrideWith((ref) async => const [])],
      child: MaterialApp(
        home: Scaffold(
          body: VueProfilAllegee(
            profil: Profil(
              id: 'c1',
              identifiantCanonique: 'mariama@exemple.org',
              statutCompte: StatutCompte.actif,
              roleRacine: role,
              prenom: 'Mariama',
              nom: 'Sow',
              identifiantEcoshop: 'EC-7K4M-2Q9',
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('direction : seulement le personnel, « Mes appareils » dans Sécurité', (tester) async {
    await monter(tester, RoleRacine.direction);
    expect(find.text('Mariama Sow'), findsOneWidget);
    expect(find.text('Identifiant EC-7K4M-2Q9'), findsOneWidget);
    for (final section in ['MON COMPTE', 'SÉCURITÉ', 'PRÉFÉRENCES']) {
      expect(find.text(section), findsOneWidget, reason: section);
    }
    expect(find.byKey(const Key('profil_mes_informations')), findsOneWidget);
    expect(find.byKey(const Key('profil_mes_invitations')), findsOneWidget);
    expect(find.byKey(const Key('menu_code_secret')), findsOneWidget);
    expect(find.byKey(const Key('menu_mes_appareils')), findsOneWidget);
    expect(find.byKey(const Key('menu_langue_affichage')), findsOneWidget);
    // Plus aucun outil de travail : ils sont sur l'accueil.
    for (final travail in ['Comptabilité', 'Cahier des encaissements', 'Transport scolaire', 'Personnel & RH',
                           'Inscriptions en ligne', 'Boutique']) {
      expect(find.text(travail), findsNothing, reason: travail);
    }
    // « Se déconnecter » seul, tout en bas.
    await tester.scrollUntilVisible(find.text('Se déconnecter'), 300, scrollable: find.byType(Scrollable).first);
    final bas = tester.getTopLeft(find.text('Se déconnecter')).dy;
    expect(bas, greaterThan(tester.getTopLeft(find.byKey(const Key('menu_cgu'))).dy));
    expect(find.text('Se déconnecter'), findsOneWidget);

    // REG-31 : confidentialité dans « Vos données », suppression du compte
    // tout en bas (règle Google Play : facile à trouver).
    await tester.scrollUntilVisible(find.byKey(const Key('menu_confidentialite')), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('VOS DONNÉES'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('bouton_supprimer_compte')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const Key('bouton_supprimer_compte')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const Key('bouton_supprimer_compte'))).dy,
        greaterThan(tester.getTopLeft(find.text('Se déconnecter')).dy),
        reason: 'sous « Se déconnecter », tout en bas');
    expect(find.text('Supprimer mon compte'), findsOneWidget);
  });

  testWidgets('parent : l’avis du portail reste dans les préférences', (tester) async {
    await monter(tester, RoleRacine.parent);
    expect(find.text('PRÉFÉRENCES'), findsOneWidget);
    expect(find.text('Scan-Exercice'), findsNothing);
  });
}
