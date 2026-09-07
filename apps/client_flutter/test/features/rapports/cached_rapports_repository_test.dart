import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/features/rapports/data/cached_rapports_repository.dart';
import 'package:ecoshop_client/features/rapports/domain/anomalie_statistique.dart';
import 'package:ecoshop_client/features/rapports/domain/indicateur_cle.dart';
import 'package:ecoshop_client/features/rapports/domain/rapport.dart';
import 'package:ecoshop_client/features/rapports/domain/rapports_repository.dart';
import 'package:ecoshop_client/features/rapports/domain/recommandation_strategique.dart';

Rapport _rapport({String id = 'r1', String etablissementId = 'et1'}) => Rapport(
      id: id,
      etablissementId: etablissementId,
      anneeScolaireId: 'a1',
      type: 'bulletin',
    );

class _FauxDistant implements RapportsRepository {
  bool horsLigne = false;
  String? codeErreur;

  @override
  Future<List<Rapport>> rapportsDeFiche(String ficheEleveId) async {
    if (horsLigne) throw const ErreurRapports('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<List<Rapport>> rapportsEtablissement(String etablissementId) async {
    if (horsLigne) throw const ErreurRapports('ERREUR_RESEAU');
    return [_rapport(etablissementId: etablissementId)];
  }

  @override
  Future<bool> demanderRapport(Rapport rapport) async {
    final code = codeErreur;
    if (code != null) throw ErreurRapports(code);
    return true;
  }

  @override
  Future<List<IndicateurCle>> indicateursEtablissement(String etablissementId, String anneeScolaireId) async {
    if (horsLigne) throw const ErreurRapports('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<int> consoliderIndicateurs(String etablissementId, String anneeScolaireId) async => 6;

  @override
  Future<List<AnomalieStatistique>> anomaliesEtablissement(String etablissementId, String anneeScolaireId) async {
    if (horsLigne) throw const ErreurRapports('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<int> detecterAnomalies(String etablissementId, String anneeScolaireId) async => 0;

  @override
  Future<void> traiterAnomalie(String anomalieId, String statut, {required String traiteePar}) async {}

  @override
  Future<List<RecommandationStrategique>> recommandationsEtablissement(
    String etablissementId,
    String anneeScolaireId,
  ) async {
    if (horsLigne) throw const ErreurRapports('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<int> genererRecommandations(String etablissementId, String anneeScolaireId) async => 0;

  @override
  Future<void> statuerRecommandation(String recommandationId, String statut, {required String valideePar}) async {}

  @override
  Future<Map<String, dynamic>> risqueClasse(String classeId) async => {'score_risque': 0.4};

  @override
  Future<String> resumeExecutif(String etablissementId, String anneeScolaireId) async => 'Résumé';
}

void main() {
  late AppDatabase db;
  late _FauxDistant distant;
  late CachedRapportsRepository repository;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    distant = _FauxDistant();
    repository = CachedRapportsRepository(distant, CacheDocumentStore(db, 'rapports'), DriftSyncRepository(db));
  });

  tearDown(() => db.close());

  group('lecture', () {
    test('rapportsEtablissement retombe sur le cache hors ligne', () async {
      await repository.rapportsEtablissement('et1');
      distant.horsLigne = true;

      final liste = await repository.rapportsEtablissement('et1');
      expect(liste.single.etablissementId, 'et1');
    });
  });

  group('demanderRapport', () {
    test('renvoie true sans rien enfiler quand le réseau réussit', () async {
      final synchronisee = await repository.demanderRapport(_rapport());

      expect(synchronisee, isTrue);
      expect(await DriftSyncRepository(db).entreesEnAttente(), isEmpty);
    });

    test('enfile la demande et renvoie false sur une panne réseau non métier', () async {
      distant.codeErreur = 'ERREUR_RESEAU';

      final synchronisee = await repository.demanderRapport(_rapport());

      expect(synchronisee, isFalse);
      final enAttente = await DriftSyncRepository(db).entreesEnAttente();
      expect(enAttente, hasLength(1));
      expect(enAttente.single.entite, 'rapports');
    });

    test('remonte une erreur métier authentique sans l\'enfiler', () async {
      distant.codeErreur = 'RAPPORT_CLASSE_AUTRE_ETABLISSEMENT';

      await expectLater(
        repository.demanderRapport(_rapport()),
        throwsA(isA<ErreurRapports>().having((e) => e.code, 'code', 'RAPPORT_CLASSE_AUTRE_ETABLISSEMENT')),
      );
      expect(await DriftSyncRepository(db).entreesEnAttente(), isEmpty);
    });
  });

  group('rapportsEtablissement — superposition de la file d\'attente', () {
    test('une demande en attente apparaît immédiatement dans la liste', () async {
      distant.codeErreur = 'ERREUR_RESEAU';
      await repository.demanderRapport(_rapport(id: 'r2'));
      distant.codeErreur = null;

      final liste = await repository.rapportsEtablissement('et1');
      expect(liste.any((r) => r.id == 'r2'), isTrue);
    });
  });
}
