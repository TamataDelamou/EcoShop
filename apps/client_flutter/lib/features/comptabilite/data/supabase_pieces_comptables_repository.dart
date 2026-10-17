import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/pieces_comptables.dart';

/// Implémentation Supabase (REG-03 C2) : lectures sous RLS, toute écriture
/// par RPC (aucun droit d'écriture directe sur les pièces).
class SupabasePiecesComptablesRepository implements PiecesComptablesRepository {
  const SupabasePiecesComptablesRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ExerciceComptable>> exercices(String etablissementId) => _executer(() async {
        final lignes = await _client
            .from('exercices_comptables')
            .select('id, libelle, date_debut, date_fin, statut, cloture_jusqu_au, resultat')
            .eq('etablissement_id', etablissementId)
            .order('date_debut', ascending: false);
        return [for (final l in lignes) ExerciceComptable.depuisJson(l)];
      });

  @override
  Future<String> ouvrirExercice(String etablissementId, DateTime debut, DateTime fin) => _executer(() =>
      _client.rpc<String>('ouvrir_exercice', params: {
        'p_etablissement': etablissementId,
        'p_date_debut': dateIso(debut),
        'p_date_fin': dateIso(fin),
      }));

  @override
  Future<void> cloturerPeriode(String etablissementId, DateTime jusquAu) => _executer(() =>
      _client.rpc<dynamic>('cloturer_periode', params: {
        'p_etablissement': etablissementId,
        'p_jusqu_au': dateIso(jusquAu),
      }));

  @override
  Future<ResultatClotureExercice> cloturerExercice(String exerciceId) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('cloturer_exercice', params: {'p_exercice_id': exerciceId});
        return ResultatClotureExercice(
          resultat: (json['resultat'] as num?)?.toDouble() ?? 0,
          pieceANouveauxId: json['piece_a_nouveaux_id'] as String?,
          exerciceSuivantId: json['exercice_suivant_id'] as String?,
        );
      });

  @override
  Future<List<PieceComptable>> pieces(String etablissementId, String exerciceId) => _executer(() async {
        final lignes = await _client
            .from('pieces_comptables')
            .select('id, exercice_id, journal_id, date_piece, libelle, statut, reference, piece_justificative, '
                'origine, annulee_par_piece_id, piece_annulee_id')
            .eq('etablissement_id', etablissementId)
            .eq('exercice_id', exerciceId)
            .order('date_piece', ascending: false)
            .order('created_at', ascending: false)
            .limit(300);
        return [for (final l in lignes) PieceComptable.depuisJson(l)];
      });

  @override
  Future<PieceComptable> detail(String pieceId) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('piece_comptable_detail', params: {'p_piece_id': pieceId});
        return PieceComptable.depuisJson(json);
      });

  @override
  Future<String> enregistrer(SaisiePiece s) => _executer(() => _client.rpc<String>('enregistrer_piece', params: {
        'p_etablissement': s.etablissementId,
        'p_journal': s.journalId,
        'p_date': dateIso(s.datePiece),
        'p_libelle': s.libelle,
        'p_lignes': [for (final l in s.lignes) l.versJsonSaisie()],
        'p_piece_justificative': s.pieceJustificative,
        'p_piece_id': s.pieceId,
      }));

  @override
  Future<String> valider(String pieceId) =>
      _executer(() => _client.rpc<String>('valider_piece', params: {'p_piece_id': pieceId}));

  @override
  Future<void> supprimerBrouillard(String pieceId) =>
      _executer(() => _client.rpc<dynamic>('supprimer_brouillard', params: {'p_piece_id': pieceId}));

  @override
  Future<String> contrepasser(String pieceId, String motif, DateTime date) =>
      _executer(() => _client.rpc<String>('contrepasser_piece', params: {
            'p_piece_id': pieceId,
            'p_motif': motif,
            'p_date': dateIso(date),
          }));

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      throw ErreurPiecesComptables(RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier) ? premier : 'ERREUR_RESEAU');
    }
  }
}
