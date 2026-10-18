import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/pieces_hors_ligne_repository.dart';
import '../data/supabase_comptabilisation_automatique_repository.dart';
import '../data/supabase_pieces_comptables_repository.dart';
import '../domain/comptabilisation_automatique.dart';
import '../domain/pieces_comptables.dart';

/// Pièces comptables — hors connexion d'abord (REG-03 C7) : consultation
/// gardée sur l'appareil, brouillards préparés sans réseau puis envoyés.
final piecesComptablesRepositoryProvider = Provider<PiecesComptablesRepository>((ref) {
  return PiecesHorsLigneRepository(
    SupabasePiecesComptablesRepository(ref.watch(supabaseClientProvider), ref.watch(lectureComptabiliteProvider)),
    ref.watch(syncRepositoryProvider),
  );
});

final exercicesComptablesProvider =
    FutureProvider.autoDispose.family<List<ExerciceComptable>, String>((ref, etablissementId) {
  return ref.watch(piecesComptablesRepositoryProvider).exercices(etablissementId);
});

final piecesComptablesProvider = FutureProvider.autoDispose
    .family<List<PieceComptable>, ({String etablissementId, String exerciceId})>((ref, args) {
  return ref.watch(piecesComptablesRepositoryProvider).pieces(args.etablissementId, args.exerciceId);
});

final pieceComptableDetailProvider = FutureProvider.autoDispose.family<PieceComptable, String>((ref, pieceId) {
  return ref.watch(piecesComptablesRepositoryProvider).detail(pieceId);
});

final comptabilisationAutomatiqueRepositoryProvider = Provider<ComptabilisationAutomatiqueRepository>((ref) {
  return SupabaseComptabilisationAutomatiqueRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(lectureComptabiliteProvider),
  );
});

final etatComptabilisationAutomatiqueProvider =
    FutureProvider.autoDispose.family<EtatComptabilisationAutomatique, String>((ref, etablissementId) {
  return ref.watch(comptabilisationAutomatiqueRepositoryProvider).etat(etablissementId);
});
