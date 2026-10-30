import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/revision_repository.dart';
import '../domain/quiz.dart';

final revisionRepositoryProvider = Provider<RevisionRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return RevisionRepository(
    ref.watch(supabaseClientProvider),
    CacheDocumentStore(db, 'revision_appareil'),
    LectureHorsLigne(CacheDocumentStore(db, 'revision_hl'), ref.watch(fraicheurHorsLigneProvider)),
    ref.watch(syncRepositoryProvider),
  );
});

/// Tout ce qu'il faut pour l'écran des révisions d'un élève.
class EspaceRevision {
  const EspaceRevision({required this.niveau, required this.paquet, required this.traces, required this.resume});

  final NiveauRevision niveau;
  final PaquetRevision paquet;
  final Map<String, TraceQuestion> traces;
  final ResumeRevision resume;
}

final espaceRevisionProvider = FutureProvider.autoDispose.family<EspaceRevision, String>((ref, ficheId) async {
  ref.watch(suiviSyncProvider); // relu quand un quiz en attente part
  final depot = ref.watch(revisionRepositoryProvider);
  final niveau = await depot.niveau(ficheId);
  final paquet = await depot.paquet(niveau);
  final traces = await depot.traces(ficheId);
  final resume = await depot.resume(ficheId, paquet: paquet);
  return EspaceRevision(niveau: niveau, paquet: paquet, traces: traces, resume: resume);
});
