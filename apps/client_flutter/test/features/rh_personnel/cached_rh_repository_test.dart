import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/features/rh_personnel/data/cached_rh_repository.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/absence_personnel.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/bulletin_paie.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/conge.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/contrat.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/effectif_categorie.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/employe.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/enums_rh.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/recommandation_formation.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/remplacement_suggere.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/rh_repository.dart';

Employe _employe({String id = 'e1', String etablissementId = 'et1'}) => Employe(
      id: id,
      etablissementId: etablissementId,
      profileId: 'p1',
      matricule: 'MAT-001',
      dateEmbauche: DateTime(2020, 9, 1),
      nomAffiche: 'Employé Test',
    );

class _FauxDistant implements RhRepository {
  bool horsLigne = false;
  String? codeErreur;

  @override
  Future<List<Employe>> employesEtablissement(String etablissementId) async {
    if (horsLigne) throw const ErreurRh('ERREUR_RESEAU');
    return [_employe(etablissementId: etablissementId)];
  }

  @override
  Future<Employe?> employeParProfil(String profileId) async {
    if (horsLigne) throw const ErreurRh('ERREUR_RESEAU');
    return _employe();
  }

  @override
  Future<Employe?> employe(String employeId) async {
    if (horsLigne) throw const ErreurRh('ERREUR_RESEAU');
    return _employe(id: employeId);
  }

  @override
  Future<List<Contrat>> contratsDeEmploye(String employeId) async {
    if (horsLigne) throw const ErreurRh('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<List<Conge>> congesDeEmploye(String employeId) async {
    if (horsLigne) throw const ErreurRh('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<List<AbsencePersonnel>> absencesDeEmploye(String employeId) async {
    if (horsLigne) throw const ErreurRh('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<List<BulletinPaie>> bulletinsDeEmploye(String employeId) async {
    if (horsLigne) throw const ErreurRh('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<int> chargeHoraire(String employeId) async => 18;

  @override
  Future<List<EffectifCategorie>> analyserEffectifs(String etablissementId) async {
    if (horsLigne) throw const ErreurRh('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<double> scoreTurnover(String employeId) async => 0.35;

  @override
  Future<List<RecommandationFormation>> recommanderFormation(String employeId, String anneeScolaireId) async =>
      const [];

  @override
  Future<List<RemplacementSuggere>> optimiserRemplacements(String etablissementId, DateTime date) async => const [];

  @override
  Future<void> creerOuModifierEmploye(Employe employe) async {}

  @override
  Future<Contrat> creerContrat(Contrat contrat) async => contrat;

  @override
  Future<bool> demanderConge(Conge conge) async {
    final code = codeErreur;
    if (code != null) throw ErreurRh(code);
    return true;
  }

  @override
  Future<void> validerConge(String congeId, {required String statut, required String valideePar}) async {}

  @override
  Future<bool> pointerAbsence(AbsencePersonnel absence) async {
    final code = codeErreur;
    if (code != null) throw ErreurRh(code);
    return true;
  }
}

void main() {
  late AppDatabase db;
  late _FauxDistant distant;
  late CachedRhRepository repository;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    distant = _FauxDistant();
    repository = CachedRhRepository(distant, CacheDocumentStore(db, 'rh_personnel'), DriftSyncRepository(db));
  });

  tearDown(() => db.close());

  group('lecture', () {
    test('employesEtablissement retombe sur le cache hors ligne', () async {
      await repository.employesEtablissement('et1');
      distant.horsLigne = true;

      final liste = await repository.employesEtablissement('et1');
      expect(liste.single.matricule, 'MAT-001');
    });

    test('scoreTurnover retombe sur le cache hors ligne', () async {
      final valeur = await repository.scoreTurnover('e1');
      expect(valeur, 0.35);
    });
  });

  group('demanderConge', () {
    test('renvoie true sans rien enfiler quand le réseau réussit', () async {
      final synchronisee = await repository.demanderConge(
        Conge(
          id: 'g1',
          etablissementId: 'et1',
          employeId: 'e1',
          dateDebut: DateTime(2026, 3, 1),
          dateFin: DateTime(2026, 3, 2),
          nbJours: 2,
        ),
      );

      expect(synchronisee, isTrue);
      expect(await DriftSyncRepository(db).entreesEnAttente(), isEmpty);
    });

    test('enfile la demande et renvoie false sur une panne réseau non métier', () async {
      distant.codeErreur = 'ERREUR_RESEAU';

      final synchronisee = await repository.demanderConge(
        Conge(
          id: 'g1',
          etablissementId: 'et1',
          employeId: 'e1',
          dateDebut: DateTime(2026, 3, 1),
          dateFin: DateTime(2026, 3, 2),
          nbJours: 2,
        ),
      );

      expect(synchronisee, isFalse);
      final enAttente = await DriftSyncRepository(db).entreesEnAttente();
      expect(enAttente, hasLength(1));
      expect(enAttente.single.entite, 'conges');
    });

    test('remonte une erreur métier authentique sans l\'enfiler', () async {
      distant.codeErreur = 'EMPLOYE_AUTRE_ETABLISSEMENT';

      await expectLater(
        repository.demanderConge(
          Conge(
            id: 'g1',
            etablissementId: 'et1',
            employeId: 'e1',
            dateDebut: DateTime(2026, 3, 1),
            dateFin: DateTime(2026, 3, 2),
            nbJours: 2,
          ),
        ),
        throwsA(isA<ErreurRh>().having((e) => e.code, 'code', 'EMPLOYE_AUTRE_ETABLISSEMENT')),
      );
      expect(await DriftSyncRepository(db).entreesEnAttente(), isEmpty);
    });
  });

  group('pointerAbsence', () {
    test('enfile le pointage et renvoie false sur une panne réseau non métier', () async {
      distant.codeErreur = 'ERREUR_RESEAU';

      final synchronisee = await repository.pointerAbsence(
        AbsencePersonnel(
          id: 'a1',
          etablissementId: 'et1',
          employeId: 'e1',
          dateAbsence: DateTime(2026, 3, 1),
        ),
      );

      expect(synchronisee, isFalse);
      final enAttente = await DriftSyncRepository(db).entreesEnAttente();
      expect(enAttente, hasLength(1));
      expect(enAttente.single.entite, 'absences_personnel');
    });
  });

  group('congesDeEmploye — superposition de la file d\'attente', () {
    test('une demande en attente apparaît immédiatement dans la liste', () async {
      distant.codeErreur = 'ERREUR_RESEAU';
      await repository.demanderConge(
        Conge(
          id: 'g1',
          etablissementId: 'et1',
          employeId: 'e1',
          dateDebut: DateTime(2026, 3, 1),
          dateFin: DateTime(2026, 3, 2),
          nbJours: 2,
        ),
      );
      distant.codeErreur = null;

      final liste = await repository.congesDeEmploye('e1');
      expect(liste.single.id, 'g1');
      expect(liste.single.statut, StatutConge.demande);
    });
  });
}
