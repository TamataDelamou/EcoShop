import '../../../core/db/cache_document_store.dart';

/// Persistance locale du réglage « Contraste élevé » (D4, §34.9). Même
/// mécanisme que `ThemePreferenceStore` (Drift partagé, domaine
/// `preferences`) — pas de dépendance `shared_preferences` pour un seul champ.
class ContrasteEleveStore {
  ContrasteEleveStore(this._store);

  final CacheDocumentStore _store;

  static const _type = 'accessibilite';
  static const _cle = 'contraste_eleve';

  Future<bool> lire() async {
    final document = await _store.lireDocument(_type, _cle);
    return document?['actif'] as bool? ?? false;
  }

  Future<void> ecrire(bool actif) {
    return _store.ecrireDocument(_type, _cle, {'actif': actif});
  }
}
