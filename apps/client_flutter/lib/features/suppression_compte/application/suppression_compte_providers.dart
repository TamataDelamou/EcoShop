import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/config/env.dart';
import '../../../core/providers.dart';
import '../../auth/application/auth_providers.dart';
import '../data/supabase_suppression_compte_repository.dart';
import '../domain/suppression_compte.dart';

final suppressionCompteRepositoryProvider = Provider<SuppressionCompteRepository>(
  (ref) => SupabaseSuppressionCompteRepository(ref.watch(supabaseClientProvider)),
);

/// Demande de suppression en cours pour le compte connecté (REG-31). Sans
/// réseau ou sans serveur : « aucune » — le bandeau ne s'affiche pas, la
/// demande reste connue du serveur, qui seul décide.
final etatSuppressionCompteProvider = FutureProvider<EtatSuppressionCompte>((ref) async {
  if (!Env.estConfigure || !ref.watch(estEnLigneProvider)) return const EtatSuppressionCompte.aucune();
  final profil = await ref.watch(profilProvider.future);
  if (profil == null) return const EtatSuppressionCompte.aucune();
  try {
    return await ref.watch(suppressionCompteRepositoryProvider).etat();
  } catch (_) {
    return const EtatSuppressionCompte.aucune();
  }
});
