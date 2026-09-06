import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/auth/e164_validator.dart';

void main() {
  group('Validators.normalizeE164', () {
    test('normalise indicatif + numéro local (ch. 5.4.1)', () {
      expect(
        Validators.normalizeE164(indicatifPays: '+224', numeroLocal: '620 00 00 00'),
        '+224620000000',
      );
    });

    test('accepte un indicatif sans le préfixe +', () {
      expect(
        Validators.normalizeE164(indicatifPays: '224', numeroLocal: '620000000'),
        '+224620000000',
      );
    });

    test('retire les séparateurs et espaces', () {
      expect(
        Validators.normalizeE164(indicatifPays: '225', numeroLocal: '07-08-09-10-11'),
        '+2250708091011',
      );
    });

    test('renvoie null si le numéro local est vide', () {
      expect(
        Validators.normalizeE164(indicatifPays: '224', numeroLocal: '  '),
        isNull,
      );
    });

    test('renvoie null si le résultat est trop court', () {
      expect(
        Validators.normalizeE164(indicatifPays: '1', numeroLocal: '23'),
        isNull,
      );
    });
  });

  group('Validators.estE164', () {
    test('valide un numéro E.164', () {
      expect(Validators.estE164('+224620000000'), isTrue);
    });

    test('rejette une chaîne sans préfixe +', () {
      expect(Validators.estE164('224620000000'), isFalse);
    });
  });
}
