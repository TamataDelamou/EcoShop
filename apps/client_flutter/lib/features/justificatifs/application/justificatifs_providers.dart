import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/justificatifs_repository.dart';
import '../domain/justificatif.dart';

/// Copies des justificatifs pour la lecture sans réseau (chiffrées par
/// compte, REG-35).
final lectureJustificatifsProvider = Provider<LectureHorsLigne>((ref) {
  return LectureHorsLigne(
    CacheDocumentStore(ref.watch(databaseProvider), 'justificatifs_hl'),
    ref.watch(fraicheurHorsLigneProvider),
  );
});

final justificatifsRepositoryProvider = Provider<JustificatifsRepository>((ref) {
  return JustificatifsRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(lectureJustificatifsProvider),
    ref.watch(syncRepositoryProvider),
  );
});

final justificatifsDeFicheProvider = FutureProvider.autoDispose.family<List<Justificatif>, String>((ref, ficheId) {
  ref.watch(suiviSyncProvider); // relu quand un dépôt en attente part
  return ref.watch(justificatifsRepositoryProvider).deFiche(ficheId);
});

final justificatifsATraiterProvider = FutureProvider.autoDispose.family<List<Justificatif>, String>((ref, etablissementId) {
  return ref.watch(justificatifsRepositoryProvider).aTraiter(etablissementId);
});
