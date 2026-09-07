import '../../../core/db/cache_document_store.dart';
import '../domain/affectation_enseignant.dart';
import '../domain/enums_scolarite.dart';
import '../domain/fiche_eleve.dart';
import '../domain/inscription.dart';
import '../domain/relation_parent_eleve.dart';
import '../domain/scolarite_repository.dart';
import '../domain/structure_etablissement.dart';

/// Décore un [ScolariteRepository] réseau avec un repli SQLite/Drift.
///
/// Même politique que `CachedReferentielRepository` (M4) : réseau d'abord,
/// écriture systématique du cache en cas de succès, lecture du cache en cas
/// d'échec réseau. Seule [lierEnfant] (écriture) ne connaît pas de repli —
/// elle exige le réseau par nature.
class CachedScolariteRepository implements ScolariteRepository {
  const CachedScolariteRepository(this._distant, this._cache);

  final ScolariteRepository _distant;
  final CacheDocumentStore _cache;

  static const _typeStructure = 'structure';
  static const _typeInscriptionsClasse = 'inscriptions_classe';
  static const _typeInscriptionsFiche = 'inscriptions_fiche';
  static const _typeAffectationsClasse = 'affectations_classe';
  static const _typeMesAffectations = 'mes_affectations';
  static const _typeMesEnfants = 'mes_enfants';
  static const _typeFiche = 'fiche';
  static const _typeMaFiche = 'ma_fiche';

  @override
  Future<StructureEtablissement> structureEtablissement(
    String etablissementId, {
    String? anneeScolaireId,
  }) async {
    final cle = '$etablissementId::${anneeScolaireId ?? 'courante'}';
    try {
      final structure = await _distant.structureEtablissement(
        etablissementId,
        anneeScolaireId: anneeScolaireId,
      );
      await _cache.ecrireDocument(_typeStructure, cle, structure.versJson());
      return structure;
    } on ErreurScolarite {
      final document = await _cache.lireDocument(_typeStructure, cle);
      if (document == null) rethrow;
      return StructureEtablissement.depuisJson(document);
    }
  }

  @override
  Future<List<Inscription>> inscriptionsDeClasse(String classeId) {
    return _listeAvecCache(
      type: _typeInscriptionsClasse,
      cle: classeId,
      lire: () => _distant.inscriptionsDeClasse(classeId),
      versJson: (i) => i.versJsonCache(),
      depuisJson: Inscription.depuisJson,
    );
  }

  @override
  Future<List<Inscription>> inscriptionsDeFiche(String ficheEleveId) {
    return _listeAvecCache(
      type: _typeInscriptionsFiche,
      cle: ficheEleveId,
      lire: () => _distant.inscriptionsDeFiche(ficheEleveId),
      versJson: (i) => i.versJsonCache(),
      depuisJson: Inscription.depuisJson,
    );
  }

  @override
  Future<List<AffectationEnseignant>> affectationsDeClasse(String classeId) {
    return _listeAvecCache(
      type: _typeAffectationsClasse,
      cle: classeId,
      lire: () => _distant.affectationsDeClasse(classeId),
      versJson: (a) => a.versJsonCache(),
      depuisJson: AffectationEnseignant.depuisJsonCache,
    );
  }

  @override
  Future<List<AffectationEnseignant>> mesAffectations() {
    return _listeAvecCache(
      type: _typeMesAffectations,
      cle: CacheDocumentStore.cleUnique,
      lire: _distant.mesAffectations,
      versJson: (a) => a.versJsonCache(),
      depuisJson: AffectationEnseignant.depuisJsonCache,
    );
  }

  @override
  Future<List<RelationParentEleve>> mesEnfants() {
    return _listeAvecCache(
      type: _typeMesEnfants,
      cle: CacheDocumentStore.cleUnique,
      lire: _distant.mesEnfants,
      versJson: (r) => r.versJsonCache(),
      depuisJson: RelationParentEleve.depuisJson,
    );
  }

  @override
  Future<FicheEleve?> ficheEleve(String ficheId) async {
    try {
      final fiche = await _distant.ficheEleve(ficheId);
      if (fiche != null) {
        await _cache.ecrireDocument(_typeFiche, ficheId, fiche.versJson());
      }
      return fiche;
    } on ErreurScolarite {
      final document = await _cache.lireDocument(_typeFiche, ficheId);
      if (document == null) rethrow;
      return FicheEleve.depuisJson(document);
    }
  }

  @override
  Future<FicheEleve?> maFiche() async {
    try {
      final fiche = await _distant.maFiche();
      if (fiche != null) {
        await _cache.ecrireDocument(_typeMaFiche, CacheDocumentStore.cleUnique, fiche.versJson());
      }
      return fiche;
    } on ErreurScolarite {
      final document =
          await _cache.lireDocument(_typeMaFiche, CacheDocumentStore.cleUnique);
      if (document == null) rethrow;
      return FicheEleve.depuisJson(document);
    }
  }

  @override
  Future<String> lierEnfant({
    required String matricule,
    required DateTime dateNaissance,
    TypeRelationParentale type = TypeRelationParentale.parent,
  }) {
    return _distant.lierEnfant(
      matricule: matricule,
      dateNaissance: dateNaissance,
      type: type,
    );
  }

  Future<List<T>> _listeAvecCache<T>({
    required String type,
    required String cle,
    required Future<List<T>> Function() lire,
    required Map<String, dynamic> Function(T) versJson,
    required T Function(Map<String, dynamic>) depuisJson,
  }) async {
    try {
      final liste = await lire();
      await _cache.ecrireDocument(type, cle, {
        'lignes': liste.map(versJson).toList(growable: false),
      });
      return liste;
    } on ErreurScolarite {
      final document = await _cache.lireDocument(type, cle);
      if (document == null) rethrow;
      return (document['lignes'] as List<dynamic>)
          .map((l) => depuisJson(l as Map<String, dynamic>))
          .toList(growable: false);
    }
  }
}
