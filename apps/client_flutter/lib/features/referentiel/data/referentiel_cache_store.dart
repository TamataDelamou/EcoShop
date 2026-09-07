import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';

/// Accès Drift au cache générique du référentiel pédagogique.
///
/// Chaque sous-arbre (liste des pays, arborescence d'un pays, arborescence
/// d'un niveau) est sérialisé en un unique document JSON par ligne : c'est le
/// même parti pris que `SyncQueueEntries.payload`, qui évite de dupliquer le
/// schéma SQL des tables serveur côté client pour de la simple consultation.
class ReferentielCacheStore {
  const ReferentielCacheStore(this._db);

  final AppDatabase _db;

  static const typeSystemes = 'systemes';
  static const typePays = 'pays';
  static const typePaysDetail = 'pays_detail';
  static const typeNiveauDetail = 'niveau_detail';

  static const _cleUnique = 'global';

  Future<void> ecrireListe(String type, List<Map<String, dynamic>> lignes) {
    return _ecrire(type, _cleUnique, {'lignes': lignes});
  }

  Future<List<Map<String, dynamic>>?> lireListe(String type) async {
    final document = await _lire(type, _cleUnique);
    if (document == null) return null;
    return (document['lignes'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<void> ecrireDocument(
    String type,
    String cle,
    Map<String, dynamic> document,
  ) {
    return _ecrire(type, cle, document);
  }

  Future<Map<String, dynamic>?> lireDocument(String type, String cle) {
    return _lire(type, cle);
  }

  Future<void> _ecrire(String type, String cle, Map<String, dynamic> document) {
    return _db
        .into(_db.referentielCacheEntries)
        .insertOnConflictUpdate(
          ReferentielCacheEntriesCompanion.insert(
            type: type,
            cle: cle,
            payload: jsonEncode(document),
            misAJourLe: Value(DateTime.now()),
          ),
        );
  }

  Future<Map<String, dynamic>?> _lire(String type, String cle) async {
    final ligne = await (_db.select(_db.referentielCacheEntries)
          ..where((t) => t.type.equals(type) & t.cle.equals(cle)))
        .getSingleOrNull();
    if (ligne == null) return null;
    return jsonDecode(ligne.payload) as Map<String, dynamic>;
  }
}
