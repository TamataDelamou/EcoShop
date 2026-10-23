import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'coffre_fort.dart';

/// Ouverture par empreinte ou visage (REG-18, partie C), facultative ; le
/// code secret reste toujours le recours.
///
/// Liée à la cryptographie, pas à un simple « oui » du système (OWASP
/// MASWE-0020) : un jeton aléatoire est rangé sous une clé du Keystore
/// Android (ou du Keychain iOS) qui ne se déchiffre qu'après une lecture
/// biométrique **forte** réussie (`BiometricPrompt` + `CryptoObject`). La
/// clé est annulée par le système quand une empreinte ou un visage est
/// ajouté au téléphone : l'empreinte doit alors être réactivée après le
/// code.
abstract interface class Biometrie {
  /// Active pour ce compte (une lecture biométrique est demandée). Faux si
  /// le téléphone n'a pas de biométrie forte enregistrée ou si la personne
  /// annule.
  Future<bool> activer(String compteId);

  Future<bool> estActivee(String compteId);

  /// Vrai si la lecture biométrique a réussi.
  Future<bool> deverrouiller(String compteId);

  Future<void> desactiver(String compteId);
}

class BiometrieSysteme implements Biometrie {
  BiometrieSysteme(this._coffre);

  final CoffreFort _coffre;

  // Espace à part : chaque lecture déclenche la demande d'empreinte, sans
  // toucher au reste du coffre.
  static const _stockage = FlutterSecureStorage(
    aOptions: AndroidOptions.biometric(
      storageNamespace: 'ecoshop_biometrie',
      enforceBiometrics: true,
      requireBiometricsPerOperation: true,
      biometricType: AndroidBiometricType.strongBiometricOnly,
      biometricPromptTitle: 'Ouvrir EcoShop',
      biometricPromptSubtitle: 'Empreinte ou visage',
      biometricPromptNegativeButton: 'Utiliser mon code',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.passcode,
      accessControlFlags: [AccessControlFlag.biometryCurrentSet],
    ),
  );

  static String _cle(String compteId) => 'bio.$compteId';
  static String _cleAttendu(String compteId) => 'bio_attendu.$compteId';

  @override
  Future<bool> activer(String compteId) async {
    final aleatoire = Random.secure();
    final jeton = base64Encode(List<int>.generate(32, (_) => aleatoire.nextInt(256)));
    try {
      await _stockage.write(key: _cle(compteId), value: jeton);
      // Relu tout de suite : prouve que la lecture biométrique fonctionne.
      if (await _stockage.read(key: _cle(compteId)) != jeton) return false;
      await _coffre.ecrire(_cleAttendu(compteId), jeton);
      return true;
    } catch (e) {
      debugPrint('Biométrie indisponible : $e');
      await desactiver(compteId);
      return false;
    }
  }

  @override
  Future<bool> estActivee(String compteId) async => await _coffre.lire(_cleAttendu(compteId)) != null;

  @override
  Future<bool> deverrouiller(String compteId) async {
    final attendu = await _coffre.lire(_cleAttendu(compteId));
    if (attendu == null) return false;
    try {
      return await _stockage.read(key: _cle(compteId)) == attendu;
    } catch (e) {
      // Annulation, ou clé annulée par un changement d'empreinte.
      debugPrint('Lecture biométrique refusée : $e');
      return false;
    }
  }

  @override
  Future<void> desactiver(String compteId) async {
    await _coffre.effacer(_cleAttendu(compteId));
    try {
      await _stockage.delete(key: _cle(compteId));
    } catch (_) {
      // Rien à effacer.
    }
  }
}

/// Double de test.
class BiometrieMemoire implements Biometrie {
  BiometrieMemoire({this.disponible = true, this.reussit = true});

  bool disponible;
  bool reussit;
  final Set<String> actives = {};

  @override
  Future<bool> activer(String compteId) async {
    if (!disponible || !reussit) return false;
    actives.add(compteId);
    return true;
  }

  @override
  Future<bool> estActivee(String compteId) async => actives.contains(compteId);

  @override
  Future<bool> deverrouiller(String compteId) async => actives.contains(compteId) && reussit;

  @override
  Future<void> desactiver(String compteId) async => actives.remove(compteId);
}
