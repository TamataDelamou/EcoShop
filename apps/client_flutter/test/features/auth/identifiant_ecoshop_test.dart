import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/auth/application/connexion_controller.dart';
import 'package:ecoshop_client/features/auth/domain/auth_repository.dart';
import 'package:ecoshop_client/features/auth/domain/identifiant_ecoshop.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/faux_auth_repository.dart';

/// REG-18, partie D : identifiant EcoShop. Mêmes vecteurs que la base
/// (tests/rls/81_identifiant_ecoshop.sql) et l'Edge Function
/// (connexion_identifiant_test.ts).
void main() {
  group('IdentifiantEcoshop', () {
    test('caractère de contrôle Luhn mod 32 : 7K4M2Q -> M (comme le serveur)', () {
      expect(IdentifiantEcoshop.controle('7K4M2Q'), 'M');
    });

    test('saisie libre normalisée', () {
      expect(IdentifiantEcoshop.normaliser('ec 7k4m 2qm'), 'EC-7K4M-2QM');
      expect(IdentifiantEcoshop.normaliser('EC-7K4M-2QM'), 'EC-7K4M-2QM');
    });

    test('fautes de frappe refusées sans appel au serveur', () {
      expect(IdentifiantEcoshop.normaliser('EC-7K4M-2Q9'), isNull, reason: 'mauvais contrôle');
      expect(IdentifiantEcoshop.normaliser('EC-7K4M-Q2M'), isNull, reason: 'voisins inversés');
      expect(IdentifiantEcoshop.normaliser('EC-7K4M-2QMX'), isNull, reason: 'un caractère de trop');
      expect(IdentifiantEcoshop.normaliser('awa@gmail.com'), isNull);
    });

    test('O lu comme 0, I et L lus comme 1', () {
      final valide = 'EC-1K4M-2Q${IdentifiantEcoshop.controle('1K4M2Q')}';
      expect(IdentifiantEcoshop.normaliser(valide.replaceFirst('1', 'L')), valide);
      expect(IdentifiantEcoshop.normaliser(valide.replaceFirst('1', 'i')), valide);
      final avecZero = 'EC-0K4M-2Q${IdentifiantEcoshop.controle('0K4M2Q')}';
      expect(IdentifiantEcoshop.normaliser(avecZero.replaceFirst('0', 'O')), avecZero);
    });

    test('profil : identifiant lu depuis la base', () {
      final p = Profil.depuisJson({'id': 'p1', 'statut_compte': 'actif', 'identifiant_ecoshop': 'EC-7K4M-2QM'});
      expect(p.identifiantEcoshop, 'EC-7K4M-2QM');
    });
  });

  group('Connexion par identifiant EcoShop', () {
    late FauxAuthRepository faux;
    late ProviderContainer container;

    setUp(() {
      faux = FauxAuthRepository();
      container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(faux),
        sessionOuverteProvider.overrideWithValue(false),
      ]);
      addTearDown(container.dispose);
    });

    ConnexionController controleur() => container.read(connexionControllerProvider.notifier);
    EtatConnexion etat() => container.read(connexionControllerProvider);

    test('le même champ accepte l’identifiant : code envoyé à l’adresse masquée', () async {
      await controleur().demanderCode(' ec-7k4m-2qm ');

      expect(faux.appels, ['demanderCodeParIdentifiant:EC-7K4M-2QM']);
      expect(etat().etape, EtapeConnexion.code);
      expect(etat().parIdentifiantEcoshop, isTrue);
      expect(etat().adresseMasquee, 'a•••@gmail.com');
    });

    test('faute de frappe signalée sans appel au serveur', () async {
      await controleur().demanderCode('EC-7K4M-2Q9');

      expect(faux.appels, isEmpty);
      expect(etat().codeErreur, 'IDENTIFIANT_ECOSHOP_INVALIDE');
      expect(etat().etape, EtapeConnexion.identifiant);
    });

    test('vérification et renvoi passent par l’identifiant', () async {
      await controleur().demanderCode('EC-7K4M-2QM');
      await controleur().renvoyerCode();
      await controleur().verifierCode(' 123456 ');

      expect(faux.appels, [
        'demanderCodeParIdentifiant:EC-7K4M-2QM',
        'demanderCodeParIdentifiant:EC-7K4M-2QM',
        'verifierCodeParIdentifiant:EC-7K4M-2QM:123456',
      ]);
      expect(etat().connecte, isTrue);
    });

    test('refus du serveur transporté tel quel', () async {
      faux.erreurALever = const ErreurAuth('TROP_DE_TENTATIVES');
      await controleur().demanderCode('EC-7K4M-2QM');

      expect(etat().codeErreur, 'TROP_DE_TENTATIVES');
      expect(etat().etape, EtapeConnexion.identifiant);
    });

    test('une adresse e-mail suit toujours le parcours habituel', () async {
      await controleur().demanderCode('awa@gmail.com');

      expect(faux.appels, ['demanderCode:awa@gmail.com:email_otp']);
      expect(etat().parIdentifiantEcoshop, isFalse);
    });

    test('message clair pour une faute de frappe', () {
      expect(messageErreurAuth('IDENTIFIANT_ECOSHOP_INVALIDE'), contains('EC-XXXX-XXX'));
    });
  });
}
