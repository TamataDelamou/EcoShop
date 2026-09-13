import 'package:drift/native.dart';
import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:ecoshop_client/features/coquille/presentation/coquille_app.dart';
import 'package:ecoshop_client/features/coquille/presentation/garde_session.dart';
import 'package:ecoshop_client/features/auth/presentation/ecran_choix_espace.dart';
import 'package:ecoshop_client/features/auth/presentation/ecran_choix_role.dart';
import 'package:ecoshop_client/features/auth/presentation/ecran_connexion.dart';
import 'package:ecoshop_client/features/auth/presentation/ecran_liaison_fiche.dart';
import 'package:ecoshop_client/features/etablissement/presentation/ecran_selection_etablissement.dart';
import 'package:ecoshop_client/features/regionalisation/application/regionalisation_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth_repository.dart';

class _OnboardingRegionalisationToujoursVu extends OnboardingRegionalisationNotifier {
  @override
  Future<bool> build() async => true;
}

late AppDatabase _db;

/// Monte [RacineApp] avec un port simulé — aucun accès à Supabase.
///
/// `databaseProvider` est surchargé par une base Drift en mémoire (même
/// patron que les autres tests qui touchent le cache local, `_db` créée par
/// `setUp`/fermée par `tearDown` dans `main()`) : depuis D3,
/// `destinationProvider` lit `onboardingRegionalisationVuProvider`
/// (persistance locale de l'étape Langue/Région), ce qui n'était pas le cas
/// avant — sans cette surcharge, la vraie base tente d'ouvrir un fichier via
/// `path_provider`, indisponible en test, et `pumpAndSettle` ne se stabilise
/// jamais. `onboardingRegionalisationVuProvider` est lui-même figé à "déjà
/// vue" : ce fichier teste la progression de session par rôle, pas l'étape
/// D3 elle-même (couverte séparément par
/// `test/features/regionalisation/ecran_onboarding_regionalisation_test.dart`
/// et par `GardeSession.resoudre` dans `garde_session_test.dart`).
Future<void> monter(
  WidgetTester tester, {
  required bool session,
  required FauxAuthRepository faux,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(faux),
        sessionOuverteProvider.overrideWithValue(session),
        databaseProvider.overrideWithValue(_db),
        onboardingRegionalisationVuProvider.overrideWith(_OnboardingRegionalisationToujoursVu.new),
      ],
      child: const MaterialApp(home: RacineApp()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _db = AppDatabase.pourTests(NativeDatabase.memory()));
  tearDown(() => _db.close());

  testWidgets('sans session, affiche le choix d’espace', (tester) async {
    await monter(tester, session: false, faux: FauxAuthRepository());
    expect(find.byType(EcranChoixEspace), findsOneWidget);
    expect(find.byType(EcranConnexion), findsNothing);
  });

  testWidgets('choisir un espace mène à la connexion OTP (un seul mécanisme d’auth)', (tester) async {
    await monter(tester, session: false, faux: FauxAuthRepository());
    await tester.tap(find.text('Marketplace'));
    await tester.pumpAndSettle();
    expect(find.byType(EcranConnexion), findsOneWidget);
  });

  testWidgets('rôle non défini, affiche le choix de rôle', (tester) async {
    await monter(
      tester,
      session: true,
      faux: FauxAuthRepository(profil: profilTest(role: null)),
    );
    expect(find.byType(EcranChoixRole), findsOneWidget);
  });

  testWidgets('le choix de rôle ne propose que Élève et Parent (ch. 5.2)',
      (tester) async {
    await monter(
      tester,
      session: true,
      faux: FauxAuthRepository(profil: profilTest(role: null)),
    );

    expect(find.text('Élève'), findsOneWidget);
    expect(find.text('Parent'), findsOneWidget);
    // Aucun rôle à privilège n'est proposé : ils passent par invitation.
    expect(find.text('Direction'), findsNothing);
    expect(find.text('Enseignant'), findsNothing);
  });

  testWidgets('élève sans fiche liée, affiche la liaison de fiche',
      (tester) async {
    await monter(
      tester,
      session: true,
      faux: FauxAuthRepository(
        profil: profilTest(role: RoleRacine.eleve),
        fiche: false,
      ),
    );
    expect(find.byType(EcranLiaisonFiche), findsOneWidget);
  });

  testWidgets('plusieurs établissements, affiche le sélecteur', (tester) async {
    await monter(
      tester,
      session: true,
      faux: FauxAuthRepository(
        profil: profilTest(role: RoleRacine.enseignant),
        etablissements: [
          etablissementTest('e1', 'Lycee Innovation'),
          etablissementTest('e2', 'College Energie'),
        ],
      ),
    );

    expect(find.byType(EcranSelectionEtablissement), findsOneWidget);
    expect(find.text('Lycee Innovation'), findsOneWidget);
  });

  testWidgets('compte suspendu, aucun accès à la coquille', (tester) async {
    await monter(
      tester,
      session: true,
      faux: FauxAuthRepository(
        profil: profilTest(statut: StatutCompte.suspendu),
      ),
    );

    expect(find.text('Compte indisponible'), findsOneWidget);
    expect(find.byType(CoquilleApp), findsNothing);
  });

  testWidgets('parcours complet, affiche la coquille', (tester) async {
    await monter(
      tester,
      session: true,
      faux: FauxAuthRepository(profil: profilTest(role: RoleRacine.parent)),
    );
    expect(find.byType(CoquilleApp), findsOneWidget);
  });

  testWidgets('la coquille n’expose que les onglets du rôle', (tester) async {
    await monter(
      tester,
      session: true,
      faux: FauxAuthRepository(profil: profilTest(role: RoleRacine.vendeur)),
    );

    // Un vendeur n'a ni scolarité ni moteur de révision.
    expect(find.text('Boutique'), findsWidgets);
    expect(find.text('Scolarité'), findsNothing);
    expect(find.text('Révision'), findsNothing);
  });

  group('OngletCoquille.pourRole', () {
    test('l’élève accède au moteur de révision, pas le parent', () {
      expect(
        OngletCoquille.pourRole(RoleRacine.eleve),
        contains(OngletCoquille.revision),
      );
      expect(
        OngletCoquille.pourRole(RoleRacine.parent),
        isNot(contains(OngletCoquille.revision)),
      );
    });

    test('un rôle inconnu retombe sur le strict minimum', () {
      expect(
        OngletCoquille.pourRole(null),
        [OngletCoquille.accueil, OngletCoquille.profil],
      );
    });
  });
}
