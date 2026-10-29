import 'dart:async';

import 'package:drift/native.dart';
import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/auth/application/connexion_controller.dart';
import 'package:ecoshop_client/features/auth/application/telephone_profil_providers.dart';
import 'package:ecoshop_client/features/auth/data/connexion_google.dart';
import 'package:ecoshop_client/features/auth/data/rejeu_telephone.dart';
import 'package:ecoshop_client/features/auth/domain/auth_repository.dart';
import 'package:ecoshop_client/features/auth/domain/canal_otp.dart';
import 'package:ecoshop_client/features/auth/domain/destination_session.dart';
import 'package:ecoshop_client/features/auth/domain/telephone_profil.dart';
import 'package:ecoshop_client/features/auth/presentation/bouton_google.dart';
import 'package:ecoshop_client/features/auth/presentation/ecran_connexion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/faux_auth_repository.dart';

class _FauxGoogle implements ConnexionGoogle {
  _FauxGoogle({this.disponible = true});

  @override
  final bool disponible;

  String? jeton = 'jeton-google';
  String? jetonAutorise;
  Object? erreur;
  int interactifs = 0;
  bool oublie = false;

  @override
  Future<String?> jetonInteractif() async {
    interactifs++;
    final e = erreur;
    if (e != null) throw e;
    return jeton;
  }

  /// Feuille du système encore ouverte : réponse différée.
  Completer<String?>? feuilleOuverte;

  @override
  Future<String?> jetonSilencieux() async => feuilleOuverte != null ? feuilleOuverte!.future : jetonAutorise;

  @override
  Future<void> oublier() async => oublie = true;
}

/// Simule une panne de réseau au moment d'enregistrer le numéro.
class _AuthSansReseau extends FauxAuthRepository {
  _AuthSansReseau({super.profil}) : super(telephone: null);

  @override
  Future<TelephoneProfil> declarerTelephone(String numero) async =>
      throw http.ClientException('Failed host lookup');
}

void main() {
  late AppDatabase db;
  late FauxAuthRepository faux;
  late _FauxGoogle google;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    faux = FauxAuthRepository(profil: profilTest());
    google = _FauxGoogle();
  });
  tearDown(() => db.close());

  ProviderContainer conteneur({FauxAuthRepository? repo}) {
    final c = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(repo ?? faux),
      sessionOuverteProvider.overrideWithValue(true),
      databaseProvider.overrideWithValue(db),
      connexionGoogleProvider.overrideWithValue(google),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  group('connexion', () {
    test('le code par e-mail est proposé par défaut (SMS suspendu)', () {
      final c = conteneur();
      expect(c.read(connexionControllerProvider).canal, CanalOtp.emailOtp);
    });

    test('Google : le jeton du compte choisi ouvre la session', () async {
      final c = conteneur();
      await c.read(connexionControllerProvider.notifier).connecterAvecGoogle();
      expect(faux.appels, contains('connecterAvecGoogle:jeton-google'));
      expect(c.read(connexionControllerProvider).codeErreur, isNull);
      expect(c.read(connexionControllerProvider).enCours, isFalse);
    });

    test('Google : choix annulé, aucune erreur affichée', () async {
      google.jeton = null;
      final c = conteneur();
      await c.read(connexionControllerProvider.notifier).connecterAvecGoogle();
      expect(faux.appels.where((a) => a.startsWith('connecterAvecGoogle')), isEmpty);
      expect(c.read(connexionControllerProvider).codeErreur, isNull);
    });

    test('Google : panne expliquée, sauf pendant la tentative silencieuse', () async {
      google.erreur = const ErreurAuth('GOOGLE_INDISPONIBLE');
      final c = conteneur();
      await c.read(connexionControllerProvider.notifier).connecterAvecGoogle(silencieux: true);
      expect(c.read(connexionControllerProvider).codeErreur, isNull);
      expect(google.interactifs, 0, reason: 'la tentative silencieuse n’ouvre pas le sélecteur');

      await c.read(connexionControllerProvider.notifier).connecterAvecGoogle();
      expect(c.read(connexionControllerProvider).codeErreur, 'GOOGLE_INDISPONIBLE');
      expect(messageErreurAuth('GOOGLE_INDISPONIBLE'), contains('e-mail'));
    });

    test('Google : compte déjà autorisé repris à l’ouverture', () async {
      google.jetonAutorise = 'jeton-connu';
      final c = conteneur();
      await c.read(connexionControllerProvider.notifier).connecterAvecGoogle(silencieux: true);
      expect(faux.appels, contains('connecterAvecGoogle:jeton-connu'));
    });

    test('REG-29 : une seule feuille Google à la fois, pas de second sélecteur derrière', () async {
      google.feuilleOuverte = Completer<String?>();
      final c = conteneur();
      final ctrl = c.read(connexionControllerProvider.notifier);
      final premiere = ctrl.connecterAvecGoogle(silencieux: true);
      final seconde = ctrl.connecterAvecGoogle();
      expect(google.interactifs, 0, reason: 'la feuille ouverte n’est pas doublée par le sélecteur');
      google.feuilleOuverte!.complete('jeton-connu');
      await Future.wait([premiere, seconde]);
      expect(faux.appels.where((a) => a.startsWith('connecterAvecGoogle')), ['connecterAvecGoogle:jeton-connu']);

      // Demande terminée : le bouton fonctionne de nouveau.
      google.feuilleOuverte = null;
      await c.read(connexionControllerProvider.notifier).connecterAvecGoogle();
      expect(google.interactifs, 0, reason: 'déjà connecté : rien à redemander');
    });

    test('renvoyer le code réutilise l’adresse normalisée', () async {
      final c = conteneur();
      final ctrl = c.read(connexionControllerProvider.notifier);
      await ctrl.demanderCode('  Awa@Exemple.com ');
      await ctrl.renvoyerCode();
      expect(faux.appels.where((a) => a == 'demanderCode:awa@exemple.com:email_otp').length, 2);
    });

    testWidgets('écran : bouton Google seulement s’il est configuré', (tester) async {
      Future<void> monter(_FauxGoogle g) async {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(faux),
            sessionOuverteProvider.overrideWithValue(false),
            connexionGoogleProvider.overrideWithValue(g),
          ],
          child: const MaterialApp(home: EcranConnexion()),
        ));
        await tester.pumpAndSettle();
      }

      await monter(_FauxGoogle());
      expect(find.byKey(const Key('bouton_google')), findsOneWidget);
      // Règles de présentation Google : logo « G » officiel, libellé
      // permis, thème clair (fond blanc, contour #747775, texte #1F1F1F).
      final bouton = find.byKey(const Key('bouton_google'));
      final logo = tester.widget<Image>(find.descendant(of: bouton, matching: find.byType(Image)));
      expect((logo.image as AssetImage).assetName, BoutonGoogle.logo);
      expect(find.text('Continuer avec Google'), findsOneWidget);
      final fond = tester.widget<Material>(find.descendant(of: bouton, matching: find.byType(Material)).first);
      expect(fond.color, const Color(0xFFFFFFFF));
      expect((fond.shape! as StadiumBorder).side.color, const Color(0xFF747775));
      expect(tester.widget<Text>(find.text('Continuer avec Google')).style?.color, const Color(0xFF1F1F1F));
      expect(tester.getSize(bouton).height, 40);
      expect(find.text('Recevoir le code'), findsOneWidget);
      expect(find.text('Téléphone'), findsNothing, reason: 'SMS suspendu');

      await monter(_FauxGoogle(disponible: false));
      expect(find.byKey(const Key('bouton_google')), findsNothing);
    });
  });

  group('étape « Votre numéro »', () {
    test('garde : après les CGU, avant la langue', () {
      final d = GardeSession.resoudre(
        sessionOuverte: true,
        profil: profilTest(),
        ficheLiee: true,
        nombreEtablissements: 1,
        cguAcceptee: true,
        regionalisationVue: false,
        telephoneAFournir: true,
      );
      expect(d, DestinationSession.telephoneProfil);
      expect(
        GardeSession.resoudre(
          sessionOuverte: true,
          profil: profilTest(),
          ficheLiee: true,
          nombreEtablissements: 1,
          cguAcceptee: false,
          telephoneAFournir: true,
        ),
        DestinationSession.cguNonAcceptees,
      );
    });

    test('demandée au parent sans numéro, jamais à l’élève', () async {
      faux.telephone = null;
      expect(await conteneur().read(etapeTelephoneProvider.future), isTrue);

      final eleve = FauxAuthRepository(profil: profilTest(role: RoleRacine.eleve), telephone: null);
      expect(await conteneur(repo: eleve).read(etapeTelephoneProvider.future), isFalse);

      final avecNumero = FauxAuthRepository(profil: profilTest());
      expect(await conteneur(repo: avecNumero).read(etapeTelephoneProvider.future), isFalse);
    });

    test('enregistrer : numéro déclaré, étape terminée', () async {
      faux.telephone = null;
      final c = conteneur();
      await c.read(etapeTelephoneProvider.future);
      final r = await c.read(etapeTelephoneProvider.notifier).enregistrer('+224620112233');
      expect(r.verifie, isFalse);
      expect(faux.appels, contains('declarerTelephone:+224620112233'));
      expect(c.read(etapeTelephoneProvider).valueOrNull, isFalse);
      expect((await c.read(telephoneProfilProvider.future))?.statut, 'À faire confirmer par l’école');
    });

    test('« Plus tard » : l’étape ne revient pas avant 30 jours', () async {
      faux.telephone = null;
      final c = conteneur();
      await c.read(etapeTelephoneProvider.future);
      await c.read(etapeTelephoneProvider.notifier).passer();
      c.invalidate(etapeTelephoneProvider);
      expect(await c.read(etapeTelephoneProvider.future), isFalse);
    });

    test('sans réseau : numéro gardé et envoyé au retour de la connexion', () async {
      final repo = _AuthSansReseau(profil: profilTest());
      final c = conteneur(repo: repo);
      await c.read(etapeTelephoneProvider.future);
      final r = await c.read(etapeTelephoneProvider.notifier).enregistrer('+224620112233');
      expect(r.enAttenteEnvoi, isTrue);
      final file = await DriftSyncRepository(db).entreesEnAttente();
      expect(file.single.entite, RejeuTelephone.entite);
      expect(RejeuTelephone.libelle(file.single), contains('+224620112233'));
      expect((await c.read(telephoneProfilProvider.future))?.statut, 'En attente d’envoi');
    });

    test('format lisible des numéros guinéens', () {
      expect(const TelephoneProfil(numero: '+224620112233').lisible, '+224 620 11 22 33');
      expect(const TelephoneProfil(numero: '+33612345678').lisible, '+33612345678');
    });
  });
}
