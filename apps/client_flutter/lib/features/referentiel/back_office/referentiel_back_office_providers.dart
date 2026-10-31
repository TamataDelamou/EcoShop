import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import 'referentiel_back_office.dart';
import 'referentiel_back_office_repository.dart';

final referentielBackOfficeRepositoryProvider = Provider<ReferentielBackOfficeRepository>((ref) => ReferentielBackOfficeRepository(
      ref.watch(supabaseClientProvider),
      LectureHorsLigne(CacheDocumentStore(ref.watch(databaseProvider), 'referentiel_bo_hl'), ref.watch(fraicheurHorsLigneProvider)),
      ref.watch(syncRepositoryProvider),
    ));

final paysBackOfficeProvider = FutureProvider.autoDispose<List<PaysBackOffice>>((ref) {
  ref.watch(suiviSyncProvider); // relu quand une écriture en attente part
  return ref.watch(referentielBackOfficeRepositoryProvider).pays();
});

final referentielPaysProvider = FutureProvider.autoDispose.family<ReferentielPays, String>((ref, code) {
  ref.watch(suiviSyncProvider);
  return ref.watch(referentielBackOfficeRepositoryProvider).referentiel(code);
});
