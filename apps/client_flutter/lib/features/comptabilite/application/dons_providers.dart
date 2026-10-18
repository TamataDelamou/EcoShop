import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/db/cache_document_store.dart';
import '../../../core/providers.dart';
import '../../../core/sync/device_id_provider.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/dons_hors_ligne_repository.dart';
import '../data/supabase_dons_repository.dart';
import '../domain/dons.dart';

/// Dons et donateurs — hors connexion d'abord (REG-03 C7) : reçus
/// provisoires sans réseau, numéro définitif attribué à l'envoi.
final donsRepositoryProvider = Provider<DonsRepository>((ref) {
  return DonsHorsLigneRepository(
    SupabaseDonsRepository(ref.watch(supabaseClientProvider), ref.watch(lectureComptabiliteProvider)),
    ref.watch(syncRepositoryProvider),
    CacheDocumentStore(ref.watch(databaseProvider), 'comptabilite_hl'),
    () => ref.read(deviceIdProvider.future),
  );
});

typedef CleAnnee = ({String etablissementId, int annee});

final tableauBordDonsProvider = FutureProvider.autoDispose.family<TableauBordDons, CleAnnee>((ref, cle) {
  return ref.watch(donsRepositoryProvider).tableauBord(cle.etablissementId, cle.annee);
});

final listeDonsProvider = FutureProvider.autoDispose.family<List<Don>, CleAnnee>((ref, cle) {
  return ref.watch(donsRepositoryProvider).dons(cle.etablissementId, cle.annee);
});

final donateursProvider = FutureProvider.autoDispose.family<List<Donateur>, String>((ref, etablissementId) {
  return ref.watch(donsRepositoryProvider).donateurs(etablissementId);
});

final affectationsDonsProvider = FutureProvider.autoDispose.family<List<AffectationDon>, String>((ref, etablissementId) {
  return ref.watch(donsRepositoryProvider).affectations(etablissementId);
});
