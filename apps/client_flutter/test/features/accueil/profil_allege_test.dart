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
    // La liste ne construit que ce qui est à l'écran (REG-32 a ajouté
    // « Relier mon enfant ») : défiler jusqu'à chaque élément avant de le vérifier.
    final liste = find.byType(Scrollable).first;
    // Dans l'ordre de la page, de haut en bas.
    final attendus = <Finder>[
      find.text('MON COMPTE'),
      find.byKey(const Key('profil_mes_informations')),
      find.byKey(const Key('profil_mes_invitations')),
      find.byKey(const Key('profil_relier_enfant')),
      find.text('SÉCURITÉ'),
      find.byKey(const Key('menu_code_secret')),
      find.byKey(const Key('menu_mes_appareils')),
      find.text('PRÉFÉRENCES'),
      find.byKey(const Key('menu_langue_affichage')),
    ];
    for (final f in attendus) {
      await tester.scrollUntilVisible(f, 200, scrollable: liste);
      expect(f, findsOneWidget, reason: f.toString());
    }
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
    await tester.scrollUntilVisible(find.text('PRÉFÉRENCES'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('PRÉFÉRENCES'), findsOneWidget);
    expect(find.text('Scan-Exercice'), findsNothing);
  });
}
