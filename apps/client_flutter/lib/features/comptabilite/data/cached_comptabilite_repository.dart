import 'dart:convert';

import '../../../core/db/cache_document_store.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/comptabilite_repository.dart';
import '../domain/ecriture_comptable.dart';
import '../domain/journal.dart';
import '../domain/ligne_balance.dart';
import '../domain/ligne_journal.dart';
import '../domain/mouvement_grand_livre.dart';
import '../domain/plan_comptable.dart';
import '../domain/signaux_ia_comptables.dart';

/// Décore un [ComptabiliteRepository] réseau avec un repli SQLite/Drift.
///
/// Périmètre hors-ligne aligné sur le DDL réel : seule
/// `ecritures_comptables` porte `device_id`/`client_ts` côté serveur et est
/// donc tolérante hors-ligne via `sync_queue` (même pattern que les
/// présences M7, l'emploi du temps M11, le panier M13). Le plan comptable et
/// les journaux restent une configuration en ligne uniquement (comme les
/// salles en M11) ; les documents (journal, grand livre, balance) et les
/// fonctions IA sont des agrégats calculés à la demande, jamais mis en cache
/// ni rejoués hors-ligne.
class CachedComptabiliteRepository implements ComptabiliteRepository {
  const CachedComptabiliteRepository(this._distant, this._cache, this._syncRepo);

  final ComptabiliteRepository _distant;
  final CacheDocumentStore _cache;
  final DriftSyncRepository _syncRepo;

  static const _typePlan = 'plan_comptable';
  static const _typeJournaux = 'journaux';
  static const _typeEcritures = 'ecritures_recentes';

  /// Codes métier authentiques des triggers M14 — jamais mis en file.
  static const _codesMetierBloquants = {
    'PLAN_COMPTABLE_PARENT_INCOHERENT',
    'ECRITURE_TENANT_INCOHERENT',
    'ECRITURE_COMPTES_IDENTIQUES',
  };

  @override
  Future<List<PlanComptable>> planComptable(String etablissementId) async {
    try {
      final liste = await _distant.planComptable(etablissementId);
      await _cache.ecrireDocument(_typePlan, etablissementId, {
        'lignes': liste.map((c) => c.versJsonCache()).toList(growable: false),
      });
      return liste;
    } on ErreurComptabilite {
      final document = await _cache.lireDocument(_typePlan, etablissementId);
      if (document == null) rethrow;
      return (document['lignes'] as List<dynamic>)
          .map((l) => PlanComptable.depuisJsonCache(l as Map<String, dynamic>))
          .toList(growable: false);
    }
  }

  @override
  Future<bool> enregistrerCompte(PlanComptable compte) => _distant.enregistrerCompte(compte);

  @override
  Future<List<Journal>> journaux(String etablissementId) async {
    try {
      final liste = await _distant.journaux(etablissementId);
      await _cache.ecrireDocument(_typeJournaux, etablissementId, {
        'lignes': liste.map((j) => j.versJsonCache()).toList(growable: false),
      });
      return liste;
    } on ErreurComptabilite {
      final document = await _cache.lireDocument(_typeJournaux, etablissementId);
      if (document == null) rethrow;
      return (document['lignes'] as List<dynamic>)
          .map((l) => Journal.depuisJsonCache(l as Map<String, dynamic>))
          .toList(growable: false);
    }
  }

  @override
  Future<bool> enregistrerJournal(Journal journal) => _distant.enregistrerJournal(journal);

  @override
  Future<List<EcritureComptable>> ecrituresRecentes(String etablissementId, {int limite = 100}) async {
    List<EcritureComptable> base;
    try {
      base = await _distant.ecrituresRecentes(etablissementId, limite: limite);
      await _cache.ecrireDocument(_typeEcritures, etablissementId, {
        'lignes': base.map((e) => e.versJsonCache()).toList(growable: false),
      });
    } on ErreurComptabilite {
      final document = await _cache.lireDocument(_typeEcritures, etablissementId);
      if (document == null) rethrow;
      base = (document['lignes'] as List<dynamic>)
          .map((l) => EcritureComptable.depuisJsonCache(l as Map<String, dynamic>))
          .toList(growable: false);
    }

    final enAttente = await _syncRepo.entreesEnAttente();
    final parId = {for (final e in base) e.id: e};
    for (final entree in enAttente) {
      if (entree.entite != 'ecritures_comptables') continue;
      final enCours = EcritureComptable.depuisJsonEcriture(jsonDecode(entree.payload) as Map<String, dynamic>);
      if (enCours.etablissementId == etablissementId) parId[enCours.id] = enCours;
    }
    final fusion = parId.values.toList()..sort((a, b) => b.dateEcriture.compareTo(a.dateEcriture));
    return fusion.take(limite).toList(growable: false);
  }

  @override
  Future<bool> enregistrerEcriture(EcritureComptable ecriture) async {
    try {
      return await _distant.enregistrerEcriture(ecriture);
    } catch (e) {
      if (e is ErreurComptabilite && _codesMetierBloquants.contains(e.code)) rethrow;
      await _syncRepo.enfiler(
        SyncEntree(
          id: ecriture.id,
          entite: 'ecritures_comptables',
          operation: 'upsert',
          payload: jsonEncode(ecriture.versJsonEcriture()),
        ),
      );
      return false;
    }
  }

  @override
  Future<List<LigneJournal>> journalComptable(
    String etablissementId,
    String journalId,
    DateTime debut,
    DateTime fin,
  ) =>
      _distant.journalComptable(etablissementId, journalId, debut, fin);

  @override
  Future<List<MouvementGrandLivre>> grandLivre(
    String etablissementId,
    String compteId,
    DateTime debut,
    DateTime fin,
  ) =>
      _distant.grandLivre(etablissementId, compteId, debut, fin);

  @override
  Future<List<LigneBalance>> balanceComptable(String etablissementId, DateTime date) =>
      _distant.balanceComptable(etablissementId, date);

  @override
  Future<List<Balance>> genererBalance(String etablissementId, DateTime date) =>
      _distant.genererBalance(etablissementId, date);

  @override
  Future<List<AnomalieComptable>> detecterAnomalies(String etablissementId) =>
      _distant.detecterAnomalies(etablissementId);

  @override
  Future<List<ProjectionTresorerie>> predireTresorerie(String etablissementId, {int jours = 30}) =>
      _distant.predireTresorerie(etablissementId, jours: jours);

  @override
  Future<List<EcritureRecommandee>> recommanderEcritures(String etablissementId) =>
      _distant.recommanderEcritures(etablissementId);

  @override
  Future<List<TendanceMensuelle>> analyserTendances(String etablissementId, {int mois = 12}) =>
      _distant.analyserTendances(etablissementId, mois: mois);
}
