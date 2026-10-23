import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage protégé par le système (REG-18) : Android Keystore (AES-GCM, clé
/// jamais exportable), iOS Keychain (lisible seulement sur cet appareil).
///
/// Y sont rangés : la session Supabase, l'empreinte du code secret et son
/// compteur d'échecs, la clé de chiffrement de la file d'envoi de chaque
/// compte. Jamais un code en clair.
abstract interface class CoffreFort {
  Future<String?> lire(String cle);
  Future<void> ecrire(String cle, String valeur);
  Future<void> effacer(String cle);
}

/// Implémentation du système.
class CoffreFortSysteme implements CoffreFort {
  CoffreFortSysteme()
    : _stockage = const FlutterSecureStorage(
        aOptions: AndroidOptions(storageNamespace: 'ecoshop_coffre'),
        // Jamais sauvegardé dans iCloud ni restauré sur un autre appareil.
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
      );

  final FlutterSecureStorage _stockage;

  @override
  Future<String?> lire(String cle) => _stockage.read(key: cle);

  @override
  Future<void> ecrire(String cle, String valeur) => _stockage.write(key: cle, value: valeur);

  @override
  Future<void> effacer(String cle) => _stockage.delete(key: cle);
}

/// Double de test (et repli quand le système n'offre pas de stockage
/// protégé, PC de développement).
class CoffreFortMemoire implements CoffreFort {
  final Map<String, String> valeurs = {};

  @override
  Future<String?> lire(String cle) async => valeurs[cle];

  @override
  Future<void> ecrire(String cle, String valeur) async => valeurs[cle] = valeur;

  @override
  Future<void> effacer(String cle) async => valeurs.remove(cle);
}
