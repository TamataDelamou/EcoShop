import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../data/supabase_validation_marketplace_repository.dart';
import '../domain/agrement_vendeur.dart';
import '../domain/validation_marketplace_repository.dart';
import '../domain/vendeur_validation.dart';

final validationMarketplaceRepositoryProvider = Provider<ValidationMarketplaceRepository>((ref) {
  return SupabaseValidationMarketplaceRepository(ref.watch(supabaseClientProvider));
});

final vendeursValidationProvider = FutureProvider<List<VendeurValidation>>((ref) {
  return ref.watch(validationMarketplaceRepositoryProvider).vendeurs();
});

final agrementsEtablissementProvider = FutureProvider.family<List<AgrementVendeur>, String>((ref, etablissementId) {
  return ref.watch(validationMarketplaceRepositoryProvider).agrementsPourEtablissement(etablissementId);
});
