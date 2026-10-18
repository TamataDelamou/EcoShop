import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/cache_document_store.dart';
import '../offline/lecture_hors_ligne.dart';
import '../providers.dart';
import 'drift_sync_repository.dart';
import 'journal_rejets.dart';

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

/// Opérations en attente d'envoi et refusées, en direct (bandeau).
final suiviSyncProvider = StreamProvider<({int enAttente, int rejetees})>((ref) {
  return ref.watch(syncRepositoryProvider).suivre();
});

/// Refus du serveur au retour du réseau, à montrer à l'utilisateur.
final journalRejetsProvider = Provider<JournalRejets>((ref) {
  return JournalRejets(
    CacheDocumentStore(ref.watch(databaseProvider), 'sync_rejets'),
    ref.watch(syncRepositoryProvider),
  );
});

/// Date des données affichées quand elles viennent de l'appareil (`null` :
/// données fraîches du serveur).
final fraicheurHorsLigneProvider = Provider<ValueNotifier<DateTime?>>((ref) {
  final notifier = ValueNotifier<DateTime?>(null);
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// Lecture hors connexion des écrans de comptabilité (REG-03), domaine de
/// cache dédié, purgé à la déconnexion.
final lectureComptabiliteProvider = Provider<LectureHorsLigne>((ref) {
  return LectureHorsLigne(
    CacheDocumentStore(ref.watch(databaseProvider), 'comptabilite_hl'),
    ref.watch(fraicheurHorsLigneProvider),
  );
});
