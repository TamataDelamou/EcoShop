import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';

import 'coffre_fort.dart';

/// Chiffreur de la file d'envoi. Null sans configuration Supabase (mode
/// diagnostic, tests qui ne portent pas sur lui) : la file reste en clair.
final chiffreurFileProvider = Provider<ChiffreurFile?>((ref) {
  if (!Env.estConfigure) return null;
  return ChiffreurFile(ref.watch(coffreFortProvider));
});

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

  /// Clés déjà lues dans le coffre : les copies d'écran (REG-35) sont
  /// chiffrées une à une, le coffre du système n'est lu qu'une fois.
  final _cles = <String, SecretKey>{};

  Future<SecretKey> _cleDe(String compteId) async {
    final enMemoire = _cles[compteId];
    if (enMemoire != null) return enMemoire;
    final connue = await _coffre.lire(_cle(compteId));
    if (connue != null) return _cles[compteId] = SecretKey(base64Decode(connue));
    final octets = List<int>.generate(32, (_) => _aleatoire.nextInt(256));
    await _coffre.ecrire(_cle(compteId), base64Encode(octets));
    return _cles[compteId] = SecretKey(octets);
  }

  /// Efface la clé du compte (« appareil partagé » à la déconnexion) : tout
  /// ce qui a été chiffré avec elle devient illisible, sur-le-champ.
  Future<void> oublierCle(String compteId) async {
    _cles.remove(compteId);
    await _coffre.effacer(_cle(compteId));
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
    SecretKey? cle = _cles[compteId];
    if (cle == null) {
      final connue = await _coffre.lire(_cle(compteId));
      if (connue == null) return null;
      cle = _cles[compteId] = SecretKey(base64Decode(connue));
    }
    try {
      final boite = SecretBox.fromConcatenation(
        base64Decode(texte.substring(prefixe.length)),
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      final clair = await _aes.decrypt(boite, secretKey: cle, aad: utf8.encode(compteId));
      return utf8.decode(clair);
    } catch (_) {
      return null;
    }
  }
}
