import '../../../core/db/cache_document_store.dart';

/// Persistance locale de la préférence de langue (D3).
///
/// Choix stocké dès maintenant, même si l'app ne traduit encore rien : la
/// construction de l'infrastructure `intl`/ARB et la traduction des écrans
/// existants sont un chantier distinct, non commencé ici (voir
/// `ANALYSE_GLOBALE.md` §4.5, D3). Même mécanisme que
/// `ThemePreferenceStore` (Drift partagé, domaine `preferences`) — pas de
/// dépendance `shared_preferences` pour un seul champ.
class LanguePreferenceStore {
  LanguePreferenceStore(this._store);

  final CacheDocumentStore _store;

  static const _type = 'regionalisation';
  static const _cle = 'langue';
  static const defautCode = 'fr';

  Future<String> lire() async {
    final document = await _store.lireDocument(_type, _cle);
    return document?['code'] as String? ?? defautCode;
  }

  Future<void> ecrire(String code) {
    return _store.ecrireDocument(_type, _cle, {'code': code});
  }
}
