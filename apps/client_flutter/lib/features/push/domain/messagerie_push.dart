/// Notification reçue du service push (Firebase Cloud Messaging).
///
/// `donnees` reprend ce que la fonction serveur `envoyer_push` joint à
/// chaque envoi : `type` (`pointage_arrivee`, `alerte_absence`,
/// `relance_impaye`, `inscription_…`), `notification_id`, puis les
/// variables du message.
class MessagePush {
  const MessagePush({this.titre, this.corps, this.donnees = const {}});

  final String? titre;
  final String? corps;
  final Map<String, String> donnees;

  String? get type => donnees['type'];
  String? get notificationId => donnees['notification_id'];
}

/// Accès au service push du téléphone. Séparé de Firebase pour que la
/// logique de rattachement soit testable sans téléphone.
///
/// Le téléphone est désigné par son identifiant d'installation Firebase
/// (FID), qui remplace depuis 2026 les anciens « jetons » d'appareil.
abstract interface class MessageriePush {
  /// Demande à l'utilisateur d'autoriser les notifications (Android 13+,
  /// iOS). `true` si elles sont autorisées.
  Future<bool> demanderAutorisation();

  /// Identifiant du téléphone, émis à chaque [enregistrer], au démarrage
  /// et quand il change.
  Stream<String> get identifiantEnregistre;

  /// Inscrit le téléphone au service push ; l'identifiant arrive par
  /// [identifiantEnregistre] (à écouter avant l'appel).
  Future<void> enregistrer();

  /// Le téléphone ne reçoit plus rien (déconnexion).
  Future<void> desenregistrer();

  /// Reçues pendant que l'application est ouverte à l'écran.
  Stream<MessagePush> get messagesPremierPlan;

  /// Touchées dans la barre de notifications, application en arrière-plan.
  Stream<MessagePush> get messagesOuverts;

  /// Touchée dans la barre de notifications alors que l'application était
  /// fermée : c'est elle qui l'a lancée.
  Future<MessagePush?> messageInitial();
}
