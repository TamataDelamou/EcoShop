import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'sync_engine.dart';

/// Implémentation Drift du port [SyncRepository] — file `sync_queue` (ch. 34-35).
///
/// Jusqu'à M6, [SyncEngine] n'avait aucune implémentation concrète : le
/// module Notes est le premier à écrire hors connexion (saisie de notes par
/// l'enseignant), d'où l'introduction de ce repository partagé par tous les
/// modules d'écriture à venir (M7 absences, M8 RH…).
class DriftSyncRepository implements SyncRepository {
  const DriftSyncRepository(this._db);

  final AppDatabase _db;

  /// Enfile une opération à rejouer. Un même [SyncEntree.id] réenfilé (ex. la
  /// même note modifiée deux fois hors connexion avant reconnexion) remplace
  /// la précédente et repart avec un budget de tentatives neuf, plutôt que de
  /// rester bloqué sur un ancien statut `echec`.
  Future<void> enfiler(SyncEntree entree) {
    return _db.into(_db.syncQueueEntries).insertOnConflictUpdate(
          SyncQueueEntriesCompanion.insert(
            id: entree.id,
            entite: entree.entite,
            operation: entree.operation,
            payload: entree.payload,
            tentatives: const Value(0),
            statut: Value(SyncStatut.enAttente.code),
          ),
        );
  }

  /// Entrées à rejouer : ni terminées, ni refusées définitivement par le
  /// serveur (celles-là attendent une décision de l'utilisateur).
  @override
  Future<List<SyncEntree>> entreesEnAttente() async {
    final lignes = await (_db.select(_db.syncQueueEntries)
          ..where((t) => t.statut.isIn([SyncStatut.termine.code, SyncStatut.rejete.code]).not())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return lignes.map(_versEntree).toList(growable: false);
  }

  /// Entrées refusées par le serveur, les plus récentes d'abord.
  Future<List<SyncEntree>> entreesRejetees() async {
    final lignes = await (_db.select(_db.syncQueueEntries)
          ..where((t) => t.statut.equals(SyncStatut.rejete.code))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return lignes.map(_versEntree).toList(growable: false);
  }

  /// Suivi en direct pour l'interface : opérations en attente d'envoi et
  /// opérations refusées.
  Stream<({int enAttente, int rejetees})> suivre() {
    return _db.select(_db.syncQueueEntries).watch().map((lignes) => (
          enAttente: lignes
              .where((l) => l.statut != SyncStatut.termine.code && l.statut != SyncStatut.rejete.code)
              .length,
          rejetees: lignes.where((l) => l.statut == SyncStatut.rejete.code).length,
        ));
  }

  /// Retire une entrée (refus pris en compte par l'utilisateur).
  Future<void> retirer(String id) {
    return (_db.delete(_db.syncQueueEntries)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<void> marquer(SyncEntree entree) {
    return (_db.update(_db.syncQueueEntries)..where((t) => t.id.equals(entree.id)))
        .write(
      SyncQueueEntriesCompanion(
        statut: Value(entree.statut.code),
        tentatives: Value(entree.tentatives),
      ),
    );
  }

  static SyncEntree _versEntree(SyncQueueEntry ligne) => SyncEntree(
        id: ligne.id,
        entite: ligne.entite,
        operation: ligne.operation,
        payload: ligne.payload,
        tentatives: ligne.tentatives,
        statut: SyncStatutCode.depuisCode(ligne.statut) ?? SyncStatut.enAttente,
      );
}
