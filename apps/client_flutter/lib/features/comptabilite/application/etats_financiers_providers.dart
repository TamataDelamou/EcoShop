import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../data/supabase_etats_financiers_repository.dart';
import '../domain/etats_financiers.dart';

final etatsFinanciersRepositoryProvider = Provider<EtatsFinanciersRepository>((ref) {
  return SupabaseEtatsFinanciersRepository(ref.watch(supabaseClientProvider));
});

final etatFinancierProvider = FutureProvider.autoDispose
    .family<EtatFinancier, ({String etablissementId, String exerciceId})>((ref, args) {
  return ref.watch(etatsFinanciersRepositoryProvider).etat(args.etablissementId, args.exerciceId);
});

final apercuPcaProvider = FutureProvider.autoDispose.family<ApercuPca, String>((ref, exerciceId) {
  return ref.watch(etatsFinanciersRepositoryProvider).apercuPca(exerciceId);
});
