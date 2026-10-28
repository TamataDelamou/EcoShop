import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import 'auth_providers.dart';
import 'session_locale.dart';

/// Bucket privé des photos de profil (migration 20260906001571).
const bucketPhotosProfils = 'photos-profils';

/// Photo de profil (REG-23) : dépôt dans le dossier du compte, chemin
/// enregistré sur le profil, lecture des octets.
abstract interface class PhotoProfilRepository {
  Future<String> televerser(String profilId, Uint8List octets, String extension);
  Future<void> definir(String? chemin);
  Future<Uint8List> telecharger(String chemin);
}

class ErreurPhotoProfil implements Exception {
  const ErreurPhotoProfil(this.message);
  final String message;
  @override
  String toString() => message;
}

class SupabasePhotoProfilRepository implements PhotoProfilRepository {
  const SupabasePhotoProfilRepository(this._client);

  final SupabaseClient _client;

  /// 512 Ko (limite du bucket) : la photo est réduite avant l'envoi.
  static const tailleMaxOctets = 512 * 1024;

  @override
  Future<String> televerser(String profilId, Uint8List octets, String extension) async {
    if (octets.length > tailleMaxOctets) {
      throw const ErreurPhotoProfil('La photo dépasse 512 Ko. Choisissez une image plus légère.');
    }
    final ext = extension == 'png' ? 'png' : 'jpg';
    final chemin = '$profilId/photo-${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await _client.storage.from(bucketPhotosProfils).uploadBinary(
            chemin,
            octets,
            fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg', upsert: true),
          );
      return chemin;
    } on StorageException {
      throw const ErreurPhotoProfil('Envoi impossible pour le moment. Vérifiez votre connexion et réessayez.');
    }
  }

  @override
  Future<void> definir(String? chemin) async {
    try {
      await _client.rpc<dynamic>('definir_photo_profil', params: {'p_chemin': chemin});
    } on PostgrestException {
      throw const ErreurPhotoProfil('Enregistrement impossible pour le moment. Réessayez.');
    }
  }

  @override
  Future<Uint8List> telecharger(String chemin) => _client.storage.from(bucketPhotosProfils).download(chemin);
}

final photoProfilRepositoryProvider = Provider<PhotoProfilRepository>(
  (ref) => SupabasePhotoProfilRepository(ref.watch(supabaseClientProvider)),
);

/// Octets d'une photo de profil, gardés sur le téléphone (hors connexion
/// d'abord) : une photo déjà vue s'affiche sans réseau. Le chemin change à
/// chaque nouvelle photo, la copie ne devient donc jamais fausse. Copie
/// effacée à la déconnexion (copie de session). Jamais d'erreur : null.
final photoProfilProvider = FutureProvider.family<Uint8List?, String>((ref, chemin) async {
  final store = ref.read(storeSessionLocaleProvider);
  try {
    final doc = await store.lireDocument('photo_profil', chemin);
    final b64 = doc?['b64'] as String?;
    if (b64 != null) return base64Decode(b64);
  } catch (_) {}
  try {
    final octets = await ref.read(photoProfilRepositoryProvider).telecharger(chemin);
    try {
      await store.ecrireDocument('photo_profil', chemin, {'b64': base64Encode(octets)});
    } catch (_) {}
    return octets;
  } catch (_) {
    return null;
  }
});

/// Choix d'une photo dans la galerie ou à l'appareil photo (réduite à
/// 512 px). Abstrait pour les tests.
typedef ImageProfil = ({Uint8List octets, String extension});

final selecteurPhotoProfilProvider = Provider<Future<ImageProfil?> Function(ImageSource source)>((ref) {
  return (source) async {
    final fichier = await ImagePicker().pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 82,
      preferredCameraDevice: CameraDevice.front,
    );
    if (fichier == null) return null;
    final nom = fichier.name.toLowerCase();
    return (octets: await fichier.readAsBytes(), extension: nom.endsWith('.png') ? 'png' : 'jpeg');
  };
});

/// Change (ou retire, [octets] null) la photo du compte connecté, puis
/// relit le profil : toute l'application affiche la nouvelle photo.
Future<void> changerPhotoProfil(WidgetRef ref, {required String profilId, ImageProfil? image}) async {
  final depot = ref.read(photoProfilRepositoryProvider);
  String? chemin;
  if (image != null) {
    chemin = await depot.televerser(profilId, image.octets, image.extension);
    // Copie locale tout de suite : pas de second téléchargement.
    try {
      await ref.read(storeSessionLocaleProvider).ecrireDocument('photo_profil', chemin, {'b64': base64Encode(image.octets)});
    } catch (_) {}
  }
  await depot.definir(chemin);
  ref.invalidate(profilProvider);
}
