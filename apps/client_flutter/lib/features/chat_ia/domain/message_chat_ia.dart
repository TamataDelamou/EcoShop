/// Un message de conversation IA (`ai_messages`, M16). Écrit par le CLIENT
/// après chaque tour — ni `envoyer_message_ia` ni
/// `demarrer_analyse_risque_echec` n'écrivent elles-mêmes dans cette table
/// (voir l'en-tête de ces deux Edge Functions) : c'est délibéré, pour que
/// l'écriture passe toujours par la policy RLS `ai_messages_insert_auteur`.
class MessageChatIa {
  const MessageChatIa({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.content,
    required this.createdAt,
  });

  factory MessageChatIa.depuisJson(Map<String, dynamic> json) => MessageChatIa(
        id: json['id'] as String,
        conversationId: json['conversation_id'] as String,
        sender: json['sender'] as String,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id;
  final String conversationId;

  /// 'user' ou 'assistant' (contrainte `ai_messages_sender_check`).
  final String sender;
  final String content;
  final DateTime createdAt;

  bool get estAssistant => sender == 'assistant';
}
