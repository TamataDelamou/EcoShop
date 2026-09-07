import 'dart:convert';

import '../../../core/db/cache_document_store.dart';
import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/appreciation.dart';
import '../domain/bulletin.dart';
import '../domain/evaluation.dart';
import '../domain/note.dart';
import '../domain/notes_repository.dart';

/// Décore un [NotesRepository] réseau avec un repli SQLite/Drift, et rend
/// [saisirNote] utilisable hors connexion via la file `sync_queue`.
///
/// Lecture : même politique que M4/M5 (réseau d'abord, cache en secours).
/// Écriture : [saisirNote] tente d'abord le réseau. Un échec de nature
/// réseau (timeout, absence de connectivité, code non reconnu) enfile la
/// note pour rejeu ultérieur ; un rejet **métier** authentique (barème
/// dépassé, élève non inscrit…) est en revanche remonté tel quel — le
/// mettre en file l'exposerait à un échec silencieux et permanent (contrat
/// M06 §5-6, codes `NOTE_SUP_BAREME`/`ELEVE_NON_INSCRIT`/…).
class CachedNotesRepository implements NotesRepository {
  const CachedNotesRepository(this._distant, this._cache, this._syncRepo);

  final NotesRepository _distant;
  final CacheDocumentStore _cache;
  final DriftSyncRepository _syncRepo;

  static const _typeEvaluationsClasse = 'evaluations_classe';
  static const _typeNotesEvaluation = 'notes_evaluation';
  static const _typeNotesFiche = 'notes_fiche';
  static const _typeMoyenneEleve = 'moyenne_eleve';
  static const _typeMoyenneClasse = 'moyenne_classe';
  static const _typeAppreciations = 'appreciations_fiche';
  static const _typeBulletins = 'bulletins_fiche';

  /// Codes métier authentiques des triggers M6 — jamais mis en file, toujours
  /// remontés immédiatement à l'appelant.
  static const _codesMetierBloquants = {
    'NOTE_SUP_BAREME',
    'ELEVE_NON_INSCRIT',
    'EVALUATION_INTROUVABLE',
    'EVALUATION_AUTRE_ETABLISSEMENT',
    'ENSEIGNANT_NON_MEMBRE',
  };

  @override
  Future<List<Evaluation>> evaluationsDeClasse(String classeId, {String? periodeId}) {
    return _listeAvecCache(
      type: _typeEvaluationsClasse,
      cle: '$classeId::${periodeId ?? 'toutes'}',
      lire: () => _distant.evaluationsDeClasse(classeId, periodeId: periodeId),
      versJson: (e) => e.versJsonCache(),
      depuisJson: Evaluation.depuisJsonCache,
    );
  }

  @override
  Future<List<Note>> notesDeEvaluation(String evaluationId) async {
    final base = await _listeAvecCache(
      type: _typeNotesEvaluation,
      cle: evaluationId,
      lire: () => _distant.notesDeEvaluation(evaluationId),
      versJson: (n) => n.versJson(),
      depuisJson: Note.depuisJsonCache,
    );
    return _fusionnerFileAttente(evaluationId, base);
  }

  @override
  Future<List<Note>> notesDeFiche(String ficheEleveId, {String? periodeId}) {
    return _listeAvecCache(
      type: _typeNotesFiche,
      cle: '$ficheEleveId::${periodeId ?? 'toutes'}',
      lire: () => _distant.notesDeFiche(ficheEleveId, periodeId: periodeId),
      versJson: (n) => n.versJson(),
      depuisJson: Note.depuisJsonCache,
    );
  }

  @override
  Future<double?> moyenneEleve(
    String ficheEleveId, {
    String? programmeMatiereId,
    String? periodeId,
  }) async {
    final cle = '$ficheEleveId::${programmeMatiereId ?? '-'}::${periodeId ?? '-'}';
    try {
      final moyenne = await _distant.moyenneEleve(
        ficheEleveId,
        programmeMatiereId: programmeMatiereId,
        periodeId: periodeId,
      );
      await _cache.ecrireDocument(_typeMoyenneEleve, cle, {'valeur': moyenne});
      return moyenne;
    } on ErreurNotes {
      final document = await _cache.lireDocument(_typeMoyenneEleve, cle);
      if (document == null) rethrow;
      return (document['valeur'] as num?)?.toDouble();
    }
  }

  @override
  Future<double?> moyenneClasse(
    String classeId, {
    String? programmeMatiereId,
    String? periodeId,
  }) async {
    final cle = '$classeId::${programmeMatiereId ?? '-'}::${periodeId ?? '-'}';
    try {
      final moyenne = await _distant.moyenneClasse(
        classeId,
        programmeMatiereId: programmeMatiereId,
        periodeId: periodeId,
      );
      await _cache.ecrireDocument(_typeMoyenneClasse, cle, {'valeur': moyenne});
      return moyenne;
    } on ErreurNotes {
      final document = await _cache.lireDocument(_typeMoyenneClasse, cle);
      if (document == null) rethrow;
      return (document['valeur'] as num?)?.toDouble();
    }
  }

  @override
  Future<List<Appreciation>> appreciationsDeFiche(String ficheEleveId, {String? periodeId}) async {
    final cle = '$ficheEleveId::${periodeId ?? 'toutes'}';
    try {
      final liste = await _distant.appreciationsDeFiche(ficheEleveId, periodeId: periodeId);
      await _cache.ecrireDocument(_typeAppreciations, cle, {
        'lignes': liste
            .map((a) => {
                  'id': a.id,
                  'etablissement_id': a.etablissementId,
                  'fiche_eleve_id': a.ficheEleveId,
                  'annee_scolaire_id': a.anneeScolaireId,
                  'periode_id': a.periodeId,
                  'programme_matiere_id': a.programmeMatiereId,
                  'type': a.type.code,
                  'texte': a.texte,
                  'ton': a.ton?.code,
                  'points_forts': a.pointsForts,
                  'points_faibles': a.pointsFaibles,
                  'redige_par': a.redigePar,
                  'programmes_matieres': a.nomMatiere == null ? null : {'nom': a.nomMatiere},
                })
            .toList(growable: false),
      });
      return liste;
    } on ErreurNotes {
      final document = await _cache.lireDocument(_typeAppreciations, cle);
      if (document == null) rethrow;
      return (document['lignes'] as List<dynamic>)
          .map((l) => Appreciation.depuisJson(l as Map<String, dynamic>))
          .toList(growable: false);
    }
  }

  @override
  Future<List<Bulletin>> bulletinsDeFiche(String ficheEleveId) {
    return _listeAvecCache(
      type: _typeBulletins,
      cle: ficheEleveId,
      lire: () => _distant.bulletinsDeFiche(ficheEleveId),
      versJson: (b) => b.versJsonCache(),
      depuisJson: Bulletin.depuisJson,
    );
  }

  @override
  Future<Evaluation> creerEvaluation(Evaluation evaluation) => _distant.creerEvaluation(evaluation);

  @override
  Future<void> publierEvaluation(String evaluationId) => _distant.publierEvaluation(evaluationId);

  @override
  Future<bool> saisirNote(Note note) async {
    try {
      return await _distant.saisirNote(note);
    } catch (e) {
      if (e is ErreurNotes && _codesMetierBloquants.contains(e.code)) rethrow;
      await _syncRepo.enfiler(
        SyncEntree(id: note.id, entite: 'notes', operation: 'upsert', payload: jsonEncode(note.versJsonEcriture())),
      );
      return false;
    }
  }

  /// Superpose aux notes déjà connues les saisies encore en attente de
  /// synchronisation pour cette évaluation (grille de l'enseignant).
  Future<List<Note>> _fusionnerFileAttente(String evaluationId, List<Note> base) async {
    final enAttente = await _syncRepo.entreesEnAttente();
    final parFiche = {for (final n in base) n.ficheEleveId: n};

    for (final entree in enAttente) {
      if (entree.entite != 'notes') continue;
      final json = jsonDecode(entree.payload) as Map<String, dynamic>;
      if (json['evaluation_id'] != evaluationId) continue;

      final enCours = Note.depuisJsonEcriture(json);
      parFiche[enCours.ficheEleveId] = enCours.avecAffichage(parFiche[enCours.ficheEleveId]);
    }

    return parFiche.values.toList(growable: false);
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
    } on ErreurNotes {
      final document = await _cache.lireDocument(type, cle);
      if (document == null) rethrow;
      return (document['lignes'] as List<dynamic>)
          .map((l) => depuisJson(l as Map<String, dynamic>))
          .toList(growable: false);
    }
  }
}
