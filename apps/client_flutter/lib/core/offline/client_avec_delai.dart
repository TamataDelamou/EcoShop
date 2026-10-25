import 'dart:async';

import 'package:http/http.dart' as http;

/// Client HTTP de Supabase avec un délai maximum par requête.
///
/// Sans lui, une requête vers un serveur injoignable (Wi-Fi sans Internet,
/// réseau mobile saturé) peut attendre plusieurs dizaines de secondes avant
/// d'échouer — renouvellement du jeton compris, qui passe aussi par ce
/// client. Le délai lève une [TimeoutException], reconnue comme une panne
/// de réseau (`estErreurReseau`).
///
/// Les envois volumineux (photo, logo, pièce jointe) n'ont pas de délai :
/// sur un réseau lent, ils prennent légitimement plus longtemps.
class ClientAvecDelai extends http.BaseClient {
  ClientAvecDelai(this._interne, {this.delai = const Duration(seconds: 20)});

  final http.Client _interne;
  final Duration delai;

  static const _envoiVolumineux = 100 * 1024;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final envoi = _interne.send(request);
    if ((request.contentLength ?? 0) > _envoiVolumineux) return envoi;
    return envoi.timeout(
      delai,
      onTimeout: () => throw TimeoutException('Le serveur ne répond pas (${request.url.host})', delai),
    );
  }

  @override
  void close() => _interne.close();
}
