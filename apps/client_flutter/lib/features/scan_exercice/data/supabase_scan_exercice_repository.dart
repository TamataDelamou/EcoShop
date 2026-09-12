import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/scan_exercice_repository.dart';

/// Implémentation Supabase du port [ScanExerciceRepository] (M16,
/// sous-livrable 5/7). N'appelle jamais Anthropic — uniquement l'Edge
/// Function `demarrer_scan_exercice` (`functions.invoke`), même discipline
/// que `SupabaseChatIaRepository`.
class SupabaseScanExerciceRepository implements ScanExerciceRepository {
  const SupabaseScanExerciceRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ReponseScanExercice> demarrerScan({
    required String etablissementId,
    required String ficheEleveId,
    required String texteExtrait,
    required bool consentement,
  }) async {
    try {
      final reponse = await _client.functions.invoke(
        'demarrer_scan_exercice',
        body: {
          'etablissementId': etablissementId,
          'ficheEleveId': ficheEleveId,
          'texteExtrait': texteExtrait,
          'consentement': consentement,
        },
      );
      final corps = reponse.data as Map<String, dynamic>;
      return ReponseScanExercice(
        conversationId: corps['conversationId'] as String,
        matiere: corps['matiere'] as String?,
        chapitre: corps['chapitre'] as String?,
        reply: corps['reply'] as String,
      );
    } on FunctionException catch (e) {
      throw ErreurChatIa(_codeDepuisDetails(e.details), e.reasonPhrase);
    }
  }

  static String _codeDepuisDetails(Object? details) {
    if (details is Map && details['error'] is String) {
      return (details['error'] as String).toUpperCase();
    }
    return 'ERREUR_RESEAU';
  }
}
