import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/auth/supabase_auth_provider.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:ecoshop_client/features/auth/domain/telephone_profil.dart';
import 'package:ecoshop_client/features/cgu/application/cgu_providers.dart';
import 'package:ecoshop_client/features/cgu/domain/cgu_repository.dart';
import 'package:ecoshop_client/features/cgu/domain/cgu_statut.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/regionalisation/application/regionalisation_providers.dart';
import 'package:ecoshop_client/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show Session, User;

import '../../support/faux_auth_repository.dart';

/// Ouverture sans réseau (défaut constaté sur l'APK : première ouverture
/// très longue, sans message). Règle :
/// - copie sur le téléphone : accueil en 2 s au plus, bandeau « Hors
///   connexion — affichage des données enregistrées » ;
/// - aucune copie : « Pas de connexion… » avec « Réessayer » ;
/// - jamais de chargement sans message.
///
/// Trois situations du téléphone, délais réels de l'application (horloge
/// simulée) :
/// - mode avion : aucune connectivité, toute requête échoue tout de suite ;
/// - données coupées sans mode avion : aucune connectivité, l'adresse du
///   serveur ne se résout pas (erreur du journal du 25/10) ;
/// - réseau présent mais Internet bloqué : le téléphone se croit connecté,
///   le serveur ne répond jamais.

enum _Situation { enLigne, modeAvion, donneesCoupees, internetBloque }

const _compte = 'compte-awa';

class _Serveur {
  _Situation situation = _Situation.enLigne;

  Future<T> appel<T>(T Function() reponse) {
    switch (situation) {
      case _Situation.enLigne:
        return Future.value(reponse());
      case _Situation.modeAvion:
        return Future.error(const SocketException('Network is unreachable'));
      case _Situation.donneesCoupees:
        return Future.error(http.ClientException(
            "SocketException: Failed host lookup: 'nlydvaszgdtjohneggqt.supabase.co' "
            '(OS Error: No address associated with hostname, errno = 7)'));
      case _Situation.internetBloque:
        return Completer<T>().future; // Jamais de réponse.
    }
  }
}

class _Depot extends FauxAuthRepository {
  _Depot(this.serveur);

  final _Serveur serveur;

  @override
  Future<Profil?> profilCourant() => serveur.appel(() => Profil(
        id: _compte,
        identifiantCanonique: 'awa@exemple.com',
        statutCompte: StatutCompte.actif,
        roleRacine: RoleRacine.parent,
        prenom: 'Awa',
        identifiantEcoshop: 'EC-7K4M-2QM',
      ));

  @override
  Future<List<Etablissement>> mesEtablissements() => serveur.appel(() => [etablissementTest('e1', 'Bambino')]);

  @override
  Future<bool> ficheLiee() => serveur.appel(() => true);

  @override
  Future<TelephoneProfil?> monTelephone() =>
      serveur.appel(() => const TelephoneProfil(numero: '+224620000000', verifie: true));
}

class _Cgu implements CguRepository {
  _Cgu(this.serveur);

  final _Serveur serveur;

  @override
  Future<CguStatut?> statut() => serveur.appel(() => CguStatut(
        cguVersionId: 'v1',
        parcours: 'complet',
        numeroVersion: '1.0',
        contenu: 'Conditions',
        publieeLe: DateTime.utc(2026, 9, 1),
        acceptee: true,
      ));

  @override
  Future<void> accepter(String cguVersionId) async {}
}

class _RegionalisationVue extends OnboardingRegionalisationNotifier {
  @override
  Future<bool> build() async => true;
}

Session _session() => Session(
      accessToken: 'jeton',
      tokenType: 'bearer',
      user: const User(
        id: _compte,
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-10-22T08:00:00Z',
      ),
    );

final _accueil = find.byKey(const Key('raccourci_profil'));
final _bandeau = find.text('Hors connexion — affichage des données enregistrées');
final _sansConnexion = find.text('Pas de connexion. Vos informations s’afficheront dès le retour du réseau.');
final _chargement = find.byKey(const Key('message_chargement'));

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  var lancement = 0;
  late StateProvider<bool> reseau;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    serveur = _Serveur();
  });
  tearDown(() => db.close());

  /// Un lancement de l'application (même base : le stockage du téléphone).
  Future<void> lancer(WidgetTester tester, {required bool connectivite}) async {
    reseau = StateProvider<bool>((ref) => connectivite);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      key: ValueKey(lancement++),
      overrides: [
        sessionOuverteProvider.overrideWithValue(true),
        sessionProvider.overrideWithValue(_session()),
        authRepositoryProvider.overrideWithValue(_Depot(serveur)),
        cguRepositoryProvider.overrideWithValue(_Cgu(serveur)),
        databaseProvider.overrideWithValue(db),
        onboardingRegionalisationVuProvider.overrideWith(_RegionalisationVue.new),
        estEnLigneProvider.overrideWith((ref) => ref.watch(reseau)),
      ],
      child: const EcoShopApp(configure: true),
    ));
  }

  /// Avance l'horloge par petits pas en vérifiant qu'aucun chargement n'est
  /// muet ; rend vrai dès que [condition] est remplie.
  Future<Duration?> attendre(WidgetTester tester, Finder cible, Duration limite) async {
    const pas = Duration(milliseconds: 100);
    var ecoule = Duration.zero;
    while (ecoule <= limite) {
      await tester.pump(pas);
      ecoule += pas;
      if (cible.evaluate().isNotEmpty) return ecoule;
      if (find.byType(CircularProgressIndicator).evaluate().isNotEmpty) {
        expect(_chargement, findsOneWidget, reason: 'jamais de chargement sans message');
      }
    }
    return null;
  }

  /// Ferme l'application et laisse expirer les délais en cours.
  Future<void> fermer(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  Future<void> premierLancementEnLigne(WidgetTester tester) async {
    await lancer(tester, connectivite: true);
    expect(await attendre(tester, _accueil, const Duration(seconds: 2)), isNotNull);
    expect(_bandeau, findsNothing, reason: 'en ligne : pas de bandeau');
    await fermer(tester);
  }

  for (final (situation, connectivite) in [
    (_Situation.modeAvion, false),
    (_Situation.donneesCoupees, false),
    (_Situation.internetBloque, true),
  ]) {
    testWidgets('${situation.name}, copie sur le téléphone : accueil et bandeau en 2 s au plus', (tester) async {
      await premierLancementEnLigne(tester);

      serveur.situation = situation;
      await lancer(tester, connectivite: connectivite);

      final accueil = await attendre(tester, _accueil, const Duration(seconds: 2));
      expect(accueil, isNotNull, reason: 'accueil en 2 s au plus');
      final bandeau = await attendre(tester, _bandeau, const Duration(seconds: 2) - accueil!);
      expect(bandeau, isNotNull, reason: 'bandeau en 2 s au plus après le lancement');
      expect(tester.takeException(), isNull);

      await fermer(tester);
    });

    testWidgets('${situation.name}, aucune copie : « Pas de connexion » et « Réessayer »', (tester) async {
      serveur.situation = situation;
      await lancer(tester, connectivite: connectivite);

      // Sans connectivité : tout de suite. Internet bloqué : au plus le
      // délai de lecture (8 s), avec « Ouverture de votre espace… » d'ici là.
      final limite = connectivite ? const Duration(seconds: 9) : const Duration(seconds: 2);
      expect(await attendre(tester, _sansConnexion, limite), isNotNull);
      expect(find.text('Réessayer'), findsOneWidget);

      // Retour du réseau, « Réessayer » : l'application s'ouvre.
      serveur.situation = _Situation.enLigne;
      ProviderScope.containerOf(tester.element(_sansConnexion)).read(reseau.notifier).state = true;
      await tester.tap(find.text('Réessayer'));
      expect(await attendre(tester, _accueil, const Duration(seconds: 2)), isNotNull);
      expect(tester.takeException(), isNull);

      await fermer(tester);
    });
  }
}
