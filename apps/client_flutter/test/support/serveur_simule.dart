import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// État du réseau entre le téléphone et le serveur simulé (REG-35, lot 6).
///
/// Inspiré des « 2G Tuesdays » de Facebook (travailler une journée sur un
/// réseau 2G) et de Toxiproxy (Shopify) : latence, coupure franche, coupure
/// au milieu d'une série d'échanges.
enum Reseau {
  /// Réponses immédiates.
  normal,

  /// Réponses retardées de [ServeurSimule.latence] (réseau 2G saturé).
  lent,

  /// Aucune réponse : mode avion, données coupées.
  coupe,
}

/// Serveur Supabase simulé, en mémoire : lectures PostgREST filtrées par
/// `eq`, insertions (avec contrôle de la clé primaire), upserts, mises à
/// jour, suppressions et fonctions (`rpc`). Assez fidèle pour faire tourner
/// les vrais dépôts de l'application, sans réseau.
class ServeurSimule {
  Reseau reseau = Reseau.normal;
  Duration latence = const Duration(seconds: 5);

  /// Coupe le réseau après ce nombre de requêtes (coupure en cours
  /// d'amorçage) ; null : jamais.
  int? coupureApres;

  /// Table → lignes.
  final tables = <String, List<Map<String, dynamic>>>{};

  /// Fonctions serveur : nom → réponse selon le corps reçu.
  final fonctions = <String, Object? Function(Map<String, dynamic> corps)>{};

  /// Requêtes reçues (« GET inscriptions », « POST rpc/mes_annonces »…).
  final journal = <String>[];

  /// Écritures appliquées par le serveur dont la réponse se perd en route
  /// (coupure juste après l'envoi) : le téléphone croit à un échec.
  int reponsesPerdues = 0;

  int _requetes = 0;

  List<Map<String, dynamic>> table(String nom) => tables.putIfAbsent(nom, () => []);

  /// Client Supabase relié à ce serveur, connecté en tant que [compte].
  Future<SupabaseClient> client({required String compte}) async {
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit),
      httpClient: MockClient(_repondre),
    );
    await client.auth.recoverSession(jsonEncode(_session(compte)));
    return client;
  }

  Future<http.Response> _repondre(http.Request requete) async {
    final reponse = await _traiter(requete);
    if (requete.method != 'GET' && reponsesPerdues > 0) {
      reponsesPerdues--;
      throw http.ClientException('Connection closed while receiving data');
    }
    return reponse;
  }

  Future<http.Response> _traiter(http.Request requete) async {
    _requetes++;
    final limite = coupureApres;
    if (limite != null && _requetes > limite) reseau = Reseau.coupe;
    if (reseau == Reseau.coupe) throw http.ClientException('Network is unreachable');
    if (reseau == Reseau.lent) await Future<void>.delayed(latence);

    final segments = requete.url.pathSegments;
    final estRpc = segments.length >= 2 && segments[segments.length - 2] == 'rpc';
    final nom = segments.last;
    journal.add('${requete.method} ${estRpc ? 'rpc/' : ''}$nom');

    http.Response json(Object? corps, [int statut = 200]) => http.Response(jsonEncode(corps), statut,
        headers: {'content-type': 'application/json; charset=utf-8'}, request: requete);

    if (estRpc) {
      final corps = requete.body.isEmpty ? <String, dynamic>{} : (jsonDecode(requete.body) as Map).cast<String, dynamic>();
      final f = fonctions[nom];
      return json(f == null ? <Object>[] : f(corps));
    }

    final lignes = table(nom);
    final filtres = <String, String>{
      for (final e in requete.url.queryParameters.entries)
        if (e.value.startsWith('eq.')) e.key: e.value.substring(3),
    };
    bool correspond(Map<String, dynamic> l) => filtres.entries.every((f) => '${l[f.key]}' == f.value);
    final objet = (requete.headers['accept'] ?? '').contains('vnd.pgrst.object');
    final representation = (requete.headers['prefer'] ?? '').contains('return=representation');

    switch (requete.method) {
      case 'GET':
        final trouvees = lignes.where(correspond).toList();
        if (objet) {
          if (trouvees.isEmpty) {
            return json({'code': 'PGRST116', 'message': 'JSON object requested, multiple (or no) rows returned', 'details': 'The result contains 0 rows', 'hint': null}, 406);
          }
          return json(trouvees.first);
        }
        return json(trouvees);
      case 'POST':
        final brut = jsonDecode(requete.body);
        final nouvelles = [
          for (final l in (brut is List ? brut : [brut])) (l as Map).cast<String, dynamic>(),
        ];
        final conflit = requete.url.queryParameters['on_conflict']?.split(',');
        for (final n in nouvelles) {
          n['id'] ??= 'srv-${lignes.length + 1}';
          final existante = lignes.where((l) => conflit == null
              ? l['id'] == n['id']
              : conflit.every((c) => l[c] == n[c])).firstOrNull;
          if (existante != null) {
            if (conflit == null) {
              return json({'code': '23505', 'message': 'duplicate key value violates unique constraint', 'details': null, 'hint': null}, 409);
            }
            existante.addAll(n);
          } else {
            lignes.add(n);
          }
        }
        if (!representation) return http.Response('', 201, request: requete);
        return objet ? json(nouvelles.first, 201) : json(nouvelles, 201);
      case 'PATCH':
        final valeurs = (jsonDecode(requete.body) as Map).cast<String, dynamic>();
        final dans = <String, List<String>>{
          for (final e in requete.url.queryParameters.entries)
            if (e.value.startsWith('in.(')) e.key: e.value.substring(4, e.value.length - 1).replaceAll('"', '').split(','),
        };
        final modifiees = <Map<String, dynamic>>[];
        for (final l in lignes.where(correspond)) {
          if (dans.entries.any((d) => !d.value.contains('${l[d.key]}'))) continue;
          l.addAll(valeurs);
          modifiees.add(l);
        }
        if (!representation) return http.Response('', 204, request: requete);
        return json(modifiees);
      case 'DELETE':
        lignes.removeWhere(correspond);
        return http.Response('', 204, request: requete);
    }
    return json({'message': 'non simulé'}, 400);
  }

  /// Session de test valide pour longtemps (aucun appel au serveur
  /// d'authentification).
  static Map<String, dynamic> _session(String compte) {
    String b64(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final expire = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
    final jeton = '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64({'sub': compte, 'exp': expire, 'role': 'authenticated'})}.signature';
    return {
      'access_token': jeton,
      'token_type': 'bearer',
      'expires_in': 2592000,
      'expires_at': expire,
      'refresh_token': 'rafraichissement-$compte',
      'user': {
        'id': compte,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': '$compte@exemple.gn',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-10-01T00:00:00Z',
      },
    };
  }
}
