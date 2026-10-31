import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';

/// Albums photo de l'école (REG-39, migration 20260906001595) : par classe
/// ou pour toute l'école, affichage en mosaïque de photos.
///
/// Hors connexion d'abord : la liste des albums, celle des photos et les
/// photos déjà vues sont gardées sur le téléphone (copies chiffrées par
/// compte, effacées à la déconnexion avec le reste). L'ajout de photos
/// demande le réseau : l'écran le dit.
const bucketAlbums = 'albums';

class Album {
  const Album({
    required this.id,
    required this.titre,
    this.classeId,
    this.classeNom,
    this.description,
    this.couverture,
    this.nombrePhotos = 0,
    this.peutGerer = false,
  });

  factory Album.depuisJson(Map<String, dynamic> j) => Album(
        id: j['id'] as String,
        titre: j['titre'] as String? ?? 'Album',
        classeId: j['classe_id'] as String?,
        classeNom: j['classe_nom'] as String?,
        description: j['description'] as String?,
        couverture: j['couverture_chemin'] as String?,
        nombrePhotos: (j['nombre_photos'] as num?)?.toInt() ?? 0,
        peutGerer: j['peut_gerer'] as bool? ?? false,
      );

  Map<String, dynamic> versJson() => {
        'id': id,
        'titre': titre,
        'classe_id': classeId,
        'classe_nom': classeNom,
        'description': description,
        'couverture_chemin': couverture,
        'nombre_photos': nombrePhotos,
        'peut_gerer': peutGerer,
      };

  final String id;
  final String titre;
  final String? classeId;
  final String? classeNom;
  final String? description;
  final String? couverture;
  final int nombrePhotos;
  final bool peutGerer;

  /// « Toute l'école » ou le nom de la classe.
  String get portee => classeNom ?? 'Toute l’école';
}

class PhotoAlbum {
  const PhotoAlbum({required this.id, required this.chemin, this.legende});

  factory PhotoAlbum.depuisJson(Map<String, dynamic> j) =>
      PhotoAlbum(id: j['id'] as String, chemin: j['chemin'] as String, legende: j['legende'] as String?);

  Map<String, dynamic> versJson() => {'id': id, 'chemin': chemin, 'legende': legende};

  final String id;
  final String chemin;
  final String? legende;
}

class ErreurAlbum implements Exception {
  const ErreurAlbum(this.message);
  final String message;
  @override
  String toString() => message;
}

class AlbumsRepository {
  AlbumsRepository(this._client, this._lecture, this._photos);

  final SupabaseClient _client;
  final LectureHorsLigne _lecture;
  final CacheDocumentStore _photos;

  /// 1 Mo (limite du bucket) : les photos sont réduites avant l'envoi.
  static const tailleMax = 1024 * 1024;

  Future<List<Album>> albums(String etablissementId) => _lecture.lire(
        type: 'albums',
        cle: etablissementId,
        source: () async {
          final lignes = await _client.rpc<dynamic>('albums_etablissement', params: {'p_etablissement': etablissementId});
          return [for (final l in lignes as List) Album.depuisJson((l as Map).cast<String, dynamic>()).versJson()];
        },
        decoder: (j) => [for (final x in (j as List? ?? const [])) Album.depuisJson((x as Map).cast<String, dynamic>())],
      );

  Future<List<PhotoAlbum>> photos(String albumId) => _lecture.lire(
        type: 'albums_photos',
        cle: albumId,
        source: () async {
          final lignes = await _client
              .from('albums_photos')
              .select('id, chemin, legende')
              .eq('album_id', albumId)
              .isFilter('deleted_at', null)
              .order('created_at');
          return [for (final l in lignes) PhotoAlbum.depuisJson(l).versJson()];
        },
        decoder: (j) => [for (final x in (j as List? ?? const [])) PhotoAlbum.depuisJson((x as Map).cast<String, dynamic>())],
      );

  /// Octets d'une photo : copie du téléphone d'abord (une photo déjà vue
  /// s'affiche sans réseau), sinon téléchargement puis copie.
  Future<Uint8List?> octets(String chemin) async {
    try {
      final copie = await _photos.lireDocument('photo', chemin);
      final b64 = copie?['b64'] as String?;
      if (b64 != null) return base64Decode(b64);
    } catch (_) {}
    try {
      final o = await _client.storage.from(bucketAlbums).download(chemin);
      try {
        await _photos.ecrireDocument('photo', chemin, {'b64': base64Encode(o)});
      } catch (_) {}
      return o;
    } catch (_) {
      return null;
    }
  }

  Future<String> creerAlbum({
    required String etablissementId,
    required String titre,
    String? classeId,
    String? description,
  }) async {
    final id = const Uuid().v4();
    try {
      await _client.from('albums').insert({
        'id': id,
        'etablissement_id': etablissementId,
        'classe_id': classeId,
        'titre': titre.trim(),
        if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
      });
      return id;
    } on PostgrestException {
      throw const ErreurAlbum('Création impossible : vérifiez votre connexion, ou vos droits sur cette classe.');
    }
  }

  Future<void> ajouterPhoto({
    required String etablissementId,
    required String albumId,
    required Uint8List octets,
    String? legende,
  }) async {
    if (octets.length > tailleMax) throw const ErreurAlbum('Photo trop lourde (1 Mo au plus).');
    final id = const Uuid().v4();
    final chemin = '$etablissementId/$albumId/$id.jpg';
    try {
      await _client.storage.from(bucketAlbums).uploadBinary(
            chemin,
            octets,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      await _client.from('albums_photos').insert({
        'id': id,
        'album_id': albumId,
        'etablissement_id': etablissementId,
        'chemin': chemin,
        if (legende != null && legende.trim().isNotEmpty) 'legende': legende.trim(),
      });
      try {
        await _photos.ecrireDocument('photo', chemin, {'b64': base64Encode(octets)});
      } catch (_) {}
    } on StorageException {
      throw const ErreurAlbum('Envoi impossible pour le moment. Vérifiez votre connexion.');
    } on PostgrestException {
      throw const ErreurAlbum('Enregistrement impossible pour le moment.');
    }
  }

  Future<void> retirerPhoto(PhotoAlbum photo) async {
    try {
      await _client
          .from('albums_photos')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', photo.id);
    } on PostgrestException {
      throw const ErreurAlbum('Retrait impossible pour le moment.');
    }
  }

  Future<void> definirCouverture(String albumId, String chemin) async {
    try {
      await _client.from('albums').update({'couverture_chemin': chemin}).eq('id', albumId);
    } on PostgrestException {
      throw const ErreurAlbum('Modification impossible pour le moment.');
    }
  }

  Future<void> retirerAlbum(String albumId) async {
    try {
      await _client.from('albums').update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', albumId);
    } on PostgrestException {
      throw const ErreurAlbum('Retrait impossible pour le moment.');
    }
  }
}

final albumsRepositoryProvider = Provider<AlbumsRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return AlbumsRepository(
    ref.watch(supabaseClientProvider),
    LectureHorsLigne(CacheDocumentStore(db, 'albums_hl'), ref.watch(fraicheurHorsLigneProvider)),
    CacheDocumentStore(db, 'albums_photos'),
  );
});

final albumsProvider = FutureProvider.autoDispose.family<List<Album>, String>(
  (ref, etablissementId) => ref.watch(albumsRepositoryProvider).albums(etablissementId),
);

final photosAlbumProvider = FutureProvider.autoDispose.family<List<PhotoAlbum>, String>(
  (ref, albumId) => ref.watch(albumsRepositoryProvider).photos(albumId),
);

/// Photo déjà vue : gardée en mémoire le temps de la session.
final octetsPhotoAlbumProvider = FutureProvider.family<Uint8List?, String>(
  (ref, chemin) => ref.watch(albumsRepositoryProvider).octets(chemin),
);
