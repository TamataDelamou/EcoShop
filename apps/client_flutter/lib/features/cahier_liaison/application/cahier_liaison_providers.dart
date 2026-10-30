import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/supabase_cahier_liaison_repository.dart';
import '../domain/cahier_liaison.dart';

/// Derniers fils reçus, gardés pour la lecture sans réseau ; purgés à la
/// déconnexion.
final lectureCahierLiaisonProvider = Provider<LectureHorsLigne>((ref) {
  return LectureHorsLigne(
    CacheDocumentStore(ref.watch(databaseProvider), 'cahier_liaison_hl'),
    ref.watch(fraicheurHorsLigneProvider),
  );
});

final cahierLiaisonRepositoryProvider = Provider<CahierLiaisonRepository>((ref) {
  return SupabaseCahierLiaisonRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(syncRepositoryProvider),
    ref.watch(lectureCahierLiaisonProvider),
  );
});

/// Élèves du cahier : `null` pour un parent (ses enfants), l'école pour le
/// personnel.
final elevesLiaisonProvider = FutureProvider.autoDispose.family<List<EleveLiaison>, String?>((ref, etablissementId) {
  return ref.watch(cahierLiaisonRepositoryProvider).eleves(etablissementId: etablissementId);
});

final cahierLiaisonProvider = FutureProvider.autoDispose.family<List<MotLiaison>, String>((ref, ficheEleveId) {
  return ref.watch(cahierLiaisonRepositoryProvider).cahier(ficheEleveId);
});

/// Parent : à qui écrire au sujet de cet enfant, et heures de l'école.
final contactsEcoleProvider = FutureProvider.autoDispose.family<ContactsEcole, String>((ref, ficheEleveId) {
  return ref.watch(cahierLiaisonRepositoryProvider).contacts(ficheEleveId);
});
