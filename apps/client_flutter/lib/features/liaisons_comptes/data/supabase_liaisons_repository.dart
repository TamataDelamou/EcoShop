import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/liaison_compte.dart';

/// Implémentation Supabase de [LiaisonsRepository] (REG-18, partie E). Tout
/// passe par des RPC `SECURITY DEFINER` qui vérifient elles-mêmes que
/// l'appelant gère les liaisons de l'école.
class SupabaseLiaisonsRepository implements LiaisonsRepository {
  const SupabaseLiaisonsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<LiaisonCompte>> liaisons(String etablissementId, {int jours = 30}) => _executer(() async {
        final lignes = await _client.rpc<List<dynamic>>('liaisons_comptes', params: {
          'p_etablissement': etablissementId,
          'p_jours': jours,
        });
        return [for (final l in lignes) LiaisonCompte.depuisJson((l as Map).cast<String, dynamic>())];
      });

  @override
  Future<StatutLiaison> decider(String relationId, {required bool accepter}) => _executer(() async {
        final statut = await _client.rpc<String>('decider_liaison_parent', params: {
          'p_relation': relationId,
          'p_accepter': accepter,
        });
        return StatutLiaison.depuisCode(statut);
      });

  @override
  Future<void> revoquer(LiaisonCompte liaison) => _executer(() async {
        if (liaison.nature == NatureLiaison.eleve) {
          await _client.rpc<void>('revoquer_liaison_eleve', params: {'p_fiche': liaison.ficheEleveId});
        } else {
          await _client.rpc<void>('revoquer_liaison_parent', params: {'p_relation': liaison.liaisonId});
        }
      });

  @override
  Future<int> plafond(String etablissementId) => _executer(() async {
        final n = await _client.rpc<int>('plafond_parents', params: {'p_etablissement': etablissementId});
        return n;
      });

  @override
  Future<int> definirPlafond(String etablissementId, int plafond) => _executer(() async {
        final n = await _client.rpc<int>('definir_plafond_parents', params: {
          'p_etablissement': etablissementId,
          'p_plafond': plafond,
        });
        return n;
      });

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw ErreurLiaisons(_codeDepuisMessage(e.message), e.message);
    } on AuthException catch (e) {
      throw ErreurLiaisons('AUTH_REQUISE', e.message);
    } catch (e) {
      if (e is ErreurLiaisons) rethrow;
      throw ErreurLiaisons('ERREUR_RESEAU', '$e');
    }
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_RESEAU';
  }
}
