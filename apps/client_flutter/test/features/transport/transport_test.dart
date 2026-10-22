import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/offline/lecture_hors_ligne.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/features/transport/data/supabase_transport_repository.dart';
import 'package:ecoshop_client/features/transport/domain/transport.dart';

const _arrets = [
  ArretTransport(id: 'a1', ordre: 1, nom: 'Kaloum', latitude: 9.5092, longitude: -13.7122),
  ArretTransport(id: 'a2', ordre: 2, nom: 'Dixinn'),
  ArretTransport(id: 'a3', ordre: 3, nom: 'Ratoma'),
];

const _circuit = CircuitTransport(
  id: 'c1',
  nom: 'Circuit 1',
  arrets: _arrets,
  eleves: [
    EleveTransporte(ficheEleveId: 'f-awa', nom: 'BAH', prenom: 'Awa', arretId: 'a2', jeton: 'CARTE-AWA'),
    EleveTransporte(ficheEleveId: 'f-ibra', nom: 'SOW', prenom: 'Ibrahima', arretId: 'a3', jeton: 'CARTE-IBRA'),
  ],
);

void main() {
  group('logique du trajet', () {
    test('ordre des arrêts : aller du premier au dernier, retour à l’envers', () {
      final aller = TrajetLocal(id: 't', circuitId: 'c1', sens: SensTrajet.aller, demarreLe: DateTime(2026));
      expect(aller.prochainArret(_arrets)?.nom, 'Kaloum');
      expect(aller.avec(arretsPasses: ['a1']).prochainArret(_arrets)?.nom, 'Dixinn');
      final retour = TrajetLocal(id: 't', circuitId: 'c1', sens: SensTrajet.retour, demarreLe: DateTime(2026));
      expect(retour.prochainArret(_arrets)?.nom, 'Ratoma');
    });

    test('famille : arrêts restants avant le sien, selon le sens', () {
      const aller = SuiviTransport(affecte: true, arretId: 'a3', arrets: _arrets, trajetSens: SensTrajet.aller, dernierArretOrdre: 1);
      expect(aller.arretsAvantLeMien, 1);
      const retour = SuiviTransport(affecte: true, arretId: 'a1', arrets: _arrets, trajetSens: SensTrajet.retour, dernierArretOrdre: 3);
      expect(retour.arretsAvantLeMien, 1);
      const passe = SuiviTransport(affecte: true, arretId: 'a1', arrets: _arrets, trajetSens: SensTrajet.aller, dernierArretOrdre: 2);
      expect(passe.arretsAvantLeMien, isNull, reason: 'arrêt déjà dépassé');
    });

    test('distance : moins de 120 m = arrêt atteint', () {
      expect(distanceMetres(9.5092, -13.7122, 9.5100, -13.7122), lessThan(rayonArretMetres));
      expect(distanceMetres(9.5092, -13.7122, 9.5200, -13.7122), greaterThan(1000));
    });
  });

  group('chauffeur sans réseau', () {
    late AppDatabase db;
    late DriftSyncRepository file;
    late SupabaseTransportRepository depot;

    setUp(() {
      db = AppDatabase.pourTests(NativeDatabase.memory());
      file = DriftSyncRepository(db);
      final horsLigne = SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        accessToken: () async => 'test-jwt',
        httpClient: MockClient((_) async => throw http.ClientException('Failed host lookup')),
      );
      final store = CacheDocumentStore(db, 'transport_hl');
      depot = SupabaseTransportRepository(horsLigne, file, store, LectureHorsLigne(store, ValueNotifier<DateTime?>(null)));
    });

    tearDown(() => db.close());

    test('trajet complet hors connexion : gardé, repris, scans, enfant resté à bord signalé', () async {
      var trajet = await depot.demarrer(_circuit, SensTrajet.aller);
      expect((await depot.trajetLocal('c1'))?.id, trajet.id, reason: 'le trajet reprend après une coupure');

      trajet = await depot.passerArret(trajet, _arrets[0]);
      var (r, t) = await depot.scanner(trajet: trajet, circuit: _circuit, lecture: 'CARTE-AWA', evenement: EvenementBus.montee);
      expect(r.statut, StatutScanBus.enAttenteEnvoi);
      expect(r.eleve?.prenom, 'Awa');
      trajet = t;

      (r, t) = await depot.scanner(trajet: trajet, circuit: _circuit, lecture: 'CARTE-AWA', evenement: EvenementBus.montee);
      expect(r.statut, StatutScanBus.dejaFait, reason: 'carte présentée deux fois');

      (r, t) = await depot.scanner(trajet: trajet, circuit: _circuit, lecture: 'CARTE-IBRA', evenement: EvenementBus.montee);
      trajet = t;
      (r, t) = await depot.scanner(trajet: trajet, circuit: _circuit, lecture: 'CARTE-AWA', evenement: EvenementBus.descente);
      trajet = t;
      expect(trajet.aBord, ['f-ibra']);

      await depot.signalerPosition(trajet, 9.51, -13.71);
      await depot.signalerPosition(trajet, 9.52, -13.70);

      final restes = await depot.terminer(trajet, _circuit);
      expect(restes.single.prenom, 'Ibrahima', reason: 'vérification faite sur le téléphone, sans réseau');
      expect(await depot.trajetLocal('c1'), isNull);

      final file0 = await file.entreesEnAttente();
      expect(file0.where((e) => e.entite == SupabaseTransportRepository.entitePosition).length, 1,
          reason: 'seule la dernière position attend le réseau');
      final position = jsonDecode(file0.firstWhere((e) => e.entite == SupabaseTransportRepository.entitePosition).payload);
      expect(position['params']['p_latitude'], 9.52);
      expect(file0.first.entite, SupabaseTransportRepository.entiteTrajet, reason: 'le départ est rejoué en premier');
      expect(file0.where((e) => e.entite == SupabaseTransportRepository.entiteMontee).length, 3);
    });
  });
}
