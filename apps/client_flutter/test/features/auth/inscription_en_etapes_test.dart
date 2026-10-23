import 'package:drift/native.dart';
import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/auth/application/inscription_providers.dart';
import 'package:ecoshop_client/features/auth/domain/destination_session.dart';
import 'package:ecoshop_client/features/auth/domain/inscription_en_cours.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:ecoshop_client/features/auth/presentation/ecran_choix_role.dart';
import 'package:ecoshop_client/features/auth/presentation/ecran_connexion.dart';
import 'package:ecoshop_client/features/auth/presentation/ecran_nom_profil.dart';
import 'package:ecoshop_client/features/auth/presentation/ecran_recapitulatif.dart';
import 'package:ecoshop_client/features/cgu/application/cgu_providers.dart';
import 'package:ecoshop_client/features/cgu/domain/cgu_statut.dart';
import 'package:ecoshop_client/features/coquille/presentation/coquille_app.dart';
import 'package:ecoshop_client/features/coquille/presentation/garde_session.dart';
import 'package:ecoshop_client/features/regionalisation/application/regionalisation_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth_repository.dart';

/// REG-18, partie B : inscription en étapes. Espace et nom saisis avant la
/// vérification, gardés sur le téléphone, appliqués après ; représentant
/// d'un établissement ; personnel invité ; récapitulatif.

class _RegionalisationVue extends OnboardingRegionalisationNotifier {
  @override
  Future<bool> build() async => true;
}

class _CguRienAAccepter extends CguStatutNotifier {
  @override
  Future<CguStatut?> build() async => null;
}

/// Compte tout juste créé par la vérification : ni rôle ni nom.
Profil _nouveauCompte({bool finalise = false}) => Profil(
      id: 'p-nouveau',
      identifiantCanonique: 'awa@exemple.com',
      statutCompte: StatutCompte.actif,
      identifiantEcoshop: 'EC-7K4M-2QM',
      inscriptionFinalisee: finalise,
    );

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.pourTests(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<ProviderContainer> monter(WidgetTester tester, {required bool session, required FauxAuthRepository faux}) async {
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(faux),
      sessionOuverteProvider.overrideWithValue(session),
      databaseProvider.overrideWithValue(db),
      onboardingRegionalisationVuProvider.overrideWith(_RegionalisationVue.new),
      cguStatutProvider.overrideWith(_CguRienAAccepter.new),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: RacineApp()),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  group('« Créer un compte » avant la vérification', () {
    testWidgets('espace, puis nom, puis vérification ; saisies gardées sur le téléphone', (tester) async {
      final c = await monter(tester, session: false, faux: FauxAuthRepository());

      await tester.tap(find.byKey(const Key('bouton_creer_compte')));
      await tester.pumpAndSettle();
      // Les trois espaces, dont le représentant d'un établissement.
      expect(find.text('Élève'), findsOneWidget);
      expect(find.text('Parent'), findsOneWidget);
      expect(find.text('Je représente un établissement'), findsOneWidget);

      await tester.tap(find.byKey(const Key('espace_parent')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('champ_prenom')), 'Awa');
      await tester.enterText(find.byKey(const Key('champ_nom')), 'Bah');
      await tester.tap(find.byKey(const Key('bouton_suivant_nom')));
      await tester.pumpAndSettle();

      expect(find.byType(EcranConnexion), findsOneWidget);
      expect(find.textContaining('votre compte est créé à cette étape'), findsOneWidget);
      final gardee = c.read(inscriptionEnCoursProvider).value!;
      expect(gardee.espace, EspaceInscription.parent);
      expect((gardee.prenom, gardee.nom), ('Awa', 'Bah'));
    });

    testWidgets('nom obligatoire, sans chiffre ni @', (tester) async {
      await monter(tester, session: false, faux: FauxAuthRepository());
      await tester.tap(find.byKey(const Key('bouton_creer_compte')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('espace_eleve')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('champ_prenom')), 'Awa2');
      await tester.tap(find.byKey(const Key('bouton_suivant_nom')));
      await tester.pumpAndSettle();

      expect(find.text('Sans chiffre ni @.'), findsOneWidget);
      expect(find.text('Obligatoire.'), findsOneWidget);
      expect(find.byType(EcranConnexion), findsNothing);
    });

    testWidgets('retour d’une étape à l’autre jusqu’à l’accueil', (tester) async {
      await monter(tester, session: false, faux: FauxAuthRepository());
      await tester.tap(find.byKey(const Key('bouton_creer_compte')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('espace_eleve')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('retour_creation')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('espace_eleve')), findsOneWidget);
      await tester.tap(find.byKey(const Key('retour_creation')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bouton_creer_compte')), findsOneWidget);
    });

    testWidgets('« Se connecter » oublie une saisie de création restée sur le téléphone', (tester) async {
      final c = await monter(tester, session: false, faux: FauxAuthRepository());
      await c.read(inscriptionEnCoursProvider.notifier).enregistrer(espace: EspaceInscription.eleve, prenom: 'A', nom: 'B');

      await tester.tap(find.byKey(const Key('bouton_se_connecter')));
      await tester.pumpAndSettle();

      expect(c.read(inscriptionEnCoursProvider).value, isNull);
    });
  });

  group('Après la vérification', () {
    testWidgets('saisies faites avant : appliquées sans rien redemander, puis récapitulatif', (tester) async {
      final faux = FauxAuthRepository(profil: _nouveauCompte());
      final c = await monter(tester, session: false, faux: faux);
      await c.read(inscriptionEnCoursProvider.notifier).enregistrer(espace: EspaceInscription.parent, prenom: 'Awa', nom: 'Bah');

      // La vérification ouvre la session.
      c.updateOverrides([
        authRepositoryProvider.overrideWithValue(faux),
        sessionOuverteProvider.overrideWithValue(true),
        databaseProvider.overrideWithValue(db),
        onboardingRegionalisationVuProvider.overrideWith(_RegionalisationVue.new),
        cguStatutProvider.overrideWith(_CguRienAAccepter.new),
      ]);
      await tester.pumpAndSettle();

      expect(faux.appels, contains('finaliserInscription:parent:Awa:Bah'));
      expect(c.read(inscriptionEnCoursProvider).value, isNull, reason: 'saisie appliquée puis effacée');
      expect(find.byType(EcranRecapitulatif), findsOneWidget);
      expect(find.text('Bienvenue, Awa'), findsOneWidget);
      expect(find.text('EC-7K4M-2QM'), findsOneWidget);
      expect(find.textContaining('Ajouter un enfant'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bouton_commencer')));
      await tester.pumpAndSettle();
      expect(find.byType(CoquilleApp), findsOneWidget);
      expect(c.read(destinationProvider), DestinationSession.accueil);
    });

    testWidgets('« Se connecter » avec une adresse inconnue : espace et nom demandés ici', (tester) async {
      final faux = FauxAuthRepository(profil: _nouveauCompte());
      await monter(tester, session: true, faux: faux);

      expect(find.byType(EcranChoixRole), findsOneWidget);
      expect(find.text('Encore une étape'), findsOneWidget);
      await tester.tap(find.byKey(const Key('espace_eleve')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('champ_prenom')), 'Mamadou');
      await tester.enterText(find.byKey(const Key('champ_nom')), 'Diallo');
      await tester.ensureVisible(find.byKey(const Key('bouton_continuer_espace')));
      await tester.tap(find.byKey(const Key('bouton_continuer_espace')));
      await tester.pumpAndSettle();

      expect(faux.appels, contains('finaliserInscription:eleve:Mamadou:Diallo'));
      expect(faux.profil?.roleRacine, RoleRacine.eleve);
    });

    testWidgets('« Je représente un établissement » : nom enregistré, aucun rôle, demande et réseau proposés',
        (tester) async {
      final faux = FauxAuthRepository(profil: _nouveauCompte());
      await monter(tester, session: true, faux: faux);

      await tester.tap(find.byKey(const Key('espace_etablissement')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('champ_prenom')), 'Ibrahima');
      await tester.enterText(find.byKey(const Key('champ_nom')), 'Sow');
      await tester.ensureVisible(find.byKey(const Key('bouton_continuer_espace')));
      await tester.tap(find.byKey(const Key('bouton_continuer_espace')));
      await tester.pumpAndSettle();

      expect(faux.appels, contains('definirMonNom:Ibrahima:Sow'));
      expect(faux.appels.where((a) => a.startsWith('finaliserInscription')), isEmpty);
      expect(faux.profil?.roleRacine, isNull, reason: 'le rôle Direction vient de la validation GSG');
      expect(find.byKey(const Key('bouton_creer_etablissement')), findsOneWidget);
      expect(find.byKey(const Key('espace_reseau')), findsOneWidget);

      // Retour possible vers élève ou parent.
      await tester.ensureVisible(find.byKey(const Key('autre_espace')));
      await tester.tap(find.byKey(const Key('autre_espace')));
      await tester.pumpAndSettle();
      expect(find.text('Encore une étape'), findsOneWidget);
    });

    testWidgets('nom fourni par Google : pré-rempli et seulement confirmé', (tester) async {
      final faux = FauxAuthRepository(profil: _nouveauCompte());
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(faux),
        sessionOuverteProvider.overrideWithValue(true),
        databaseProvider.overrideWithValue(db),
        onboardingRegionalisationVuProvider.overrideWith(_RegionalisationVue.new),
        cguStatutProvider.overrideWith(_CguRienAAccepter.new),
        nomsGoogleProvider.overrideWithValue((prenom: 'Awa Mariama', nom: 'Bah')),
      ]);
      addTearDown(container.dispose);
      // Google choisi à l'étape du nom, sans saisie.
      await container.read(inscriptionEnCoursProvider.notifier).enregistrer(espace: EspaceInscription.parent);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: RacineApp())));
      await tester.pumpAndSettle();

      expect(find.text('Encore une étape'), findsOneWidget);
      expect(tester.widget<TextFormField>(find.byKey(const Key('champ_prenom'))).controller?.text, 'Awa Mariama');
      expect(tester.widget<TextFormField>(find.byKey(const Key('champ_nom'))).controller?.text, 'Bah');
      await tester.ensureVisible(find.byKey(const Key('bouton_continuer_espace')));
      await tester.tap(find.byKey(const Key('bouton_continuer_espace')));
      await tester.pumpAndSettle();

      expect(faux.appels, contains('finaliserInscription:parent:Awa Mariama:Bah'));
    });

    testWidgets('personnel invité sans nom : nom demandé une fois, sans choix d’espace', (tester) async {
      final faux = FauxAuthRepository(
        profil: const Profil(
          id: 'p-prof',
          identifiantCanonique: 'prof@ecole.org',
          statutCompte: StatutCompte.actif,
          roleRacine: RoleRacine.enseignant,
          inscriptionFinalisee: false,
        ),
      );
      await monter(tester, session: true, faux: faux);

      expect(find.byType(EcranNomProfil), findsOneWidget);
      await tester.enterText(find.byKey(const Key('champ_prenom')), 'Fatou');
      await tester.enterText(find.byKey(const Key('champ_nom')), 'Camara');
      await tester.tap(find.byKey(const Key('bouton_valider_nom')));
      await tester.pumpAndSettle();

      expect(faux.appels, contains('definirMonNom:Fatou:Camara'));
      expect(find.byType(EcranNomProfil), findsNothing);
    });

    testWidgets('compte existant (déjà en service) : jamais renvoyé dans l’inscription', (tester) async {
      await monter(tester, session: true, faux: FauxAuthRepository(profil: profilTest(role: RoleRacine.parent)));
      expect(find.byType(CoquilleApp), findsOneWidget);
    });
  });

  group('Règles', () {
    test('nom : obligatoire, 80 caractères, sans chiffre ni @', () {
      expect(verifierNom(' Awa '), isNull);
      expect(verifierNom(''), isNotNull);
      expect(verifierNom('a' * 81), isNotNull);
      expect(verifierNom('awa@x'), isNotNull);
      expect(verifierNom('Awa2'), isNotNull);
    });

    test('noms Google : prénom et nom séparés, ou nom complet découpé', () {
      expect(nomsDepuisGoogle({'given_name': 'Awa', 'family_name': 'Bah'}), (prenom: 'Awa', nom: 'Bah'));
      expect(nomsDepuisGoogle({'full_name': 'Awa Mariama Bah'}), (prenom: 'Awa', nom: 'Mariama Bah'));
      expect(nomsDepuisGoogle(null), (prenom: null, nom: null));
    });

    test('saisie oubliée au bout de 24 h', () {
      final i = InscriptionEnCours(espace: EspaceInscription.eleve, creeLe: DateTime(2026, 10, 23, 8));
      expect(i.estValide(DateTime(2026, 10, 24, 7)), isTrue);
      expect(i.estValide(DateTime(2026, 10, 24, 9)), isFalse);
    });

    test('garde : nom à compléter seulement pour un compte jamais finalisé', () {
      DestinationSession d(Profil p) =>
          GardeSession.resoudre(sessionOuverte: true, profil: p, ficheLiee: true, nombreEtablissements: 1);
      const sansNom = Profil(id: 'p', identifiantCanonique: 'x', statutCompte: StatutCompte.actif, roleRacine: RoleRacine.enseignant);
      expect(d(sansNom), DestinationSession.accueil, reason: 'compte d’avant REG-18 : rien à redemander');
      const invite = Profil(
          id: 'p', identifiantCanonique: 'x', statutCompte: StatutCompte.actif, roleRacine: RoleRacine.enseignant, inscriptionFinalisee: false);
      expect(d(invite), DestinationSession.nomACompleter);
      expect(
        GardeSession.resoudre(sessionOuverte: true, profil: sansNom, ficheLiee: true, nombreEtablissements: 1, recapitulatifAMontrer: true),
        DestinationSession.recapitulatif,
      );
    });
  });
}
