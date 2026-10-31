import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/concours_repository.dart';
import '../domain/concours.dart';

final concoursRepositoryProvider = Provider<ConcoursRepository>((ref) => ConcoursRepository(
      ref.watch(supabaseClientProvider),
      LectureHorsLigne(CacheDocumentStore(ref.watch(databaseProvider), 'concours_hl'), ref.watch(fraicheurHorsLigneProvider)),
      ref.watch(syncRepositoryProvider),
    ));

final concoursEleveProvider = FutureProvider.autoDispose.family<List<Concours>, String>((ref, ficheId) {
  ref.watch(suiviSyncProvider); // relu quand une copie en attente part
  return ref.watch(concoursRepositoryProvider).concoursEleve(ficheId);
});

typedef CleClassementConcours = ({String concours, String? fiche, String? pays, String? etablissement});

final classementConcoursProvider =
    FutureProvider.autoDispose.family<ClassementConcours, CleClassementConcours>((ref, c) {
  ref.watch(suiviSyncProvider);
  return ref
      .watch(concoursRepositoryProvider)
      .classement(c.concours, ficheId: c.fiche, pays: c.pays, etablissementId: c.etablissement);
});

/// Concours organisés : par l'école, ou par GSG si l'identifiant est nul.
final concoursOrganisesProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String?>(
  (ref, etablissementId) => ref.watch(concoursRepositoryProvider).organises(etablissementId),
);

final questionsProposeesProvider = FutureProvider.autoDispose.family<List<QuestionProposee>, String>(
  (ref, concoursId) => ref.watch(concoursRepositoryProvider).questionsProposees(concoursId),
);
