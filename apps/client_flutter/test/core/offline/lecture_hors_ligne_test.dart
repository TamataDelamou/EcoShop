import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/offline/lecture_hors_ligne.dart';

void main() {
  late AppDatabase db;
  late LectureHorsLigne lecture;
  late ValueNotifier<DateTime?> fraicheur;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    fraicheur = ValueNotifier<DateTime?>(null);
    lecture = LectureHorsLigne(CacheDocumentStore(db, 'comptabilite_hl'), fraicheur);
  });

  tearDown(() async {
    fraicheur.dispose();
    await db.close();
  });

  Future<int> lireTotal(Future<Object?> Function() source) => lecture.lire(
        type: 'etat',
        cle: 'x2026',
        source: source,
        decoder: (json) => ((json! as Map<String, dynamic>)['total'] as num).toInt(),
      );

  test('en ligne : réponse du serveur, gardée sur l\'appareil', () async {
    expect(await lireTotal(() async => {'total': 42}), 42);
    expect(fraicheur.value, isNull);
  });

  test('sans réseau : dernière réponse resservie, avec sa date', () async {
    await lireTotal(() async => {'total': 42});
    final total = await lireTotal(() => Future.error(http.ClientException('Failed host lookup')));
    expect(total, 42);
    expect(fraicheur.value, isNotNull);

    // De retour en ligne : données fraîches, plus de bandeau.
    expect(await lireTotal(() async => {'total': 50}), 50);
    expect(fraicheur.value, isNull);
  });

  test('sans réseau et jamais consulté : l\'erreur de réseau remonte', () async {
    expect(lireTotal(() => Future.error(TimeoutException('délai'))), throwsA(isA<TimeoutException>()));
  });

  test('un refus du serveur n\'est jamais masqué par le cache', () async {
    await lireTotal(() async => {'total': 42});
    expect(lireTotal(() => Future.error(StateError('COMPTABLE_REQUIS'))), throwsA(isA<StateError>()));
  });

  test('reconnaît les pannes de réseau', () {
    expect(estErreurReseau(http.ClientException('x')), isTrue);
    expect(estErreurReseau(TimeoutException('x')), isTrue);
    expect(estErreurReseau(StateError('x')), isFalse);
  });
}
