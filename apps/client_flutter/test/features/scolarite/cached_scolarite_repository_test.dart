import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/features/scolarite/data/cached_scolarite_repository.dart';
import 'package:ecoshop_client/features/scolarite/domain/affectation_enseignant.dart';
import 'package:ecoshop_client/features/scolarite/domain/enums_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/fiche_eleve.dart';
import 'package:ecoshop_client/features/scolarite/domain/inscription.dart';
import 'package:ecoshop_client/features/scolarite/domain/relation_parent_eleve.dart';
import 'package:ecoshop_client/features/scolarite/domain/scolarite_repository.dart';
import 'package:ecoshop_client/features/scolarite/domain/structure_etablissement.dart';

FicheEleve _ficheTest({String id = 'f1'}) => FicheEleve(
      id: id,
      etablissementId: 'e1',
      matricule: 'MAT-1',
      nom: 'Diallo',
      prenom: 'Aïcha',
      dateNaissance: DateTime(2015, 3, 4),
    );

class _FauxDistant implements ScolariteRepository {
  bool horsLigne = false;
  int appelsStructure = 0;

  @override
  Future<StructureEtablissement> structureEtablissement(
    String etablissementId, {
    String? anneeScolaireId,
  }) async {
    appelsStructure++;
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return const StructureEtablissement(unites: [], anneesScolaires: [], classes: [], periodes: []);
  }

  @override
  Future<List<Inscription>> inscriptionsDeClasse(String classeId) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return [
      Inscription(
        id: 'i1',
        etablissementId: 'e1',
        ficheEleveId: 'f1',
        classeId: classeId,
        anneeScolaireId: 'a1',
        dateInscription: DateTime(2026, 9, 1),
        fiche: _ficheTest(),
      ),
    ];
  }

  @override
  Future<List<Inscription>> inscriptionsDeFiche(String ficheEleveId) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<FicheEleve?> maFiche() async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return _ficheTest();
  }

  @override
  Future<FicheEleve?> ficheEleve(String ficheId) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return _ficheTest(id: ficheId);
  }

  @override
  Future<List<AffectationEnseignant>> affectationsDeClasse(String classeId) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<List<AffectationEnseignant>> mesAffectations() async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<List<RelationParentEleve>> mesEnfants() async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return [RelationParentEleve(id: 'r1', etablissementId: 'e1', parentProfileId: 'p1', ficheEleveId: 'f1', fiche: _ficheTest())];
  }

  @override
  Future<String> lierEnfant({
    required String matricule,
    required DateTime dateNaissance,
    TypeRelationParentale type = TypeRelationParentale.parent,
  }) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return 'relation-1';
  }
}

void main() {
  late AppDatabase db;
  late _FauxDistant distant;
  late CachedScolariteRepository repository;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    distant = _FauxDistant();
    repository = CachedScolariteRepository(distant, CacheDocumentStore(db, 'scolarite'));
  });

  tearDown(() => db.close());

  test('structureEtablissement retombe sur le cache hors ligne', () async {
    await repository.structureEtablissement('e1');
    distant.horsLigne = true;

    final structure = await repository.structureEtablissement('e1');
    expect(structure, isNotNull);
    expect(distant.appelsStructure, 2);
  });

  test('mesEnfants retombe sur le cache hors ligne', () async {
    final enLigne = await repository.mesEnfants();
    expect(enLigne, hasLength(1));

    distant.horsLigne = true;
    final horsLigne = await repository.mesEnfants();
    expect(horsLigne.single.fiche?.nomComplet, 'Aïcha Diallo');
  });

  test('maFiche retombe sur le cache hors ligne', () async {
    await repository.maFiche();
    distant.horsLigne = true;

    final fiche = await repository.maFiche();
    expect(fiche?.matricule, 'MAT-1');
  });

  test('inscriptionsDeClasse retombe sur le cache hors ligne (fiche embarquée)', () async {
    await repository.inscriptionsDeClasse('c1');
    distant.horsLigne = true;

    final inscriptions = await repository.inscriptionsDeClasse('c1');
    expect(inscriptions.single.fiche?.matricule, 'MAT-1');
  });

  test('propage l\'erreur si le cache est vide et le réseau indisponible', () async {
    distant.horsLigne = true;
    expect(repository.mesEnfants(), throwsA(isA<ErreurScolarite>()));
  });

  test('lierEnfant ne connaît aucun repli hors ligne', () async {
    distant.horsLigne = true;
    expect(
      repository.lierEnfant(matricule: 'MAT-1', dateNaissance: DateTime(2015, 3, 4)),
      throwsA(isA<ErreurScolarite>()),
    );
  });
}
