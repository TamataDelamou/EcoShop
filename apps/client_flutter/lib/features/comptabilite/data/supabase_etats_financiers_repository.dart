import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/etats_financiers.dart';

/// Implémentation Supabase (REG-03 C4, C5) — RPC uniquement.
class SupabaseEtatsFinanciersRepository implements EtatsFinanciersRepository {
  const SupabaseEtatsFinanciersRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<EtatFinancier> etat(String etablissementId, String exerciceId) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('etat_financier',
            params: {'p_etablissement': etablissementId, 'p_exercice_id': exerciceId});
        return EtatFinancier.depuisJson(json);
      });

  @override
  Future<ApercuPca> apercuPca(String exerciceId) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('apercu_produits_constates_avance',
            params: {'p_exercice_id': exerciceId});
        return ApercuPca.depuisJson(json);
      });

  @override
  Future<double> passerPca(String exerciceId) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('passer_produits_constates_avance',
            params: {'p_exercice_id': exerciceId});
        return (json['montant'] as num?)?.toDouble() ?? 0;
      });

  @override
  Future<TableauFlux> fluxTresorerie(String etablissementId, String exerciceId) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('tableau_flux_tresorerie',
            params: {'p_etablissement': etablissementId, 'p_exercice_id': exerciceId});
        return TableauFlux.depuisJson(json);
      });

  @override
  Future<NotesAnnexes> notesAnnexes(String etablissementId, String exerciceId) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('notes_annexes',
            params: {'p_etablissement': etablissementId, 'p_exercice_id': exerciceId});
        return NotesAnnexes.depuisJson(json);
      });

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
    }
  }
}
