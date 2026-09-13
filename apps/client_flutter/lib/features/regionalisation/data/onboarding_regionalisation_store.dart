import '../../../core/db/cache_document_store.dart';

/// Persistance locale du passage (ou non) de l'étape d'onboarding
/// Langue/Région (D3), **par profil** (clé = `profileId`, pas la clé
/// unique `global`) : un second compte se connectant sur le même appareil
/// doit revoir sa propre région dérivée de son propre établissement, pas
/// hériter du « déjà vu » d'un compte précédent.
class OnboardingRegionalisationStore {
  OnboardingRegionalisationStore(this._store);

  final CacheDocumentStore _store;

  static const _type = 'regionalisation_onboarding';

  Future<bool> lireVu(String profileId) async {
    final document = await _store.lireDocument(_type, profileId);
    return document?['vu'] as bool? ?? false;
  }

  Future<void> ecrireVu(String profileId) {
    return _store.ecrireDocument(_type, profileId, {'vu': true});
  }
}
