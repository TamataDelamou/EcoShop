import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/auth/application/connexion_controller.dart';
import 'package:ecoshop_client/features/auth/domain/auth_repository.dart';
import 'package:ecoshop_client/features/auth/domain/canal_otp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth_repository.dart';

void main() {
  late FauxAuthRepository faux;
  late ProviderContainer container;

  setUp(() {
    faux = FauxAuthRepository();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(faux),
        // La garde n'est pas sollicitée ici : on isole le parcours OTP.
        sessionOuverteProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);
  });

  ConnexionController controleurCourant() =>
      container.read(connexionControllerProvider.notifier);
  EtatConnexion etatCourant() => container.read(connexionControllerProvider);

  group('ConnexionController — normalisation (ch. 5.4.1)', () {
    test('normalise le numéro en E.164 avant l’appel', () async {
      controleurCourant().choisirIndicatif('+224');
      await controleurCourant().demanderCode('620 00 00 00');

      expect(faux.appels, contains('demanderCode:+224620000000:sms'));
      expect(etatCourant().identifiantNormalise, '+224620000000');
      expect(etatCourant().etape, EtapeConnexion.code);
    });

    test('refuse un numéro invalide sans appeler le serveur', () async {
      await controleurCourant().demanderCode('abc');

      expect(faux.appels, isEmpty);
      expect(etatCourant().codeErreur, 'IDENTIFIANT_INVALIDE');
      expect(etatCourant().etape, EtapeConnexion.identifiant);
    });

    test('met l’e-mail en minuscules', () async {
      controleurCourant().choisirCanal(CanalOtp.emailOtp);
      await controleurCourant().demanderCode('  Amina@Exemple.COM ');

      expect(faux.appels, contains('demanderCode:amina@exemple.com:email_otp'));
    });

    test('refuse une adresse e-mail malformée', () async {
      controleurCourant().choisirCanal(CanalOtp.emailOtp);
      await controleurCourant().demanderCode('amina@exemple');

      expect(faux.appels, isEmpty);
      expect(etatCourant().codeErreur, 'IDENTIFIANT_INVALIDE');
    });
  });

  group('ConnexionController — parcours', () {
    test('le lien magique ne demande pas de code', () async {
      controleurCourant().choisirCanal(CanalOtp.magicLink);
      await controleurCourant().demanderCode('amina@exemple.com');

      expect(etatCourant().etape, EtapeConnexion.lienEnvoye);
    });

    test('transporte le code d’erreur du serveur sans le réinterpréter', () async {
      faux.erreurALever = const ErreurAuth('TROP_DE_TENTATIVES');
      await controleurCourant().demanderCode('620000000');

      expect(etatCourant().codeErreur, 'TROP_DE_TENTATIVES');
      expect(etatCourant().enCours, isFalse);
    });

    test('vérifie le code avec l’identifiant normalisé mémorisé', () async {
      await controleurCourant().demanderCode('620 00 00 00');
      await controleurCourant().verifierCode(' 123456 ');

      expect(faux.appels, contains('verifierCode:+224620000000:123456'));
      expect(etatCourant().codeErreur, isNull);
    });

    test('un code refusé laisse l’utilisateur à l’étape de saisie', () async {
      await controleurCourant().demanderCode('620 00 00 00');
      faux.erreurALever = const ErreurAuth('otp_expired');
      await controleurCourant().verifierCode('000000');

      expect(etatCourant().etape, EtapeConnexion.code);
      expect(etatCourant().codeErreur, 'otp_expired');
    });

    test('changer d’étape efface l’erreur précédente', () async {
      faux.erreurALever = const ErreurAuth('TROP_DE_TENTATIVES');
      await controleurCourant().demanderCode('620000000');
      expect(etatCourant().codeErreur, isNotNull);

      controleurCourant().recommencer();
      expect(etatCourant().codeErreur, isNull);
      expect(etatCourant().etape, EtapeConnexion.identifiant);
    });

    test('recommencer conserve le canal et l’indicatif choisis', () async {
      controleurCourant().choisirIndicatif('+225');
      controleurCourant().choisirCanal(CanalOtp.whatsapp);
      await controleurCourant().demanderCode('0700000000');
      controleurCourant().recommencer();

      expect(etatCourant().indicatifPays, '+225');
      expect(etatCourant().canal, CanalOtp.whatsapp);
    });
  });

  group('CanalOtp', () {
    test('chaque entrée propose exactement deux canaux', () {
      expect(CanalOtp.pourEntree(TypeIdentifiant.telephone),
          [CanalOtp.sms, CanalOtp.whatsapp]);
      expect(CanalOtp.pourEntree(TypeIdentifiant.email),
          [CanalOtp.magicLink, CanalOtp.emailOtp]);
    });

    test('seul le lien magique n’exige pas de saisie de code', () {
      for (final canal in CanalOtp.values) {
        expect(canal.demandeSaisieCode, canal != CanalOtp.magicLink);
      }
    });
  });

  group('messageErreurAuth', () {
    test('traduit les codes métier connus', () {
      expect(messageErreurAuth('TROP_DE_TENTATIVES'), contains('heure'));
      expect(messageErreurAuth('LIAISON_IMPOSSIBLE'), contains('matricule'));
    });

    test('retombe sur un message générique pour un code inconnu', () {
      expect(messageErreurAuth('xyz'), 'Une erreur est survenue. Réessayez.');
    });
  });
}
