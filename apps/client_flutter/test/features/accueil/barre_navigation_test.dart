import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/features/accueil/presentation/ecrans_destinations.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// REG-21, étape 1 : destinations de la barre du bas.
Profil _profil(RoleRacine role) => Profil(
  id: 'c1',
  identifiantCanonique: 'a@b.org',
  statutCompte: StatutCompte.actif,
  roleRacine: role,
  prenom: 'Awa',
);

Future<void> _monter(WidgetTester tester, Widget ecran) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      etablissementActifProvider.overrideWithValue(
        Etablissement.depuisJson({'id': 'e1', 'nom': 'École A', 'slug': 'a', 'devise_code': 'GNF'}),
      ),
    ],
    child: MaterialApp(home: ecran),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Messages, parent : annonces et cahier de liaison', (tester) async {
    await _monter(tester, EcranMessages(profil: _profil(RoleRacine.parent), badges: const {'annonces_non_lues': 3}));
    expect(find.byKey(const Key('messages_annonces')), findsOneWidget);
    expect(find.byKey(const Key('messages_cahier')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('Messages : le badge est lu par TalkBack (« Annonces, 3 nouvelles »)', (tester) async {
    final semantique = tester.ensureSemantics();
    await _monter(tester, EcranMessages(profil: _profil(RoleRacine.parent), badges: const {'annonces_non_lues': 3}));
    expect(find.bySemanticsLabel('Annonces, 3 nouvelles'), findsOneWidget);
    semantique.dispose();
  });

  testWidgets('Messages, vendeur : pas de cahier de liaison', (tester) async {
    await _monter(tester, EcranMessages(profil: _profil(RoleRacine.vendeur)));
    expect(find.byKey(const Key('messages_annonces')), findsOneWidget);
    expect(find.byKey(const Key('messages_cahier')), findsNothing);
  });

  testWidgets('Messages, enseignant : écrire aux parents', (tester) async {
    await _monter(tester, EcranMessages(profil: _profil(RoleRacine.enseignant)));
    expect(find.text('Écrivez aux parents au sujet d’un élève'), findsOneWidget);
  });
}
