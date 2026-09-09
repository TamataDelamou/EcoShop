import '../../../../core/db/cache_document_store.dart';
import '../domain/entree_communication_locale.dart';

/// Persistance du **prototype local** de messagerie/annonces/cahier de
/// liaison (M9) — délibérément local uniquement (`CacheDocumentStore`,
/// domaine `communication_locale`), sans aucun appel réseau : voir
/// [EntreeCommunicationLocale] pour le contexte (aucune table serveur
/// n'existe pour ces entités). N'implémente aucune interface `*Repository`
/// réseau/cache du reste du projet — ce n'est pas un module métier au même
/// titre que les autres, mais une maquette fonctionnelle.
class CommunicationLocaleRepository {
  const CommunicationLocaleRepository(this._cache);

  final CacheDocumentStore _cache;

  Future<List<EntreeCommunicationLocale>> lister(TypeEntreeLocale type) async {
    final lignes = await _cache.lireListe(type.code);
    if (lignes == null) return const [];
    final entrees = lignes.map(EntreeCommunicationLocale.depuisJson).toList();
    entrees.sort((a, b) => b.dateCreation.compareTo(a.dateCreation));
    return entrees;
  }

  Future<void> ajouter(EntreeCommunicationLocale entree) async {
    final existantes = await lister(entree.type);
    await _cache.ecrireListe(entree.type.code, [
      entree.versJson(),
      ...existantes.map((e) => e.versJson()),
    ]);
  }

  Future<void> marquerLu(TypeEntreeLocale type, String id) => _mettreAJour(type, id, (e) => e.copierAvec(lu: true));

  Future<void> marquerAccuseReception(TypeEntreeLocale type, String id) =>
      _mettreAJour(type, id, (e) => e.copierAvec(accuseReception: true));

  /// Purge tout le domaine (`communication_locale`) — patch de sécurité M9,
  /// appelé à la déconnexion (voir `session_logout.dart`).
  Future<void> purgerTout() => _cache.purgerTout();

  Future<void> _mettreAJour(
    TypeEntreeLocale type,
    String id,
    EntreeCommunicationLocale Function(EntreeCommunicationLocale) transformer,
  ) async {
    final entrees = await lister(type);
    final maj = entrees.map((e) => e.id == id ? transformer(e) : e).toList(growable: false);
    await _cache.ecrireListe(type.code, maj.map((e) => e.versJson()).toList(growable: false));
  }
}
