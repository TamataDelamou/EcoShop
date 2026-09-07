import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../domain/paquet_referentiel.dart';
import '../domain/referentiel_repository.dart';

/// Télécharge et vérifie un [PaquetReferentiel] avant toute mise en cache.
///
/// Contrat M04 §5 : « le client vérifie l'empreinte avant mise en cache
/// locale ». Un paquet dont le SHA-256 ne correspond pas est rejeté sans être
/// exploité — protège contre une troncature réseau ou une corruption côté CDN.
///
/// NB (constat d'audit) : le schéma `paquets_referentiel` décrit le
/// *transport* (url, taille, empreinte) mais pas le *format* du contenu
/// téléchargé. Ce service rend donc les octets vérifiés à l'appelant ; le
/// point d'ingestion (parser → [ReferentielCacheStore]) doit être branché une
/// fois le format de sérialisation du paquet confirmé côté back-office.
class TelechargementPaquetService {
  /// [_client] : injecté en test ; sinon un client éphémère est créé et fermé
  /// à chaque appel de [telecharger].
  const TelechargementPaquetService([this._client]);

  final http.Client? _client;

  /// Télécharge [paquet.url] et vérifie son empreinte SHA-256.
  ///
  /// Lève [ErreurReferentiel] avec le code `PAQUET_SANS_URL` ou
  /// `PAQUET_INTEGRITE_INVALIDE` en cas d'échec.
  Future<Uint8List> telecharger(PaquetReferentiel paquet) async {
    final url = paquet.url;
    if (url == null || url.isEmpty) {
      throw const ErreurReferentiel('PAQUET_SANS_URL');
    }

    final client = _client ?? http.Client();
    try {
      final reponse = await client.get(Uri.parse(url));
      if (reponse.statusCode != 200) {
        throw ErreurReferentiel(
          'PAQUET_TELECHARGEMENT_ECHOUE',
          'HTTP ${reponse.statusCode}',
        );
      }

      final octets = reponse.bodyBytes;
      final empreinte = sha256.convert(octets).toString();
      if (empreinte != paquet.empreinteSha256.toLowerCase()) {
        throw const ErreurReferentiel('PAQUET_INTEGRITE_INVALIDE');
      }

      return octets;
    } finally {
      if (_client == null) client.close();
    }
  }
}

/// Décodage utilitaire d'un paquet supposé JSON UTF-8 (format provisoire —
/// voir la note d'audit sur [TelechargementPaquetService]).
Map<String, dynamic> decoderPaquetJson(Uint8List octets) {
  return jsonDecode(utf8.decode(octets)) as Map<String, dynamic>;
}
