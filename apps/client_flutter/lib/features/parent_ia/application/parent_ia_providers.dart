import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../data/supabase_parent_ia_repository.dart';
import '../domain/parent_ia_config.dart';
import '../domain/parent_ia_repository.dart';
import '../domain/restriction_parent_ia.dart';

/// Port PARENT IA — réseau direct, pas de décorateur de cache hors-ligne
/// (même discipline que `ChatIaRepository`, M16 3/7) : ce module dépend
/// d'une analyse IA qui suppose une connexion active.
final parentIaRepositoryProvider = Provider<ParentIaRepository>((ref) {
  return SupabaseParentIaRepository(ref.watch(supabaseClientProvider));
});

/// Configuration PARENT IA d'une fiche (élève propriétaire ou parent confirmé).
final parentIaConfigProvider = FutureProvider.family<ParentIaConfig, String>((
  ref,
  ficheEleveId,
) {
  return ref.watch(parentIaRepositoryProvider).configuration(ficheEleveId);
});

/// Historique des restrictions d'une fiche, du plus récent au plus ancien.
final parentIaHistoriqueProvider =
    FutureProvider.family<List<RestrictionParentIa>, String>((
      ref,
      ficheEleveId,
    ) {
      return ref.watch(parentIaRepositoryProvider).historique(ficheEleveId);
    });
