import 'dart:convert';

import '../../../core/db/cache_document_store.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/anomalie_statistique.dart';
import '../domain/indicateur_cle.dart';
import '../domain/rapport.dart';
import '../domain/rapports_repository.dart';
import '../domain/recommandation_strategique.dart';

/// Décore un [RapportsRepository] réseau avec un repli SQLite/Drift, et rend
/// [demanderRapport] utilisable hors connexion via la même file `sync_queue`
/// que les autres modules (M6-M9) — cohérent avec le contrat M10
/// (`demande_hors_ligne` + `cache_valide_jus`) : panne réseau ⇒ mise en
/// file ; rejet métier authentique ⇒ remonté tel quel.
class CachedRapportsRepository implements RapportsRepository {
  const CachedRapportsRepository(this._distant, this._cache, this._syncRepo);

  final RapportsRepository _distant;
  final CacheDocumentStore _cache;
  final DriftSyncRepository _syncRepo;

  static const _typeRapportsFiche = 'rapports_fiche';
  static const _typeRapportsEtablissement = 'rapports_etablissement';
  static const _typeIndicateurs = 'indicateurs_etablissement';
  static const _typeAnomalies = 'anomalies_etablissement';
  static const _typeRecommandations = 'recommandations_etablissement';

  /// Codes métier authentiques du trigger `rapports_verifie_tenant` —
  /// jamais mis en file.
  static const _codesMetierBloquants = {
    'RAPPORT_ANNEE_AUTRE_ETABLISSEMENT',
    'RAPPORT_CLASSE_AUTRE_ETABLISSEMENT',
    'RAPPORT_FICHE_AUTRE_ETABLISSEMENT',
  };

  @override
  Future<List<Rapport>> rapportsDeFiche(String ficheEleveId) async {
    final base = await _listeAvecCache(
      type: _typeRapportsFiche,
      cle: ficheEleveId,
      lire: () => _distant.rapportsDeFiche(ficheEleveId),
      versJson: (r) => r.versJsonCache(),
      depuisJson: Rapport.depuisJsonCache,
    );
    return _fusionnerDemandesEnAttente(base, (r) => r.ficheEleveId == ficheEleveId);
  }

  @override
  Future<List<Rapport>> rapportsEtablissement(String etablissementId) async {
    final base = await _listeAvecCache(
      type: _typeRapportsEtablissement,
      cle: etablissementId,
      lire: () => _distant.rapportsEtablissement(etablissementId),
      versJson: (r) => r.versJsonCache(),
      depuisJson: Rapport.depuisJsonCache,
    );
    return _fusionnerDemandesEnAttente(base, (r) => r.etablissementId == etablissementId);
  }

  @override
  Future<bool> demanderRapport(Rapport rapport) async {
    try {
      return await _distant.demanderRapport(rapport);
    } catch (e) {
      if (e is ErreurRapports && _codesMetierBloquants.contains(e.code)) rethrow;
      await _syncRepo.enfiler(
        SyncEntree(
          id: rapport.id,
          entite: 'rapports',
          operation: 'upsert',
          payload: jsonEncode(rapport.versJsonEcriture()..['demande_hors_ligne'] = true),
        ),
      );
      return false;
    }
  }

  @override
  Future<List<IndicateurCle>> indicateursEtablissement(String etablissementId, String anneeScolaireId) {
    return _listeAvecCache(
      type: _typeIndicateurs,
      cle: '$etablissementId::$anneeScolaireId',
      lire: () => _distant.indicateursEtablissement(etablissementId, anneeScolaireId),
      versJson: (i) => {
        'id': i.id,
        'etablissement_id': i.etablissementId,
        'annee_scolaire_id': i.anneeScolaireId,
        'periode_id': i.periodeId,
        'classe_id': i.classeId,
        'code': i.code,
        'valeur_numeric': i.valeurNumeric,
        'valeur_texte': i.valeurTexte,
        'calcule_le': i.calculeLe.toIso8601String(),
        'version': i.version,
      },
      depuisJson: IndicateurCle.depuisJson,
    );
  }

  @override
  Future<int> consoliderIndicateurs(String etablissementId, String anneeScolaireId) =>
      _distant.consoliderIndicateurs(etablissementId, anneeScolaireId);

  @override
  Future<List<AnomalieStatistique>> anomaliesEtablissement(String etablissementId, String anneeScolaireId) {
    return _listeAvecCache(
      type: _typeAnomalies,
      cle: '$etablissementId::$anneeScolaireId',
      lire: () => _distant.anomaliesEtablissement(etablissementId, anneeScolaireId),
      versJson: (a) => {
        'id': a.id,
        'etablissement_id': a.etablissementId,
        'annee_scolaire_id': a.anneeScolaireId,
        'classe_id': a.classeId,
        'fiche_eleve_id': a.ficheEleveId,
        'employe_id': a.employeId,
        'type': a.type,
        'severite': a.severite,
        'description': a.description,
        'valeur_observee': a.valeurObservee,
        'valeur_attendue': a.valeurAttendue,
        'ecart': a.ecart,
        'statut': a.statut.code,
        'detectee_le': a.detecteeLe.toIso8601String(),
      },
      depuisJson: AnomalieStatistique.depuisJson,
    );
  }

  @override
  Future<int> detecterAnomalies(String etablissementId, String anneeScolaireId) =>
      _distant.detecterAnomalies(etablissementId, anneeScolaireId);

  @override
  Future<void> traiterAnomalie(String anomalieId, String statut, {required String traiteePar}) =>
      _distant.traiterAnomalie(anomalieId, statut, traiteePar: traiteePar);

  @override
  Future<List<RecommandationStrategique>> recommandationsEtablissement(
    String etablissementId,
    String anneeScolaireId,
  ) {
    return _listeAvecCache(
      type: _typeRecommandations,
      cle: '$etablissementId::$anneeScolaireId',
      lire: () => _distant.recommandationsEtablissement(etablissementId, anneeScolaireId),
      versJson: (r) => {
        'id': r.id,
        'etablissement_id': r.etablissementId,
        'annee_scolaire_id': r.anneeScolaireId,
        'classe_id': r.classeId,
        'type': r.type,
        'titre': r.titre,
        'description': r.description,
        'priorite': r.priorite,
        'statut': r.statut.code,
        'cree_le': r.creeLe.toIso8601String(),
      },
      depuisJson: RecommandationStrategique.depuisJson,
    );
  }

  @override
  Future<int> genererRecommandations(String etablissementId, String anneeScolaireId) =>
      _distant.genererRecommandations(etablissementId, anneeScolaireId);

  @override
  Future<void> statuerRecommandation(String recommandationId, String statut, {required String valideePar}) =>
      _distant.statuerRecommandation(recommandationId, statut, valideePar: valideePar);

  @override
  Future<Map<String, dynamic>> risqueClasse(String classeId) => _distant.risqueClasse(classeId);

  @override
  Future<String> resumeExecutif(String etablissementId, String anneeScolaireId) =>
      _distant.resumeExecutif(etablissementId, anneeScolaireId);

  /// Superpose à [base] les demandes de rapport encore en attente et
  /// concernées par [filtre], pour un affichage immédiat après un dépôt
  /// hors-ligne.
  Future<List<Rapport>> _fusionnerDemandesEnAttente(List<Rapport> base, bool Function(Rapport) filtre) async {
    final enAttente = await _syncRepo.entreesEnAttente();
    final parId = {for (final r in base) r.id: r};

    for (final entree in enAttente) {
      if (entree.entite != 'rapports') continue;
      final json = jsonDecode(entree.payload) as Map<String, dynamic>;
      final enCours = Rapport.depuisJsonEcriture(json);
      if (!filtre(enCours)) continue;
      parId[enCours.id] = enCours;
    }

    return parId.values.toList(growable: false);
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
    } on ErreurRapports {
      final document = await _cache.lireDocument(type, cle);
      if (document == null) rethrow;
      return (document['lignes'] as List<dynamic>)
          .map((l) => depuisJson(l as Map<String, dynamic>))
          .toList(growable: false);
    }
  }
}
