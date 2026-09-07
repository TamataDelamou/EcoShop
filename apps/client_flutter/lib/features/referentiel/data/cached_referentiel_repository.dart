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
  Future<List<SystemeEducatif>> systemesEducatifs() async {
    try {
      final liste = await _distant.systemesEducatifs();
      await _cache.ecrireListe(
        ReferentielCacheStore.typeSystemes,
        liste.map((s) => s.versJson()).toList(growable: false),
      );
      return liste;
    } on ErreurReferentiel {
      final lignes = await _cache.lireListe(ReferentielCacheStore.typeSystemes);
      if (lignes == null) rethrow;
      return lignes.map(SystemeEducatif.depuisJson).toList(growable: false);
    }
  }

  @override
  Future<List<PaysPedagogique>> paysPedagogiques() async {
    try {
      final liste = await _distant.paysPedagogiques();
      await _cache.ecrireListe(
        ReferentielCacheStore.typePays,
        liste.map((p) => p.versJson()).toList(growable: false),
      );
      return liste;
    } on ErreurReferentiel {
      final lignes = await _cache.lireListe(ReferentielCacheStore.typePays);
      if (lignes == null) rethrow;
      return lignes.map(PaysPedagogique.depuisJson).toList(growable: false);
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
