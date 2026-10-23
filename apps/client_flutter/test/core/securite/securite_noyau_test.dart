import 'package:ecoshop_client/core/securite/chiffrement_file.dart';
import 'package:ecoshop_client/core/securite/code_secret.dart';
import 'package:ecoshop_client/core/securite/coffre_fort.dart';
import 'package:ecoshop_client/core/securite/delais_verrouillage.dart';
import 'package:ecoshop_client/core/securite/gardien_actions_sensibles.dart';
import 'package:flutter_test/flutter_test.dart';

/// REG-18, partie C : règles du code secret, échecs, délais par rôle,
/// actions sensibles, chiffrement de la file d'envoi.
void main() {
  group('choix du code', () {
    test('6 chiffres exactement', () {
      expect(ReglesCode.verifierChoix('48261'), RefusCode.format);
      expect(ReglesCode.verifierChoix('4826173'), RefusCode.format);
      expect(ReglesCode.verifierChoix('48a617'), RefusCode.format);
      expect(ReglesCode.verifierChoix('482617'), isNull);
    });

    test('suites évidentes refusées (OWASP, NIST 800-63B)', () {
      for (final code in [
        '123456',
        '000000',
        '654321',
        '234567',
        '876543',
        '901234',
        '111222',
        '121212',
        '456456',
        '777777',
        '147258',
      ]) {
        expect(ReglesCode.verifierChoix(code), RefusCode.evident, reason: code);
      }
    });

    test('date de naissance refusée quand elle est connue', () {
      final nee = DateTime(2009, 3, 14);
      expect(ReglesCode.verifierChoix('140309', dateNaissance: nee), RefusCode.dateNaissance);
      expect(ReglesCode.verifierChoix('090314', dateNaissance: nee), RefusCode.dateNaissance);
      expect(ReglesCode.verifierChoix('200903', dateNaissance: nee), RefusCode.dateNaissance);
      expect(ReglesCode.verifierChoix('140309'), isNull, reason: 'date inconnue : code accepté');
    });
  });

  group('code enregistré et 5 échecs', () {
    late CoffreFortMemoire coffre;
    late ServiceCodeSecret service;

    setUp(() {
      coffre = CoffreFortMemoire();
      // Peu d'itérations : le test porte sur les règles, pas sur la lenteur.
      service = ServiceCodeSecret(coffre: coffre, iterations: 1000);
    });

    test('le code n’est jamais gardé en clair', () async {
      await service.creer('compte', '482617');
      expect(await service.existe('compte'), isTrue);
      expect(coffre.valeurs.values.any((v) => v.contains('482617')), isFalse);
    });

    test('code évident refusé à la création', () async {
      expect(() => service.creer('compte', '123456'), throwsA(isA<CodeRefuse>()));
      expect(await service.existe('compte'), isFalse);
    });

    test('bon code : ouvert, compteur remis à zéro', () async {
      await service.creer('compte', '482617');
      expect(await service.verifier('compte', '111113'), isA<CodeFaux>());
      expect(await service.verifier('compte', '482617'), isA<CodeBon>());
      expect(await service.echecs('compte'), 0);
    });

    test('5 codes faux de suite : bloqué, même avec le bon code ensuite', () async {
      await service.creer('compte', '482617');
      final restants = <int>[];
      for (var i = 0; i < 4; i++) {
        final r = await service.verifier('compte', '999990');
        restants.add((r as CodeFaux).essaisRestants);
      }
      expect(restants, [4, 3, 2, 1]);
      expect(await service.verifier('compte', '999990'), isA<CodeBloque>());
      expect(await service.verifier('compte', '482617'), isA<CodeBloque>());
    });

    test('échec compté avant le calcul : quitter pendant la vérification ne remet rien à zéro', () async {
      final lent = ServiceCodeSecret(coffre: coffre, iterations: 1000, deriveur: _DeriveurInterrompu());
      await service.creer('compte', '482617');
      await expectLater(lent.verifier('compte', '999990'), throwsStateError);
      expect(await service.echecs('compte'), 1);
    });

    test('chaque compte a son code (téléphone partagé)', () async {
      await service.creer('awa', '482617');
      await service.creer('binta', '730519');
      expect(await service.verifier('awa', '730519'), isA<CodeFaux>());
      expect(await service.verifier('binta', '730519'), isA<CodeBon>());
    });

    test('oublier efface le code et le compteur', () async {
      await service.creer('compte', '482617');
      await service.verifier('compte', '999990');
      await service.oublier('compte');
      expect(await service.existe('compte'), isFalse);
      expect(await service.echecs('compte'), 0);
    });
  });

  group('délais de verrouillage par rôle', () {
    test('valeurs décidées le 2026-10-23', () {
      expect(DelaisVerrouillage.pour(['admin_gsg']), const Duration(minutes: 2));
      expect(DelaisVerrouillage.pour(['admin_contenu']), const Duration(minutes: 2));
      expect(DelaisVerrouillage.pour(['direction']), const Duration(minutes: 5));
      expect(DelaisVerrouillage.pour(['fondateur_reseau']), const Duration(minutes: 5));
      expect(DelaisVerrouillage.pour(['vendeur']), const Duration(minutes: 5));
      expect(DelaisVerrouillage.pour(['enseignant']), const Duration(minutes: 15));
      expect(DelaisVerrouillage.pour(['parent']), const Duration(minutes: 30));
      expect(DelaisVerrouillage.pour(['eleve']), const Duration(minutes: 30));
    });

    test('plusieurs rôles : le plus court', () {
      expect(DelaisVerrouillage.pour(['parent', 'enseignant']), const Duration(minutes: 15));
      expect(DelaisVerrouillage.pour(['eleve', 'direction', 'enseignant']), const Duration(minutes: 5));
    });

    test('poste inconnu ou aucun rôle : 5 min (personnel administratif)', () {
      expect(DelaisVerrouillage.pour(['comptable']), const Duration(minutes: 5));
      expect(DelaisVerrouillage.pour(const []), const Duration(minutes: 5));
    });

    test('captures protégées pour le personnel, pas pour parents et élèves', () {
      expect(DelaisVerrouillage.protegerCaptures(['parent']), isFalse);
      expect(DelaisVerrouillage.protegerCaptures(['eleve']), isFalse);
      expect(DelaisVerrouillage.protegerCaptures(['enseignant']), isTrue);
      expect(DelaisVerrouillage.protegerCaptures(['parent', 'direction']), isTrue);
    });
  });

  group('actions sensibles', () {
    tearDown(() => GardienActionsSensibles.brancher(null));

    test('code demandé à chaque fois', () async {
      final motifs = <String>[];
      GardienActionsSensibles.brancher((motif) async {
        motifs.add(motif);
        return true;
      });
      await exigerCodeSecret('Encaissement');
      await exigerCodeSecret('Encaissement');
      expect(motifs, ['Encaissement', 'Encaissement']);
    });

    test('code non confirmé : l’action n’a pas lieu', () async {
      GardienActionsSensibles.brancher((_) async => false);
      expect(() => exigerCodeSecret('Valider les notes'), throwsA(isA<ActionSensibleAnnulee>()));
    });

    test('sans verrou branché (tests, mode diagnostic) : rien n’est demandé', () async {
      GardienActionsSensibles.brancher(null);
      await exigerCodeSecret('Paiement');
    });
  });

  group('file d’envoi chiffrée', () {
    test('lisible par le même compte seulement, clé gardée après déconnexion', () async {
      final coffre = CoffreFortMemoire();
      final chiffreur = ChiffreurFile(coffre);
      final chiffre = await chiffreur.chiffrer('awa', '{"montant":150000}');
      expect(ChiffreurFile.estChiffre(chiffre), isTrue);
      expect(chiffre.contains('150000'), isFalse);
      expect(await chiffreur.dechiffrer('awa', chiffre), '{"montant":150000}');
      expect(await chiffreur.dechiffrer('binta', chiffre), isNull);
      // Nouvelle instance (application relancée) : même clé, même lecture.
      expect(await ChiffreurFile(coffre).dechiffrer('awa', chiffre), '{"montant":150000}');
    });
  });
}

class _DeriveurInterrompu implements DeriveurCode {
  @override
  Future<List<int>> deriver(String code, List<int> sel, int iterations) async => throw StateError('application fermée');
}
