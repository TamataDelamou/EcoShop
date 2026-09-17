import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../data/supabase_proclamation_repository.dart';
import '../domain/eleve_mention.dart';
import '../domain/proclamation_repository.dart';

/// Action toujours en ligne (comme `NotesRepository`/`ScolariteRepository`
/// pour leurs écritures) : un verrouillage définitif ne se met jamais en
/// file d'attente hors connexion.
final proclamationRepositoryProvider = Provider<ProclamationRepository>((ref) {
  return SupabaseProclamationRepository(ref.watch(supabaseClientProvider));
});

final classeEstExamenProvider = FutureProvider.family<bool, String>((ref, classeId) {
  return ref.watch(proclamationRepositoryProvider).classeEstExamen(classeId);
});

final classeEstProclameeProvider =
    FutureProvider.family<bool, ({String classeId, String anneeScolaireId})>((ref, args) {
  return ref.watch(proclamationRepositoryProvider).classeEstProclamee(
        classeId: args.classeId,
        anneeScolaireId: args.anneeScolaireId,
      );
});

final elevesDeClasseMentionProvider = FutureProvider.family<List<EleveMention>, String>((ref, classeId) {
  return ref.watch(proclamationRepositoryProvider).elevesDeClasse(classeId);
});
