import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'coffre_fort.dart';

/// Chiffrement des opérations en attente d'envoi (REG-18).
///
/// Chaque compte a sa clé AES-256 dans le [CoffreFort] (Keystore / Keychain).
/// Elle n'est **jamais effacée** à la déconnexion ni après 5 codes faux :
/// les encaissements, écritures comptables et pointages faits sans réseau
/// restent sur le téléphone, illisibles pour un autre compte, et partent
/// quand le même compte se reconnecte.
class ChiffreurFile {
  ChiffreurFile(this._coffre, {Random? aleatoire}) : _aleatoire = aleatoire ?? Random.secure();

  final CoffreFort _coffre;
  final Random _aleatoire;
  final _aes = AesGcm.with256bits();

  static const prefixe = 'chiffre:v1:';

  static String _cle(String compteId) => 'file_cle.$compteId';

  Future<SecretKey> _cleDe(String compteId) async {
    final connue = await _coffre.lire(_cle(compteId));
    if (connue != null) return SecretKey(base64Decode(connue));
    final octets = List<int>.generate(32, (_) => _aleatoire.nextInt(256));
    await _coffre.ecrire(_cle(compteId), base64Encode(octets));
    return SecretKey(octets);
  }

  static bool estChiffre(String texte) => texte.startsWith(prefixe);

  Future<String> chiffrer(String compteId, String texte) async {
    final boite = await _aes.encrypt(
      utf8.encode(texte),
      secretKey: await _cleDe(compteId),
      nonce: _aes.newNonce(),
      // Lie le contenu au compte : une ligne recopiée vers un autre compte
      // ne se déchiffre pas.
      aad: utf8.encode(compteId),
    );
    return '$prefixe${base64Encode(boite.concatenation())}';
  }

  /// Null si le texte n'est pas déchiffrable par ce compte.
  Future<String?> dechiffrer(String compteId, String texte) async {
    if (!estChiffre(texte)) return texte;
    final connue = await _coffre.lire(_cle(compteId));
    if (connue == null) return null;
    try {
      final boite = SecretBox.fromConcatenation(
        base64Decode(texte.substring(prefixe.length)),
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      final clair = await _aes.decrypt(boite, secretKey: SecretKey(base64Decode(connue)), aad: utf8.encode(compteId));
      return utf8.decode(clair);
    } catch (_) {
      return null;
    }
  }
}
