import 'dart:async';

import 'package:ecoshop_client/core/offline/client_avec_delai.dart';
import 'package:ecoshop_client/core/offline/lecture_hors_ligne.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('serveur muet : la requête échoue au délai, reconnue comme panne de réseau', () async {
    final muet = MockClient((_) => Completer<http.Response>().future);
    final client = ClientAvecDelai(muet, delai: const Duration(milliseconds: 50));

    final erreur = await client.get(Uri.parse('https://exemple.supabase.co/rest/v1/profiles')).then<Object?>(
          (_) => null,
          onError: (Object e) => e,
        );

    expect(erreur, isA<TimeoutException>());
    expect(estErreurReseau(erreur!), isTrue);
  });

  test('serveur qui répond : réponse transmise telle quelle', () async {
    final client = ClientAvecDelai(MockClient((_) async => http.Response('[]', 200)));
    final reponse = await client.get(Uri.parse('https://exemple.supabase.co/rest/v1/profiles'));
    expect(reponse.statusCode, 200);
    expect(reponse.body, '[]');
  });

  test('envoi volumineux (photo) : pas de délai', () async {
    final lent = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return http.Response('ok', 200);
    });
    final client = ClientAvecDelai(lent, delai: const Duration(milliseconds: 50));
    final reponse = await client.post(
      Uri.parse('https://exemple.supabase.co/storage/v1/object/logos/a.png'),
      body: List<int>.filled(200 * 1024, 0),
    );
    expect(reponse.statusCode, 200);
  });
}
