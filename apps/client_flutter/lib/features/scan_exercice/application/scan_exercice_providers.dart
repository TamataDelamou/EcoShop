import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/supabase_auth_provider.dart';
import '../data/supabase_scan_exercice_repository.dart';
import '../domain/scan_exercice_repository.dart';

/// Port du scan d'exercice — toujours réseau direct, comme
/// `chatIaRepositoryProvider` (M16, sous-livrable 5/7) : pas de décorateur de
/// cache/file hors-ligne, un scan suppose une connexion active.
final scanExerciceRepositoryProvider = Provider<ScanExerciceRepository>((ref) {
  return SupabaseScanExerciceRepository(ref.watch(supabaseClientProvider));
});
