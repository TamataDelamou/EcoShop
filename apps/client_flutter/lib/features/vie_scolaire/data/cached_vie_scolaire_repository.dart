import 'dart:convert';

import '../../../core/db/cache_document_store.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/alerte_decrochage.dart';
import '../domain/evenement_scolaire.dart';
import '../domain/presence.dart' as domaine;
import '../domain/retard.dart';
import '../domain/sanction.dart';
import '../domain/vie_scolaire_repository.dart';

/// Décore un [VieScolaireRepository] réseau avec un repli SQLite/Drift, et
/// rend [saisirPresence]/[saisirRetard] utilisables hors connexion via la
/// même file `sync_queue` que les notes (M6) — même politique exactement :
/// panne réseau ⇒ mise en file ; rejet métier authentique ⇒ remonté tel quel.
class CachedVieScolaireRepository implements VieScolaireRepository {
  const CachedVieScolaireRepository(this._distant, this._cache, this._syncRepo);

  final VieScolaireRepository _distant;
  final CacheDocumentStore _cache;
  final DriftSyncRepository _syncRepo;

  static const _typePresencesClasse = 'presences_classe';
  static const _typePresencesFiche = 'presences_fiche';
  static const _typeRetardsFiche = 'retards_fiche';
  static const _typeSanctionsFiche = 'sanctions_fiche';
  static const _typeEvenements = 'evenements_etablissement';
  static const _typeAnalyse = 'analyse_comportement';
  static const _typeScore = 'score_decrochage';

  /// Codes métier authentiques des triggers M7 — jamais mis en file.
  static const _codesMetierBloquants = {
    'ELEVE_NON_INSCRIT',
    'CLASSE_AUTRE_ANNEE',
    'FICHE_AUTRE_ETABLISSEMENT',
    'CLASSE_AUTRE_ETABLISSEMENT',
    'ANNEE_AUTRE_ETABLISSEMENT',
    'DECISIONNAIRE_NON_MEMBRE',
    'SANCTION_IA_NON_VALIDEE',
  };

  @override
  Future<List<domaine.Presence>> presencesDeClasse(String classeId, DateTime date) async {
    final cle = '$classeId::${date.year}-${date.month}-${date.day}';
    final base = await _listeAvecCache(
      type: _typePresencesClasse,
      cle: cle,
      lire: () => _distant.presencesDeClasse(classeId, date),
      versJson: (p) => p.versJson(),
      depuisJson: domaine.Presence.depuisJsonCache,
    );
    return _fusionnerFileAttente('presences', base, (n) => n.ficheEleveId, (json) {
      final entrant = domaine.Presence.depuisJsonEcriture(json);
      return entrant.classeId == classeId && entrant.datePresence.year == date.year &&
              entrant.datePresence.month == date.month && entrant.datePresence.day == date.day
          ? entrant
          : null;
    });
  }

  @override
  Future<List<domaine.Presence>> presencesDeFiche(String ficheEleveId) {
    return _listeAvecCache(
      type: _typePresencesFiche,
      cle: ficheEleveId,
      lire: () => _distant.presencesDeFiche(ficheEleveId),
      versJson: (p) => p.versJson(),
      depuisJson: domaine.Presence.depuisJsonCache,
    );
  }

  @override
  Future<List<Retard>> retardsDeFiche(String ficheEleveId) {
    return _listeAvecCache(
      type: _typeRetardsFiche,
      cle: ficheEleveId,
      lire: () => _distant.retardsDeFiche(ficheEleveId),
      versJson: (r) => r.versJsonCache(),
      depuisJson: Retard.depuisJsonCache,
    );
  }

  @override
  Future<List<Sanction>> sanctionsDeFiche(String ficheEleveId) async {
    try {
      final liste = await _distant.sanctionsDeFiche(ficheEleveId);
      await _cache.ecrireDocument(_typeSanctionsFiche, ficheEleveId, {
        'lignes': liste.map((s) => s.versJsonCache()).toList(growable: false),
      });
      return liste;
    } on ErreurVieScolaire {
      final document = await _cache.lireDocument(_typeSanctionsFiche, ficheEleveId);
      if (document == null) rethrow;
      return (document['lignes'] as List<dynamic>)
          .map((l) => Sanction.depuisJson(l as Map<String, dynamic>))
          .toList(growable: false);
    }
  }

  @override
  Future<List<AlerteDecrochage>> alertesDeFiche(String ficheEleveId) async {
    try {
      return await _distant.alertesDeFiche(ficheEleveId);
    } on ErreurVieScolaire {
      // Les alertes sont un signal ponctuel, jamais un état bloquant : pas de
      // repli cache dédié, une liste vide hors ligne est acceptable.
      return const [];
    }
  }

  @override
  Future<List<AlerteDecrochage>> alertesEtablissement(String etablissementId) async {
    try {
      return await _distant.alertesEtablissement(etablissementId);
    } on ErreurVieScolaire {
      return const [];
    }
  }

  @override
  Future<List<EvenementScolaire>> evenementsEtablissement(String etablissementId) {
    return _listeAvecCache(
      type: _typeEvenements,
      cle: etablissementId,
      lire: () => _distant.evenementsEtablissement(etablissementId),
      versJson: (e) => e.versJsonCache(),
      depuisJson: EvenementScolaire.depuisJsonCache,
    );
  }

  @override
  Future<Map<String, dynamic>> analyseComportement(String ficheEleveId, String anneeScolaireId) async {
    final cle = '$ficheEleveId::$anneeScolaireId';
    try {
      final resultat = await _distant.analyseComportement(ficheEleveId, anneeScolaireId);
      await _cache.ecrireDocument(_typeAnalyse, cle, resultat);
      return resultat;
    } on ErreurVieScolaire {
      final document = await _cache.lireDocument(_typeAnalyse, cle);
      if (document == null) rethrow;
      return document;
    }
  }

  @override
  Future<double> scoreDecrochage(String ficheEleveId, String anneeScolaireId) async {
    final cle = '$ficheEleveId::$anneeScolaireId';
    try {
      final score = await _distant.scoreDecrochage(ficheEleveId, anneeScolaireId);
      await _cache.ecrireDocument(_typeScore, cle, {'valeur': score});
      return score;
    } on ErreurVieScolaire {
      final document = await _cache.lireDocument(_typeScore, cle);
      if (document == null) rethrow;
      return (document['valeur'] as num).toDouble();
    }
  }

  @override
  Future<Map<String, dynamic>> recommandationSanction(String ficheEleveId, String anneeScolaireId) {
    // Recommandation ponctuelle consultée en contexte de décision active :
    // pas de repli hors-ligne pertinent (une recommandation vieille de
    // plusieurs jours serait trompeuse pour une décision prise aujourd'hui).
    return _distant.recommandationSanction(ficheEleveId, anneeScolaireId);
  }

  @override
  Future<double> predirePresence(String etablissementId, DateTime date) {
    return _distant.predirePresence(etablissementId, date);
  }

  @override
  Future<bool> saisirPresence(domaine.Presence presence) async {
    try {
      return await _distant.saisirPresence(presence);
    } catch (e) {
      if (e is ErreurVieScolaire && _codesMetierBloquants.contains(e.code)) rethrow;
      await _syncRepo.enfiler(
        SyncEntree(
          id: presence.id,
          entite: 'presences',
          operation: 'upsert',
          payload: jsonEncode(presence.versJsonEcriture()),
        ),
      );
      return false;
    }
  }

  @override
  Future<bool> saisirRetard(Retard retard) async {
    try {
      return await _distant.saisirRetard(retard);
    } catch (e) {
      if (e is ErreurVieScolaire && _codesMetierBloquants.contains(e.code)) rethrow;
      await _syncRepo.enfiler(
        SyncEntree(
          id: retard.id,
          entite: 'retards',
          operation: 'upsert',
          payload: jsonEncode(retard.versJsonEcriture()),
        ),
      );
      return false;
    }
  }

  @override
  Future<Sanction> proposerSanction(Sanction sanction) => _distant.proposerSanction(sanction);

  @override
  Future<void> validerSanction(String sanctionId, {required String valideePar}) =>
      _distant.validerSanction(sanctionId, valideePar: valideePar);

  @override
  Future<void> changerStatutSanction(String sanctionId, String statut) =>
      _distant.changerStatutSanction(sanctionId, statut);

  /// Superpose à [base] les entrées `sync_queue` de [entite] encore en
  /// attente, pour un affichage immédiat des pointages hors-ligne (même
  /// principe que `notesDeEvaluation` en M6).
  Future<List<domaine.Presence>> _fusionnerFileAttente(
    String entite,
    List<domaine.Presence> base,
    String Function(domaine.Presence) cleDe,
    domaine.Presence? Function(Map<String, dynamic>) filtrer,
  ) async {
    final enAttente = await _syncRepo.entreesEnAttente();
    final parCle = {for (final p in base) cleDe(p): p};

    for (final entree in enAttente) {
      if (entree.entite != entite) continue;
      final json = jsonDecode(entree.payload) as Map<String, dynamic>;
      final enCours = filtrer(json);
      if (enCours == null) continue;
      parCle[cleDe(enCours)] = enCours.avecAffichage(parCle[cleDe(enCours)]);
    }

    return parCle.values.toList(growable: false);
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
    } on ErreurVieScolaire {
      final document = await _cache.lireDocument(type, cle);
      if (document == null) rethrow;
      return (document['lignes'] as List<dynamic>)
          .map((l) => depuisJson(l as Map<String, dynamic>))
          .toList(growable: false);
    }
  }
}
