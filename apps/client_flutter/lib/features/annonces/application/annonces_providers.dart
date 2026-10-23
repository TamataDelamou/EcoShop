import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/supabase_annonces_repository.dart';
import '../domain/annonce.dart';

/// Dernières annonces reçues, gardées pour la lecture sans réseau ; purgées
/// à la déconnexion.
final lectureAnnoncesProvider = Provider<LectureHorsLigne>((ref) {
  return LectureHorsLigne(
    CacheDocumentStore(ref.watch(databaseProvider), 'annonces_hl'),
    ref.watch(fraicheurHorsLigneProvider),
  );
});

final annoncesRepositoryProvider = Provider<AnnoncesRepository>((ref) {
  return SupabaseAnnoncesRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(syncRepositoryProvider),
    ref.watch(lectureAnnoncesProvider),
  );
});

final mesAnnoncesProvider = FutureProvider.autoDispose<List<Annonce>>((ref) {
  return ref.watch(annoncesRepositoryProvider).mesAnnonces();
});

final annoncesEtablissementProvider = FutureProvider.autoDispose.family<List<Annonce>, String>((ref, etablissementId) {
  return ref.watch(annoncesRepositoryProvider).annoncesEtablissement(etablissementId);
});

final porteesAnnonceProvider = FutureProvider.autoDispose.family<PorteesDisponibles, String>((ref, etablissementId) {
  return ref.watch(annoncesRepositoryProvider).portees(etablissementId);
});
