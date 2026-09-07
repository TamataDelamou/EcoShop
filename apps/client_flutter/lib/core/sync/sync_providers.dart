import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'drift_sync_repository.dart';

/// Repository Drift de la file `sync_queue`, partagé par tous les modules
/// d'écriture hors-ligne (M6 et suivants).
///
/// L'assemblage du [SyncEngine] lui-même (avec sa fonction de rejeu,
/// spécifique à chaque module) vit à la racine applicative
/// (`features/coquille/application/sync_composition.dart`) : le socle ne doit
/// pas connaître les entités métier qu'il rejoue.
final syncRepositoryProvider = Provider<DriftSyncRepository>((ref) {
  return DriftSyncRepository(ref.watch(databaseProvider));
});
