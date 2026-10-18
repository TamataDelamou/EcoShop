import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/etats_financiers_hors_ligne_repository.dart';
import '../data/supabase_etats_financiers_repository.dart';
import '../domain/etats_financiers.dart';

/// États financiers — hors connexion d'abord (REG-03 C7) : consultation et
/// PDF depuis l'appareil, notes rédigées sans réseau puis envoyées.
final etatsFinanciersRepositoryProvider = Provider<EtatsFinanciersRepository>((ref) {
  return EtatsFinanciersHorsLigneRepository(
    SupabaseEtatsFinanciersRepository(ref.watch(supabaseClientProvider), ref.watch(lectureComptabiliteProvider)),
    ref.watch(syncRepositoryProvider),
  );
});

final etatFinancierProvider = FutureProvider.autoDispose
    .family<EtatFinancier, ({String etablissementId, String exerciceId})>((ref, args) {
  return ref.watch(etatsFinanciersRepositoryProvider).etat(args.etablissementId, args.exerciceId);
});

final apercuPcaProvider = FutureProvider.autoDispose.family<ApercuPca, String>((ref, exerciceId) {
  return ref.watch(etatsFinanciersRepositoryProvider).apercuPca(exerciceId);
});

final fluxTresorerieProvider = FutureProvider.autoDispose
    .family<TableauFlux, ({String etablissementId, String exerciceId})>((ref, args) {
  return ref.watch(etatsFinanciersRepositoryProvider).fluxTresorerie(args.etablissementId, args.exerciceId);
});

final notesAnnexesProvider = FutureProvider.autoDispose
    .family<NotesAnnexes, ({String etablissementId, String exerciceId})>((ref, args) {
  return ref.watch(etatsFinanciersRepositoryProvider).notesAnnexes(args.etablissementId, args.exerciceId);
});
