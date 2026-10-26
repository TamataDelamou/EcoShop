import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Refus du serveur qui concernent la session entière (REG-22) :
/// - [sessionRevoquee] : cet appareil a été déconnecté (depuis un autre
///   appareil, ou « Ce n'est pas moi ») → déconnexion et effacement ;
/// - [appareilAVerifier] : nouvel appareil pas encore vérifié → étape
///   « Code de votre compte ».
enum RefusSession { sessionRevoquee, appareilAVerifier }

/// Client HTTP de Supabase qui repère ces refus, quelle que soit la requête
/// (tables, fonctions, fichiers), et les annonce sur [refus].
///
/// Seules les réponses 401/403 sont lues (petites) ; leur contenu est rendu
/// intact à l'appelant.
class SurveillanceSession extends http.BaseClient {
  SurveillanceSession(this._interne);

  final http.Client _interne;

  static final _refus = StreamController<RefusSession>.broadcast();

  /// Refus constatés, pour toute l'application.
  static Stream<RefusSession> get refus => _refus.stream;

  /// Pour les tests.
  static void annoncer(RefusSession r) => _refus.add(r);

  static RefusSession? reconnaitre(int statut, String corps) {
    if (statut != 401 && statut != 403) return null;
    if (corps.contains('SESSION_REVOQUEE')) return RefusSession.sessionRevoquee;
    if (corps.contains('APPAREIL_A_VERIFIER')) return RefusSession.appareilAVerifier;
    return null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final reponse = await _interne.send(request);
    if (reponse.statusCode != 401 && reponse.statusCode != 403) return reponse;
    final octets = await reponse.stream.toBytes();
    final r = reconnaitre(reponse.statusCode, utf8.decode(octets, allowMalformed: true));
    if (r != null) _refus.add(r);
    return http.StreamedResponse(
      http.ByteStream.fromBytes(octets),
      reponse.statusCode,
      contentLength: octets.length,
      request: reponse.request,
      headers: reponse.headers,
      isRedirect: reponse.isRedirect,
      persistentConnection: reponse.persistentConnection,
      reasonPhrase: reponse.reasonPhrase,
    );
  }

  @override
  void close() => _interne.close();
}
