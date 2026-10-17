import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../data/supabase_creation_etablissement_repository.dart';
import '../domain/demande_etablissement.dart';

final creationEtablissementRepositoryProvider = Provider<CreationEtablissementRepository>((ref) {
  return SupabaseCreationEtablissementRepository(ref.watch(supabaseClientProvider));
});

/// Dernière demande du compte connecté — relue à la demande (bouton
/// « Actualiser ») : la validation GSG peut intervenir à tout moment.
final maDemandeEtablissementProvider = FutureProvider.autoDispose<DemandeEtablissement?>((ref) {
  return ref.watch(creationEtablissementRepositoryProvider).maDerniereDemande();
});

final demandesEtablissementATraiterProvider = FutureProvider.autoDispose<List<DemandeATraiter>>((ref) {
  return ref.watch(creationEtablissementRepositoryProvider).demandesATraiter();
});
