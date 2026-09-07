import 'dart:convert';

import '../../../core/db/cache_document_store.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/absence_personnel.dart';
import '../domain/bulletin_paie.dart' as domaine;
import '../domain/conge.dart' as domaine;
import '../domain/contrat.dart';
import '../domain/effectif_categorie.dart';
import '../domain/employe.dart' as domaine;
import '../domain/recommandation_formation.dart';
import '../domain/remplacement_suggere.dart';
import '../domain/rh_repository.dart';

/// Décore un [RhRepository] réseau avec un repli SQLite/Drift, et rend
/// [demanderConge]/[pointerAbsence] utilisables hors connexion via la même
/// file `sync_queue` que les présences/retards (M7) — même politique
/// exactement : panne réseau ⇒ mise en file ; rejet métier authentique ⇒
/// remonté tel quel.
///
/// Cache pertinent pour l'« annuaire du personnel » demandé au cahier des
/// charges (consultation fluide hors-ligne des fiches et emplois du temps) ;
/// les actions de bureau (fiche employé, contrat, validation de congé)
/// restent en ligne, cohérent avec [RhRepository].
class CachedRhRepository implements RhRepository {
  const CachedRhRepository(this._distant, this._cache, this._syncRepo);

  final RhRepository _distant;
  final CacheDocumentStore _cache;
  final DriftSyncRepository _syncRepo;

  static const _typeAnnuaire = 'employes_etablissement';
  static const _typeEmployeParProfil = 'employe_par_profil';
  static const _typeEmploye = 'employe';
  static const _typeContrats = 'contrats_employe';
  static const _typeConges = 'conges_employe';
  static const _typeAbsences = 'absences_employe';
  static const _typePaie = 'paie_employe';
  static const _typeChargeHoraire = 'charge_horaire';
  static const _typeEffectifs = 'analyser_effectifs';
  static const _typeTurnover = 'score_turnover';
  static const _typeFormation = 'recommandation_formation';

  /// Codes métier authentiques des triggers M8 — jamais mis en file.
  static const _codesMetierBloquants = {
    'EMPLOYE_AUTRE_ETABLISSEMENT',
    'VALIDATION_RH_REQUISE',
  };

  @override
  Future<List<domaine.Employe>> employesEtablissement(String etablissementId) {
    return _listeAvecCache(
      type: _typeAnnuaire,
      cle: etablissementId,
      lire: () => _distant.employesEtablissement(etablissementId),
      versJson: (e) => e.versJsonCache(),
      depuisJson: domaine.Employe.depuisJsonCache,
    );
  }

  @override
  Future<domaine.Employe?> employeParProfil(String profileId) async {
    try {
      final employe = await _distant.employeParProfil(profileId);
      if (employe != null) await _cache.ecrireDocument(_typeEmployeParProfil, profileId, employe.versJsonCache());
      return employe;
    } on ErreurRh {
      final document = await _cache.lireDocument(_typeEmployeParProfil, profileId);
      return document == null ? null : domaine.Employe.depuisJsonCache(document);
    }
  }

  @override
  Future<domaine.Employe?> employe(String employeId) async {
    try {
      final employe = await _distant.employe(employeId);
      if (employe != null) await _cache.ecrireDocument(_typeEmploye, employeId, employe.versJsonCache());
      return employe;
    } on ErreurRh {
      final document = await _cache.lireDocument(_typeEmploye, employeId);
      return document == null ? null : domaine.Employe.depuisJsonCache(document);
    }
  }

  @override
  Future<List<Contrat>> contratsDeEmploye(String employeId) {
    return _listeAvecCache(
      type: _typeContrats,
      cle: employeId,
      lire: () => _distant.contratsDeEmploye(employeId),
      versJson: (c) => c.versJsonEcriture()..['id'] = c.id,
      depuisJson: Contrat.depuisJson,
    );
  }

  @override
  Future<List<domaine.Conge>> congesDeEmploye(String employeId) async {
    final base = await _listeAvecCache(
      type: _typeConges,
      cle: employeId,
      lire: () => _distant.congesDeEmploye(employeId),
      versJson: (c) => c.versJsonCache(),
      depuisJson: domaine.Conge.depuisJsonCache,
    );
    return _fusionnerFileAttente('conges', base, employeId);
  }

  @override
  Future<List<AbsencePersonnel>> absencesDeEmploye(String employeId) {
    return _listeAvecCache(
      type: _typeAbsences,
      cle: employeId,
      lire: () => _distant.absencesDeEmploye(employeId),
      versJson: (a) => a.versJsonCache(),
      depuisJson: AbsencePersonnel.depuisJsonCache,
    );
  }

  @override
  Future<List<domaine.BulletinPaie>> bulletinsDeEmploye(String employeId) {
    // Consultation seule (M14 prépare l'écriture) : un simple repli cache
    // suffit, pas de superposition de file d'attente pertinente ici.
    return _listeAvecCache(
      type: _typePaie,
      cle: employeId,
      lire: () => _distant.bulletinsDeEmploye(employeId),
      versJson: (b) => {
        'id': b.id,
        'etablissement_id': b.etablissementId,
        'employe_id': b.employeId,
        'contrat_id': b.contratId,
        'periode_debut': _dateIso(b.periodeDebut),
        'periode_fin': _dateIso(b.periodeFin),
        'salaire_base': b.salaireBase,
        'primes': b.primes,
        'retenues': b.retenues,
        'net': b.net,
        'statut': b.statut.code,
      },
      depuisJson: domaine.BulletinPaie.depuisJson,
    );
  }

  @override
  Future<int> chargeHoraire(String employeId) async {
    try {
      final charge = await _distant.chargeHoraire(employeId);
      await _cache.ecrireDocument(_typeChargeHoraire, employeId, {'valeur': charge});
      return charge;
    } on ErreurRh {
      final document = await _cache.lireDocument(_typeChargeHoraire, employeId);
      if (document == null) rethrow;
      return (document['valeur'] as num).toInt();
    }
  }

  @override
  Future<List<EffectifCategorie>> analyserEffectifs(String etablissementId) {
    return _listeAvecCache(
      type: _typeEffectifs,
      cle: etablissementId,
      lire: () => _distant.analyserEffectifs(etablissementId),
      versJson: (e) => {
        'categorie': e.categorie,
        'effectif': e.effectif,
        'anciennete_moyenne_jours': e.ancienneteMoyenneJours,
        'masse_salariale_base': e.masseSalarialeBase,
      },
      depuisJson: EffectifCategorie.depuisJson,
    );
  }

  @override
  Future<double> scoreTurnover(String employeId) async {
    try {
      final score = await _distant.scoreTurnover(employeId);
      await _cache.ecrireDocument(_typeTurnover, employeId, {'valeur': score});
      return score;
    } on ErreurRh {
      final document = await _cache.lireDocument(_typeTurnover, employeId);
      if (document == null) rethrow;
      return (document['valeur'] as num).toDouble();
    }
  }

  @override
  Future<List<RecommandationFormation>> recommanderFormation(String employeId, String anneeScolaireId) {
    return _listeAvecCache(
      type: _typeFormation,
      cle: '$employeId::$anneeScolaireId',
      lire: () => _distant.recommanderFormation(employeId, anneeScolaireId),
      versJson: (r) => {
        'programme_matiere_id': r.programmeMatiereId,
        'code': r.code,
        'libelle': r.libelle,
        'raison': r.raison,
      },
      depuisJson: RecommandationFormation.depuisJson,
    );
  }

  @override
  Future<List<RemplacementSuggere>> optimiserRemplacements(String etablissementId, DateTime date) {
    // Outil opérationnel du jour même (« qui remplace qui aujourd'hui ») :
    // une suggestion vieille de plusieurs jours serait trompeuse, pas de
    // repli hors-ligne pertinent (même choix que `recommandationSanction`
    // en M7).
    return _distant.optimiserRemplacements(etablissementId, date);
  }

  @override
  Future<void> creerOuModifierEmploye(domaine.Employe employe) => _distant.creerOuModifierEmploye(employe);

  @override
  Future<Contrat> creerContrat(Contrat contrat) => _distant.creerContrat(contrat);

  @override
  Future<bool> demanderConge(domaine.Conge conge) async {
    try {
      return await _distant.demanderConge(conge);
    } catch (e) {
      if (e is ErreurRh && _codesMetierBloquants.contains(e.code)) rethrow;
      await _syncRepo.enfiler(
        SyncEntree(
          id: conge.id,
          entite: 'conges',
          operation: 'upsert',
          payload: jsonEncode(conge.versJsonEcriture()),
        ),
      );
      return false;
    }
  }

  @override
  Future<void> validerConge(String congeId, {required String statut, required String valideePar}) =>
      _distant.validerConge(congeId, statut: statut, valideePar: valideePar);

  @override
  Future<bool> pointerAbsence(AbsencePersonnel absence) async {
    try {
      return await _distant.pointerAbsence(absence);
    } catch (e) {
      if (e is ErreurRh && _codesMetierBloquants.contains(e.code)) rethrow;
      await _syncRepo.enfiler(
        SyncEntree(
          id: absence.id,
          entite: 'absences_personnel',
          operation: 'upsert',
          payload: jsonEncode(absence.versJsonEcriture()),
        ),
      );
      return false;
    }
  }

  /// Superpose à [base] les demandes de congé encore en attente pour
  /// [employeId], pour un affichage immédiat après un dépôt hors-ligne.
  Future<List<domaine.Conge>> _fusionnerFileAttente(
    String entite,
    List<domaine.Conge> base,
    String employeId,
  ) async {
    final enAttente = await _syncRepo.entreesEnAttente();
    final parId = {for (final c in base) c.id: c};

    for (final entree in enAttente) {
      if (entree.entite != entite) continue;
      final json = jsonDecode(entree.payload) as Map<String, dynamic>;
      final enCours = domaine.Conge.depuisJsonEcriture(json);
      if (enCours.employeId != employeId) continue;
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
    } on ErreurRh {
      final document = await _cache.lireDocument(type, cle);
      if (document == null) rethrow;
      return (document['lignes'] as List<dynamic>)
          .map((l) => depuisJson(l as Map<String, dynamic>))
          .toList(growable: false);
    }
  }

  static String _dateIso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
