import 'package:drift/native.dart';
import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/core/securite/biometrie.dart';
import 'package:ecoshop_client/core/securite/code_secret.dart';
import 'package:ecoshop_client/core/securite/gardien_actions_sensibles.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/auth/domain/destination_session.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:ecoshop_client/features/coquille/application/verrou_controller.dart';
import 'package:ecoshop_client/features/coquille/presentation/ecran_verrou.dart';
import 'package:ecoshop_client/features/coquille/presentation/gardien_verrou.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth_repository.dart';

/// REG-18, partie C : verrou de l'application, règle par règle.
const _code = '482617';

Profil _profil(RoleRacine role) => Profil(
  id: 'compte-1',
  identifiantCanonique: 'awa@exemple.org',
  statutCompte: StatutCompte.actif,
  roleRacine: role,
  prenom: 'Awa',
);

/// Libellés lus par l'accessibilité (arbre réel, pas l'état mémorisé).
List<String> _libellesAccessibles(WidgetTester tester) {
  final libelles = <String>[];
  void visiter(SemanticsNode noeud) {
    if (noeud.label.isNotEmpty) libelles.add(noeud.label);
    noeud.visitChildren((enfant) {
      visiter(enfant);
      return true;
    });
  }

  final racine = tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;
  if (racine != null) visiter(racine);
  return libelles;
}

class _Banc {
  _Banc(RoleRacine role, {bool avecCode = true, bool identiteVerifiee = false}) {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    auth = FauxAuthRepository(profil: _profil(role));
    container = ProviderContainer(overrides: overrides);
    if (identiteVerifiee) container.read(identiteVerifieeProvider.notifier).state = true;
    if (avecCode) _creation = service.creer('compte-1', _code);
  }

  late final AppDatabase db;
  late final FauxAuthRepository auth;
  late final ProviderContainer container;
  final coffre = CoffreFortMemoire();
  final biometrie = BiometrieMemoire();
  late final service = ServiceCodeSecret(coffre: coffre, iterations: 1000);
  DateTime maintenant = DateTime(2026, 10, 23, 8);
  Future<void>? _creation;

  List<Override> get overrides => [
    databaseProvider.overrideWithValue(db),
    authRepositoryProvider.overrideWithValue(auth),
    sessionOuverteProvider.overrideWithValue(true),
    verrouActifProvider.overrideWithValue(true),
    coffreFortProvider.overrideWithValue(coffre),
    serviceCodeSecretProvider.overrideWithValue(service),
    biometrieProvider.overrideWithValue(biometrie),
    horlogeVerrouProvider.overrideWithValue(() => maintenant),
  ];

  VerrouController get verrou => container.read(verrouControllerProvider.notifier);
  EtatVerrou get etat => container.read(verrouControllerProvider);

  /// Attend que le verrou ait lu le coffre.
  Future<void> pret() async {
    await _creation;
    container.listen(verrouControllerProvider, (_, _) {});
    await container.read(profilProvider.future);
    for (var i = 0; i < 50 && (etat.phase == PhaseVerrou.chargement || etat.phase == PhaseVerrou.inactif); i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Arrière-plan pendant [duree], puis retour.
  void absence(Duration duree) {
    verrou.enArrierePlan();
    maintenant = maintenant.add(duree);
    verrou.auPremierPlan();
  }

  void fermer() {
    container.dispose();
    db.close();
  }
}

void main() {
  group('ouverture', () {
    test('téléphone déjà connu : verrouillée à l’ouverture', () async {
      final banc = _Banc(RoleRacine.parent);
      await banc.pret();
      expect(banc.etat.phase, PhaseVerrou.verrouille);
      banc.fermer();
    });

    test('compte sans code (nouveau, ou créé avant REG-18) : création obligatoire', () async {
      final banc = _Banc(RoleRacine.parent, avecCode: false);
      await banc.pret();
      expect(banc.etat.phase, PhaseVerrou.codeACreer);
      // Après le numéro de téléphone, avant la langue et la région.
      final profil = _profil(RoleRacine.parent);
      expect(
        GardeSession.resoudre(
          sessionOuverte: true,
          profil: profil,
          ficheLiee: true,
          nombreEtablissements: 1,
          codeSecretACreer: true,
        ),
        DestinationSession.codeSecret,
      );
      expect(
        GardeSession.resoudre(
          sessionOuverte: true,
          profil: profil,
          ficheLiee: true,
          nombreEtablissements: 1,
          codeSecretACreer: true,
          telephoneAFournir: true,
        ),
        DestinationSession.telephoneProfil,
      );
      expect(
        GardeSession.resoudre(
          sessionOuverte: true,
          profil: profil,
          ficheLiee: true,
          nombreEtablissements: 1,
          codeSecretACreer: true,
          regionalisationVue: false,
        ),
        DestinationSession.codeSecret,
      );
      banc.fermer();
    });

    test('identité prouvée à l’instant (e-mail ou Google) : ouverte sans redemander le code', () async {
      final banc = _Banc(RoleRacine.parent, identiteVerifiee: true);
      await banc.pret();
      expect(banc.etat.phase, PhaseVerrou.ouvert);
      expect(banc.container.read(identiteVerifieeProvider), isFalse, reason: 'ne sert qu’une fois');
      banc.fermer();
    });

    test('hors connexion : le code est vérifié sur le téléphone, aucun appel au serveur', () async {
      final banc = _Banc(RoleRacine.parent);
      await banc.pret();
      final appelsAvant = List.of(banc.auth.appels);
      expect(await banc.verrou.saisirCode(_code), isA<CodeBon>());
      expect(banc.etat.phase, PhaseVerrou.ouvert);
      expect(banc.auth.appels, appelsAvant);
      banc.fermer();
    });
  });

  group('délai après passage en arrière-plan, selon le rôle', () {
    final cas = {
      RoleRacine.adminGsg: 2,
      RoleRacine.adminContenu: 2,
      RoleRacine.direction: 5,
      RoleRacine.fondateurReseau: 5,
      RoleRacine.vendeur: 5,
      RoleRacine.enseignant: 15,
      RoleRacine.parent: 30,
      RoleRacine.eleve: 30,
    };
    for (final MapEntry(key: role, value: minutes) in cas.entries) {
      test('${role.code} : ouverte avant $minutes min, verrouillée à $minutes min', () async {
        final banc = _Banc(role);
        await banc.pret();
        await banc.verrou.saisirCode(_code);

        banc.absence(Duration(minutes: minutes) - const Duration(seconds: 1));
        expect(banc.etat.phase, PhaseVerrou.ouvert);

        banc.absence(Duration(minutes: minutes));
        expect(banc.etat.phase, PhaseVerrou.verrouille);
        banc.fermer();
      });
    }

    test('plusieurs passages en arrière-plan : le délai part du premier', () async {
      final banc = _Banc(RoleRacine.direction);
      await banc.pret();
      await banc.verrou.saisirCode(_code);
      banc.verrou.enArrierePlan();
      banc.maintenant = banc.maintenant.add(const Duration(minutes: 3));
      banc.verrou.enArrierePlan(); // écran éteint après passage en arrière-plan
      banc.maintenant = banc.maintenant.add(const Duration(minutes: 3));
      banc.verrou.auPremierPlan();
      expect(banc.etat.phase, PhaseVerrou.verrouille);
      banc.fermer();
    });
  });

  group('codes faux', () {
    test('essais restants affichés, puis 5ᵉ code faux : session fermée, code oublié', () async {
      final banc = _Banc(RoleRacine.parent);
      await banc.pret();
      for (final restants in [4, 3, 2, 1]) {
        expect(await banc.verrou.saisirCode('999990'), isA<CodeFaux>());
        expect(banc.etat.essaisRestants, restants);
      }
      expect(await banc.verrou.saisirCode('999990'), isA<CodeBloque>());
      expect(banc.auth.appels, contains('deconnecter'));
      expect(await banc.service.existe('compte-1'), isFalse, reason: 'nouveau code après reconnexion');
      banc.fermer();
    });

    test('code oublié : code effacé, session fermée (reconnexion par e-mail ou Google)', () async {
      final banc = _Banc(RoleRacine.enseignant);
      await banc.pret();
      await banc.verrou.codeOublie();
      expect(banc.auth.appels, contains('deconnecter'));
      expect(await banc.service.existe('compte-1'), isFalse);
      banc.fermer();
    });

    test('« Ce n’est pas moi » : déconnexion, le code du compte reste pour son retour', () async {
      final banc = _Banc(RoleRacine.parent);
      await banc.pret();
      await banc.verrou.ceNestPasMoi();
      expect(banc.auth.appels, contains('deconnecter'));
      expect(await banc.service.existe('compte-1'), isTrue);
      banc.fermer();
    });
  });

  group('empreinte', () {
    test('facultative : activée après le code, ouvre ; refusée : le code reste le recours', () async {
      final banc = _Banc(RoleRacine.parent, avecCode: false);
      await banc.pret();
      await banc.verrou.creerCode(_code, ouvrir: false);
      expect(banc.etat.phase, PhaseVerrou.codeACreer, reason: 'empreinte proposée avant d’ouvrir');
      expect(await banc.verrou.activerBiometrie(), isTrue);
      await banc.verrou.terminerCreation();
      expect(banc.etat.phase, PhaseVerrou.ouvert);

      banc.absence(const Duration(hours: 1));
      expect(banc.etat.phase, PhaseVerrou.verrouille);
      banc.biometrie.reussit = false;
      expect(await banc.verrou.deverrouillerParBiometrie(), isFalse);
      expect(banc.etat.phase, PhaseVerrou.verrouille);
      banc.biometrie.reussit = true;
      expect(await banc.verrou.deverrouillerParBiometrie(), isTrue);
      expect(banc.etat.phase, PhaseVerrou.ouvert);
      banc.fermer();
    });

    test('code trop facile refusé à la création', () async {
      final banc = _Banc(RoleRacine.parent, avecCode: false);
      await banc.pret();
      expect(() => banc.verrou.creerCode('123456'), throwsA(isA<CodeRefuse>()));
      banc.fermer();
    });
  });

  group('actions sensibles', () {
    test('le code est vérifié sans changer l’écran ; codes faux comptés comme au verrou', () async {
      final banc = _Banc(RoleRacine.direction, identiteVerifiee: true);
      await banc.pret();
      expect(banc.etat.phase, PhaseVerrou.ouvert);
      expect(await banc.verrou.saisirCode('999990', pourAction: true), isA<CodeFaux>());
      expect(await banc.verrou.saisirCode(_code, pourAction: true), isA<CodeBon>());
      expect(banc.etat.phase, PhaseVerrou.ouvert);
      banc.fermer();
    });
  });

  group('écran', () {
    late _Banc banc;

    Future<void> monter(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: banc.container,
          child: MaterialApp(
            navigatorKey: cleNavigateurRacine,
            builder: (context, enfant) => GardienVerrou(navigateur: cleNavigateurRacine, child: enfant!),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Encaissements du jour'))),
                    ),
                    child: const Text('Accueil'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> taper(WidgetTester tester, String code) async {
      for (final c in code.split('')) {
        await tester.tap(find.descendant(of: find.byType(EcranVerrou), matching: find.text(c)).last);
        await tester.pump();
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
    }

    testWidgets('verrou au-dessus des pages ouvertes ; contenu jamais visible derrière', (tester) async {
      final semantique = tester.ensureSemantics();
      banc = _Banc(RoleRacine.direction, identiteVerifiee: true);
      await tester.runAsync(banc.pret);
      await monter(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Accueil'));
      await tester.pumpAndSettle();
      expect(find.text('Encaissements du jour'), findsOneWidget);

      banc.absence(const Duration(minutes: 6));
      await tester.pumpAndSettle();
      expect(find.byType(EcranVerrou), findsOneWidget);
      expect(find.text('Bonjour Awa'), findsOneWidget);
      expect(find.text('Encaissements du jour').hitTestable(), findsNothing);
      expect(_libellesAccessibles(tester), isNot(contains('Encaissements du jour')));
      expect(_libellesAccessibles(tester), contains('Bonjour Awa'));

      await taper(tester, _code);
      semantique.dispose();
      expect(find.byType(EcranVerrou), findsNothing);
      expect(find.text('Encaissements du jour'), findsOneWidget, reason: 'on retrouve la page où on était');

      await tester.pumpWidget(const SizedBox());
      banc.fermer();
    });

    testWidgets('dès que l’application quitte le premier plan, un écran uni cache le contenu', (tester) async {
      banc = _Banc(RoleRacine.parent, identiteVerifiee: true);
      await tester.runAsync(banc.pret);
      await monter(tester);
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byKey(const ValueKey('cache_verrou')), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byKey(const ValueKey('cache_verrou')), findsNothing);
      expect(find.byType(EcranVerrou), findsNothing, reason: 'parent, retour immédiat : pas de verrou');

      await tester.pumpWidget(const SizedBox());
      banc.fermer();
    });

    testWidgets('action sensible : feuille du code, branchée par le gardien', (tester) async {
      banc = _Banc(RoleRacine.direction, identiteVerifiee: true);
      await tester.runAsync(banc.pret);
      await monter(tester);
      await tester.pumpAndSettle();
      expect(GardienActionsSensibles.estBranche, isTrue);

      final resultat = exigerCodeSecret('Enregistrer l’encaissement');
      await tester.pumpAndSettle();
      expect(find.text('Enregistrer l’encaissement'), findsOneWidget);
      for (final c in _code.split('')) {
        await tester.tap(find.text(c).last);
        await tester.pump();
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      await resultat; // ne lève pas : confirmé
      expect(find.text('Enregistrer l’encaissement'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      expect(GardienActionsSensibles.estBranche, isFalse);
      banc.fermer();
    });
  });
}
