import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../data/supabase_dons_repository.dart';
import '../domain/dons.dart';

final donsRepositoryProvider = Provider<DonsRepository>((ref) {
  return SupabaseDonsRepository(ref.watch(supabaseClientProvider));
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
