import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/scolarite/application/scolarite_providers.dart';
import 'package:ecoshop_client/features/scolarite/domain/enums_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/fiche_eleve.dart';
import 'package:ecoshop_client/features/scolarite/domain/relation_parent_eleve.dart';

FicheEleve _fiche(String id, String prenom) => FicheEleve(
      id: id,
      etablissementId: 'e1',
      matricule: 'MAT-$id',
      nom: 'Doe',
      prenom: prenom,
      dateNaissance: DateTime(2015, 1, 1),
    );

RelationParentEleve _relation(FicheEleve fiche, {StatutRelation statut = StatutRelation.confirmee}) =>
    RelationParentEleve(
      id: 'r-${fiche.id}',
      etablissementId: 'e1',
      parentProfileId: 'p1',
      ficheEleveId: fiche.id,
      statut: statut,
      fiche: fiche,
    );

void main() {
  test('enfantActifProvider choisit le premier enfant confirmé par défaut', () async {
    final fiche1 = _fiche('f1', 'Alpha');
    final fiche2 = _fiche('f2', 'Beta');
    final container = ProviderContainer(overrides: [
      mesEnfantsProvider.overrideWith((ref) async => [_relation(fiche1), _relation(fiche2)]),
    ]);
    addTearDown(container.dispose);

    await container.read(mesEnfantsProvider.future);

    expect(container.read(enfantActifProvider)?.id, 'f1');
  });

  test('enfantActifProvider ignore les relations non confirmées', () async {
    final fiche1 = _fiche('f1', 'Alpha');
    final fiche2 = _fiche('f2', 'Beta');
    final container = ProviderContainer(overrides: [
      mesEnfantsProvider.overrideWith(
        (ref) async => [_relation(fiche1, statut: StatutRelation.enAttente), _relation(fiche2)],
      ),
    ]);
    addTearDown(container.dispose);

    await container.read(mesEnfantsProvider.future);

    expect(container.read(enfantActifProvider)?.id, 'f2');
  });

  test('un choix explicite valide est conservé', () async {
    final fiche1 = _fiche('f1', 'Alpha');
    final fiche2 = _fiche('f2', 'Beta');
    final container = ProviderContainer(overrides: [
      mesEnfantsProvider.overrideWith((ref) async => [_relation(fiche1), _relation(fiche2)]),
    ]);
    addTearDown(container.dispose);

    await container.read(mesEnfantsProvider.future);
    container.read(enfantSelectionneProvider.notifier).state = fiche2;

    expect(container.read(enfantActifProvider)?.id, 'f2');
  });

  test('un choix devenu invalide retombe sur le premier enfant confirmé', () async {
    final fiche1 = _fiche('f1', 'Alpha');
    final autreFiche = _fiche('disparu', 'Fantôme');
    final container = ProviderContainer(overrides: [
      mesEnfantsProvider.overrideWith((ref) async => [_relation(fiche1)]),
    ]);
    addTearDown(container.dispose);

    await container.read(mesEnfantsProvider.future);
    container.read(enfantSelectionneProvider.notifier).state = autreFiche;

    expect(container.read(enfantActifProvider)?.id, 'f1');
  });

  test('aucun enfant confirmé renvoie null', () async {
    final container = ProviderContainer(overrides: [
      mesEnfantsProvider.overrideWith((ref) async => const []),
    ]);
    addTearDown(container.dispose);

    await container.read(mesEnfantsProvider.future);

    expect(container.read(enfantActifProvider), isNull);
  });
}
