import 'dart:convert';

import 'package:drift/drift.dart';

import 'app_database.dart';

/// Accès Drift au cache générique partagé (table [CacheEntries]).
///
/// Chaque module (M5 et suivants) instancie un store avec son propre
/// [domaine] (ex. `'scolarite'`) : les lignes ne se mélangent jamais entre
/// modules, mais le schéma SQL et le code d'accès sont partagés plutôt que
/// dupliqués module après module (voir [CacheEntries] pour le contexte).
class CacheDocumentStore {
  const CacheDocumentStore(this._db, this.domaine);

  final AppDatabase _db;
  final String domaine;

  static const cleUnique = 'global';

  Future<void> ecrireListe(String type, List<Map<String, dynamic>> lignes) {
    return ecrireDocument(type, cleUnique, {'lignes': lignes});
  }

  Future<List<Map<String, dynamic>>?> lireListe(String type) async {
    final document = await lireDocument(type, cleUnique);
    if (document == null) return null;
    return (document['lignes'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<void> ecrireDocument(
    String type,
    String cle,
    Map<String, dynamic> document,
  ) {
    return _db.into(_db.cacheEntries).insertOnConflictUpdate(
          CacheEntriesCompanion.insert(
            domaine: domaine,
            type: type,
            cle: cle,
            payload: jsonEncode(document),
            misAJourLe: Value(DateTime.now()),
          ),
        );
  }

  Future<Map<String, dynamic>?> lireDocument(String type, String cle) async {
    final ligne = await (_db.select(_db.cacheEntries)
          ..where((t) =>
              t.domaine.equals(domaine) & t.type.equals(type) & t.cle.equals(cle)))
        .getSingleOrNull();
    if (ligne == null) return null;
    return jsonDecode(ligne.payload) as Map<String, dynamic>;
  }

  /// Supprime toutes les lignes de ce domaine — patch de sécurité M9 : un
  /// domaine dont le contenu n'est pas isolé par profil (clé unique
  /// `'global'`, cf. `CommunicationLocaleRepository`) doit être purgé à la
  /// déconnexion pour ne pas fuiter vers le prochain compte connecté sur le
  /// même appareil.
  Future<void> purgerTout() {
    return (_db.delete(_db.cacheEntries)..where((t) => t.domaine.equals(domaine))).go();
  }
}
