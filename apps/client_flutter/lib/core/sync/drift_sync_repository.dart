import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../securite/chiffrement_file.dart';
import 'sync_engine.dart';

/// Implémentation Drift du port [SyncRepository] — file `sync_queue` (ch. 34-35).
///
/// Jusqu'à M6, [SyncEngine] n'avait aucune implémentation concrète : le
/// module Notes est le premier à écrire hors connexion (saisie de notes par
/// l'enseignant), d'où l'introduction de ce repository partagé par tous les
/// modules d'écriture à venir (M7 absences, M8 RH…).
///
/// Chiffrement par compte (REG-18) : avec un [chiffreur] et un [compte],
/// chaque opération est chiffrée à l'entrée dans la file avec la clé du
/// compte. La file ne rend que les opérations que ce compte peut lire : celles
/// d'un autre compte (tablette partagée, déconnexion avec des envois en
/// attente) restent sur le téléphone, intactes, et partent quand ce compte se
/// reconnecte. Jamais rejouées au nom d'un autre compte.
class DriftSyncRepository implements SyncRepository {
  const DriftSyncRepository(this._db, {this.chiffreur, this.compte});

  final AppDatabase _db;
  final ChiffreurFile? chiffreur;

  /// Compte connecté, ou null sans session.
  final String? compte;

  /// Enfile une opération à rejouer. Un même [SyncEntree.id] réenfilé (ex. la
  /// même note modifiée deux fois hors connexion avant reconnexion) remplace
  /// la précédente et repart avec un budget de tentatives neuf, plutôt que de
  /// rester bloqué sur un ancien statut `echec`.
  Future<void> enfiler(SyncEntree entree) async {
    final payload = await _chiffrer(entree.payload);
    await _db.into(_db.syncQueueEntries).insertOnConflictUpdate(
          SyncQueueEntriesCompanion.insert(
            id: entree.id,
            entite: entree.entite,
            operation: entree.operation,
            payload: payload,
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
    return _lisibles(lignes);
  }

  /// Entrées refusées par le serveur, les plus récentes d'abord.
  Future<List<SyncEntree>> entreesRejetees() async {
    final lignes = await (_db.select(_db.syncQueueEntries)
          ..where((t) => t.statut.equals(SyncStatut.rejete.code))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return _lisibles(lignes);
  }

  /// Suivi en direct pour l'interface : opérations en attente d'envoi et
  /// opérations refusées.
  /// Seules comptent celles du compte connecté.
  Stream<({int enAttente, int rejetees})> suivre() {
    return _db.select(_db.syncQueueEntries).watch().asyncMap((toutes) async {
      final lignes = await _lisibles(toutes);
      return (
        enAttente: lignes
            .where((l) => l.statut != SyncStatut.termine && l.statut != SyncStatut.rejete)
            .length,
        rejetees: lignes.where((l) => l.statut == SyncStatut.rejete).length,
      );
    });
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

  /// Chiffre pour le compte connecté. Sans clé disponible (Keystore en
  /// panne), l'opération est gardée en clair plutôt que perdue.
  Future<String> _chiffrer(String payload) async {
    final c = chiffreur;
    final k = compte;
    if (c == null || k == null) return payload;
    try {
      return await c.chiffrer(k, payload);
    } catch (e) {
      debugPrint('File d’envoi : chiffrement impossible, opération gardée en clair ($e)');
      return payload;
    }
  }

  /// Entrées lisibles par le compte connecté, déchiffrées. Les entrées en
  /// clair (enfilées avant REG-18, ou sans clé) restent lisibles.
  Future<List<SyncEntree>> _lisibles(List<SyncQueueEntry> lignes) async {
    final resultat = <SyncEntree>[];
    for (final ligne in lignes) {
      if (!ChiffreurFile.estChiffre(ligne.payload)) {
        resultat.add(_versEntree(ligne, ligne.payload));
        continue;
      }
      final c = chiffreur;
      final k = compte;
      if (c == null || k == null) continue;
      final clair = await c.dechiffrer(k, ligne.payload);
      if (clair != null) resultat.add(_versEntree(ligne, clair));
    }
    return resultat;
  }

  static SyncEntree _versEntree(SyncQueueEntry ligne, String payload) => SyncEntree(
        id: ligne.id,
        entite: ligne.entite,
        operation: ligne.operation,
        payload: payload,
        tentatives: ligne.tentatives,
        statut: SyncStatutCode.depuisCode(ligne.statut) ?? SyncStatut.enAttente,
      );
}
