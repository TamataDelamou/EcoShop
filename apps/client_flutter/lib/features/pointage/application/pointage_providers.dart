import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/supabase_pointage_repository.dart';
import '../domain/pointage.dart';

/// Cache dédié (cartes du portail, tableaux), purgé à la déconnexion.
final lecturePointageProvider = Provider<LectureHorsLigne>((ref) {
  return LectureHorsLigne(
    CacheDocumentStore(ref.watch(databaseProvider), 'pointage_hl'),
    ref.watch(fraicheurHorsLigneProvider),
  );
});

final pointageRepositoryProvider = Provider<PointageRepository>((ref) {
  return SupabasePointageRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(syncRepositoryProvider),
    CacheDocumentStore(ref.watch(databaseProvider), 'pointage_hl'),
    ref.watch(lecturePointageProvider),
  );
});

final presenceDuJourProvider = FutureProvider.autoDispose.family<PresenceDuJour, String>((ref, etablissementId) {
  ref.watch(suiviSyncProvider);
  return ref.watch(pointageRepositoryProvider).presenceDuJour(etablissementId);
});

final parametresPointageProvider = FutureProvider.autoDispose.family<ParametresPointage, String>((ref, etablissementId) {
  return ref.watch(pointageRepositoryProvider).parametres(etablissementId);
});

final creditsSmsProvider = FutureProvider.autoDispose.family<CreditsSms, String>((ref, etablissementId) {
  return ref.watch(pointageRepositoryProvider).creditsSms(etablissementId);
});

final apercuRelancesProvider = FutureProvider.autoDispose.family<ApercuRelances, String>((ref, etablissementId) {
  return ref.watch(pointageRepositoryProvider).apercuRelances(etablissementId);
});

final avisArriveeSortieProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(pointageRepositoryProvider).avisArriveeSortie();
});
