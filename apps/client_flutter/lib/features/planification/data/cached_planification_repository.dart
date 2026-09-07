import 'dart:convert';

import '../../../core/db/cache_document_store.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/charge_travail.dart';
import '../domain/conflit_emploi.dart';
import '../domain/emploi_du_temps.dart';
import '../domain/evenement_agenda.dart';
import '../domain/planification_repository.dart';
import '../domain/progression_pedagogique.dart';
import '../domain/salle.dart';

/// Décore un [PlanificationRepository] réseau avec un repli SQLite/Drift, et
/// rend [enregistrerSeance]/[enregistrerEvenement]/[enregistrerProgression]
/// utilisables hors connexion via la même file `sync_queue` que les
/// présences (M7) — panne réseau ⇒ mise en file ; rejet métier authentique
/// ⇒ remonté tel quel. Cache pertinent pour la consultation fluide hors
/// ligne des plannings et agendas demandée au cahier des charges.
class CachedPlanificationRepository implements PlanificationRepository {
  const CachedPlanificationRepository(this._distant, this._cache, this._syncRepo);

  final PlanificationRepository _distant;
  final CacheDocumentStore _cache;
  final DriftSyncRepository _syncRepo;

  static const _typeSalles = 'salles_etablissement';
  static const _typeEmploisClasse = 'emplois_classe';
  static const _typeEmploisEnseignant = 'emplois_enseignant';
  static const _typeEmploisSalle = 'emplois_salle';
  static const _typeEvenementsEtablissement = 'evenements_etablissement';
  static const _typeEvenementsClasse = 'evenements_classe';
  static const _typeProgression = 'progression_classe';

  /// Codes métier authentiques des triggers M11 — jamais mis en file.
  static const _codesMetierBloquants = {
    'EMPLOI_ANNEE_AUTRE_ETABLISSEMENT',
    'EMPLOI_CLASSE_AUTRE_ETABLISSEMENT',
    'EMPLOI_CLASSE_AUTRE_ANNEE',
    'EMPLOI_SALLE_AUTRE_ETABLISSEMENT',
    'EMPLOI_ENSEIGNANT_NON_MEMBRE',
    'EVENEMENT_ANNEE_AUTRE_ETABLISSEMENT',
    'EVENEMENT_CLASSE_AUTRE_ETABLISSEMENT',
    'EVENEMENT_CLASSE_AUTRE_ANNEE',
    'PROGRESSION_ANNEE_AUTRE_ETABLISSEMENT',
    'PROGRESSION_CLASSE_AUTRE_ETABLISSEMENT',
    'PROGRESSION_CLASSE_AUTRE_ANNEE',
    'PROGRESSION_EVALUATION_AUTRE_ETABLISSEMENT',
  };

  @override
  Future<List<Salle>> sallesEtablissement(String etablissementId) {
    return _listeAvecCache(
      type: _typeSalles,
      cle: etablissementId,
      lire: () => _distant.sallesEtablissement(etablissementId),
      versJson: (s) => s.versJsonCache(),
      depuisJson: Salle.depuisJsonCache,
    );
  }

  @override
  Future<List<EmploiDuTemps>> emploisDeClasse(String classeId) async {
    final base = await _listeAvecCache(
      type: _typeEmploisClasse,
      cle: classeId,
      lire: () => _distant.emploisDeClasse(classeId),
      versJson: (e) => e.versJsonCache(),
      depuisJson: EmploiDuTemps.depuisJsonCache,
    );
    return _fusionnerEmplois(base, (e) => e.classeId == classeId);
  }

  @override
  Future<List<EmploiDuTemps>> emploisDeEnseignant(
    String enseignantProfileId,
    String etablissementId,
    String anneeScolaireId,
  ) async {
    final base = await _listeAvecCache(
      type: _typeEmploisEnseignant,
      cle: '$enseignantProfileId::$etablissementId::$anneeScolaireId',
      lire: () => _distant.emploisDeEnseignant(enseignantProfileId, etablissementId, anneeScolaireId),
      versJson: (e) => e.versJsonCache(),
      depuisJson: EmploiDuTemps.depuisJsonCache,
    );
    return _fusionnerEmplois(base, (e) => e.enseignantProfileId == enseignantProfileId);
  }

  @override
  Future<List<EmploiDuTemps>> emploisDeSalle(String salleId, String anneeScolaireId) async {
    final base = await _listeAvecCache(
      type: _typeEmploisSalle,
      cle: '$salleId::$anneeScolaireId',
      lire: () => _distant.emploisDeSalle(salleId, anneeScolaireId),
      versJson: (e) => e.versJsonCache(),
      depuisJson: EmploiDuTemps.depuisJsonCache,
    );
    return _fusionnerEmplois(base, (e) => e.salleId == salleId);
  }

  @override
  Future<bool> enregistrerSeance(EmploiDuTemps emploi) async {
    try {
      return await _distant.enregistrerSeance(emploi);
    } catch (e) {
      if (e is ErreurPlanification && _codesMetierBloquants.contains(e.code)) rethrow;
      await _syncRepo.enfiler(
        SyncEntree(
          id: emploi.id,
          entite: 'emplois_du_temps',
          operation: 'upsert',
          payload: jsonEncode(emploi.versJsonEcriture()),
        ),
      );
      return false;
    }
  }

  @override
  Future<List<EvenementAgenda>> evenementsEtablissement(String etablissementId, String anneeScolaireId) async {
    final base = await _listeAvecCache(
      type: _typeEvenementsEtablissement,
      cle: '$etablissementId::$anneeScolaireId',
      lire: () => _distant.evenementsEtablissement(etablissementId, anneeScolaireId),
      versJson: (e) => e.versJsonCache(),
      depuisJson: EvenementAgenda.depuisJsonCache,
    );
    return _fusionnerEvenements(base, (e) => e.etablissementId == etablissementId);
  }

  @override
  Future<List<EvenementAgenda>> evenementsDeClasse(String classeId, String anneeScolaireId) async {
    final base = await _listeAvecCache(
      type: _typeEvenementsClasse,
      cle: '$classeId::$anneeScolaireId',
      lire: () => _distant.evenementsDeClasse(classeId, anneeScolaireId),
      versJson: (e) => e.versJsonCache(),
      depuisJson: EvenementAgenda.depuisJsonCache,
    );
    return _fusionnerEvenements(base, (e) => e.classeId == classeId);
  }

  @override
  Future<bool> enregistrerEvenement(EvenementAgenda evenement) async {
    try {
      return await _distant.enregistrerEvenement(evenement);
    } catch (e) {
      if (e is ErreurPlanification && _codesMetierBloquants.contains(e.code)) rethrow;
      await _syncRepo.enfiler(
        SyncEntree(
          id: evenement.id,
          entite: 'evenements_agenda',
          operation: 'upsert',
          payload: jsonEncode(evenement.versJsonEcriture()),
        ),
      );
      return false;
    }
  }

  @override
  Future<List<ProgressionPedagogique>> progressionDeClasse(String classeId, String anneeScolaireId) async {
    final base = await _listeAvecCache(
      type: _typeProgression,
      cle: '$classeId::$anneeScolaireId',
      lire: () => _distant.progressionDeClasse(classeId, anneeScolaireId),
      versJson: (p) => p.versJsonCache(),
      depuisJson: ProgressionPedagogique.depuisJsonCache,
    );
    return _fusionnerProgression(base, (p) => p.classeId == classeId);
  }

  @override
  Future<bool> enregistrerProgression(ProgressionPedagogique progression) async {
    try {
      return await _distant.enregistrerProgression(progression);
    } catch (e) {
      if (e is ErreurPlanification && _codesMetierBloquants.contains(e.code)) rethrow;
      await _syncRepo.enfiler(
        SyncEntree(
          id: progression.id,
          entite: 'progression_pedagogique',
          operation: 'upsert',
          payload: jsonEncode(progression.versJsonEcriture()),
        ),
      );
      return false;
    }
  }

  @override
  Future<void> changerStatutProgression(String progressionId, String statut) =>
      _distant.changerStatutProgression(progressionId, statut);

  @override
  Future<int> recommanderSeances(String etablissementId, String anneeScolaireId) =>
      _distant.recommanderSeances(etablissementId, anneeScolaireId);

  @override
  Future<Map<String, dynamic>?> suggererPlacement({
    required String etablissementId,
    required String anneeScolaireId,
    required String enseignantProfileId,
    required String classeId,
    required String salleId,
  }) {
    return _distant.suggererPlacement(
      etablissementId: etablissementId,
      anneeScolaireId: anneeScolaireId,
      enseignantProfileId: enseignantProfileId,
      classeId: classeId,
      salleId: salleId,
    );
  }

  @override
  Future<List<ConflitEmploi>> detecterConflits(String etablissementId, String anneeScolaireId) =>
      _distant.detecterConflits(etablissementId, anneeScolaireId);

  @override
  Future<ChargeTravailEnseignant> chargeEnseignant(
    String etablissementId,
    String anneeScolaireId,
    String enseignantProfileId,
  ) =>
      _distant.chargeEnseignant(etablissementId, anneeScolaireId, enseignantProfileId);

  @override
  Future<ChargeTravailEleve> chargeEleve(String classeId) => _distant.chargeEleve(classeId);

  Future<List<EmploiDuTemps>> _fusionnerEmplois(
    List<EmploiDuTemps> base,
    bool Function(EmploiDuTemps) filtre,
  ) async {
    final enAttente = await _syncRepo.entreesEnAttente();
    final parId = {for (final e in base) e.id: e};
    for (final entree in enAttente) {
      if (entree.entite != 'emplois_du_temps') continue;
      final enCours = EmploiDuTemps.depuisJsonEcriture(jsonDecode(entree.payload) as Map<String, dynamic>);
      if (filtre(enCours)) parId[enCours.id] = enCours;
    }
    return parId.values.toList(growable: false);
  }

  Future<List<EvenementAgenda>> _fusionnerEvenements(
    List<EvenementAgenda> base,
    bool Function(EvenementAgenda) filtre,
  ) async {
    final enAttente = await _syncRepo.entreesEnAttente();
    final parId = {for (final e in base) e.id: e};
    for (final entree in enAttente) {
      if (entree.entite != 'evenements_agenda') continue;
      final enCours = EvenementAgenda.depuisJsonEcriture(jsonDecode(entree.payload) as Map<String, dynamic>);
      if (filtre(enCours)) parId[enCours.id] = enCours;
    }
    return parId.values.toList(growable: false);
  }

  Future<List<ProgressionPedagogique>> _fusionnerProgression(
    List<ProgressionPedagogique> base,
    bool Function(ProgressionPedagogique) filtre,
  ) async {
    final enAttente = await _syncRepo.entreesEnAttente();
    final parId = {for (final p in base) p.id: p};
    for (final entree in enAttente) {
      if (entree.entite != 'progression_pedagogique') continue;
      final enCours = ProgressionPedagogique.depuisJsonEcriture(jsonDecode(entree.payload) as Map<String, dynamic>);
      if (filtre(enCours)) parId[enCours.id] = enCours;
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
    } on ErreurPlanification {
      final document = await _cache.lireDocument(type, cle);
      if (document == null) rethrow;
      return (document['lignes'] as List<dynamic>)
          .map((l) => depuisJson(l as Map<String, dynamic>))
          .toList(growable: false);
    }
  }
}
