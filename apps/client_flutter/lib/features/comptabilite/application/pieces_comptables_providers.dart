import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../data/supabase_comptabilisation_automatique_repository.dart';
import '../data/supabase_pieces_comptables_repository.dart';
import '../domain/comptabilisation_automatique.dart';
import '../domain/pieces_comptables.dart';

final piecesComptablesRepositoryProvider = Provider<PiecesComptablesRepository>((ref) {
  return SupabasePiecesComptablesRepository(ref.watch(supabaseClientProvider));
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
  return SupabaseComptabilisationAutomatiqueRepository(ref.watch(supabaseClientProvider));
});

final etatComptabilisationAutomatiqueProvider =
    FutureProvider.autoDispose.family<EtatComptabilisationAutomatique, String>((ref, etablissementId) {
  return ref.watch(comptabilisationAutomatiqueRepositoryProvider).etat(etablissementId);
});
