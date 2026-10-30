import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/core/sync/entites_differees.dart';
import 'package:ecoshop_client/core/sync/journal_rejets.dart';
import 'package:ecoshop_client/core/sync/sync_engine.dart';
import 'package:ecoshop_client/core/sync/sync_providers.dart';
import 'package:ecoshop_client/features/coquille/application/amorcage_controller.dart';
import 'package:ecoshop_client/features/coquille/application/sync_composition.dart';
import 'package:ecoshop_client/features/coquille/presentation/ecran_etat_synchronisation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// REG-35 lot 5 — écran « État de la synchronisation » et Wi-Fi seulement.
void main() {
  group('affichage', () {
    final maintenant = DateTime(2026, 10, 30, 17, 0);
    test('âge des données en mots simples', () {
      expect(ageLisible(maintenant, maintenant: maintenant), 'à l’instant');
      expect(ageLisible(maintenant.subtract(const Duration(minutes: 5)), maintenant: maintenant), 'il y a 5 min');
      expect(ageLisible(maintenant.subtract(const Duration(hours: 2)), maintenant: maintenant), 'il y a 2 h');
      expect(ageLisible(DateTime(2026, 10, 28, 9), maintenant: maintenant), 'le 28/10');
    });

    test('place occupée lisible', () {
      expect(tailleLisible(850 * 1024), '850 Ko');
      expect(tailleLisible((12.4 * 1024 * 1024).round()), '12,4 Mo');
    });

    test('chaque opération connue a un libellé lisible', () {
      for (final entite in ['notes', 'presences', 'conges', ...EntitesDifferees.toutes]) {
        final entree = SyncEntree(id: 'x', entite: entite, operation: 'update', payload: jsonEncode({'id': 'x'}));
        expect(libelleOperation(entree), isNot('Opération'), reason: entite);
      }
    });
  });

  group('Wi-Fi seulement', () {
    test('désactivé : toute connexion convient', () {
      expect(peutAmorcerSur([ConnectivityResult.mobile], wifiSeulement: false), isTrue);
    });
    test('activé : Wi-Fi ou Ethernet, jamais les données mobiles', () {
      expect(peutAmorcerSur([ConnectivityResult.mobile], wifiSeulement: true), isFalse);
      expect(peutAmorcerSur([ConnectivityResult.wifi], wifiSeulement: true), isTrue);
      expect(peutAmorcerSur([ConnectivityResult.ethernet], wifiSeulement: true), isTrue);
    });
    test('connexion inconnue : on ne bloque pas', () {
      expect(peutAmorcerSur(null, wifiSeulement: true), isTrue);
    });
  });

  group('écran', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.pourTests(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> ouvrir(WidgetTester tester) async {
      final file = DriftSyncRepository(db);
      await tester.runAsync(() async {
        await file.enfiler(SyncEntree(
          id: 'conge_decision:c1',
          entite: EntitesDifferees.congeDecision,
          operation: 'update',
          payload: jsonEncode({'id': 'c1', 'statut': 'valide'}),
        ));
        await CacheDocumentStore(db, 'notes').ecrireDocument('notes_fiche', 'f1', {'note': 17});
      });
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          syncRepositoryProvider.overrideWithValue(file),
          journalRejetsProvider.overrideWithValue(JournalRejets(CacheDocumentStore(db, 'sync_rejets'), file)),
          suiviSyncProvider.overrideWith((ref) => Stream.value((enAttente: 1, rejetees: 0))),
          estEnLigneProvider.overrideWithValue(false),
          derniereAmorcageProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: EcranEtatSynchronisation()),
      ));
      // Lectures de la base (vraies, hors horloge simulée) puis affichage.
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
    }

    /// La liste ne construit que ce qui est à l'écran : on y va d'abord.
    Future<void> allerA(WidgetTester tester, Finder cible) =>
        tester.scrollUntilVisible(cible, 150, scrollable: find.byType(Scrollable).first);

    testWidgets('hors connexion : saisies gardées, envoi listé en clair, bouton indisponible', (tester) async {
      await ouvrir(tester);
      expect(find.textContaining('Hors connexion'), findsOneWidget);
      final bouton = tester.widget<FilledButton>(find.byKey(const Key('bouton_synchroniser')));
      expect(bouton.onPressed, isNull);
      await allerA(tester, find.text('Décision sur un congé'));
      expect(find.textContaining('part au retour du réseau'), findsOneWidget);
      await allerA(tester, find.byKey(const Key('refus_vides')));
      expect(find.byKey(const Key('refus_vides')), findsOneWidget);
    });

    testWidgets('l\'option Wi-Fi seulement se garde', (tester) async {
      await ouvrir(tester);
      final interrupteur = find.byKey(const Key('interrupteur_wifi_seulement'));
      await allerA(tester, interrupteur);
      await tester.ensureVisible(interrupteur);
      await tester.pump();
      await tester.tap(find.descendant(of: interrupteur, matching: find.byType(Switch)));
      // Écriture dans la base (vraie, hors horloge simulée).
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
      expect(tester.widget<SwitchListTile>(interrupteur).value, isTrue);
      final doc = await tester.runAsync(
          () => CacheDocumentStore(db, 'preferences').lireDocument('amorcage_wifi_seulement', 'appareil'));
      expect(doc, {'actif': true});
    });
  });
}
