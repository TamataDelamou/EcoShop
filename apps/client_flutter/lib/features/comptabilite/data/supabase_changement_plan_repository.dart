import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/changement_plan.dart';
import '../domain/referentiel_comptable.dart';

/// Implémentation Supabase (REG-03 C6) — RPC uniquement.
class SupabaseChangementPlanRepository implements ChangementPlanRepository {
  const SupabaseChangementPlanRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ChangementPlan> proposer(String etablissementId, ReferentielComptable cible, FormeJuridique? forme) =>
      _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('proposer_changement_plan', params: {
          'p_etablissement': etablissementId,
          'p_referentiel': cible.code,
          'p_forme_juridique': forme?.code,
        });
        return ChangementPlan.depuisJson(json);
      });

  @override
  Future<ChangementPlan> definir(String changementId, String ancienCompteId, String? codeCible) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('definir_correspondance', params: {
          'p_changement_id': changementId,
          'p_ancien_compte_id': ancienCompteId,
          'p_code_cible': codeCible,
        });
        return ChangementPlan.depuisJson(json);
      });

  @override
  Future<ResultatChangementPlan> appliquer(String changementId) => _executer(() async {
        final json = await _client.rpc<Map<String, dynamic>>('appliquer_changement_plan',
            params: {'p_changement_id': changementId});
        return ResultatChangementPlan.depuisJson(json);
      });

  @override
  Future<void> abandonner(String changementId) =>
      _executer(() => _client.rpc<dynamic>('abandonner_changement_plan', params: {'p_changement_id': changementId}));

  @override
  Future<List<CompteCible>> comptesCibles(ReferentielComptable referentiel) => _executer(() async {
        final lignes = await _client.rpc<List<dynamic>>('comptes_cibles', params: {'p_referentiel': referentiel.code});
        return [for (final l in lignes) CompteCible.depuisJson(l as Map<String, dynamic>)];
      });

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      throw ErreurChangementPlan(RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier) ? premier : 'ERREUR_RESEAU');
    }
  }
}
