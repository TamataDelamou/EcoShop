import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/securite/chiffrement_file.dart';
import 'package:ecoshop_client/core/securite/coffre_fort.dart';
import 'package:ecoshop_client/core/securite/scelleur_par_compte.dart';

/// REG-35 — décision sur la déconnexion : chaque compte garde ses copies,
/// chiffrées pour lui seul ; « appareil partagé » les efface.
void main() {
  late AppDatabase db;
  late ChiffreurFile chiffreur;
  String? compte;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    chiffreur = ChiffreurFile(CoffreFortMemoire());
    compte = 'awa';
    db.scelleur = ScelleurParCompte(chiffreur, () => compte);
  });

  tearDown(() => db.close());

  CacheDocumentStore store(String domaine) => CacheDocumentStore(db, domaine);

  test('la copie est chiffrée sur le disque', () async {
    await store('notes').ecrireDocument('notes_fiche', 'f1', {'note': 17});
    final ligne = await db.select(db.cacheEntries).getSingle();
    expect(ligne.payload, startsWith(ChiffreurFile.prefixe));
    expect(ligne.payload, isNot(contains('17')));
  });

  test('le même compte relit sa copie après déconnexion et reconnexion', () async {
    await store('notes').ecrireDocument('notes_fiche', 'f1', {'note': 17});
    compte = null; // déconnecté
    expect(await store('notes').lireDocument('notes_fiche', 'f1'), isNull);
    compte = 'awa';
    expect(await store('notes').lireDocument('notes_fiche', 'f1'), {'note': 17});
  });

  test('un autre compte du même appareil ne la lit pas', () async {
    await store('notes').ecrireDocument('notes_fiche', 'f1', {'note': 17});
    compte = 'moussa';
    expect(await store('notes').lireDocument('notes_fiche', 'f1'), isNull);
    expect(await store('notes').lireType('notes_fiche'), isEmpty);
  });

  test('une ancienne copie en clair n\'est pas servie à un compte connecté', () async {
    db.scelleur = null; // copie faite avant la mise à jour
    await store('scolarite').ecrireDocument('eleves', 'c1', {'eleves': ['Fanta']});
    db.scelleur = ScelleurParCompte(chiffreur, () => compte);
    expect(await store('scolarite').lireDocument('eleves', 'c1'), isNull);
  });

  test('les réglages de l\'appareil restent en clair et lisibles de tous', () async {
    await store('preferences').ecrireDocument('theme', 'appareil', {'sombre': true});
    final ligne = await db.select(db.cacheEntries).getSingle();
    expect(ligne.payload, isNot(startsWith(ChiffreurFile.prefixe)));
    compte = 'moussa';
    expect(await store('preferences').lireDocument('theme', 'appareil'), {'sombre': true});
  });

  test('appareil partagé : seules les copies du compte sont effacées, et sa clé détruite', () async {
    await store('notes').ecrireDocument('notes_fiche', 'f1', {'note': 17});
    compte = 'moussa';
    await store('notes').ecrireDocument('notes_fiche', 'f2', {'note': 12});
    compte = 'awa';

    expect(await CacheDocumentStore.effacerCopiesDuCompte(db), 1);
    await chiffreur.oublierCle('awa');

    compte = 'moussa';
    expect(await store('notes').lireDocument('notes_fiche', 'f2'), {'note': 12});
    expect((await db.select(db.cacheEntries).get()).length, 1);
  });

  test('après destruction de la clé, le chiffré restant est illisible', () async {
    final texte = await chiffreur.chiffrer('awa', 'secret');
    await chiffreur.oublierCle('awa');
    expect(await chiffreur.dechiffrer('awa', texte), isNull);
  });
}
