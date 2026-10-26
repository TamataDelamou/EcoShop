import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'coffre_fort.dart';

/// Code secret EcoShop (REG-18, partie C).
///
/// On prouve son identité une fois par téléphone (code e-mail ou Google) ;
/// ensuite l'application s'ouvre avec un code de 6 chiffres, vérifié sur le
/// téléphone, sans réseau. Le code n'est jamais gardé : seule son empreinte
/// (PBKDF2-HMAC-SHA256 salée) est rangée dans le [CoffreFort], avec le
/// compteur d'échecs.
///
/// Conforme à NIST SP 800-63B-4 §3.2.10 (secret d'activation) : 6 chiffres,
/// codes évidents refusés, au plus 10 échecs (ici 5), vérification sur
/// l'appareil.

/// Raison du refus d'un code choisi.
enum RefusCode {
  /// Pas exactement 6 chiffres.
  format,

  /// Suite évidente (123456, 000000, 121212…).
  evident,

  /// Date de naissance du compte.
  dateNaissance,
}

abstract final class ReglesCode {
  static const longueur = 6;
  static const echecsMax = 5;

  /// Codes trop souvent choisis, en plus des suites et répétitions.
  static const _courants = {
    '123123',
    '112233',
    '121212',
    '696969',
    '159753',
    '147258',
    '258369',
    '102030',
    '100200',
    '131313',
    '123321',
    '654321',
    '111222',
    '777777',
    '999999',
    '000000',
    '123456',
    '012345',
    '987654',
    '246810',
    '135790',
    '520520',
    '101010',
    '202020',
    '112211',
    '010203',
    '224466',
    '147852',
  };

  /// Null si le code est acceptable.
  static RefusCode? verifierChoix(String code, {DateTime? dateNaissance}) {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) return RefusCode.format;
    if (_courants.contains(code)) return RefusCode.evident;

    final chiffres = code.codeUnits.map((c) => c - 48).toList();
    // Un seul chiffre, ou deux chiffres seulement (111222, 121212…).
    if (chiffres.toSet().length <= 2) return RefusCode.evident;
    // Suite montante ou descendante (234567, 876543…).
    var montante = true;
    var descendante = true;
    for (var i = 1; i < chiffres.length; i++) {
      if (chiffres[i] != (chiffres[i - 1] + 1) % 10) montante = false;
      if (chiffres[i] != (chiffres[i - 1] + 9) % 10) descendante = false;
    }
    if (montante || descendante) return RefusCode.evident;
    // Motif de 3 chiffres répété (123123, 456456…).
    if (code.substring(0, 3) == code.substring(3)) return RefusCode.evident;

    if (dateNaissance != null) {
      String d2(int n) => n.toString().padLeft(2, '0');
      final j = d2(dateNaissance.day);
      final m = d2(dateNaissance.month);
      final a = d2(dateNaissance.year % 100);
      final annee = '${dateNaissance.year}';
      // JJMMAA, AAMMJJ, MMJJAA, AAAAMM, MMAAAA.
      final formes = {'$j$m$a', '$a$m$j', '$m$j$a', '$annee$m', '$m$annee'};
      if (formes.contains(code)) return RefusCode.dateNaissance;
    }
    return null;
  }

  static String message(RefusCode refus) => switch (refus) {
    RefusCode.format => 'Le code compte 6 chiffres.',
    RefusCode.evident => 'Ce code est trop facile à deviner. Choisissez des chiffres sans suite évidente.',
    RefusCode.dateNaissance => 'N’utilisez pas votre date de naissance.',
  };
}

/// Dérivation lente du code (remplaçable en test).
abstract interface class DeriveurCode {
  Future<List<int>> deriver(String code, List<int> sel, int iterations);
}

/// PBKDF2-HMAC-SHA256. `cryptography_flutter` (activé tout seul par Flutter)
/// fait faire le calcul par Android (javax.crypto), rapide même sur un téléphone
/// d'entrée de gamme.
class DeriveurPbkdf2 implements DeriveurCode {
  const DeriveurPbkdf2();

  @override
  Future<List<int>> deriver(String code, List<int> sel, int iterations) async {
    final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    final cle = await pbkdf2.deriveKey(secretKey: SecretKey(utf8.encode(code)), nonce: sel);
    return cle.extractBytes();
  }
}

/// Résultat d'une vérification.
sealed class ResultatCode {
  const ResultatCode();
}

class CodeBon extends ResultatCode {
  const CodeBon();
}

class CodeFaux extends ResultatCode {
  const CodeFaux(this.essaisRestants);
  final int essaisRestants;
}

/// 5 codes faux de suite : la session doit être fermée sur ce téléphone.
class CodeBloque extends ResultatCode {
  const CodeBloque();
}

class ServiceCodeSecret {
  ServiceCodeSecret({
    required this.coffre,
    this.deriveur = const DeriveurPbkdf2(),
    this.iterations = iterationsParDefaut,
    Random? aleatoire,
  }) : _aleatoire = aleatoire ?? Random.secure();

  /// Réglable par compte (gardé avec l'empreinte) : on peut l'augmenter plus
  /// tard sans invalider les codes existants.
  static const iterationsParDefaut = 210000;

  final CoffreFort coffre;
  final DeriveurCode deriveur;
  final int iterations;
  final Random _aleatoire;

  static String _cleCode(String compteId) => 'code_secret.$compteId';
  static String _cleEchecs(String compteId) => 'code_echecs.$compteId';
  static String _cleVersion(String compteId) => 'code_version.$compteId';

  Future<bool> existe(String compteId) async => await coffre.lire(_cleCode(compteId)) != null;

  /// Enregistre un nouveau code (après vérification des règles, sauf
  /// [sansControle] : code du compte déjà accepté par le serveur).
  Future<void> creer(String compteId, String code, {DateTime? dateNaissance, bool sansControle = false}) async {
    final refus = sansControle ? null : ReglesCode.verifierChoix(code, dateNaissance: dateNaissance);
    if (refus != null) throw CodeRefuse(refus);
    final sel = List<int>.generate(16, (_) => _aleatoire.nextInt(256));
    final empreinte = await _deriverMesure(code, sel, iterations, 'création');
    await coffre.ecrire(
      _cleCode(compteId),
      jsonEncode({'v': 1, 'sel': base64Encode(sel), 'empreinte': base64Encode(empreinte), 'iterations': iterations}),
    );
    await coffre.ecrire(_cleEchecs(compteId), '0');
  }

  Future<int> echecs(String compteId) async => int.tryParse(await coffre.lire(_cleEchecs(compteId)) ?? '') ?? 0;

  /// Vérifie le code. L'échec est compté AVANT le calcul : fermer
  /// l'application pendant la vérification ne remet pas le compteur à zéro.
  Future<ResultatCode> verifier(String compteId, String code) async {
    final brut = await coffre.lire(_cleCode(compteId));
    if (brut == null) return const CodeBloque();
    final deja = await echecs(compteId);
    if (deja >= ReglesCode.echecsMax) return const CodeBloque();
    await coffre.ecrire(_cleEchecs(compteId), '${deja + 1}');

    final enregistrement = jsonDecode(brut) as Map<String, dynamic>;
    final sel = base64Decode(enregistrement['sel'] as String);
    final attendue = base64Decode(enregistrement['empreinte'] as String);
    final obtenue = await _deriverMesure(code, sel, (enregistrement['iterations'] as num).toInt(), 'vérification');

    if (_egal(attendue, obtenue)) {
      await coffre.ecrire(_cleEchecs(compteId), '0');
      return const CodeBon();
    }
    final restants = ReglesCode.echecsMax - (deja + 1);
    return restants <= 0 ? const CodeBloque() : CodeFaux(restants);
  }

  /// Dérivation chronométrée. Le temps part dans les journaux de débogage
  /// (versions debug et profile, jamais en production) pour choisir le
  /// nombre d'itérations sur un vrai téléphone d'entrée de gamme (REG-18 :
  /// 210 000 aujourd'hui, l'OWASP en recommande 600 000 pour SHA-256).
  /// Lecture : `adb logcat | findstr "Code secret"`.
  Future<List<int>> _deriverMesure(String code, List<int> sel, int iterations, String operation) async {
    final chrono = Stopwatch()..start();
    final resultat = await deriveur.deriver(code, sel, iterations);
    chrono.stop();
    if (!kReleaseMode) {
      debugPrint('Code secret : dérivation PBKDF2-HMAC-SHA256 ($operation), '
          '$iterations itérations en ${chrono.elapsedMilliseconds} ms');
    }
    return resultat;
  }

  /// Version du code du compte (REG-22) dont ce code local est la copie ;
  /// null si inconnue (code créé avant REG-22).
  Future<int?> versionCompte(String compteId) async => int.tryParse(await coffre.lire(_cleVersion(compteId)) ?? '');

  Future<void> noterVersionCompte(String compteId, int version) => coffre.ecrire(_cleVersion(compteId), '$version');

  /// Efface le code et le compteur (déconnexion, 5 échecs, code oublié).
  Future<void> oublier(String compteId) async {
    await coffre.effacer(_cleCode(compteId));
    await coffre.effacer(_cleEchecs(compteId));
    await coffre.effacer(_cleVersion(compteId));
  }

  /// Comparaison en temps constant.
  static bool _egal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}

class CodeRefuse implements Exception {
  const CodeRefuse(this.raison);
  final RefusCode raison;

  @override
  String toString() => ReglesCode.message(raison);
}
