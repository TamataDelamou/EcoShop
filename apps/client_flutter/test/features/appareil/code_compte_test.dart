import 'dart:convert';

import 'package:drift/native.dart';
import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/core/securite/code_secret.dart';
import 'package:ecoshop_client/core/securite/surveillance_session.dart';
import 'package:ecoshop_client/features/appareil/application/appareil_providers.dart';
import 'package:ecoshop_client/features/appareil/data/appareil_repository.dart';
import 'package:ecoshop_client/features/appareil/domain/etat_appareil.dart';
import 'package:ecoshop_client/features/appareil/presentation/ecran_code_compte.dart';
import 'package:ecoshop_client/features/appareil/presentation/surveillance_appareils.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/auth/domain/destination_session.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:ecoshop_client/features/coquille/application/verrou_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/faux_auth_repository.dart';

/// REG-22, partie A : code du compte côté application.

Map<String, dynamic> _etatJson({
  bool obligatoire = true,
  bool aUnCode = true,
  String statut = 'a_verifier',
  int? version = 1,
  int essais = 5,
  String? bloque,
  String? motif,
  List<Map<String, dynamic>> mesDemandes = const [],
  List<Map<String, dynamic>> aTraiter = const [],
}) => {
  'obligatoire': obligatoire,
  'a_un_code': aUnCode,
  'statut': statut,
  'version_code': version,
  'prenom': 'Awa',
  'bloque_jusqu_a': bloque,
  'motif_blocage': motif,
  'essais_restants': essais,
  'mes_demandes': mesDemandes,
  'a_traiter': aTraiter,
};

class _FauxRepo implements AppareilRepository {
  _FauxRepo(this.etatCourant);

  EtatAppareil etatCourant;
  String codeCompte = '739146';
  int version = 1;
  int essais = 5;
  final appels = <String>[];

  @override
  Future<EtatAppareil> enregistrer({required String modele, required String systeme, required String version}) async {
    appels.add('enregistrer:$modele');
    return etatCourant;
  }

  @override
  Future<EtatAppareil> etat() async => etatCourant;

  @override
  Future<void> definirCode(String code) async {
    appels.add('definir:$code');
    codeCompte = code;
    etatCourant = EtatAppareil.depuisJson(_etatJson(statut: 'approuvee', version: 1));
  }

  @override
  Future<ResultatCodeCompte> verifierCode(String code) async {
    appels.add('verifier:$code');
    if (code == codeCompte) {
      essais = 5;
      etatCourant = EtatAppareil.depuisJson(_etatJson(statut: 'approuvee', version: version));
      return CodeCompteBon(version);
    }
    essais--;
    if (essais == 0) return CodeCompteBloque(DateTime.now().add(const Duration(hours: 1)));
    return CodeCompteFaux(essais);
  }

  @override
  Future<int> changerCode(String ancien, String nouveau) async {
    if (ancien != codeCompte) throw const ErreurCodeCompte('CODE_FAUX', 'Code incorrect.');
    codeCompte = nouveau;
    return ++version;
  }

  @override
  Future<DemandeAppareil> demanderApprobation() async {
    appels.add('demander');
    return DemandeAppareil(id: 'd1', type: TypeDemandeAppareil.approbation,
        echeance: DateTime.now().add(const Duration(minutes: 10)));
  }

  @override
  Future<void> approuver(String demandeId) async => appels.add('approuver:$demandeId');

  @override
  Future<void> refuser(String demandeId) async => appels.add('refuser:$demandeId');

  @override
  Future<int> choisirCodeApresAutorisation(String nouveau) async {
    appels.add('choisir:$nouveau');
    return ++version;
  }

  @override
  Future<DemandeAppareil> lancerRecuperation() async => DemandeAppareil(
      id: 'r1', type: TypeDemandeAppareil.recuperation, echeance: DateTime.now().add(const Duration(hours: 48)));

  @override
  Future<void> annulerRecuperation(String demandeId) async => appels.add('annuler:$demandeId');

  @override
  Future<int> finaliserRecuperation(String nouveau) async {
    appels.add('finaliser:$nouveau');
    codeCompte = nouveau;
    return ++version;
  }

  @override
  Future<List<PersonneDebloquable>> personnesDebloquables(String etablissementId, String recherche) async => const [];

  @override
  Future<List<PersonneDebloquable>> chercherCompteGsg(String recherche) async => const [];

  @override
  Future<DateTime> debloquer({required String compteId, required String motif, String? etablissementId}) async =>
      DateTime.now().add(const Duration(minutes: 30));
}

class _Banc {
  _Banc(EtatAppareil etat, {bool codeLocal = false}) {
    repo = _FauxRepo(etat);
    db = AppDatabase.pourTests(NativeDatabase.memory());
    container = ProviderContainer(overrides: overrides);
    if (codeLocal) _creation = service.creer('compte-1', '482617');
  }

  late final _FauxRepo repo;
  late final AppDatabase db;
  late final ProviderContainer container;
  final coffre = CoffreFortMemoire();
  late final service = ServiceCodeSecret(coffre: coffre, iterations: 1000);
  Future<void>? _creation;

  List<Override> get overrides => [
    databaseProvider.overrideWithValue(db),
    authRepositoryProvider.overrideWithValue(FauxAuthRepository(
      profil: const Profil(
        id: 'compte-1',
        identifiantCanonique: 'awa@exemple.org',
        statutCompte: StatutCompte.actif,
        roleRacine: RoleRacine.parent,
        prenom: 'Awa',
      ),
    )),
    sessionOuverteProvider.overrideWithValue(true),
    estEnLigneProvider.overrideWithValue(true),
    appareilActifProvider.overrideWithValue(true),
    appareilRepositoryProvider.overrideWithValue(repo),
    compteSessionProvider.overrideWithValue('compte-1'),
    sessionIdProvider.overrideWithValue('session-1'),
    infoAppareilProvider.overrideWith((ref) async => const InfoAppareil(modele: 'Tecno Spark 10', systeme: 'Android 13')),
    coffreFortProvider.overrideWithValue(coffre),
    serviceCodeSecretProvider.overrideWithValue(service),
  ];

  Future<EtatAppareil> etat() async {
    await _creation;
    return container.read(etatAppareilProvider.future);
  }

  void fermer() {
    container.dispose();
    db.close();
  }
}

void main() {
  group('état de l’appareil', () {
    test('code demandé seulement : interrupteur allumé, compte doté d’un code, appareil non vérifié', () {
      expect(EtatAppareil.depuisJson(_etatJson()).aVerifier, isTrue);
      expect(EtatAppareil.depuisJson(_etatJson(obligatoire: false)).aVerifier, isFalse);
      expect(EtatAppareil.depuisJson(_etatJson(aUnCode: false)).aVerifier, isFalse);
      expect(EtatAppareil.depuisJson(_etatJson(statut: 'approuvee')).aVerifier, isFalse);
      expect(EtatAppareil.libre.aVerifier, isFalse);
    });

    test('« Ce n’est pas moi » : blocage sans date de fin', () {
      final e = EtatAppareil.depuisJson(_etatJson(bloque: 'infinity', motif: 'pas_moi'));
      expect(e.bloque, isTrue);
      expect(e.bloquePasMoi, isTrue);
      expect(texteBlocage(e), contains('changiez le code'));
    });

    test('identifiant de session lu dans le jeton', () {
      String partie(Map<String, Object> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
      final jeton = '${partie({'alg': 'HS256'})}.${partie({'sub': 'u', 'session_id': 'abc-123'})}.sig';
      expect(sessionIdDepuisJeton(jeton), 'abc-123');
      expect(sessionIdDepuisJeton('pas-un-jeton'), isNull);
    });
  });

  group('garde de session', () {
    test('nouvel appareil : code du compte avant même le profil', () {
      expect(
        GardeSession.resoudre(sessionOuverte: true, profil: null, ficheLiee: false, nombreEtablissements: 0,
            appareilAVerifier: true),
        DestinationSession.codeCompte,
      );
    });

    test('code à confirmer : après la création du code local', () {
      const profil = Profil(id: 'c', identifiantCanonique: 'a@b.org', statutCompte: StatutCompte.actif,
          roleRacine: RoleRacine.parent, prenom: 'Awa', nom: 'Diallo');
      expect(
        GardeSession.resoudre(sessionOuverte: true, profil: profil, ficheLiee: true, nombreEtablissements: 1,
            codeCompteAConfirmer: true),
        DestinationSession.codeCompteAConfirmer,
      );
      expect(
        GardeSession.resoudre(sessionOuverte: true, profil: profil, ficheLiee: true, nombreEtablissements: 1,
            codeSecretACreer: true, codeCompteAConfirmer: true),
        DestinationSession.codeSecret,
      );
    });

    test('destination : appareil à vérifier → étape du code du compte', () async {
      final banc = _Banc(EtatAppareil.depuisJson(_etatJson()));
      await banc.etat();
      expect(banc.container.read(destinationProvider), DestinationSession.codeCompte);
      expect(banc.repo.appels, contains('enregistrer:Tecno Spark 10'));
      banc.fermer();
    });
  });

  group('refus du serveur repérés sur toute requête', () {
    test('403 SESSION_REVOQUEE et APPAREIL_A_VERIFIER annoncés, réponse rendue intacte', () async {
      final annonces = <RefusSession>[];
      final abonnement = SurveillanceSession.refus.listen(annonces.add);
      final corps = '{"code":"42501","message":"SESSION_REVOQUEE"}';
      final client = SurveillanceSession(MockClient((r) async => switch (r.url.path) {
        '/revoque' => http.Response(corps, 403),
        '/verifier' => http.Response('{"message":"APPAREIL_A_VERIFIER"}', 403),
        '/autre' => http.Response('{"message":"PERMISSION_REFUSEE"}', 403),
        _ => http.Response('[]', 200),
      }));
      final r = await client.get(Uri.parse('https://x/revoque'));
      expect(r.statusCode, 403);
      expect(r.body, corps);
      await client.get(Uri.parse('https://x/verifier'));
      await client.get(Uri.parse('https://x/autre'));
      await client.get(Uri.parse('https://x/ok'));
      await Future<void>.delayed(Duration.zero);
      expect(annonces, [RefusSession.sessionRevoquee, RefusSession.appareilAVerifier]);
      await abonnement.cancel();
    });
  });

  group('actions', () {
    test('bon code sur un nouvel appareil : il devient le code local, l’application s’ouvre', () async {
      final banc = _Banc(EtatAppareil.depuisJson(_etatJson()));
      await banc.etat();
      final r = await banc.container.read(appareilControllerProvider).verifierCode('739146');
      expect(r, isA<CodeCompteBon>());
      expect(await banc.service.verifier('compte-1', '739146'), isA<CodeBon>());
      expect(await banc.service.versionCompte('compte-1'), 1);
      expect(banc.container.read(identiteVerifieeProvider), isTrue);
      banc.fermer();
    });

    test('code faux : essais restants, rien sur le téléphone', () async {
      final banc = _Banc(EtatAppareil.depuisJson(_etatJson()));
      await banc.etat();
      final r = await banc.container.read(appareilControllerProvider).verifierCode('111110');
      expect(r, isA<CodeCompteFaux>());
      expect((r as CodeCompteFaux).essaisRestants, 4);
      expect(await banc.service.existe('compte-1'), isFalse);
      banc.fermer();
    });

    test('nouveau compte : le code créé devient celui du compte', () async {
      final banc = _Banc(EtatAppareil.depuisJson(_etatJson(aUnCode: false, statut: 'approuvee', version: null)));
      await banc.etat();
      await banc.container.read(appareilControllerProvider).codeLocalCree('582014');
      expect(banc.repo.appels, contains('definir:582014'));
      expect(await banc.service.versionCompte('compte-1'), 1);
      banc.fermer();
    });

    test('appareil autorisé par un autre : le code créé remplace celui du compte', () async {
      final banc = _Banc(EtatAppareil.depuisJson(_etatJson(statut: 'approuvee')));
      await banc.etat();
      await banc.container.read(appareilControllerProvider).codeLocalCree('582014');
      expect(banc.repo.appels, contains('choisir:582014'));
      expect(await banc.service.versionCompte('compte-1'), 2);
      banc.fermer();
    });

    test('compte d’avant REG-22 : le code local est confirmé puis devient celui du compte', () async {
      final banc = _Banc(EtatAppareil.depuisJson(_etatJson(aUnCode: false, statut: 'approuvee', version: null)),
          codeLocal: true);
      await banc.etat();
      await banc.container.read(profilProvider.future);
      expect(await banc.container.read(codeCompteAConfirmerProvider.future), isTrue);
      final controleur = banc.container.read(appareilControllerProvider);
      expect(await controleur.confirmerCodeCompte('111110'), 'Ce n’est pas le code de ce téléphone.');
      expect(banc.repo.appels.where((a) => a.startsWith('definir')), isEmpty);
      expect(await controleur.confirmerCodeCompte('482617'), isNull);
      expect(banc.repo.appels, contains('definir:482617'));
      await banc.container.read(etatAppareilProvider.future);
      expect(await banc.container.read(codeCompteAConfirmerProvider.future), isFalse);
      banc.fermer();
    });

    test('code changé sur un autre appareil : demandé une fois, puis remplace le code local', () async {
      final banc = _Banc(EtatAppareil.depuisJson(_etatJson(statut: 'approuvee', version: 3)), codeLocal: true);
      banc.repo.version = 3;
      banc.repo.codeCompte = '602417';
      await banc.etat();
      await banc.service.noterVersionCompte('compte-1', 2);
      await banc.container.read(profilProvider.future);
      expect(await banc.container.read(codeCompteAConfirmerProvider.future), isTrue);
      expect(await banc.container.read(appareilControllerProvider).confirmerCodeCompte('602417'), isNull);
      expect(await banc.service.verifier('compte-1', '602417'), isA<CodeBon>());
      expect(await banc.service.versionCompte('compte-1'), 3);
      banc.fermer();
    });

    test('changer le code du compte : nouveau code local et nouvelle version', () async {
      final banc = _Banc(EtatAppareil.depuisJson(_etatJson(statut: 'approuvee')), codeLocal: true);
      await banc.etat();
      await expectLater(banc.container.read(appareilControllerProvider).changerCode('000001', '582014'),
          throwsA(isA<ErreurCodeCompte>()));
      await banc.container.read(appareilControllerProvider).changerCode('739146', '582014');
      expect(await banc.service.verifier('compte-1', '582014'), isA<CodeBon>());
      expect(await banc.service.versionCompte('compte-1'), 2);
      banc.fermer();
    });
  });

  group('écrans', () {
    Future<_Banc> monter(WidgetTester tester, EtatAppareil etat, Widget ecran) async {
      // Téléphone en portrait : tout l'écran tient sans défilement.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final banc = _Banc(etat);
      await tester.runAsync(banc.etat);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: banc.container,
        child: MaterialApp(home: ecran),
      ));
      await tester.pump();
      return banc;
    }

    Future<void> saisir(WidgetTester tester, String code) async {
      for (final c in code.split('')) {
        await tester.tap(find.text(c).last);
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('nouvel appareil : « Bonjour Awa », code faux, essais restants', (tester) async {
      final banc = await monter(tester, EtatAppareil.depuisJson(_etatJson()), const EcranCodeCompte());
      expect(find.text('Bonjour Awa'), findsOneWidget);
      expect(find.text('Code de votre compte'), findsOneWidget);
      await saisir(tester, '111110');
      expect(find.textContaining('Encore 4 essais'), findsOneWidget);
      banc.fermer();
    });

    testWidgets('blocage : pas de pavé, heure de fin affichée', (tester) async {
      final fin = DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String();
      final banc = await monter(tester, EtatAppareil.depuisJson(_etatJson(bloque: fin, motif: 'echecs')),
          const EcranCodeCompte());
      expect(find.byKey(const Key('pave_code_compte')), findsNothing);
      expect(find.byKey(const Key('message_blocage')), findsOneWidget);
      expect(find.textContaining('Trop de codes faux'), findsOneWidget);
      banc.fermer();
    });

    testWidgets('« Code oublié ? » : les trois voies', (tester) async {
      final banc = await monter(tester, EtatAppareil.depuisJson(_etatJson()), const EcranCodeCompte());
      await tester.tap(find.byKey(const Key('bouton_code_oublie')));
      await tester.pumpAndSettle();
      expect(find.text('Autoriser depuis un autre appareil'), findsOneWidget);
      expect(find.text('Récupérer par e-mail (48 h)'), findsOneWidget);
      expect(find.text('Me présenter à l’école'), findsOneWidget);
      await tester.tap(find.byKey(const Key('choix_autoriser_autre_appareil')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(banc.repo.appels, contains('demander'));
      expect(find.byKey(const Key('texte_attente_autorisation')), findsOneWidget);
      banc.fermer();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('école : choisir un nouveau code après le déblocage', (tester) async {
      final banc = await monter(tester, EtatAppareil.depuisJson(_etatJson()), const EcranCodeCompte());
      await tester.tap(find.byKey(const Key('bouton_code_oublie')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('choix_ecole')));
      await tester.pumpAndSettle();
      expect(find.textContaining('30 minutes'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bouton_debloque_choisir')));
      await tester.pump();
      await saisir(tester, '582014');
      await saisir(tester, '582014');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(banc.repo.appels, contains('finaliser:582014'));
      banc.fermer();
    });

    testWidgets('appareil connu : « Autoriser ce nouvel appareil ? » avec le modèle', (tester) async {
      final demande = DemandeAppareil(id: 'd1', type: TypeDemandeAppareil.approbation, modele: 'Itel A70',
          echeance: DateTime.now().add(const Duration(minutes: 9)), demandeLe: DateTime(2026, 10, 25, 14, 5));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: InviteAutorisation(demande: demande))));
      expect(find.text('Itel A70'), findsOneWidget);
      expect(find.text('Demandé à 14 h 05'), findsOneWidget);
      expect(find.text('Autoriser'), findsOneWidget);
      expect(find.text('Ce n’est pas moi'), findsOneWidget);
    });
  });
}
