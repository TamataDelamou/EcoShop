import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../db/cache_document_store.dart';

/// Vrai pour une panne de réseau (pas de connexion, serveur injoignable,
/// délai dépassé) — par opposition à un refus du serveur, qui reste une
/// réponse à afficher telle quelle.
bool estErreurReseau(Object e) =>
    e is http.ClientException ||
    e is TimeoutException ||
    e.runtimeType.toString() == 'SocketException' ||
    e.toString().contains('SocketException') ||
    e.toString().contains('Failed host lookup');

/// Lecture « réseau d'abord, appareil ensuite » des écrans de consultation.
///
/// Chaque réponse du serveur est gardée telle quelle (JSON) sur l'appareil ;
/// sans réseau, la dernière réponse est servie et [fraicheur] dit de quand
/// elle date (affiché par le bandeau de synchronisation). Aucune conversion
/// spécifique à écrire : on garde la réponse brute et on la relit avec le
/// même décodeur qu'en ligne.
class LectureHorsLigne {
  LectureHorsLigne(this._store, this.fraicheur);

  final CacheDocumentStore _store;

  /// Date des données affichées quand elles viennent de l'appareil ; `null`
  /// quand elles viennent du serveur.
  final ValueNotifier<DateTime?> fraicheur;

  Future<T> lire<T>({
    required String type,
    required String cle,
    required Future<Object?> Function() source,
    required T Function(Object? json) decoder,
  }) async {
    Object? json;
    try {
      json = await source();
    } catch (e) {
      if (!estErreurReseau(e)) rethrow;
      final lu = await _lireCache(type, cle);
      if (lu == null) rethrow;
      final actuelle = fraicheur.value;
      fraicheur.value = actuelle == null || lu.misAJourLe.isBefore(actuelle) ? lu.misAJourLe : actuelle;
      return decoder(lu.document['json']);
    }
    try {
      await _store.ecrireDocument(type, cle, {'json': json});
    } catch (_) {
      // Le cache est un plus : son échec ne doit jamais bloquer l'écran.
    }
    fraicheur.value = null;
    return decoder(json);
  }

  Future<({Map<String, dynamic> document, DateTime misAJourLe})?> _lireCache(String type, String cle) async {
    try {
      return await _store.lireDocumentDate(type, cle);
    } catch (_) {
      return null;
    }
  }

  /// Purge à la déconnexion (données personnelles des donateurs, comptes).
  Future<void> purger() => _store.purgerTout();
}
