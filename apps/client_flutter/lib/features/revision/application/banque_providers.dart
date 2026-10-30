import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/banque_questions_repository.dart';
import '../domain/question.dart';

final banqueQuestionsRepositoryProvider = Provider<BanqueQuestionsRepository>((ref) {
  return BanqueQuestionsRepository(
    ref.watch(supabaseClientProvider),
    LectureHorsLigne(
      CacheDocumentStore(ref.watch(databaseProvider), 'banque_questions_hl'),
      ref.watch(fraicheurHorsLigneProvider),
    ),
    ref.watch(syncRepositoryProvider),
  );
});

final structureMatiereProvider = FutureProvider.autoDispose.family<StructureMatiere, String>(
  (ref, matiereId) => ref.watch(banqueQuestionsRepositoryProvider).structure(matiereId),
);

final questionsMatiereProvider = FutureProvider.autoDispose.family<List<Question>, String>((ref, matiereId) {
  ref.watch(suiviSyncProvider); // relu quand un brouillon en attente part
  return ref.watch(banqueQuestionsRepositoryProvider).questions(matiereId);
});

final questionsATraiterProvider = FutureProvider.autoDispose<List<Question>>(
  (ref) => ref.watch(banqueQuestionsRepositoryProvider).aTraiter(),
);

final questionsSignaleesProvider = FutureProvider.autoDispose<List<Question>>(
  (ref) => ref.watch(banqueQuestionsRepositoryProvider).signalees(),
);
