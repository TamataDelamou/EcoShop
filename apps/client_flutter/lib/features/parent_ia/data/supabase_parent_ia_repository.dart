import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/parent_ia_config.dart';
import '../domain/parent_ia_repository.dart';
import '../domain/restriction_parent_ia.dart';

/// Implémentation Supabase du port [ParentIaRepository] (M16, sous-livrable
/// 4/7). Toute écriture passe par une fonction `SECURITY DEFINER`
/// (`.rpc(...)`) — jamais un `.insert()`/`.update()` direct sur
/// `parent_ia_config`/`parent_ia_historique`, qui n'ont aucune policy
/// d'écriture cliente (voir la migration).
class SupabaseParentIaRepository implements ParentIaRepository {
  const SupabaseParentIaRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ParentIaConfig> configuration(String ficheEleveId) {
    return _executer(() async {
      final ligne = await _client
          .from('parent_ia_config')
          .select()
          .eq('fiche_eleve_id', ficheEleveId)
          .maybeSingle();
      return ligne == null
          ? ParentIaConfig.inactif()
          : ParentIaConfig.depuisJson(ligne);
    });
  }

  @override
  Future<List<RestrictionParentIa>> historique(String ficheEleveId) {
    return _executer(() async {
      final lignes = await _client
          .from('parent_ia_historique')
          .select()
          .eq('fiche_eleve_id', ficheEleveId)
          .order('created_at', ascending: false);
      return lignes
          .map((l) => RestrictionParentIa.depuisJson(l))
          .toList(growable: false);
    });
  }

  @override
  Future<ParentIaConfig> activer({
    required String ficheEleveId,
    required bool consentement,
  }) {
    return _executer(() async {
      await _client.rpc(
        'activer_parent_ia',
        params: {
          'p_fiche_eleve_id': ficheEleveId,
          'p_consentement': consentement,
        },
      );
      return configuration(ficheEleveId);
    });
  }

  @override
  Future<ParentIaConfig> desactiver(String ficheEleveId) {
    return _executer(() async {
      await _client.rpc(
        'desactiver_parent_ia',
        params: {'p_fiche_eleve_id': ficheEleveId},
      );
      return configuration(ficheEleveId);
    });
  }

  @override
  Future<bool> declarerUsage({
    required String ficheEleveId,
    required String appPrincipale,
    required int minutes,
  }) {
    return _executer(() async {
      final reponse = await _client.functions.invoke(
        'analyser_usage_parent_ia',
        body: {
          'ficheEleveId': ficheEleveId,
          'appPrincipale': appPrincipale,
          'minutes': minutes,
        },
      );
      final corps = reponse.data as Map<String, dynamic>;
      return corps['restrictionDeclenchee'] as bool? ?? false;
    });
  }

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FunctionException catch (e) {
      throw ErreurParentIa(_codeDepuisDetails(e.details), e.reasonPhrase);
    } on PostgrestException catch (e) {
      throw ErreurParentIa(_codeDepuisMessage(e.message), e.message);
    }
  }

  static String _codeDepuisDetails(Object? details) {
    if (details is Map && details['error'] is String) {
      return (details['error'] as String).toUpperCase();
    }
    return 'ERREUR_RESEAU';
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_RESEAU';
  }
}
