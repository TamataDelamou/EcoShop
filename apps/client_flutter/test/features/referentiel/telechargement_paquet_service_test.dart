import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ecoshop_client/features/referentiel/data/telechargement_paquet_service.dart';
import 'package:ecoshop_client/features/referentiel/domain/paquet_referentiel.dart';
import 'package:ecoshop_client/features/referentiel/domain/referentiel_repository.dart';

PaquetReferentiel _paquet({required String empreinte, String? url}) {
  return PaquetReferentiel(
    id: 'p1',
    paysCode: 'GN',
    version: 1,
    empreinteSha256: empreinte,
    tailleOctets: 4,
    url: url ?? 'https://cdn.example/paquet.json',
  );
}

void main() {
  group('TelechargementPaquetService.telecharger', () {
    test('accepte un paquet dont l\'empreinte correspond', () async {
      final octets = utf8.encode('{"ok":true}');
      final empreinte = sha256.convert(octets).toString();
      final client = MockClient((_) async => http.Response.bytes(octets, 200));
      final service = TelechargementPaquetService(client);

      final resultat = await service.telecharger(_paquet(empreinte: empreinte));

      expect(resultat, octets);
    });

    test('rejette un paquet dont l\'empreinte ne correspond pas', () async {
      final octets = utf8.encode('{"ok":true}');
      final client = MockClient((_) async => http.Response.bytes(octets, 200));
      final service = TelechargementPaquetService(client);

      await expectLater(
        service.telecharger(_paquet(empreinte: 'a' * 64)),
        throwsA(
          isA<ErreurReferentiel>()
              .having((e) => e.code, 'code', 'PAQUET_INTEGRITE_INVALIDE'),
        ),
      );
    });

    test('rejette un paquet sans url', () async {
      final service = const TelechargementPaquetService();

      await expectLater(
        service.telecharger(_paquet(empreinte: 'a' * 64, url: '')),
        throwsA(
          isA<ErreurReferentiel>().having((e) => e.code, 'code', 'PAQUET_SANS_URL'),
        ),
      );
    });

    test('rejette une réponse HTTP en erreur', () async {
      final client = MockClient((_) async => http.Response('erreur', 500));
      final service = TelechargementPaquetService(client);

      await expectLater(
        service.telecharger(_paquet(empreinte: 'a' * 64)),
        throwsA(
          isA<ErreurReferentiel>()
              .having((e) => e.code, 'code', 'PAQUET_TELECHARGEMENT_ECHOUE'),
        ),
      );
    });
  });
}
