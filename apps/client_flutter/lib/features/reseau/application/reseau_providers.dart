import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/supabase_reseau_repository.dart';
import '../domain/reseau.dart';

/// Cache dédié (réseaux, tableaux de bord, circulaires), purgé à la
/// déconnexion.
final lectureReseauProvider = Provider<LectureHorsLigne>((ref) {
  return LectureHorsLigne(
    CacheDocumentStore(ref.watch(databaseProvider), 'reseau_hl'),
    ref.watch(fraicheurHorsLigneProvider),
  );
});

final reseauRepositoryProvider = Provider<ReseauRepository>((ref) {
  return SupabaseReseauRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(syncRepositoryProvider),
    ref.watch(lectureReseauProvider),
  );
});

/// Réseaux du compte : ceux qu'il pilote, et ceux de son école.
final mesReseauxProvider = FutureProvider.autoDispose<List<MonReseau>>((ref) {
  ref.watch(suiviSyncProvider);
  return ref.watch(reseauRepositoryProvider).mesReseaux();
});

final maDemandeReseauProvider = FutureProvider.autoDispose<DemandeReseau?>((ref) {
  ref.watch(suiviSyncProvider);
  return ref.watch(reseauRepositoryProvider).maDerniereDemande();
});

final tableauBordReseauProvider = FutureProvider.autoDispose.family<TableauBordReseau, String>((ref, reseauId) {
  return ref.watch(reseauRepositoryProvider).tableauBord(reseauId);
});

final circulairesReseauProvider = FutureProvider.autoDispose.family<List<CirculaireReseau>, String>((ref, reseauId) {
  ref.watch(suiviSyncProvider);
  return ref.watch(reseauRepositoryProvider).circulaires(reseauId);
});

final evenementsReseauProvider =
    FutureProvider.autoDispose.family<List<EvenementReseau>, ({String reseauId, String? etablissementId})>((ref, cle) {
  ref.watch(suiviSyncProvider);
  return ref.watch(reseauRepositoryProvider).evenements(cle.reseauId, etablissementId: cle.etablissementId);
});

final demandesReseauGsgProvider = FutureProvider.autoDispose<List<DemandeReseau>>((ref) {
  return ref.watch(reseauRepositoryProvider).demandesATraiter();
});

final reseauxGsgProvider = FutureProvider.autoDispose<List<ReseauVueGsg>>((ref) {
  return ref.watch(reseauRepositoryProvider).vueEnsemble();
});
