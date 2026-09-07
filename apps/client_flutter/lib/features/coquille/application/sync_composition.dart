import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/sync/sync_providers.dart';
import '../../notes/application/notes_providers.dart';
import '../../vie_scolaire/application/vie_scolaire_providers.dart';

/// Assemble le [SyncEngine] applicatif avec la fonction de rejeu de chaque
/// module d'écriture hors-ligne.
///
/// Composition volontairement centralisée ici (coquille = racine
/// applicative) plutôt que dans `core/sync` : le socle ne doit pas connaître
/// les entités métier (`notes`, puis `absences`, `paiements`…) qu'il rejoue —
/// seule la coquille, qui assemble déjà toutes les features pour la
/// navigation, a une vue d'ensemble légitime sur ce registre.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final gestionnaires = <String, Future<void> Function(SyncEntree)>{
    'notes': ref.watch(notesRejeuProvider),
    'presences': ref.watch(presencesRejeuProvider),
    'retards': ref.watch(retardsRejeuProvider),
  };

  return SyncEngine(
    repository: ref.watch(syncRepositoryProvider),
    estConnecte: () async => ref.read(estEnLigneProvider),
    rejouer: (entree) {
      final gestionnaire = gestionnaires[entree.entite];
      return gestionnaire == null ? Future.value() : gestionnaire(entree);
    },
  );
});
