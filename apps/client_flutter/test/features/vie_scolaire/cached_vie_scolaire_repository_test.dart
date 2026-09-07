import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/features/vie_scolaire/data/cached_vie_scolaire_repository.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/alerte_decrochage.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/enums_vie_scolaire.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/evenement_scolaire.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/presence.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/retard.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/sanction.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/vie_scolaire_repository.dart';

Presence _presence({String ficheId = 'f1', DateTime? date}) => Presence(
      id: '$ficheId:pointage',
      etablissementId: 'et1',
      anneeScolaireId: 'a1',
      classeId: 'c1',
      ficheEleveId: ficheId,
      datePresence: date ?? DateTime(2026, 9, 7),
      saisiPar: 'p1',
      nomEleve: 'Élève Test',
    );

class _FauxDistant implements VieScolaireRepository {
  bool horsLigne = false;
  String? codeErreur;

  @override
  Future<List<Presence>> presencesDeClasse(String classeId, DateTime date) async {
    if (horsLigne) throw const ErreurVieScolaire('ERREUR_RESEAU');
    return [_presence(date: date)];
  }

  @override
  Future<List<Presence>> presencesDeFiche(String ficheEleveId) async {
    if (horsLigne) throw const ErreurVieScolaire('ERREUR_RESEAU');
    return [_presence(ficheId: ficheEleveId)];
  }

  @override
  Future<List<Retard>> retardsDeFiche(String ficheEleveId) async {
    if (horsLigne) throw const ErreurVieScolaire('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<List<Sanction>> sanctionsDeFiche(String ficheEleveId) async {
    if (horsLigne) throw const ErreurVieScolaire('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<List<AlerteDecrochage>> alertesDeFiche(String ficheEleveId) async {
    if (horsLigne) throw const ErreurVieScolaire('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<List<AlerteDecrochage>> alertesEtablissement(String etablissementId) async {
    if (horsLigne) throw const ErreurVieScolaire('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<List<EvenementScolaire>> evenementsEtablissement(String etablissementId) async {
    if (horsLigne) throw const ErreurVieScolaire('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<Map<String, dynamic>> analyseComportement(String ficheEleveId, String anneeScolaireId) async {
    if (horsLigne) throw const ErreurVieScolaire('ERREUR_RESEAU');
    return {'absences_non_justifiees': 3};
  }

  @override
  Future<double> scoreDecrochage(String ficheEleveId, String anneeScolaireId) async => 0.42;

  @override
  Future<Map<String, dynamic>> recommandationSanction(String ficheEleveId, String anneeScolaireId) async =>
      {'type_recommande': 'aucune'};

  @override
  Future<double> predirePresence(String etablissementId, DateTime date) async => 0.9;

  @override
  Future<bool> saisirPresence(Presence presence) async {
    final code = codeErreur;
    if (code != null) throw ErreurVieScolaire(code);
    return true;
  }

  @override
  Future<bool> saisirRetard(Retard retard) async {
    final code = codeErreur;
    if (code != null) throw ErreurVieScolaire(code);
    return true;
  }

  @override
  Future<Sanction> proposerSanction(Sanction sanction) async => sanction;

  @override
  Future<void> validerSanction(String sanctionId, {required String valideePar}) async {}

  @override
  Future<void> changerStatutSanction(String sanctionId, String statut) async {}
}

void main() {
  late AppDatabase db;
  late _FauxDistant distant;
  late CachedVieScolaireRepository repository;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    distant = _FauxDistant();
    repository = CachedVieScolaireRepository(distant, CacheDocumentStore(db, 'vie_scolaire'), DriftSyncRepository(db));
  });

  tearDown(() => db.close());

  group('lecture', () {
    test('presencesDeClasse retombe sur le cache hors ligne', () async {
      final date = DateTime(2026, 9, 7);
      await repository.presencesDeClasse('c1', date);
      distant.horsLigne = true;

      final liste = await repository.presencesDeClasse('c1', date);
      expect(liste.single.ficheEleveId, 'f1');
    });

    test('analyseComportement retombe sur le cache hors ligne', () async {
      await repository.analyseComportement('f1', 'a1');
      distant.horsLigne = true;

      final donnees = await repository.analyseComportement('f1', 'a1');
      expect(donnees['absences_non_justifiees'], 3);
    });

    test('alertesDeFiche renvoie une liste vide hors ligne plutôt que de propager l\'erreur', () async {
      distant.horsLigne = true;
      expect(await repository.alertesDeFiche('f1'), isEmpty);
    });
  });

  group('saisirPresence', () {
    test('renvoie true sans rien enfiler quand le réseau réussit', () async {
      final synchronisee = await repository.saisirPresence(_presence());

      expect(synchronisee, isTrue);
      expect(await DriftSyncRepository(db).entreesEnAttente(), isEmpty);
    });

    test('enfile la présence et renvoie false sur une panne réseau non métier', () async {
      distant.codeErreur = 'ERREUR_RESEAU';

      final synchronisee = await repository.saisirPresence(_presence());

      expect(synchronisee, isFalse);
      final enAttente = await DriftSyncRepository(db).entreesEnAttente();
      expect(enAttente, hasLength(1));
      expect(enAttente.single.entite, 'presences');
    });

    test('remonte une erreur métier authentique sans l\'enfiler', () async {
      distant.codeErreur = 'ELEVE_NON_INSCRIT';

      await expectLater(
        repository.saisirPresence(_presence()),
        throwsA(isA<ErreurVieScolaire>().having((e) => e.code, 'code', 'ELEVE_NON_INSCRIT')),
      );
      expect(await DriftSyncRepository(db).entreesEnAttente(), isEmpty);
    });
  });

  group('presencesDeClasse — superposition de la file d\'attente', () {
    test('une présence en attente masque le statut serveur pour le même élève', () async {
      final date = DateTime(2026, 9, 7);
      distant.codeErreur = 'ERREUR_RESEAU';
      await repository.saisirPresence(
        Presence(
          id: 'f1:pointage',
          etablissementId: 'et1',
          anneeScolaireId: 'a1',
          classeId: 'c1',
          ficheEleveId: 'f1',
          datePresence: date,
          saisiPar: 'p1',
          statut: StatutPresence.absent,
        ),
      );
      distant.codeErreur = null;

      final liste = await repository.presencesDeClasse('c1', date);
      final presenceF1 = liste.firstWhere((p) => p.ficheEleveId == 'f1');
      expect(presenceF1.statut, StatutPresence.absent);
      expect(presenceF1.nomEleve, 'Élève Test');
    });
  });
}
