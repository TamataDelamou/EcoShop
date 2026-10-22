import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/sync/sync_engine.dart';
import '../application/connexion_controller.dart' show messageErreurAuth;

/// Renvoi du numéro de téléphone saisi sans réseau (REG-16).
class RejeuTelephone {
  const RejeuTelephone(this._client);

  final SupabaseClient _client;

  static const entite = 'telephone_profil';

  static SyncEntree entree(String id, String telephone) => SyncEntree(
        id: id,
        entite: entite,
        operation: 'rpc',
        payload: jsonEncode({
          'rpc': 'declarer_mon_telephone',
          'params': {'p_telephone': telephone},
        }),
      );

  Future<void> rejouer(SyncEntree entree) async {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    try {
      await _client.rpc<dynamic>(p['rpc'] as String, params: (p['params'] as Map).cast<String, dynamic>());
    } on PostgrestException catch (e) {
      final premier = e.message.trim().split(RegExp(r'\s+')).first;
      if (RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(premier)) {
        throw RejetDefinitif(premier, messageErreurAuth(premier));
      }
      rethrow;
    }
  }

  static String libelle(SyncEntree entree) {
    final p = jsonDecode(entree.payload) as Map<String, dynamic>;
    return 'Numéro de téléphone ${(p['params'] as Map)['p_telephone']}';
  }
}
