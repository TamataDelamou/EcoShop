import '../db/cache_document_store.dart';
import 'drift_sync_repository.dart';
import 'sync_engine.dart';

/// Une opération faite hors connexion que le serveur a refusée au retour du
/// réseau (période clôturée entre-temps, droits retirés…).
class RejetSynchronisation {
  const RejetSynchronisation({
    required this.id,
    required this.libelle,
    required this.code,
    required this.message,
    required this.le,
  });

  final String id;

  /// Ce qui avait été saisi (« Don de 250 000 du 11/10 »…).
  final String libelle;
  final String code;
  final String message;
  final DateTime le;
}

/// Journal des refus : gardé sur l'appareil jusqu'à ce que l'utilisateur
/// l'ait vu et retiré.
class JournalRejets {
  const JournalRejets(this._store, this._file);

  final CacheDocumentStore _store;
  final DriftSyncRepository _file;

  static const _type = 'rejet';

  Future<void> enregistrer(SyncEntree entree, RejetDefinitif rejet, String libelle) {
    return _store.ecrireDocument(_type, entree.id, {
      'libelle': libelle,
      'code': rejet.code,
      'message': rejet.message,
    });
  }

  Future<List<RejetSynchronisation>> lister() async {
    final documents = await _store.lireType(_type);
    return [
      for (final d in documents)
        RejetSynchronisation(
          id: d.cle,
          libelle: d.document['libelle'] as String? ?? 'Opération',
          code: d.document['code'] as String? ?? '',
          message: d.document['message'] as String? ?? '',
          le: d.misAJourLe,
        ),
    ];
  }

  /// L'utilisateur a pris connaissance du refus : on l'oublie.
  Future<void> retirer(String id) async {
    await _store.supprimerDocument(_type, id);
    await _file.retirer(id);
  }
}
