import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:ecoshop_client/core/auth/supabase_auth_provider.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/auth/application/connexion_controller.dart';
import 'package:ecoshop_client/features/auth/data/connexion_google.dart';
import 'package:ecoshop_client/features/auth/data/supabase_auth_repository.dart';
import 'package:ecoshop_client/features/auth/domain/destination_session.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:ecoshop_client/features/auth/domain/telephone_profil.dart';
import 'package:ecoshop_client/features/cgu/application/cgu_providers.dart';
import 'package:ecoshop_client/features/cgu/domain/cgu_statut.dart';
import 'package:ecoshop_client/features/coquille/application/session_logout.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/regionalisation/application/regionalisation_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/faux_auth_repository.dart';

/// Chaîne réelle de la session : `signInWithIdToken` et `signOut` de
/// Supabase, événements Auth, garde de session. Les autres tests figent
/// `sessionOuverteProvider` ; c'est ce qui avait laissé passer une session
/// lue une seule fois au démarrage (connexion Google bloquée sur l'APK).
///
/// Seul le réseau est simulé : coupure ([_Serveur.enLigne]) ou réseau qui ne
/// répond plus ([_Serveur.sansReponse]).

const _uid = '0b1c2d3e-0000-4000-8000-000000000001';

String _jwt() {
  String b64(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64({'sub': _uid, 'exp': exp, 'role': 'authenticated'})}.signature';
}

Map<String, dynamic> _session() => {
      'access_token': _jwt(),
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'rafraichissement',
      'user': {
        'id': _uid,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'awa@exemple.com',
        'app_metadata': {'provider': 'google'},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-10-22T08:00:00Z',
      },
    };

class _Serveur {
  bool enLigne = true;

  /// Réseau faible : la requête part mais la réponse ne vient jamais.
  bool sansReponse = false;
  final appels = <String>[];

  SupabaseClient client() => SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        // Sans stockage PKCE en test (supabase_flutter le fournit dans l'application).
        authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit),
        httpClient: MockClient((requete) async {
          appels.add('${requete.method} ${requete.url.path}?${requete.url.query}');
          if (!enLigne) throw http.ClientException('Failed host lookup');
          if (sansReponse) await Completer<void>().future;
          // Jeton Google (/token) ou code reçu par e-mail (/verify) : session ouverte.
          final ouvre = requete.url.path.endsWith('/token') || requete.url.path.endsWith('/verify');
          final corps = ouvre ? jsonEncode(_session()) : '{}';
          return http.Response(corps, 200, headers: {'content-type': 'application/json'}, request: requete);
        }),
      );
}

/// Dépôt réel pour la session ; profil et rattachements fixés, pour
/// n'exercer que l'ouverture et la fermeture de session.
class _Depot extends SupabaseAuthRepository {
  _Depot(this._c) : super(_c);

  final SupabaseClient _c;

  @override
  Future<Profil?> profilCourant() async => _c.auth.currentUser == null ? null : profilTest(id: _uid);

  @override
  Future<bool> ficheLiee() async => true;

  @override
  Future<List<Etablissement>> mesEtablissements() async => [etablissementTest('e1', 'Bambino')];

  @override
  Future<TelephoneProfil?> monTelephone() async => const TelephoneProfil(numero: '+224620000000', verifie: true);
}

class _FauxGoogle implements ConnexionGoogle {
  @override
  bool get disponible => true;

  @override
  Future<String?> jetonInteractif() async => 'jeton-google';

  @override
  Future<String?> jetonSilencieux() async => null;

  @override
  Future<void> oublier() async {}
}

class _RegionalisationVue extends OnboardingRegionalisationNotifier {
  @override
  Future<bool> build() async => true;
}

class _CguRienAAccepter extends CguStatutNotifier {
  @override
  Future<CguStatut?> build() async => null;
}

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late SupabaseClient client;
  late ProviderContainer c;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    serveur = _Serveur();
    client = serveur.client();
    c = ProviderContainer(overrides: [
      supabaseClientProvider.overrideWithValue(client),
      authRepositoryProvider.overrideWithValue(_Depot(client)),
      connexionGoogleProvider.overrideWithValue(_FauxGoogle()),
      databaseProvider.overrideWithValue(db),
      onboardingRegionalisationVuProvider.overrideWith(_RegionalisationVue.new),
      cguStatutProvider.overrideWith(_CguRienAAccepter.new),
    ]);
    // La racine de l'application écoute la destination en permanence.
    c.listen(destinationProvider, (_, _) {});
  });

  tearDown(() async {
    c.dispose();
    await client.dispose();
    await db.close();
  });

  /// Laisse passer les événements Auth et les lectures du profil.
  Future<DestinationSession> destinationStable() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      final d = c.read(destinationProvider);
      if (d != DestinationSession.chargement) return d;
    }
    return c.read(destinationProvider);
  }

  test('connexion Google : la session ouverte mène à l’accueil, sans relancer l’application', () async {
    expect(await destinationStable(), DestinationSession.connexion);

    await c.read(connexionControllerProvider.notifier).connecterAvecGoogle();

    expect(serveur.appels, contains(startsWith('POST /auth/v1/token?grant_type=id_token')));
    expect(c.read(connexionControllerProvider).enCours, isFalse);
    expect(await destinationStable(), DestinationSession.accueil);
  });

  test('code par e-mail : la session ouverte mène à l’accueil ; « Valider » ne renvoie plus le code', () async {
    final ctrl = c.read(connexionControllerProvider.notifier);
    expect(await destinationStable(), DestinationSession.connexion);

    await ctrl.demanderCode('awa@exemple.com');
    await ctrl.verifierCode('123456');

    expect(c.read(connexionControllerProvider).connecte, isTrue);
    expect(await destinationStable(), DestinationSession.accueil,
        reason: 'code vérifié : l’écran suivant s’affiche sans relancer l’application');

    // Second appui (ou validation automatique puis appui) : rien ne repart,
    // sinon le serveur refuse le code déjà utilisé (« code expiré »).
    await ctrl.verifierCode('123456');
    expect(serveur.appels.where((a) => a.startsWith('POST /auth/v1/verify')), hasLength(1));
    expect(c.read(connexionControllerProvider).codeErreur, isNull);
  });

  test('déconnexion sur un réseau qui ne répond plus : immédiate, rien n’attend le serveur', () async {
    await c.read(connexionControllerProvider.notifier).connecterAvecGoogle();
    expect(await destinationStable(), DestinationSession.accueil);

    serveur.sansReponse = true;
    final appelsAvant = serveur.appels.length;
    final chrono = Stopwatch()..start();
    await c.read(_refProvider).deconnecterEtPurgerDonneesLocales();
    chrono.stop();

    expect(chrono.elapsed, lessThan(const Duration(seconds: 2)));
    expect(client.auth.currentSession, isNull);
    expect(await destinationStable(), DestinationSession.connexion);
    expect(serveur.appels.skip(appelsAvant), contains(startsWith('POST /auth/v1/logout')),
        reason: 'le serveur est quand même prévenu, en arrière-plan');
  });

  test('déconnexion sans réseau : immédiate, la garde revient à la connexion', () async {
    await c.read(connexionControllerProvider.notifier).connecterAvecGoogle();
    expect(await destinationStable(), DestinationSession.accueil);

    serveur.enLigne = false;
    final chrono = Stopwatch()..start();
    await c.read(_refProvider).deconnecterEtPurgerDonneesLocales();
    chrono.stop();

    expect(client.auth.currentSession, isNull, reason: 'session effacée de l’appareil sans attendre le serveur');
    expect(chrono.elapsed, lessThan(const Duration(seconds: 2)));
    expect(await destinationStable(), DestinationSession.connexion,
        reason: 'jamais bloqué sur le chargement d’un profil qui ne viendra plus');
  });
}
