import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/comptabilisation_automatique.dart';

/// Implémentation Supabase (REG-03 C3) — RPC uniquement.
class SupabaseComptabilisationAutomatiqueRepository implements ComptabilisationAutomatiqueRepository {
  const SupabaseComptabilisationAutomatiqueRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<EtatComptabilisationAutomatique> etat(String etablissementId) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('etat_comptabilisation_automatique',
            params: {'p_etablissement': etablissementId});
        return EtatComptabilisationAutomatique.depuisJson(json);
      });

  @override
  Future<({int comptabilises, int enEchec})> rattraper(String etablissementId) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('comptabiliser_en_attente',
            params: {'p_etablissement': etablissementId});
        return (
          comptabilises: (json['comptabilises'] as num?)?.toInt() ?? 0,
          enEchec: (json['en_echec'] as num?)?.toInt() ?? 0,
        );
      });

  @override
  Future<void> definirRegle(String etablissementId, String cle, String? compteId) => _executer(() =>
      _client.rpc<dynamic>('definir_regle_comptabilisation', params: {
        'p_etablissement': etablissementId,
        'p_cle': cle,
        'p_compte_id': compteId,
      }));

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      throw ErreurComptabilisationAutomatique(
          RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier) ? premier : 'ERREUR_RESEAU');
    }
  }
}
