import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/features/scolarite/data/cached_scolarite_repository.dart';
import 'package:ecoshop_client/features/scolarite/domain/affectation_enseignant.dart';
import 'package:ecoshop_client/features/scolarite/domain/encaissement_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/enums_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/fiche_eleve.dart';
import 'package:ecoshop_client/features/scolarite/domain/frais_scolarite_config.dart';
import 'package:ecoshop_client/features/scolarite/domain/inscription.dart';
import 'package:ecoshop_client/features/scolarite/domain/palier_paiement_config.dart';
import 'package:ecoshop_client/features/scolarite/domain/relation_parent_eleve.dart';
import 'package:ecoshop_client/features/scolarite/domain/scolarite_repository.dart';
import 'package:ecoshop_client/features/scolarite/domain/solde_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/structure_etablissement.dart';
import 'package:ecoshop_client/features/scolarite/domain/verifications_reinscription.dart';

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

  // --- M15quater — doublure minimale, non exercée par ces tests de cache --

  @override
  Future<FicheEleve?> ficheParMatricule({required String etablissementId, required String matricule}) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return _ficheTest();
  }

  @override
  Future<String> creerInscriptionNouvelEleve({
    required String etablissementId,
    required String nom,
    required String prenom,
    required DateTime dateNaissance,
    required String classeId,
    required String anneeScolaireId,
    String? sexe,
  }) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return 'f1';
  }

  @override
  Future<bool> verifierDoublonEleve({
    required String nom,
    required String prenom,
    required DateTime dateNaissance,
  }) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return false;
  }

  @override
  Future<VerificationsReinscription> verificationsReinscription({
    required String ficheEleveId,
    required String anneePrecedenteId,
  }) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return const VerificationsReinscription(impaye: false, sanctionActive: false, boursierPrecedent: false);
  }

  @override
  Future<String> creerReinscription({
    required String ficheEleveId,
    required String classeId,
    required String anneeScolaireId,
  }) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return 'i-new';
  }

  @override
  Future<void> definirStatutBoursier({required String inscriptionId, required bool boursier}) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
  }

  @override
  Future<void> mettreAJourFicheAdmin(FicheEleve fiche) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
  }

  @override
  Future<List<FraisScolariteConfig>> fraisScolariteConfig({
    required String etablissementId,
    required String anneeScolaireId,
  }) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<void> enregistrerFraisScolariteConfig(FraisScolariteConfig config) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
  }

  @override
  Future<List<PalierPaiementConfig>> paliersPaiementConfig({
    required String etablissementId,
    required String anneeScolaireId,
  }) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<void> enregistrerPalierPaiement(PalierPaiementConfig palier) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
  }

  @override
  Future<SoldeScolarite> soldeScolarite(String inscriptionId) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return const SoldeScolarite(montantDu: 1000000, montantPaye: 400000, solde: 600000);
  }

  @override
  Future<List<EncaissementScolarite>> encaissementsDeInscription(String inscriptionId) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return [
      EncaissementScolarite(
        id: 'enc1',
        etablissementId: 'e1',
        ficheEleveId: 'f1',
        inscriptionId: inscriptionId,
        montant: 400000,
        datePaiement: DateTime(2026, 10, 6),
        saisiPar: 'p-direction',
      ),
    ];
  }

  @override
  Future<List<EncaissementScolarite>> encaissementsRecents(String etablissementId, {int limite = 100}) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<EncaissementScolarite> enregistrerEncaissement(EncaissementScolarite encaissement) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
    return encaissement;
  }

  @override
  Future<void> annulerEncaissement({required String encaissementId, required String motif}) async {
    if (horsLigne) throw const ErreurScolarite('ERREUR_RESEAU');
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

  test('creerInscriptionNouvelEleve (M15quater) ne connaît aucun repli hors ligne', () async {
    distant.horsLigne = true;
    expect(
      repository.creerInscriptionNouvelEleve(
        etablissementId: 'e1',
        nom: 'Camara',
        prenom: 'Mory',
        dateNaissance: DateTime(2013, 4, 12),
        classeId: 'c1',
        anneeScolaireId: 'a1',
      ),
      throwsA(isA<ErreurScolarite>()),
    );
  });

  test('soldeScolarite (M15quater) retombe sur le cache hors ligne', () async {
    final enLigne = await repository.soldeScolarite('i1');
    expect(enLigne.solde, 600000);

    distant.horsLigne = true;
    final horsLigne = await repository.soldeScolarite('i1');
    expect(horsLigne.solde, 600000);
    expect(horsLigne.montantDu, 1000000);
  });

  test('encaissementsDeInscription (M15quater) retombe sur le cache hors ligne', () async {
    await repository.encaissementsDeInscription('i1');
    distant.horsLigne = true;

    final liste = await repository.encaissementsDeInscription('i1');
    expect(liste.single.montant, 400000);
    expect(liste.single.saisiPar, 'p-direction');
  });

  test('ficheParMatricule (M15quater) retombe sur le cache hors ligne', () async {
    await repository.ficheParMatricule(etablissementId: 'e1', matricule: 'MAT-1');
    distant.horsLigne = true;

    final fiche = await repository.ficheParMatricule(etablissementId: 'e1', matricule: 'MAT-1');
    expect(fiche?.matricule, 'MAT-1');
  });
}
