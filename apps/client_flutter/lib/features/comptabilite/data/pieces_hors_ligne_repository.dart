import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/sync/drift_sync_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/pieces_comptables.dart';
import 'supabase_pieces_comptables_repository.dart';

/// Pièces comptables d'abord hors connexion (REG-03 C7).
///
/// Un brouillard se prépare sans réseau : il part en file sous une clé
/// générée par l'appareil (renvoyé modifié, il remplace la version en
/// attente). La VALIDATION, qui attribue le numéro continu exigé par l'Acte
/// uniforme (art. 66), se fait avec le réseau ; tout comme les clôtures et
/// les contre-passations.
class PiecesHorsLigneRepository implements PiecesComptablesRepository {
  PiecesHorsLigneRepository(this._distant, this._file);

  final PiecesComptablesRepository _distant;
  final DriftSyncRepository _file;
  final Uuid _uuid = const Uuid();

  static const entite = 'pieces_brouillard';
  static const referenceEnAttente = 'En attente d\'envoi';

  static bool _horsLigne(Object e) => e is ErreurPiecesComptables && e.code == 'HORS_CONNEXION';

  Future<List<Map<String, dynamic>>> _enAttente() async => [
        for (final e in await _file.entreesEnAttente())
          if (e.entite == entite) jsonDecode(e.payload) as Map<String, dynamic>,
      ];

  static PieceComptable _versPiece(Map<String, dynamic> p, String exerciceId) => PieceComptable(
        id: p['p_id'] as String,
        exerciceId: exerciceId,
        journalId: p['p_journal'] as String,
        datePiece: DateTime.parse(p['p_date'] as String),
        libelle: p['p_libelle'] as String,
        statut: StatutPiece.brouillard,
        reference: referenceEnAttente,
        pieceJustificative: p['p_piece_justificative'] as String?,
        lignes: [
          for (final l in (p['p_lignes'] as List<dynamic>))
            LignePiece(
              compteId: (l as Map<String, dynamic>)['compte_id'] as String,
              libelle: l['libelle'] as String?,
              debit: (l['debit'] as num?)?.toDouble() ?? 0,
              credit: (l['credit'] as num?)?.toDouble() ?? 0,
            ),
        ],
      );

  @override
  Future<String> enregistrer(SaisiePiece saisie) async {
    try {
      return await _distant.enregistrer(saisie);
    } on ErreurPiecesComptables catch (e) {
      if (!_horsLigne(e)) rethrow;
    }
    final id = saisie.pieceId ?? _uuid.v4();
    await _file.enfiler(SyncEntree(
      id: id,
      entite: entite,
      operation: 'upsert',
      payload: jsonEncode(SupabasePiecesComptablesRepository.parametresHorsLigne(id, saisie)),
    ));
    return id;
  }

  @override
  Future<String> valider(String pieceId) async {
    try {
      return await _distant.valider(pieceId);
    } on ErreurPiecesComptables catch (e) {
      if (_horsLigne(e)) throw const ErreurPiecesComptables('VALIDATION_EN_LIGNE');
      rethrow;
    }
  }

  @override
  Future<List<PieceComptable>> pieces(String etablissementId, String exerciceId) async {
    List<PieceComptable> base;
    try {
      base = await _distant.pieces(etablissementId, exerciceId);
    } on ErreurPiecesComptables catch (e) {
      if (!_horsLigne(e)) rethrow;
      base = const [];
    }
    final attente = await _enAttente();
    if (attente.isEmpty) return base;
    ExerciceComptable? exercice;
    try {
      exercice = (await _distant.exercices(etablissementId)).where((x) => x.id == exerciceId).firstOrNull;
    } catch (_) {
      exercice = null;
    }
    final locales = [
      for (final p in attente)
        if (p['p_etablissement'] == etablissementId &&
            (exercice == null || exercice.contient(DateTime.parse(p['p_date'] as String))))
          _versPiece(p, exerciceId),
    ];
    return [
      ...locales,
      // Version en attente d'envoi prioritaire sur l'ancienne version connue.
      for (final p in base) if (!locales.any((l) => l.id == p.id)) p,
    ]..sort((a, b) => b.datePiece.compareTo(a.datePiece));
  }

  @override
  Future<PieceComptable> detail(String pieceId) async {
    for (final p in await _enAttente()) {
      if (p['p_id'] == pieceId) return _versPiece(p, '');
    }
    return _distant.detail(pieceId);
  }

  @override
  Future<List<ExerciceComptable>> exercices(String etablissementId) => _distant.exercices(etablissementId);

  @override
  Future<String> ouvrirExercice(String etablissementId, DateTime debut, DateTime fin) =>
      _distant.ouvrirExercice(etablissementId, debut, fin);

  @override
  Future<void> cloturerPeriode(String etablissementId, DateTime jusquAu) => _distant.cloturerPeriode(etablissementId, jusquAu);

  @override
  Future<ResultatClotureExercice> cloturerExercice(String exerciceId) => _distant.cloturerExercice(exerciceId);

  @override
  Future<void> supprimerBrouillard(String pieceId) async {
    final locale = (await _enAttente()).any((p) => p['p_id'] == pieceId);
    if (locale) {
      // Jamais parti : on le retire simplement de la file.
      await _file.retirer(pieceId);
      return;
    }
    await _distant.supprimerBrouillard(pieceId);
  }

  @override
  Future<String> contrepasser(String pieceId, String motif, DateTime date) => _distant.contrepasser(pieceId, motif, date);
}
