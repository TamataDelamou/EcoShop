import '../domain/arborescence_niveau.dart';
import '../domain/arborescence_pays.dart';
import '../domain/paquet_referentiel.dart';
import '../domain/pays_pedagogique.dart';
import '../domain/referentiel_repository.dart';
import '../domain/systeme_educatif.dart';
import 'referentiel_cache_store.dart';

/// Décore un [ReferentielRepository] réseau avec un repli SQLite/Drift.
///
/// Politique « réseau d'abord, cache en secours » (contrat M04 §5) : chaque
/// lecture réussie réécrit le cache (write-through) ; en cas d'échec réseau,
/// on sert la dernière copie locale connue plutôt que de propager l'erreur —
/// le référentiel est un contenu quasi statique, une donnée légèrement
/// obsolète hors-ligne vaut mieux qu'un écran vide.
class CachedReferentielRepository implements ReferentielRepository {
  const CachedReferentielRepository(this._distant, this._cache);

  final ReferentielRepository _distant;
  final ReferentielCacheStore _cache;

  @override
  Future<List<SystemeEducatif>> systemesEducatifs() {
    return _liste(
      ReferentielCacheStore.typeSystemes,
      _distant.systemesEducatifs,
      (s) => s.versJson(),
      SystemeEducatif.depuisJson,
    );
  }

  @override
  Future<List<PaysPedagogique>> paysPedagogiques() {
    return _liste(
      ReferentielCacheStore.typePays,
      _distant.paysPedagogiques,
      (p) => p.versJson(),
      PaysPedagogique.depuisJson,
    );
  }

  /// Liste « réseau d'abord » : une réponse vide du serveur n'efface jamais
  /// une copie locale non vide (le référentiel ne se vide pas légitimement ;
  /// un serveur vide est un défaut de déploiement, pas une donnée à garder).
  Future<List<T>> _liste<T>(
    String type,
    Future<List<T>> Function() lire,
    Map<String, dynamic> Function(T) versJson,
    T Function(Map<String, dynamic>) depuisJson,
  ) async {
    try {
      final liste = await lire();
      if (liste.isEmpty) {
        final lignes = await _cache.lireListe(type);
        if (lignes != null && lignes.isNotEmpty) {
          return lignes.map(depuisJson).toList(growable: false);
        }
        return liste;
      }
      await _cache.ecrireListe(type, liste.map(versJson).toList(growable: false));
      return liste;
    } on ErreurReferentiel {
      final lignes = await _cache.lireListe(type);
      if (lignes == null) rethrow;
      return lignes.map(depuisJson).toList(growable: false);
    }
  }

  @override
  Future<ArborescencePays> arborescencePays(String paysCode) async {
    try {
      final arbo = await _distant.arborescencePays(paysCode);
      await _cache.ecrireDocument(
        ReferentielCacheStore.typePaysDetail,
        paysCode,
        arbo.versJson(),
      );
      return arbo;
    } on ErreurReferentiel {
      final document = await _cache.lireDocument(
        ReferentielCacheStore.typePaysDetail,
        paysCode,
      );
      if (document == null) rethrow;
      return ArborescencePays.depuisJson(document);
    }
  }

  @override
  Future<ArborescenceNiveau> arborescenceNiveau(String niveauId) async {
    try {
      final arbo = await _distant.arborescenceNiveau(niveauId);
      await _cache.ecrireDocument(
        ReferentielCacheStore.typeNiveauDetail,
        niveauId,
        arbo.versJson(),
      );
      return arbo;
    } on ErreurReferentiel {
      final document = await _cache.lireDocument(
        ReferentielCacheStore.typeNiveauDetail,
        niveauId,
      );
      if (document == null) rethrow;
      return ArborescenceNiveau.depuisJson(document);
    }
  }

  @override
  Future<List<PaquetReferentiel>> paquetsDisponibles({
    required String paysCode,
    String? niveauId,
  }) {
    // Le téléchargement d'un paquet exige déjà le réseau : inutile de servir
    // une liste de paquets en cache que l'on ne pourrait pas récupérer.
    return _distant.paquetsDisponibles(paysCode: paysCode, niveauId: niveauId);
  }
}
