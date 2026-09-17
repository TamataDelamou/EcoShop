import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/cgu_repository.dart';
import '../domain/cgu_statut.dart';

/// Implémentation Supabase du port [CguRepository] (cahier §34.10).
class SupabaseCguRepository implements CguRepository {
  const SupabaseCguRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<CguStatut?> statut() {
    return _executer(() async {
      final lignes = await _client.rpc<List<dynamic>>('cgu_statut');
      if (lignes.isEmpty) return null;
      return CguStatut.depuisJson(lignes.first as Map<String, dynamic>);
    });
  }

  @override
  Future<void> accepter(String cguVersionId) {
    return _executer(() async {
      final utilisateur = _client.auth.currentUser;
      if (utilisateur == null) throw const ErreurCgu('SESSION_ABSENTE');
      await _client.from('cgu_acceptations').insert({
        'profile_id': utilisateur.id,
        'cgu_version_id': cguVersionId,
      });
    });
  }

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw ErreurCgu(_codeDepuisMessage(e.message), e.message);
    }
  }

  static final RegExp _codeMetier = RegExp(r'^[A-Z][A-Z0-9_]{3,}$');

  static String _codeDepuisMessage(String message) {
    final premier = message.trim().split(RegExp(r'\s+')).first;
    return _codeMetier.hasMatch(premier) ? premier : 'ERREUR_RESEAU';
  }
}
