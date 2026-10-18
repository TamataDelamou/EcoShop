import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../data/supabase_changement_plan_repository.dart';
import '../data/supabase_referentiel_comptable_repository.dart';
import '../domain/changement_plan.dart';
import '../domain/referentiel_comptable.dart';

final changementPlanRepositoryProvider = Provider<ChangementPlanRepository>((ref) {
  return SupabaseChangementPlanRepository(ref.watch(supabaseClientProvider));
});

/// Comptes de détail d'un plan de référence (choix d'un compte cible).
final comptesCiblesProvider =
    FutureProvider.autoDispose.family<List<CompteCible>, ReferentielComptable>((ref, referentiel) {
  return ref.watch(changementPlanRepositoryProvider).comptesCibles(referentiel);
});

final referentielComptableRepositoryProvider = Provider<ReferentielComptableRepository>((ref) {
  return SupabaseReferentielComptableRepository(ref.watch(supabaseClientProvider));
});

/// Référentiel en vigueur pour l'établissement (simplifié tant que rien
/// n'a été choisi).
final parametresComptablesProvider =
    FutureProvider.autoDispose.family<ParametresComptables, String>((ref, etablissementId) {
  return ref.watch(referentielComptableRepositoryProvider).parametres(etablissementId);
});
