import 'package:drift/native.dart';
import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/auth/application/espace_providers.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:ecoshop_client/features/cgu/application/cgu_providers.dart';
import 'package:ecoshop_client/features/cgu/domain/cgu_statut.dart';
import 'package:ecoshop_client/features/coquille/presentation/entete_utilisateur.dart';
import 'package:ecoshop_client/features/coquille/presentation/garde_session.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
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

Profil _profil(RoleRacine role) => Profil(
      id: 'p1',
      identifiantCanonique: 'awa@exemple.org',
      statutCompte: StatutCompte.actif,
      roleRacine: role,
      prenom: 'Awa',
      nom: 'Bah',
    );

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.pourTests(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> monter(WidgetTester tester, FauxAuthRepository auth) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        sessionOuverteProvider.overrideWithValue(true),
        databaseProvider.overrideWithValue(db),
        onboardingRegionalisationVuProvider.overrideWith(_RegionalisationVue.new),
        cguStatutProvider.overrideWith(_CguRienAAccepter.new),
      ],
      child: const MaterialApp(home: RacineApp()),
    ));
    await tester.pumpAndSettle();
  }

  String texte(WidgetTester tester, Key cle) =>
      tester.widget<Text>(find.descendant(of: find.byKey(cle), matching: find.byType(Text)).first).data!;

  testWidgets('vendeur : nom en grand, rôle en étiquette, sans bouton « Ajouter »', (tester) async {
    await monter(tester, FauxAuthRepository(profil: _profil(RoleRacine.vendeur)));

    expect(tester.widget<Text>(find.byKey(const Key('entete_nom'))).data, 'Awa Bah');
    expect(texte(tester, const Key('entete_role')), 'Vendeur');
    expect(find.byKey(const Key('entete_etablissement')), findsNothing, reason: 'aucun établissement');
    expect(find.byKey(const Key('entete_ajouter_enfant')), findsNothing);
  });

  testWidgets('parent : « Ajouter » sur la ligne du nom', (tester) async {
    await monter(tester, FauxAuthRepository(profil: _profil(RoleRacine.parent)));

    final nom = tester.getCenter(find.byKey(const Key('entete_nom')));
    final ajouter = tester.getCenter(find.byKey(const Key('entete_ajouter_enfant')));
    expect((nom.dy - ajouter.dy).abs(), lessThan(24), reason: 'même ligne');
    expect(texte(tester, const Key('entete_role')), 'Parent');
  });

  testWidgets('plusieurs rôles : le rôle utilisé dans l’établissement actif, et l’établissement', (tester) async {
    // Parent par son inscription, enseignant dans son école.
    await monter(
      tester,
      FauxAuthRepository(
        profil: _profil(RoleRacine.parent),
        etablissements: const [
          Etablissement(id: 'e1', nom: 'École Bambino', slug: 'bambino', roleDansEtablissement: 'enseignant'),
        ],
      ),
    );

    expect(texte(tester, const Key('entete_role')), 'Enseignant');
    expect(find.descendant(of: find.byKey(const Key('entete_etablissement')), matching: find.text('École Bambino')),
        findsOneWidget);
  });

  testWidgets('REG-32 : enseignant dans une école, parent dans une autre — chaque espace avec son école',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FauxAuthRepository(
          profil: _profil(RoleRacine.enseignant),
          etablissements: const [
            Etablissement(id: 'e1', nom: 'École Bambino', slug: 'bambino', roleDansEtablissement: 'enseignant'),
          ],
        )),
        sessionOuverteProvider.overrideWithValue(true),
        databaseProvider.overrideWithValue(db),
        onboardingRegionalisationVuProvider.overrideWith(_RegionalisationVue.new),
        cguStatutProvider.overrideWith(_CguRienAAccepter.new),
        mesEspacesProvider.overrideWith((ref) async => const [
              EspaceEcole(role: RoleRacine.enseignant, etablissementId: 'e1', etablissementNom: 'École Bambino'),
              EspaceEcole(role: RoleRacine.parent, etablissementId: 'e2', etablissementNom: 'Lycée Donka', enfants: 2),
            ]),
      ],
      child: const MaterialApp(home: RacineApp()),
    ));
    await tester.pumpAndSettle();

    // Le travail d'abord : espace enseignant dans l'école active.
    expect(texte(tester, const Key('entete_role')), 'Enseignant');
    expect(find.descendant(of: find.byKey(const Key('entete_etablissement')), matching: find.text('École Bambino')),
        findsOneWidget);
    expect(find.byKey(const Key('entete_ajouter_enfant')), findsNothing);

    await tester.tap(find.byKey(const Key('entete_changer_espace')));
    await tester.pumpAndSettle();
    expect(find.text('Lycée Donka · 2 enfants'), findsOneWidget);
    expect(find.byKey(const Key('espace_parent_e1')), findsNothing, reason: 'pas parent dans l’école de son travail');

    await tester.tap(find.byKey(const Key('espace_parent_e2')));
    await tester.pumpAndSettle();
    expect(texte(tester, const Key('entete_role')), 'Parent');
    expect(find.descendant(of: find.byKey(const Key('entete_etablissement')), matching: find.text('Lycée Donka')),
        findsOneWidget, reason: 'l’école de l’espace parent, pas l’école active');
    expect(find.byKey(const Key('entete_ajouter_enfant')), findsOneWidget);
  });

  test('REG-32 : espaces calculés sur le téléphone', () {
    final espaces = espacesDepuis(
      const [
        Etablissement(id: 'a', nom: 'École A', slug: 'a', roleDansEtablissement: 'enseignant'),
        Etablissement(id: 'p', nom: 'École P', slug: 'p', roleDansEtablissement: 'parent'),
      ],
      const [
        (etablissementId: 'b', actif: true),
        (etablissementId: 'b', actif: true),
        (etablissementId: 'c', actif: false),
      ],
    );
    expect([for (final e in espaces) e.cle], ['enseignant@a', 'parent@b'],
        reason: 'parent seulement là où un enfant est lié et confirmé');
    expect(espaces.last.enfants, 2);
    expect(espaces.first.libelle, 'Enseignant · École A');
  });

  test('libellés des rôles', () {
    final p = _profil(RoleRacine.direction);
    expect(libelleRoleUtilise(p, null), 'Direction');
    expect(libelleRoleUtilise(p, const Etablissement(id: 'e', nom: 'E', slug: 'e', roleDansEtablissement: 'vendeur')),
        'Vendeur');
    expect(RoleRacine.fondateurReseau.libelle, 'Fondateur de réseau');
    expect(Etablissement.depuisJson(const Etablissement(id: 'e', nom: 'E', slug: 'e', roleDansEtablissement: 'direction').versJson())
        .roleDansEtablissement, 'direction', reason: 'gardé dans la copie locale');
  });
}
