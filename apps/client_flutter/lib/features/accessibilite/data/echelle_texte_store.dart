import '../../../core/db/cache_document_store.dart';
import '../domain/echelle_texte.dart';

/// Persistance locale du réglage « Taille du texte » (D4, §34.9). Même
/// mécanisme que `ThemePreferenceStore` (Drift partagé, domaine
/// `preferences`) — pas de dépendance `shared_preferences` pour un seul champ.
class EchelleTexteStore {
  EchelleTexteStore(this._store);

  final CacheDocumentStore _store;

  static const _type = 'accessibilite';
  static const _cle = 'echelle_texte';

  Future<EchelleTexte> lire() async {
    final document = await _store.lireDocument(_type, _cle);
    return EchelleTexte.depuisCode(document?['code'] as String?);
  }

  Future<void> ecrire(EchelleTexte echelle) {
    return _store.ecrireDocument(_type, _cle, {'code': echelle.name});
  }
}
