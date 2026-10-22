import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/offline/lecture_hors_ligne.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/supabase_bibliotheque_repository.dart';
import '../domain/bibliotheque.dart';

/// Cache dédié (catalogue, guichet : exemplaires, cartes, prêts), purgé à
/// la déconnexion.
final lectureBibliothequeProvider = Provider<LectureHorsLigne>((ref) {
  return LectureHorsLigne(
    CacheDocumentStore(ref.watch(databaseProvider), 'bibliotheque_hl'),
    ref.watch(fraicheurHorsLigneProvider),
  );
});

final bibliothequeRepositoryProvider = Provider<BibliothequeRepository>((ref) {
  return SupabaseBibliothequeRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(syncRepositoryProvider),
    CacheDocumentStore(ref.watch(databaseProvider), 'bibliotheque_hl'),
    ref.watch(lectureBibliothequeProvider),
  );
});

final catalogueProvider =
    FutureProvider.autoDispose.family<List<Livre>, ({String etablissementId, String texte})>((ref, cle) {
  return ref.watch(bibliothequeRepositoryProvider).catalogue(cle.etablissementId, texte: cle.texte);
});

final empruntsEleveProvider = FutureProvider.autoDispose
    .family<({List<EmpruntEleve> emprunts, List<ReservationEleve> reservations}), String>((ref, ficheId) {
  return ref.watch(bibliothequeRepositoryProvider).empruntsEleve(ficheId);
});

final tableauBibliothequeProvider = FutureProvider.autoDispose.family<TableauBibliotheque, String>((ref, etablissementId) {
  ref.watch(suiviSyncProvider);
  return ref.watch(bibliothequeRepositoryProvider).tableau(etablissementId);
});
