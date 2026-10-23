import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../data/supabase_liaisons_repository.dart';
import '../domain/liaison_compte.dart';

final liaisonsRepositoryProvider = Provider<LiaisonsRepository>((ref) {
  return SupabaseLiaisonsRepository(ref.watch(supabaseClientProvider));
});

/// Liaisons récentes et en attente d'une école (direction).
final liaisonsComptesProvider = FutureProvider.autoDispose.family<List<LiaisonCompte>, String>((ref, etablissementId) {
  return ref.watch(liaisonsRepositoryProvider).liaisons(etablissementId);
});

final plafondParentsProvider = FutureProvider.autoDispose.family<int, String>((ref, etablissementId) {
  return ref.watch(liaisonsRepositoryProvider).plafond(etablissementId);
});
