import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../data/supabase_referentiel_comptable_repository.dart';
import '../domain/referentiel_comptable.dart';

final referentielComptableRepositoryProvider = Provider<ReferentielComptableRepository>((ref) {
  return SupabaseReferentielComptableRepository(ref.watch(supabaseClientProvider));
});

/// Référentiel en vigueur pour l'établissement (simplifié tant que rien
/// n'a été choisi).
final parametresComptablesProvider =
    FutureProvider.autoDispose.family<ParametresComptables, String>((ref, etablissementId) {
  return ref.watch(referentielComptableRepositoryProvider).parametres(etablissementId);
});
