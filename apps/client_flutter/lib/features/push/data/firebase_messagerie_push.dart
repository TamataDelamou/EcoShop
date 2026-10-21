import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../domain/messagerie_push.dart';

/// Démarrage de Firebase, une fois, avant l'application.
///
/// Les notifications push ne concernent que les téléphones (Android, iOS) ;
/// sur PC, ou tant que le fichier de configuration Firebase n'a pas été
/// déposé dans le projet, elles restent simplement éteintes : les
/// notifications se lisent toujours dans l'application.
abstract final class InitialisationPush {
  static bool _disponible = false;

  static bool get disponible => _disponible;

  static bool get plateformeCompatible =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static String get plateforme => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  static Future<void> initialiser() async {
    if (!plateformeCompatible) return;
    try {
      // Lecture de la configuration embarquée : aucun accès réseau.
      await Firebase.initializeApp().timeout(const Duration(seconds: 10));
      _disponible = true;
    } catch (e) {
      debugPrint('Notifications push indisponibles : $e');
    }
  }
}

class FirebaseMessageriePush implements MessageriePush {
  FirebaseMessaging get _m => FirebaseMessaging.instance;

  @override
  Future<bool> demanderAutorisation() async {
    final reglages = await _m.requestPermission();
    return reglages.authorizationStatus == AuthorizationStatus.authorized ||
        reglages.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Stream<String> get identifiantEnregistre => _m.onRegistered;

  @override
  Future<void> enregistrer() => _m.register();

  @override
  Future<void> desenregistrer() => _m.unregister();

  @override
  Stream<MessagePush> get messagesPremierPlan => FirebaseMessaging.onMessage.map(_versMessage);

  @override
  Stream<MessagePush> get messagesOuverts => FirebaseMessaging.onMessageOpenedApp.map(_versMessage);

  @override
  Future<MessagePush?> messageInitial() async {
    final message = await _m.getInitialMessage();
    return message == null ? null : _versMessage(message);
  }

  static MessagePush _versMessage(RemoteMessage m) => MessagePush(
        titre: m.notification?.title,
        corps: m.notification?.body,
        donnees: {for (final e in m.data.entries) e.key: '${e.value}'},
      );
}
