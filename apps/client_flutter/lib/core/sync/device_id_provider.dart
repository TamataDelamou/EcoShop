import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/cache_document_store.dart';
import '../providers.dart';

/// Identifiant stable de cet appareil, généré une fois et persisté localement.
///
/// Sert de facteur Last-Write-Wins pour les écritures hors-ligne (`device_id`
/// sur `notes`, cahier v4.1 ch. 34-35) : deux appareils modifiant la même
/// ligne hors connexion doivent rester distinguables une fois resynchronisés.
final deviceIdProvider = FutureProvider<String>((ref) async {
  final cache = CacheDocumentStore(ref.watch(databaseProvider), 'core');
  final document = await cache.lireDocument('device_id', CacheDocumentStore.cleUnique);
  final existant = document?['id'] as String?;
  if (existant != null) return existant;

  final nouveau = const Uuid().v4();
  await cache.ecrireDocument('device_id', CacheDocumentStore.cleUnique, {'id': nouveau});
  return nouveau;
});
