import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/supabase_transport_repository.dart';
import '../domain/transport.dart';

/// Cache dédié (circuits, élèves transportés et leurs cartes, trajet en
/// cours du chauffeur, suivi des familles), purgé à la déconnexion.
final lectureTransportProvider = Provider<LectureHorsLigne>((ref) {
  return LectureHorsLigne(
    CacheDocumentStore(ref.watch(databaseProvider), 'transport_hl'),
    ref.watch(fraicheurHorsLigneProvider),
  );
});

final transportRepositoryProvider = Provider<TransportRepository>((ref) {
  return SupabaseTransportRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(syncRepositoryProvider),
    CacheDocumentStore(ref.watch(databaseProvider), 'transport_hl'),
    ref.watch(lectureTransportProvider),
  );
});

final circuitsTransportProvider = FutureProvider.autoDispose.family<List<CircuitTransport>, String>((ref, etablissementId) {
  return ref.watch(transportRepositoryProvider).circuits(etablissementId);
});

/// Circuits que le compte conduit (vide pour qui n'est pas chauffeur).
final mesCircuitsChauffeurProvider = FutureProvider.autoDispose<List<CircuitTransport>>((ref) {
  return ref.watch(transportRepositoryProvider).mesCircuitsChauffeur();
});

final suiviTransportProvider = FutureProvider.autoDispose.family<SuiviTransport, String>((ref, ficheEleveId) {
  return ref.watch(transportRepositoryProvider).suivi(ficheEleveId);
});
