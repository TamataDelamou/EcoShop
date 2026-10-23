import 'package:drift/native.dart';
import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/auth/supabase_auth_provider.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/auth/application/relance_reseau.dart';
import 'package:ecoshop_client/features/auth/domain/destination_session.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:ecoshop_client/features/cgu/application/cgu_providers.dart';
import 'package:ecoshop_client/features/cgu/domain/cgu_repository.dart';
import 'package:ecoshop_client/features/cgu/domain/cgu_statut.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/regionalisation/application/regionalisation_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/faux_auth_repository.dart';

/// Défaut constaté sur l'APK : hors connexion, l'application ne s'ouvrait
/// pas, même avec une session ouverte ; au retour du réseau, il fallait la
/// fermer et la relancer. Profil, établissements, fiche et CGU sont
/// maintenant gardés sur le téléphone et relus au retour du réseau.

const _compte = 'compte-awa';

/// Serveur simulé : hors ligne, chaque appel échoue comme sans réseau.
class _Serveur {
  bool enLigne = true;
  String prenom = 'Awa';
  int appels = 0;

  Future<T> appel<T>(T Function() reponse) async {
    appels++;
    if (!enLigne) throw http.ClientException('Failed host lookup');
    return reponse();
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
        prenom: serveur.prenom,
        identifiantEcoshop: 'EC-7K4M-2QM',
      ));

  @override
  Future<List<Etablissement>> mesEtablissements() => serveur.appel(() => [etablissementTest('e1', 'Bambino')]);

  @override
  Future<bool> ficheLiee() => serveur.appel(() => true);
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

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late StateProvider<bool> reseau;

  setUp(() {
    // Même base d'un lancement à l'autre : c'est le stockage du téléphone.
    db = AppDatabase.pourTests(NativeDatabase.memory());
    serveur = _Serveur();
    reseau = StateProvider<bool>((ref) => true);
  });

  tearDown(() => db.close());

  /// Un lancement de l'application, session déjà ouverte sur le téléphone.
  ProviderContainer lancer() {
    final c = ProviderContainer(overrides: [
      sessionOuverteProvider.overrideWithValue(true),
      sessionProvider.overrideWithValue(_session()),
      authRepositoryProvider.overrideWithValue(_Depot(serveur)),
      cguRepositoryProvider.overrideWithValue(_Cgu(serveur)),
      databaseProvider.overrideWithValue(db),
      onboardingRegionalisationVuProvider.overrideWith(_RegionalisationVue.new),
      estEnLigneProvider.overrideWith((ref) => ref.watch(reseau)),
      delaiRelanceReseauProvider.overrideWithValue(const Duration(milliseconds: 50)),
    ]);
    c.listen(destinationProvider, (_, _) {});
    c.listen(relanceReseauProvider, (_, _) {});
    addTearDown(c.dispose);
    return c;
  }

  Future<DestinationSession> destinationStable(ProviderContainer c) async {
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
      final d = c.read(destinationProvider);
      if (d != DestinationSession.chargement) return d;
    }
    return c.read(destinationProvider);
  }

  Future<void> attendre(bool Function() condition) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('sans réseau, une session déjà ouverte mène à l’accueil ; retour du réseau sans relancer', () async {
    // Premier lancement en ligne : la copie est écrite sur le téléphone.
    final enLigne = lancer();
    expect(await destinationStable(enLigne), DestinationSession.accueil);
    enLigne.dispose();

    // Relance de l'application sans réseau.
    serveur.enLigne = false;
    final c = lancer();
    c.read(reseau.notifier).state = false;

    expect(await destinationStable(c), DestinationSession.accueil,
        reason: 'profil et établissements gardés sur le téléphone');
    expect(c.read(profilProvider).value?.prenom, 'Awa');
    expect(c.read(etablissementActifProvider)?.nom, 'Bambino');

    // Pendant ce temps, le prénom a changé sur le serveur.
    serveur.prenom = 'Awa Mariama';
    serveur.enLigne = true;
    c.read(reseau.notifier).state = true;

    await attendre(() => c.read(profilProvider).value?.prenom == 'Awa Mariama');
    expect(c.read(profilProvider).value?.prenom, 'Awa Mariama', reason: 'relu au retour du réseau, sans relancer');
    expect(c.read(destinationProvider), DestinationSession.accueil);
  });

  test('sans réseau et sans copie : attente, puis ouverture dès le retour du réseau', () async {
    serveur.enLigne = false;
    final c = lancer();
    c.read(reseau.notifier).state = false;

    expect(await destinationStable(c), DestinationSession.chargement);

    serveur.enLigne = true;
    c.read(reseau.notifier).state = true;
    await attendre(() => c.read(destinationProvider) == DestinationSession.accueil);

    expect(c.read(destinationProvider), DestinationSession.accueil);
  });

  test('Wi-Fi sans Internet : nouvel essai régulier jusqu’à la réussite', () async {
    // Le téléphone se croit connecté, mais le serveur ne répond pas.
    serveur.enLigne = false;
    final c = lancer();
    expect(await destinationStable(c), DestinationSession.chargement);

    final appelsAvant = serveur.appels;
    serveur.enLigne = true;
    await attendre(() => c.read(destinationProvider) == DestinationSession.accueil);

    expect(c.read(destinationProvider), DestinationSession.accueil);
    expect(serveur.appels, greaterThan(appelsAvant));
  });

  test('ouverture en ligne : la copie s’affiche tout de suite, le serveur est relu en arrière-plan', () async {
    final premier = lancer();
    expect(await destinationStable(premier), DestinationSession.accueil);
    premier.dispose();

    serveur.prenom = 'Awa Mariama';
    final c = lancer();
    expect(await destinationStable(c), DestinationSession.accueil);
    await attendre(() => c.read(profilProvider).value?.prenom == 'Awa Mariama');

    expect(c.read(profilProvider).value?.prenom, 'Awa Mariama');
  });
}
