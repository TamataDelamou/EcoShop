import 'dart:convert';
import '../../../core/securite/gardien_actions_sensibles.dart';

import 'package:uuid/uuid.dart';

import '../../../core/db/cache_document_store.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/affectation_enseignant.dart';
import '../domain/encaissement_scolarite.dart';
import '../domain/enums_financier_scolaire.dart';
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
///
/// Encaissements au guichet d'abord hors connexion : sans réseau,
/// l'encaissement est gardé sur l'appareil sous une clé générée ici, avec un
/// reçu PROVISOIRE (`PROV-<appareil>-0001`), et envoyé au retour du réseau
/// (le serveur reconnaît la clé, attribue le numéro définitif continu et
/// garde le provisoire) ; il apparaît aussitôt dans l'historique et dans le
/// solde. Une annulation sans réseau part elle aussi en file.
class CachedScolariteRepository implements ScolariteRepository {
  const CachedScolariteRepository(this._distant, this._cache, [this._file, this._identifiantAppareil]);

  final ScolariteRepository _distant;
  final CacheDocumentStore _cache;
  final DriftSyncRepository? _file;
  final Future<String> Function()? _identifiantAppareil;

  static const entiteEncaissement = 'encaissements_scolarite';
  static const entiteAnnulationEncaissement = 'encaissements_scolarite_annulation';

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

  /// Exige la connectivité, comme les autres actions ponctuelles d'export/
  /// administration (ex. `creerEvaluation`) : pas de repli hors ligne pour
  /// une donnée consultée uniquement au moment de générer un bulletin.
  @override
  Future<int?> classeIsced(String classeId) => _distant.classeIsced(classeId);

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
  Future<EncaissementScolarite> enregistrerEncaissement(EncaissementScolarite encaissement) async {
    await exigerCodeSecret('Enregistrer l’encaissement');
    final cle = encaissement.id.isEmpty ? const Uuid().v4() : encaissement.id;
    final avecCle = encaissement.avecCle(cle, saisiLe: encaissement.saisiLeClient ?? DateTime.now());
    final file = _file;
    try {
      return await _distant.enregistrerEncaissement(avecCle);
    } on ErreurScolarite catch (e) {
      if (e.code != 'HORS_CONNEXION' || file == null) rethrow;
    }
    final local = avecCle.avecCle(cle, numeroProvisoire: await _prochainNumeroProvisoire(), enAttenteEnvoi: true);
    await file.enfiler(SyncEntree(
      id: cle,
      entite: entiteEncaissement,
      operation: 'insert',
      payload: jsonEncode({...local.versParamsEnregistrement(), '_cache': local.versJsonCache()}),
    ));
    return local;
  }

  @override
  Future<void> annulerEncaissement({required String encaissementId, required String motif}) async {
    await exigerCodeSecret('Annuler l’encaissement');
    final file = _file;
    try {
      return await _distant.annulerEncaissement(encaissementId: encaissementId, motif: motif);
    } on ErreurScolarite catch (e) {
      if (e.code != 'HORS_CONNEXION' || file == null) rethrow;
    }
    await file.enfiler(SyncEntree(
      id: 'annulation/$encaissementId',
      entite: entiteAnnulationEncaissement,
      operation: 'update',
      payload: jsonEncode({'id': encaissementId, 'motif': motif}),
    ));
  }

  Future<String> _prochainNumeroProvisoire() async {
    final document = await _cache.lireDocument('compteur_recus_provisoires', CacheDocumentStore.cleUnique);
    final n = ((document?['n'] as num?)?.toInt() ?? 0) + 1;
    await _cache.ecrireDocument('compteur_recus_provisoires', CacheDocumentStore.cleUnique, {'n': n});
    final appareil = ((await _identifiantAppareil?.call()) ?? '0000').replaceAll('-', '').toUpperCase();
    final court = appareil.length >= 4 ? appareil.substring(0, 4) : appareil.padRight(4, '0');
    return 'PROV-$court-${n.toString().padLeft(4, '0')}';
  }

  /// Encaissements saisis sur cet appareil et pas encore reçus, avec les
  /// annulations en attente appliquées.
  Future<List<EncaissementScolarite>> _encaissementsEnAttente() async {
    final file = _file;
    if (file == null) return const [];
    final entrees = await file.entreesEnAttente();
    final annulations = <String, String>{
      for (final e in entrees)
        if (e.entite == entiteAnnulationEncaissement)
          (jsonDecode(e.payload) as Map<String, dynamic>)['id'] as String:
              (jsonDecode(e.payload) as Map<String, dynamic>)['motif'] as String,
    };
    return [
      for (final e in entrees)
        if (e.entite == entiteEncaissement)
          _avecAnnulation(
            EncaissementScolarite.depuisJson((jsonDecode(e.payload) as Map<String, dynamic>)['_cache'] as Map<String, dynamic>),
            annulations,
          ),
    ];
  }

  static EncaissementScolarite _avecAnnulation(EncaissementScolarite e, Map<String, String> annulations) {
    final motif = annulations[e.id];
    if (motif == null) return e;
    return EncaissementScolarite.depuisJson({...e.versJsonCache(), 'statut': 'annule', 'motif_annulation': motif});
  }

  Future<List<EncaissementScolarite>> _avecEnAttente(
    List<EncaissementScolarite> connus,
    bool Function(EncaissementScolarite) garde,
  ) async {
    final enAttente = [for (final e in await _encaissementsEnAttente()) if (garde(e)) e];
    final annulations = <String, String>{
      for (final e in await (_file?.entreesEnAttente() ?? Future.value(const <SyncEntree>[])))
        if (e.entite == entiteAnnulationEncaissement)
          (jsonDecode(e.payload) as Map<String, dynamic>)['id'] as String:
              (jsonDecode(e.payload) as Map<String, dynamic>)['motif'] as String,
    };
    final ids = {for (final e in connus) e.id};
    return [
      for (final e in enAttente)
        if (!ids.contains(e.id)) e,
      for (final e in connus) _avecAnnulation(e, annulations),
    ];
  }

  // --- M15quater : lectures avec repli cache -------------------------------

  static const _typeFicheParMatricule = 'fiche_par_matricule';
  static const _typeEnfantsParTelephone = 'enfants_par_telephone';
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
  Future<List<FicheEleve>> rechercherEnfantsParTelephoneParent({
    required String etablissementId,
    required String telephone,
  }) {
    return _listeAvecCache(
      type: _typeEnfantsParTelephone,
      cle: '$etablissementId::$telephone',
      lire: () => _distant.rechercherEnfantsParTelephoneParent(
        etablissementId: etablissementId,
        telephone: telephone,
      ),
      versJson: (f) => f.versJson(),
      depuisJson: FicheEleve.depuisJson,
    );
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
    SoldeScolarite solde;
    try {
      solde = await _distant.soldeScolarite(inscriptionId);
      await _cache.ecrireDocument(_typeSolde, inscriptionId, {
        'montant_du': solde.montantDu,
        'montant_paye': solde.montantPaye,
        'solde': solde.solde,
      });
    } on ErreurScolarite {
      final document = await _cache.lireDocument(_typeSolde, inscriptionId);
      if (document == null) rethrow;
      solde = SoldeScolarite.depuisJson(document);
    }
    // Les encaissements de scolarité pas encore envoyés comptent déjà.
    var enAttente = 0.0;
    for (final e in await _encaissementsEnAttente()) {
      if (e.inscriptionId == inscriptionId && e.estValide && e.typeFrais == TypeFraisScolaire.scolarite) {
        enAttente += e.montant;
      }
    }
    if (enAttente == 0) return solde;
    return SoldeScolarite(
      montantDu: solde.montantDu,
      montantPaye: solde.montantPaye + enAttente,
      solde: solde.solde - enAttente,
    );
  }

  @override
  Future<List<EncaissementScolarite>> encaissementsDeInscription(String inscriptionId) async {
    final connus = await _listeAvecCache(
      type: _typeEncaissements,
      cle: inscriptionId,
      lire: () => _distant.encaissementsDeInscription(inscriptionId),
      versJson: (e) => e.versJsonCache(),
      depuisJson: EncaissementScolarite.depuisJson,
    );
    return _avecEnAttente(connus, (e) => e.inscriptionId == inscriptionId);
  }

  @override
  Future<List<EncaissementScolarite>> encaissementsRecents(String etablissementId, {int limite = 100}) async {
    final connus = await _listeAvecCache(
      type: _typeEncaissementsRecents,
      cle: etablissementId,
      lire: () => _distant.encaissementsRecents(etablissementId, limite: limite),
      versJson: (e) => e.versJsonCache(),
      depuisJson: EncaissementScolarite.depuisJson,
    );
    return _avecEnAttente(connus, (e) => e.etablissementId == etablissementId);
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
