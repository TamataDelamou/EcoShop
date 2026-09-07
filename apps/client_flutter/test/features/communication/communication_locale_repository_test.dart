import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/features/communication/prototype/data/communication_locale_repository.dart';
import 'package:ecoshop_client/features/communication/prototype/domain/entree_communication_locale.dart';

void main() {
  late AppDatabase db;
  late CommunicationLocaleRepository repository;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    repository = CommunicationLocaleRepository(CacheDocumentStore(db, 'communication_locale'));
  });

  tearDown(() => db.close());

  test('lister renvoie une liste vide quand rien n\'a été ajouté', () async {
    expect(await repository.lister(TypeEntreeLocale.message), isEmpty);
  });

  test('ajouter place les nouvelles entrées en tête, triées par date décroissante', () async {
    await repository.ajouter(
      EntreeCommunicationLocale(
        id: 'e1',
        type: TypeEntreeLocale.message,
        auteurId: 'p1',
        auteurNom: 'A',
        destinataireLabel: 'classe-cm2',
        contenu: 'Premier message',
        dateCreation: DateTime(2026, 3, 1),
      ),
    );
    await repository.ajouter(
      EntreeCommunicationLocale(
        id: 'e2',
        type: TypeEntreeLocale.message,
        auteurId: 'p1',
        auteurNom: 'A',
        destinataireLabel: 'classe-cm2',
        contenu: 'Second message',
        dateCreation: DateTime(2026, 3, 2),
      ),
    );

    final liste = await repository.lister(TypeEntreeLocale.message);
    expect(liste, hasLength(2));
    expect(liste.first.id, 'e2');
  });

  test('les types ne se mélangent pas entre eux', () async {
    await repository.ajouter(
      EntreeCommunicationLocale(
        id: 'e1',
        type: TypeEntreeLocale.annonce,
        auteurId: 'p1',
        auteurNom: 'Direction',
        destinataireLabel: 'Tout établissement',
        contenu: 'Une annonce',
        dateCreation: DateTime(2026, 3, 1),
      ),
    );

    expect(await repository.lister(TypeEntreeLocale.message), isEmpty);
    expect(await repository.lister(TypeEntreeLocale.annonce), hasLength(1));
  });

  test('marquerAccuseReception met à jour uniquement l\'entrée ciblée', () async {
    await repository.ajouter(
      EntreeCommunicationLocale(
        id: 'e1',
        type: TypeEntreeLocale.annonce,
        auteurId: 'p1',
        auteurNom: 'Direction',
        destinataireLabel: 'Tout établissement',
        contenu: 'Réunion vendredi',
        dateCreation: DateTime(2026, 3, 1),
        important: true,
      ),
    );

    await repository.marquerAccuseReception(TypeEntreeLocale.annonce, 'e1');

    final liste = await repository.lister(TypeEntreeLocale.annonce);
    expect(liste.single.accuseReception, isTrue);
    expect(liste.single.important, isTrue);
  });
}
