import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/offline/lecture_hors_ligne.dart';
import '../domain/etats_financiers.dart';

/// Implémentation Supabase (REG-03 C4, C5) — RPC uniquement.
///
/// Hors connexion d'abord (C7) : chaque consultation est gardée sur
/// l'appareil et resservie sans réseau ([LectureHorsLigne]).
class SupabaseEtatsFinanciersRepository implements EtatsFinanciersRepository {
  const SupabaseEtatsFinanciersRepository(this._client, [this._lecture]);

  final SupabaseClient _client;
  final LectureHorsLigne? _lecture;

  Future<T> _lire<T>(String type, String cle, Future<Object?> Function() source, T Function(Object? json) decoder) {
    final lecture = _lecture;
    if (lecture == null) return source().then(decoder);
    return lecture.lire(type: type, cle: cle, source: source, decoder: decoder);
  }

  @override
  Future<EtatFinancier> etat(String etablissementId, String exerciceId) => _executer(() => _lire(
        'etat_financier',
        exerciceId,
        () => _client.rpc<Map<String, dynamic>>('etat_financier',
            params: {'p_etablissement': etablissementId, 'p_exercice_id': exerciceId}),
        (json) => EtatFinancier.depuisJson(json! as Map<String, dynamic>),
      ));

  @override
  Future<ApercuPca> apercuPca(String exerciceId) => _executer(() => _lire(
        'apercu_pca',
        exerciceId,
        () => _client.rpc<Map<String, dynamic>>('apercu_produits_constates_avance', params: {'p_exercice_id': exerciceId}),
        (json) => ApercuPca.depuisJson(json! as Map<String, dynamic>),
      ));

  @override
  Future<double> passerPca(String exerciceId) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('passer_produits_constates_avance',
            params: {'p_exercice_id': exerciceId});
        return (json['montant'] as num?)?.toDouble() ?? 0;
      });

  @override
  Future<TableauFlux> fluxTresorerie(String etablissementId, String exerciceId) => _executer(() => _lire(
        'flux_tresorerie',
        exerciceId,
        () => _client.rpc<Map<String, dynamic>>('tableau_flux_tresorerie',
            params: {'p_etablissement': etablissementId, 'p_exercice_id': exerciceId}),
        (json) => TableauFlux.depuisJson(json! as Map<String, dynamic>),
      ));

  @override
  Future<NotesAnnexes> notesAnnexes(String etablissementId, String exerciceId) => _executer(() => _lire(
        'notes_annexes',
        exerciceId,
        () => _client.rpc<Map<String, dynamic>>('notes_annexes',
            params: {'p_etablissement': etablissementId, 'p_exercice_id': exerciceId}),
        (json) => NotesAnnexes.depuisJson(json! as Map<String, dynamic>),
      ));

  @override
  Future<void> enregistrerNote(String exerciceId, String cle, String texte) => _executer(() => _client.rpc<dynamic>(
      'enregistrer_note_annexe',
      params: {'p_exercice_id': exerciceId, 'p_cle': cle, 'p_texte': texte}));

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      throw ErreurEtatsFinanciers(RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier) ? premier : 'ERREUR_RESEAU');
    } catch (e) {
      if (estErreurReseau(e)) throw const ErreurEtatsFinanciers('HORS_CONNEXION');
      rethrow;
    }
  }
}
