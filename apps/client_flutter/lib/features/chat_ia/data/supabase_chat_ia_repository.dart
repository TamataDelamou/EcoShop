import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/chat_ia_repository.dart';
import '../domain/detail_eleve_pseudonymise.dart';
import '../domain/message_chat_ia.dart';

/// Implémentation Supabase du port [ChatIaRepository] (M16, sous-livrable
/// 3/7). N'appelle jamais Anthropic — uniquement les deux Edge Functions
/// (`functions.invoke`, seul point d'entrée IA autorisé côté client) et les
/// tables `ai_conversations`/`ai_messages` via PostgREST, RLS appliquée
/// normalement (JWT de l'utilisateur, jamais de clé service_role côté
/// client — cohérent avec `_shared/supabase_client.ts` côté Edge Function).
class SupabaseChatIaRepository implements ChatIaRepository {
  const SupabaseChatIaRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<String> obtenirConversationLibre(String etablissementId) {
    return _executer(() async {
      final id = await _client.rpc<String>(
        'obtenir_conversation_libre',
        params: {'p_etablissement_id': etablissementId},
      );
      return id;
    });
  }

  @override
  Future<List<MessageChatIa>> historique(String conversationId) {
    return _executer(() async {
      final lignes = await _client
          .from('ai_messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at');
      return lignes
          .map((l) => MessageChatIa.depuisJson(l))
          .toList(growable: false);
    });
  }

  @override
  Future<ReponseChatIa> envoyerMessage({
    String? conversationId,
    String? etablissementId,
    required String message,
  }) {
    return _executer(() async {
      final reponse = await _client.functions.invoke(
        'envoyer_message_ia',
        body: {
          if (conversationId != null) 'conversationId': conversationId,
          if (etablissementId != null) 'etablissementId': etablissementId,
          'message': message,
        },
      );
      final corps = reponse.data as Map<String, dynamic>;
      return ReponseChatIa(
        conversationId: corps['conversationId'] as String,
        reponse: corps['reply'] as String,
        detailEleves: DetailElevePseudonymise.depuisMapping(
          corps['mappingPseudonymes'] as Map<String, dynamic>?,
        ),
      );
    });
  }

  @override
  Future<ReponseAnalyseRisque> demarrerAnalyseRisque({
    required String etablissementId,
    required String cibleType,
    String? cibleId,
  }) {
    return _executer(() async {
      final reponse = await _client.functions.invoke(
        'demarrer_analyse_risque_echec',
        body: {
          'etablissementId': etablissementId,
          'cibleType': cibleType,
          if (cibleId != null) 'cibleId': cibleId,
        },
      );
      final corps = reponse.data as Map<String, dynamic>;
      final cibleLabel = corps['cibleLabel'] as String;
      final effectif = (corps['effectif'] as num).toInt();
      final elevesARisque = (corps['elevesARisque'] as num).toInt();
      return ReponseAnalyseRisque(
        conversationId: corps['conversationId'] as String,
        // Même texte que le message synthétique construit côté serveur
        // (voir `demarrer_analyse_risque_echec/index.ts`) — reconstruit ici
        // pour l'écrire dans `ai_messages` puisque l'Edge Function ne
        // l'écrit jamais elle-même.
        messageDeclencheur:
            "Analyse du risque d'échec pour $cibleLabel. "
            "Effectif : $effectif. "
            "Élèves à risque d'échec (score de risque ≥ 0,6) : $elevesARisque.",
        reponse: corps['reply'] as String,
        cibleLabel: cibleLabel,
        effectif: effectif,
        elevesARisque: elevesARisque,
      );
    });
  }

  @override
  Future<MessageChatIa> enregistrerMessage({
    required String conversationId,
    required String sender,
    required String content,
  }) {
    return _executer(() async {
      final ligne = await _client
          .from('ai_messages')
          .insert({
            'conversation_id': conversationId,
            'sender': sender,
            'content': content,
          })
          .select()
          .single();
      return MessageChatIa.depuisJson(ligne);
    });
  }

  static Future<T> _executer<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FunctionException catch (e) {
      throw ErreurChatIa(_codeDepuisDetails(e.details), e.reasonPhrase);
    } on PostgrestException catch (e) {
      throw ErreurChatIa(_codeDepuisMessage(e.message), e.message);
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
