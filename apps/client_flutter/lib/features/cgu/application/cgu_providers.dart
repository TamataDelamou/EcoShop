import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../data/supabase_cgu_repository.dart';
import '../domain/cgu_repository.dart';
import '../domain/cgu_statut.dart';

final cguRepositoryProvider = Provider<CguRepository>((ref) {
  return SupabaseCguRepository(ref.watch(supabaseClientProvider));
});

/// Statut CGU du compte connecté — server-backed (jamais un cache local :
/// l'acceptation doit survivre une réinstallation, contrairement à
/// `onboardingRegionalisationVuProvider`, une simple préférence d'ergonomie).
final cguStatutProvider =
    AsyncNotifierProvider<CguStatutNotifier, CguStatut?>(CguStatutNotifier.new);

class CguStatutNotifier extends AsyncNotifier<CguStatut?> {
  @override
  Future<CguStatut?> build() => ref.watch(cguRepositoryProvider).statut();

  Future<void> accepter() async {
    final statut = state.value;
    if (statut == null) return;
    await ref.read(cguRepositoryProvider).accepter(statut.cguVersionId);
    state = AsyncData(statut.copierAvecAcceptee(true));
  }
}

extension on CguStatut {
  CguStatut copierAvecAcceptee(bool acceptee) => CguStatut(
        cguVersionId: cguVersionId,
        parcours: parcours,
        numeroVersion: numeroVersion,
        contenu: contenu,
        publieeLe: publieeLe,
        acceptee: acceptee,
      );
}
