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
  ) async {
    final clair = jsonEncode(document);
    final scelleur = _db.scelleur;
    final payload = scelleur == null ? clair : await scelleur.sceller(domaine, clair);
    if (payload == null) return; // chiffrement impossible : pas de copie
    await _db.into(_db.cacheEntries).insertOnConflictUpdate(
          CacheEntriesCompanion.insert(
            domaine: domaine,
            type: type,
            cle: cle,
            payload: payload,
            misAJourLe: Value(DateTime.now()),
          ),
        );
  }

  /// Contenu lisible d'une ligne pour le compte connecté (null : copie d'un
  /// autre compte, ou illisible — traitée comme absente).
  Future<Map<String, dynamic>?> _ouvrir(String payload) async {
    final scelleur = _db.scelleur;
    final clair = scelleur == null ? payload : await scelleur.ouvrir(domaine, payload);
    if (clair == null) return null;
    try {
      return jsonDecode(clair) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> lireDocument(String type, String cle) async {
    final lu = await lireDocumentDate(type, cle);
    return lu?.document;
  }

  /// Document et date de sa dernière écriture — pour dire à l'utilisateur
  /// de quand datent les données affichées hors connexion.
  Future<({Map<String, dynamic> document, DateTime misAJourLe})?> lireDocumentDate(String type, String cle) async {
    final ligne = await (_db.select(_db.cacheEntries)
          ..where((t) =>
              t.domaine.equals(domaine) & t.type.equals(type) & t.cle.equals(cle)))
        .getSingleOrNull();
    if (ligne == null) return null;
    final document = await _ouvrir(ligne.payload);
    if (document == null) return null;
    return (document: document, misAJourLe: ligne.misAJourLe);
  }

  Future<void> supprimerDocument(String type, String cle) {
    return (_db.delete(_db.cacheEntries)
          ..where((t) => t.domaine.equals(domaine) & t.type.equals(type) & t.cle.equals(cle)))
        .go();
  }

  /// Tous les documents d'un type (ex. les refus de synchronisation).
  Future<List<({String cle, Map<String, dynamic> document, DateTime misAJourLe})>> lireType(String type) async {
    final lignes = await (_db.select(_db.cacheEntries)
          ..where((t) => t.domaine.equals(domaine) & t.type.equals(type))
          ..orderBy([(t) => OrderingTerm.desc(t.misAJourLe)]))
        .get();
    final resultat = <({String cle, Map<String, dynamic> document, DateTime misAJourLe})>[];
    for (final l in lignes) {
      final document = await _ouvrir(l.payload);
      if (document != null) resultat.add((cle: l.cle, document: document, misAJourLe: l.misAJourLe));
    }
    return resultat;
  }

  /// Supprime toutes les lignes de ce domaine — patch de sécurité M9 : un
  /// domaine dont le contenu n'est pas isolé par profil (clé unique
  /// `'global'`, cf. `CommunicationLocaleRepository`) doit être purgé à la
  /// déconnexion pour ne pas fuiter vers le prochain compte connecté sur le
  /// même appareil.
  Future<void> purgerTout() {
    return (_db.delete(_db.cacheEntries)..where((t) => t.domaine.equals(domaine))).go();
  }

  /// Efface, tous domaines confondus, les copies lisibles par le compte
  /// connecté (« appareil partagé » à la déconnexion). Les copies des autres
  /// comptes ne sont pas touchées. Renvoie le nombre de copies effacées.
  static Future<int> effacerCopiesDuCompte(AppDatabase db) async {
    final scelleur = db.scelleur;
    if (scelleur == null) return 0;
    final lignes = await db.select(db.cacheEntries).get();
    var effacees = 0;
    for (final l in lignes) {
      if (!l.payload.startsWith('chiffre:')) continue;
      if (await scelleur.ouvrir(l.domaine, l.payload) == null) continue;
      effacees += await (db.delete(db.cacheEntries)
            ..where((t) => t.domaine.equals(l.domaine) & t.type.equals(l.type) & t.cle.equals(l.cle)))
          .go();
    }
    return effacees;
  }
}
