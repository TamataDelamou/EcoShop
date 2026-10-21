import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/communication/application/comm_providers.dart';
import 'package:ecoshop_client/features/communication/domain/notif.dart';
import 'package:ecoshop_client/features/push/application/push_providers.dart';
import 'package:ecoshop_client/features/push/application/service_push.dart';
import 'package:ecoshop_client/features/push/domain/messagerie_push.dart';
import 'package:ecoshop_client/features/push/presentation/ecouteur_push.dart';

const _fid = 'cAbCdEfGhIjKlMnOpQrS_-';

class _FausseMessagerie implements MessageriePush {
  final identifiants = StreamController<String>.broadcast();
  final premierPlan = StreamController<MessagePush>.broadcast();
  final ouverts = StreamController<MessagePush>.broadcast();
  MessagePush? initial;
  bool reseau = true;
  int inscriptions = 0;
  int desinscriptions = 0;

  @override
  Future<bool> demanderAutorisation() async => true;

  @override
  Stream<String> get identifiantEnregistre => identifiants.stream;

  @override
  Future<void> enregistrer() async {
    inscriptions++;
    if (!reseau) throw Exception('hors connexion');
    identifiants.add(_fid);
  }

  @override
  Future<void> desenregistrer() async => desinscriptions++;

  @override
  Stream<MessagePush> get messagesPremierPlan => premierPlan.stream;

  @override
  Stream<MessagePush> get messagesOuverts => ouverts.stream;

  @override
  Future<MessagePush?> messageInitial() async => initial;
}

/// Mémoire de l'appareil gardée en RAM (tests d'écran, sans base locale).
class _MemoireVive extends CacheDocumentStore {
  _MemoireVive(AppDatabase db) : super(db, 'push');

  final _documents = <String, ({Map<String, dynamic> document, DateTime misAJourLe})>{};

  @override
  Future<void> ecrireDocument(String type, String cle, Map<String, dynamic> document) async =>
      _documents['$type/$cle'] = (document: document, misAJourLe: DateTime.now());

  @override
  Future<({Map<String, dynamic> document, DateTime misAJourLe})?> lireDocumentDate(String type, String cle) async =>
      _documents['$type/$cle'];

  @override
  Future<Map<String, dynamic>?> lireDocument(String type, String cle) async => _documents['$type/$cle']?.document;

  @override
  Future<void> supprimerDocument(String type, String cle) async => _documents.remove('$type/$cle');
}

void main() {
  late AppDatabase db;
  late _FausseMessagerie messagerie;
  late List<String> appelsServeur;
  late bool serveurJoignable;
  late DateTime horloge;

  ServicePush service({bool memoireVive = false}) => ServicePush(
        messagerie: messagerie,
        memoire: memoireVive ? _MemoireVive(db) : CacheDocumentStore(db, 'push'),
        plateforme: 'android',
        maintenant: () => horloge,
        enregistrer: (id, plateforme) async {
          if (!serveurJoignable) throw Exception('réseau');
          appelsServeur.add('enregistrer $id $plateforme');
        },
        retirer: (id) async {
          if (!serveurJoignable) throw Exception('réseau');
          appelsServeur.add('retirer $id');
        },
      );

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    messagerie = _FausseMessagerie();
    appelsServeur = [];
    serveurJoignable = true;
    horloge = DateTime.now();
  });

  tearDown(() => db.close());

  group('rattachement du téléphone au compte', () {
    test('une seule fois par semaine pour le même compte', () async {
      final s = service();
      expect(await s.rattacher('p1', _fid), isTrue);
      expect(await s.rattacher('p1', _fid), isTrue);
      expect(appelsServeur, ['enregistrer $_fid android']);

      horloge = horloge.add(const Duration(days: 8));
      await s.rattacher('p1', _fid);
      expect(appelsServeur, hasLength(2), reason: 'renouvelé chaque semaine (date de dernier contact)');
    });

    test('changement de compte sur le même téléphone : rattaché au nouveau', () async {
      final s = service();
      await s.rattacher('p1', _fid);
      await s.rattacher('p2', _fid);
      expect(appelsServeur, hasLength(2));
    });

    test('sans réseau : rien n\'est retenu, retenté ensuite', () async {
      final s = service();
      serveurJoignable = false;
      expect(await s.rattacher('p1', _fid), isFalse);
      serveurJoignable = true;
      expect(await s.rattacher('p1', _fid), isTrue);
      expect(appelsServeur, ['enregistrer $_fid android']);
    });

    test('déconnexion : serveur prévenu, téléphone désinscrit, rattachement oublié', () async {
      final s = service();
      await s.rattacher('p1', _fid);
      await s.detacher();
      expect(appelsServeur.last, 'retirer $_fid');
      expect(messagerie.desinscriptions, 1);
      await s.rattacher('p1', _fid);
      expect(appelsServeur.last, 'enregistrer $_fid android', reason: 'reconnexion : rattaché à nouveau');
    });

    test('déconnexion sans réseau : le téléphone est quand même désinscrit', () async {
      final s = service();
      await s.rattacher('p1', _fid);
      serveurJoignable = false;
      await s.detacher();
      expect(messagerie.desinscriptions, 1);
    });
  });

  group('écouteur dans l\'application', () {
    Future<void> monter(WidgetTester tester, {bool enLigne = true}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            messageriePushProvider.overrideWithValue(messagerie),
            servicePushProvider.overrideWithValue(service(memoireVive: true)),
            estEnLigneProvider.overrideWithValue(enLigne),
            mesNotificationsProvider.overrideWith((ref, profil) async => const <Notif>[]),
          ],
          child: const MaterialApp(home: Scaffold(body: EcouteurPush(profilId: 'p1'))),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('à l\'ouverture du compte : téléphone inscrit puis rattaché', (tester) async {
      await monter(tester);
      expect(messagerie.inscriptions, 1);
      expect(appelsServeur, ['enregistrer $_fid android']);
    });

    testWidgets('application ouverte : bandeau avec « Voir » qui ouvre la boîte', (tester) async {
      await monter(tester);
      messagerie.premierPlan.add(const MessagePush(
        titre: 'Arrivée à l\'école',
        corps: 'Awa est arrivée à 7h42',
        donnees: {'type': 'pointage_arrivee', 'notification_id': 'n1'},
      ));
      // Le bandeau ne réagit au toucher qu'une fois entièrement apparu.
      await tester.pumpAndSettle();
      expect(find.text('Arrivée à l\'école'), findsOneWidget);
      expect(find.text('Awa est arrivée à 7h42'), findsOneWidget);

      await tester.tap(find.text('Voir'));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
    });

    testWidgets('notification touchée dans la barre : boîte ouverte une seule fois', (tester) async {
      await monter(tester);
      const m = MessagePush(donnees: {'type': 'alerte_absence', 'notification_id': 'n2'});
      messagerie.ouverts
        ..add(m)
        ..add(m);
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
    });

    testWidgets('lancée par une notification : la boîte s\'ouvre au démarrage', (tester) async {
      messagerie.initial = const MessagePush(donnees: {'type': 'relance_impaye', 'notification_id': 'n3'});
      await monter(tester);
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
    });
  });
}
