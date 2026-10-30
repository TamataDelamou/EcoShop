import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/offline/lecture_hors_ligne.dart';
import 'package:ecoshop_client/core/offline/lecture_patiente.dart';
import 'package:ecoshop_client/core/offline/liste_avec_cache.dart';

/// Lot 1 hors connexion — « appareil d'abord » : un serveur lent ne fait
/// plus attendre un écran qui a déjà une copie sur le téléphone.
void main() {
  const patience = Duration(milliseconds: 50);

  group('lireAvecPatience', () {
    late Map<String, int> gardees;
    late int actualisations;

    setUp(() {
      gardees = {};
      actualisations = 0;
    });

    Future<ResultatLecture<int>> lire(
      Future<int> Function() serveur, {
      CopieAppareil<int>? copie,
    }) =>
        lireAvecPatience<int>(
          serveur: serveur,
          appareil: () async => copie,
          garder: (v) async => gardees['x'] = v,
          estPanne: estErreurReseau,
          patience: patience,
          apresActualisation: () => actualisations++,
        );

    final copie = (valeur: 1, date: DateTime(2026, 10, 29, 8));

    test('serveur rapide : réponse fraîche, gardée', () async {
      final r = await lire(() async => 7, copie: copie);
      expect(r.valeur, 7);
      expect(r.depuisAppareil, isNull);
      expect(gardees['x'], 7);
      expect(actualisations, 0);
    });

    test('serveur lent avec copie : copie tout de suite, réponse gardée ensuite', () async {
      final reponse = Completer<int>();
      final chrono = Stopwatch()..start();
      final r = await lire(() => reponse.future, copie: copie);
      chrono.stop();

      expect(r.valeur, 1);
      expect(r.depuisAppareil, copie.date);
      expect(chrono.elapsed, lessThan(const Duration(seconds: 1)));
      expect(gardees, isEmpty);

      reponse.complete(9);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(gardees['x'], 9, reason: 'la réponse tardive sert à la prochaine ouverture');
      expect(actualisations, 1);
    });

    test('serveur lent sans copie : on attend le serveur', () async {
      final reponse = Completer<int>();
      final lecture = lire(() => reponse.future);
      await Future<void>.delayed(patience * 3);
      reponse.complete(5);
      final r = await lecture;
      expect(r.valeur, 5);
      expect(r.depuisAppareil, isNull);
      expect(gardees['x'], 5);
    });

    test('serveur lent puis en panne, sans copie : la panne remonte', () async {
      final reponse = Completer<int>();
      final lecture = lire(() => reponse.future);
      await Future<void>.delayed(patience * 3);
      reponse.completeError(http.ClientException('Connection reset'));
      await expectLater(lecture, throwsA(isA<http.ClientException>()));
    });

    test('serveur en panne : copie servie', () async {
      final r = await lire(() => Future.error(http.ClientException('Failed host lookup')), copie: copie);
      expect(r.valeur, 1);
      expect(r.depuisAppareil, copie.date);
    });

    test('serveur en panne sans copie : la panne remonte', () async {
      await expectLater(
        lire(() => Future.error(TimeoutException('délai'))),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('refus du serveur : jamais masqué par la copie', () async {
      await expectLater(
        lire(() => Future.error(StateError('DROITS_RETIRES')), copie: copie),
        throwsA(isA<StateError>()),
      );
    });

    test('exception levée avant le premier await : même traitement', () async {
      final r = await lire(() => throw http.ClientException('Network is unreachable'), copie: copie);
      expect(r.valeur, 1);
    });

    test('réponse tardive en erreur après la copie : aucune erreur non traitée', () async {
      final reponse = Completer<int>();
      final r = await lire(() => reponse.future, copie: copie);
      expect(r.valeur, 1);
      reponse.completeError(StateError('refus tardif'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(gardees, isEmpty);
      expect(actualisations, 0);
    });

    test('échec de la garde locale : la lecture réussit quand même', () async {
      final r = await lireAvecPatience<int>(
        serveur: () async => 3,
        appareil: () async => null,
        garder: (_) => Future.error(StateError('disque plein')),
        estPanne: estErreurReseau,
        patience: patience,
      );
      expect(r.valeur, 3);
    });

    test('copie illisible : traitée comme absente', () async {
      await expectLater(
        lireAvecPatience<int>(
          serveur: () => Future.error(http.ClientException('x')),
          appareil: () => Future.error(StateError('base corrompue')),
          garder: (_) async {},
          estPanne: estErreurReseau,
          patience: patience,
        ),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  group('LectureHorsLigne et lireListeAvecCache', () {
    late AppDatabase db;
    late CacheDocumentStore store;
    late ValueNotifier<DateTime?> fraicheur;
    late LectureHorsLigne lecture;

    setUp(() {
      db = AppDatabase.pourTests(NativeDatabase.memory());
      store = CacheDocumentStore(db, 'essai_hl');
      fraicheur = ValueNotifier<DateTime?>(null);
      lecture = LectureHorsLigne(store, fraicheur);
    });

    tearDown(() async {
      fraicheur.dispose();
      await db.close();
    });

    Future<int> lireTotal(Future<Object?> Function() source) => lecture.lire(
          type: 'etat',
          cle: 'k',
          source: source,
          decoder: (json) => ((json! as Map<String, dynamic>)['total'] as num).toInt(),
          patience: patience,
        );

    test('réseau lent : copie affichée avec sa date, puis remplacée à la lecture suivante', () async {
      expect(await lireTotal(() async => {'total': 42}), 42);
      expect(fraicheur.value, isNull);

      final lente = Completer<Object?>();
      expect(await lireTotal(() => lente.future), 42);
      expect(fraicheur.value, isNotNull, reason: 'le bandeau dit de quand datent les données');

      lente.complete({'total': 60});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Serveur de nouveau lent : la copie servie est désormais la réponse tardive.
      expect(await lireTotal(() => Completer<Object?>().future), 60);

      // Serveur rapide : données fraîches, bandeau retiré.
      expect(await lireTotal(() async => {'total': 61}), 61);
      expect(fraicheur.value, isNull);
    });

    test('liste des anciens modules : même format de copie, même règle', () async {
      Future<List<String>> lireNoms(Future<List<String>> Function() serveur) => lireListeAvecCache<String>(
            cache: store,
            type: 'noms',
            cle: 'classe-1',
            lire: serveur,
            versJson: (n) => {'nom': n},
            depuisJson: (j) => j['nom'] as String,
            estPanne: (e) => e is StateError,
            patience: patience,
          );

      expect(await lireNoms(() async => ['Awa', 'Moussa']), ['Awa', 'Moussa']);
      final doc = await store.lireDocument('noms', 'classe-1');
      expect(doc!['lignes'], [
        {'nom': 'Awa'},
        {'nom': 'Moussa'},
      ]);

      expect(await lireNoms(() => Completer<List<String>>().future), ['Awa', 'Moussa']);
      expect(await lireNoms(() => Future.error(StateError('ErreurNotes réseau'))), ['Awa', 'Moussa']);
      await expectLater(lireNoms(() => Future.error(ArgumentError('autre'))), throwsA(isA<ArgumentError>()));
    });
  });
}
