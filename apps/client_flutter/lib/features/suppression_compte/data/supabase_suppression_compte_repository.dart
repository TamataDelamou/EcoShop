import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/securite/gardien_actions_sensibles.dart';
import '../domain/suppression_compte.dart';

/// Fonctions `etat_suppression_compte`, `demander_suppression_compte` et
/// `annuler_suppression_compte` (migration 1577). Toujours en ligne : une
/// demande de suppression ne se met pas en file d'attente.
class SupabaseSuppressionCompteRepository implements SuppressionCompteRepository {
  SupabaseSuppressionCompteRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<EtatSuppressionCompte> etat() async {
    final r = await _client.rpc('etat_suppression_compte');
    return EtatSuppressionCompte.depuisJson(Map<String, dynamic>.from(r as Map));
  }

  @override
  Future<ReponseSuppression> demander({String? motif}) => avecCode('Supprimer mon compte', () async {
        final r = await _client.rpc('demander_suppression_compte', params: {'p_motif': motif});
        return ReponseSuppression.depuisJson(Map<String, dynamic>.from(r as Map));
      });

  @override
  Future<bool> annuler() async => (await _client.rpc('annuler_suppression_compte')) == true;
}
