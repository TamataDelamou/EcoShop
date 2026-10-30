import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/supabase_groupes_classe_repository.dart';
import '../domain/groupe_classe.dart';

/// Derniers groupes et fils reçus, pour la lecture sans réseau ; purgés à
/// la déconnexion.
final lectureGroupesClasseProvider = Provider<LectureHorsLigne>((ref) {
  return LectureHorsLigne(
    CacheDocumentStore(ref.watch(databaseProvider), 'groupes_classe_hl'),
    ref.watch(fraicheurHorsLigneProvider),
  );
});

final groupesClasseRepositoryProvider = Provider<GroupesClasseRepository>((ref) {
  return SupabaseGroupesClasseRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(syncRepositoryProvider),
    ref.watch(lectureGroupesClasseProvider),
  );
});

final mesGroupesProvider = FutureProvider.autoDispose.family<MesGroupes, String>((ref, etablissementId) {
  return ref.watch(groupesClasseRepositoryProvider).mesGroupes(etablissementId);
});

final filGroupeProvider = FutureProvider.autoDispose.family<List<MessageGroupe>, String>((ref, groupeId) {
  return ref.watch(groupesClasseRepositoryProvider).fil(groupeId);
});

final signalementsGroupeProvider = FutureProvider.autoDispose.family<List<SignalementGroupe>, String>((ref, groupeId) {
  return ref.watch(groupesClasseRepositoryProvider).signalements(groupeId);
});

final heuresMessagerieProvider = FutureProvider.autoDispose.family<HeuresMessagerie?, String>((ref, etablissementId) {
  return ref.watch(groupesClasseRepositoryProvider).heures(etablissementId);
});
