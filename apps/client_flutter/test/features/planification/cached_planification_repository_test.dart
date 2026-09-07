import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/features/planification/data/cached_planification_repository.dart';
import 'package:ecoshop_client/features/planification/domain/charge_travail.dart';
import 'package:ecoshop_client/features/planification/domain/conflit_emploi.dart';
import 'package:ecoshop_client/features/planification/domain/emploi_du_temps.dart';
import 'package:ecoshop_client/features/planification/domain/evenement_agenda.dart';
import 'package:ecoshop_client/features/planification/domain/planification_repository.dart';
import 'package:ecoshop_client/features/planification/domain/progression_pedagogique.dart';
import 'package:ecoshop_client/features/planification/domain/salle.dart';

EmploiDuTemps _emploi({String id = 'e1', String classeId = 'c1'}) => EmploiDuTemps(
      id: id,
      etablissementId: 'et1',
      anneeScolaireId: 'a1',
      classeId: classeId,
      jourSemaine: 1,
      heureDebut: '08:00',
      heureFin: '09:00',
    );

class _FauxDistant implements PlanificationRepository {
  bool horsLigne = false;
  String? codeErreur;

  @override
  Future<List<Salle>> sallesEtablissement(String etablissementId) async {
    if (horsLigne) throw const ErreurPlanification('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<List<EmploiDuTemps>> emploisDeClasse(String classeId) async {
    if (horsLigne) throw const ErreurPlanification('ERREUR_RESEAU');
    return [_emploi(classeId: classeId)];
  }

  @override
  Future<List<EmploiDuTemps>> emploisDeEnseignant(
    String enseignantProfileId,
    String etablissementId,
    String anneeScolaireId,
  ) async {
    if (horsLigne) throw const ErreurPlanification('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<List<EmploiDuTemps>> emploisDeSalle(String salleId, String anneeScolaireId) async {
    if (horsLigne) throw const ErreurPlanification('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<bool> enregistrerSeance(EmploiDuTemps emploi) async {
    final code = codeErreur;
    if (code != null) throw ErreurPlanification(code);
    return true;
  }

  @override
  Future<List<EvenementAgenda>> evenementsEtablissement(String etablissementId, String anneeScolaireId) async {
    if (horsLigne) throw const ErreurPlanification('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<List<EvenementAgenda>> evenementsDeClasse(String classeId, String anneeScolaireId) async {
    if (horsLigne) throw const ErreurPlanification('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<bool> enregistrerEvenement(EvenementAgenda evenement) async {
    final code = codeErreur;
    if (code != null) throw ErreurPlanification(code);
    return true;
  }

  @override
  Future<List<ProgressionPedagogique>> progressionDeClasse(String classeId, String anneeScolaireId) async {
    if (horsLigne) throw const ErreurPlanification('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<bool> enregistrerProgression(ProgressionPedagogique progression) async {
    final code = codeErreur;
    if (code != null) throw ErreurPlanification(code);
    return true;
  }

  @override
  Future<void> changerStatutProgression(String progressionId, String statut) async {}

  @override
  Future<int> recommanderSeances(String etablissementId, String anneeScolaireId) async => 0;

  @override
  Future<Map<String, dynamic>?> suggererPlacement({
    required String etablissementId,
    required String anneeScolaireId,
    required String enseignantProfileId,
    required String classeId,
    required String salleId,
  }) async =>
      null;

  @override
  Future<List<ConflitEmploi>> detecterConflits(String etablissementId, String anneeScolaireId) async => const [];

  @override
  Future<ChargeTravailEnseignant> chargeEnseignant(
    String etablissementId,
    String anneeScolaireId,
    String enseignantProfileId,
  ) async =>
      const ChargeTravailEnseignant(heuresHebdo: 0, nbSeances: 0, volumeContractuelHebdo: 0, surcharge: false);

  @override
  Future<ChargeTravailEleve> chargeEleve(String classeId) async =>
      const ChargeTravailEleve(heuresHebdo: 0, nbSeances: 0, joursOccupes: 0, surcharge: false);
}

void main() {
  late AppDatabase db;
  late _FauxDistant distant;
  late CachedPlanificationRepository repository;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    distant = _FauxDistant();
    repository = CachedPlanificationRepository(distant, CacheDocumentStore(db, 'planification'), DriftSyncRepository(db));
  });

  tearDown(() => db.close());

  group('lecture', () {
    test('emploisDeClasse retombe sur le cache hors ligne', () async {
      await repository.emploisDeClasse('c1');
      distant.horsLigne = true;

      final liste = await repository.emploisDeClasse('c1');
      expect(liste.single.classeId, 'c1');
    });
  });

  group('enregistrerSeance', () {
    test('renvoie true sans rien enfiler quand le réseau réussit', () async {
      final synchronisee = await repository.enregistrerSeance(_emploi());

      expect(synchronisee, isTrue);
      expect(await DriftSyncRepository(db).entreesEnAttente(), isEmpty);
    });

    test('enfile la séance et renvoie false sur une panne réseau non métier', () async {
      distant.codeErreur = 'ERREUR_RESEAU';

      final synchronisee = await repository.enregistrerSeance(_emploi());

      expect(synchronisee, isFalse);
      final enAttente = await DriftSyncRepository(db).entreesEnAttente();
      expect(enAttente, hasLength(1));
      expect(enAttente.single.entite, 'emplois_du_temps');
    });

    test('remonte une erreur métier authentique sans l\'enfiler', () async {
      distant.codeErreur = 'EMPLOI_ENSEIGNANT_NON_MEMBRE';

      await expectLater(
        repository.enregistrerSeance(_emploi()),
        throwsA(isA<ErreurPlanification>().having((e) => e.code, 'code', 'EMPLOI_ENSEIGNANT_NON_MEMBRE')),
      );
      expect(await DriftSyncRepository(db).entreesEnAttente(), isEmpty);
    });
  });

  group('emploisDeClasse — superposition de la file d\'attente', () {
    test('une séance en attente apparaît immédiatement dans la liste', () async {
      distant.codeErreur = 'ERREUR_RESEAU';
      await repository.enregistrerSeance(_emploi(id: 'e2'));
      distant.codeErreur = null;

      final liste = await repository.emploisDeClasse('c1');
      expect(liste.any((e) => e.id == 'e2'), isTrue);
    });
  });
}
