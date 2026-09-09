import '../../../core/db/cache_document_store.dart';
import '../domain/affectation_enseignant.dart';
import '../domain/encaissement_scolarite.dart';
import '../domain/enums_scolarite.dart';
import '../domain/fiche_eleve.dart';
import '../domain/frais_scolarite_config.dart';
import '../domain/inscription.dart';
import '../domain/palier_paiement_config.dart';
import '../domain/relation_parent_eleve.dart';
import '../domain/scolarite_repository.dart';
import '../domain/solde_scolarite.dart';
import '../domain/structure_etablissement.dart';
import '../domain/verifications_reinscription.dart';

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

  // --- M15quater : écritures — réseau exigé, aucun repli offline ----------
  //
  // Un matricule généré serveur, une détection de doublon ou un solde ne
  // peuvent pas être approximés localement (même principe que [lierEnfant]).

  @override
  Future<String> creerInscriptionNouvelEleve({
    required String etablissementId,
    required String nom,
    required String prenom,
    required DateTime dateNaissance,
    required String classeId,
    required String anneeScolaireId,
    String? sexe,
  }) {
    return _distant.creerInscriptionNouvelEleve(
      etablissementId: etablissementId,
      nom: nom,
      prenom: prenom,
      dateNaissance: dateNaissance,
      classeId: classeId,
      anneeScolaireId: anneeScolaireId,
      sexe: sexe,
    );
  }

  @override
  Future<bool> verifierDoublonEleve({
    required String nom,
    required String prenom,
    required DateTime dateNaissance,
  }) {
    return _distant.verifierDoublonEleve(nom: nom, prenom: prenom, dateNaissance: dateNaissance);
  }

  @override
  Future<VerificationsReinscription> verificationsReinscription({
    required String ficheEleveId,
    required String anneePrecedenteId,
  }) {
    return _distant.verificationsReinscription(
      ficheEleveId: ficheEleveId,
      anneePrecedenteId: anneePrecedenteId,
    );
  }

  @override
  Future<String> creerReinscription({
    required String ficheEleveId,
    required String classeId,
    required String anneeScolaireId,
  }) {
    return _distant.creerReinscription(
      ficheEleveId: ficheEleveId,
      classeId: classeId,
      anneeScolaireId: anneeScolaireId,
    );
  }

  @override
  Future<void> definirStatutBoursier({required String inscriptionId, required bool boursier}) {
    return _distant.definirStatutBoursier(inscriptionId: inscriptionId, boursier: boursier);
  }

  @override
  Future<void> mettreAJourFicheAdmin(FicheEleve fiche) => _distant.mettreAJourFicheAdmin(fiche);

  @override
  Future<void> enregistrerFraisScolariteConfig(FraisScolariteConfig config) =>
      _distant.enregistrerFraisScolariteConfig(config);

  @override
  Future<void> enregistrerPalierPaiement(PalierPaiementConfig palier) =>
      _distant.enregistrerPalierPaiement(palier);

  @override
  Future<EncaissementScolarite> enregistrerEncaissement(EncaissementScolarite encaissement) =>
      _distant.enregistrerEncaissement(encaissement);

  @override
  Future<void> annulerEncaissement({required String encaissementId, required String motif}) =>
      _distant.annulerEncaissement(encaissementId: encaissementId, motif: motif);

  // --- M15quater : lectures avec repli cache -------------------------------

  static const _typeFicheParMatricule = 'fiche_par_matricule';
  static const _typeFraisConfig = 'frais_config';
  static const _typePaliersConfig = 'paliers_config';
  static const _typeSolde = 'solde_scolarite';
  static const _typeEncaissements = 'encaissements_inscription';
  static const _typeEncaissementsRecents = 'encaissements_recents';

  @override
  Future<FicheEleve?> ficheParMatricule({
    required String etablissementId,
    required String matricule,
  }) async {
    final cle = '$etablissementId::$matricule';
    try {
      final fiche = await _distant.ficheParMatricule(etablissementId: etablissementId, matricule: matricule);
      if (fiche != null) {
        await _cache.ecrireDocument(_typeFicheParMatricule, cle, fiche.versJson());
      }
      return fiche;
    } on ErreurScolarite {
      final document = await _cache.lireDocument(_typeFicheParMatricule, cle);
      if (document == null) rethrow;
      return FicheEleve.depuisJson(document);
    }
  }

  @override
  Future<List<FraisScolariteConfig>> fraisScolariteConfig({
    required String etablissementId,
    required String anneeScolaireId,
  }) {
    return _listeAvecCache(
      type: _typeFraisConfig,
      cle: '$etablissementId::$anneeScolaireId',
      lire: () => _distant.fraisScolariteConfig(
        etablissementId: etablissementId,
        anneeScolaireId: anneeScolaireId,
      ),
      versJson: (f) => f.versJsonEcriture()..['id'] = f.id,
      depuisJson: FraisScolariteConfig.depuisJson,
    );
  }

  @override
  Future<List<PalierPaiementConfig>> paliersPaiementConfig({
    required String etablissementId,
    required String anneeScolaireId,
  }) {
    return _listeAvecCache(
      type: _typePaliersConfig,
      cle: '$etablissementId::$anneeScolaireId',
      lire: () => _distant.paliersPaiementConfig(
        etablissementId: etablissementId,
        anneeScolaireId: anneeScolaireId,
      ),
      versJson: (p) => p.versJsonEcriture()..['id'] = p.id,
      depuisJson: PalierPaiementConfig.depuisJson,
    );
  }

  @override
  Future<SoldeScolarite> soldeScolarite(String inscriptionId) async {
    try {
      final solde = await _distant.soldeScolarite(inscriptionId);
      await _cache.ecrireDocument(_typeSolde, inscriptionId, {
        'montant_du': solde.montantDu,
        'montant_paye': solde.montantPaye,
        'solde': solde.solde,
      });
      return solde;
    } on ErreurScolarite {
      final document = await _cache.lireDocument(_typeSolde, inscriptionId);
      if (document == null) rethrow;
      return SoldeScolarite.depuisJson(document);
    }
  }

  @override
  Future<List<EncaissementScolarite>> encaissementsDeInscription(String inscriptionId) {
    return _listeAvecCache(
      type: _typeEncaissements,
      cle: inscriptionId,
      lire: () => _distant.encaissementsDeInscription(inscriptionId),
      versJson: (e) => e.versJsonCache(),
      depuisJson: EncaissementScolarite.depuisJson,
    );
  }

  @override
  Future<List<EncaissementScolarite>> encaissementsRecents(String etablissementId, {int limite = 100}) {
    return _listeAvecCache(
      type: _typeEncaissementsRecents,
      cle: etablissementId,
      lire: () => _distant.encaissementsRecents(etablissementId, limite: limite),
      versJson: (e) => e.versJsonCache(),
      depuisJson: EncaissementScolarite.depuisJson,
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
