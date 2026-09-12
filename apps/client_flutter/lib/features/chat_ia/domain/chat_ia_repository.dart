import 'detail_eleve_pseudonymise.dart';
import 'message_chat_ia.dart';

/// Erreur métier du chat IA, à code stable.
class ErreurChatIa implements Exception {
  const ErreurChatIa(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() => 'ErreurChatIa($code)';
}

/// Résultat d'un tour de chat libre (Edge Function `envoyer_message_ia`).
class ReponseChatIa {
  const ReponseChatIa({
    required this.conversationId,
    required this.reponse,
    this.detailEleves = const [],
  });

  final String conversationId;
  final String reponse;

  /// Non vide seulement si l'IA a appelé l'outil de détail nominatif dans ce
  /// tour (couche 3, direction uniquement) — voir [DetailElevePseudonymise].
  final List<DetailElevePseudonymise> detailEleves;
}

/// Résultat du déclenchement structuré (Edge Function
/// `demarrer_analyse_risque_echec`, couche 1→2).
class ReponseAnalyseRisque {
  const ReponseAnalyseRisque({
    required this.conversationId,
    required this.messageDeclencheur,
    required this.reponse,
    required this.cibleLabel,
    required this.effectif,
    required this.elevesARisque,
  });

  final String conversationId;

  /// Message "user" synthétique — chiffres réels uniquement, jamais un texte
  /// libre client — c'est le CLIENT qui l'écrit dans `ai_messages` (même
  /// division des responsabilités que `envoyer_message_ia`).
  final String messageDeclencheur;
  final String reponse;
  final String cibleLabel;
  final int effectif;
  final int elevesARisque;
}

/// Port du chat IA à rôles (M16, sous-livrable 3/7). Le client Flutter
/// n'appelle JAMAIS l'API Anthropic directement, uniquement ces deux Edge
/// Functions — qui re-vérifient le rôle réel côté serveur
/// (`determiner_role_ia`) et ne font jamais confiance à un rôle envoyé par
/// le client. Volontairement SANS décorateur de cache/file hors-ligne
/// (contrairement à `RapportsRepository`) : un chat IA suppose une
/// connexion active, rien de sensé à mettre en file d'attente hors-ligne.
abstract interface class ChatIaRepository {
  /// Envoie un message dans une conversation libre — crée la conversation si
  /// [conversationId] est nul (auquel cas [etablissementId] est requis).
  Future<ReponseChatIa> envoyerMessage({
    String? conversationId,
    String? etablissementId,
    required String message,
  });

  /// Déclenche l'analyse structurée du risque d'échec — direction
  /// uniquement, jamais à partir d'un texte libre (bouton structuré côté
  /// UI, voir l'en-tête de l'Edge Function correspondante).
  Future<ReponseAnalyseRisque> demarrerAnalyseRisque({
    required String etablissementId,
    required String cibleType,
    String? cibleId,
  });

  /// Persiste un message dans `ai_messages` et renvoie la ligne créée
  /// (id/horodatage réels) — c'est le CLIENT qui écrit, jamais l'Edge
  /// Function (voir son en-tête de fichier).
  Future<MessageChatIa> enregistrerMessage({
    required String conversationId,
    required String sender,
    required String content,
  });
}
