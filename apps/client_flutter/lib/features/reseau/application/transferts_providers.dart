import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/supabase_transferts_reseau_repository.dart';
import '../domain/regles_transferts.dart';
import 'reseau_providers.dart';

final transfertsReseauRepositoryProvider = Provider<TransfertsReseauRepository>((ref) {
  return SupabaseTransfertsReseauRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(syncRepositoryProvider),
    ref.watch(lectureReseauProvider),
  );
});

final reglesReseauProvider =
    FutureProvider.autoDispose.family<ReglesReseau, ({String reseauId, String? etablissementId})>((ref, cle) {
  return ref.watch(transfertsReseauRepositoryProvider).regles(cle.reseauId, etablissementId: cle.etablissementId);
});

/// Transferts d'un réseau (Direction Générale) ou d'une école (départs et
/// arrivées).
final transfertsReseauProvider =
    FutureProvider.autoDispose.family<List<TransfertReseau>, ({String? reseauId, String? etablissementId})>((ref, cle) {
  ref.watch(suiviSyncProvider);
  return ref
      .watch(transfertsReseauRepositoryProvider)
      .transferts(reseauId: cle.reseauId, etablissementId: cle.etablissementId);
});

final destinationsTransfertProvider =
    FutureProvider.autoDispose.family<List<DestinationTransfert>, String>((ref, etablissementId) {
  return ref.watch(transfertsReseauRepositoryProvider).destinations(etablissementId);
});

final elevesTransferablesProvider =
    FutureProvider.autoDispose.family<List<EleveTransferable>, ({String etablissementId, String texte})>((ref, cle) {
  return ref.watch(transfertsReseauRepositoryProvider).elevesTransferables(cle.etablissementId, texte: cle.texte);
});

final classesAccueilProvider = FutureProvider.autoDispose.family<List<ClasseAccueil>, String>((ref, transfertId) {
  return ref.watch(transfertsReseauRepositoryProvider).classesAccueil(transfertId);
});
