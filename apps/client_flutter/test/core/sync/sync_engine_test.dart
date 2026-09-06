import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/sync/sync_engine.dart';

class _FakeRepo implements SyncRepository {
  _FakeRepo(this.entrees);

  final List<SyncEntree> entrees;
  final List<SyncEntree> marquages = [];

  @override
  Future<List<SyncEntree>> entreesEnAttente() async => List.of(entrees);

  @override
  Future<void> marquer(SyncEntree entree) async => marquages.add(entree);
}

SyncEntree _entree({int tentatives = 0}) => SyncEntree(
      id: '1',
      entite: 'notes',
      operation: 'insert',
      payload: '{"valeur": 12}',
      tentatives: tentatives,
    );

void main() {
  group('SyncEngine.synchroniser', () {
    test('ne traite rien hors ligne', () async {
      final repo = _FakeRepo([_entree()]);
      final moteur = SyncEngine(
        repository: repo,
        estConnecte: () async => false,
        rejouer: (_) async {},
      );

      expect(await moteur.synchroniser(), 0);
      expect(repo.marquages, isEmpty);
    });

    test('rejoue une entrée et la marque terminée', () async {
      final repo = _FakeRepo([_entree()]);
      var rejouees = 0;
      final moteur = SyncEngine(
        repository: repo,
        estConnecte: () async => true,
        rejouer: (_) async => rejouees++,
      );

      expect(await moteur.synchroniser(), 1);
      expect(rejouees, 1);
      expect(repo.marquages.last.statut, SyncStatut.termine);
      expect(repo.marquages.last.tentatives, 1);
    });

    test('marque échec si le replay lève une exception', () async {
      final repo = _FakeRepo([_entree()]);
      final moteur = SyncEngine(
        repository: repo,
        estConnecte: () async => true,
        rejouer: (_) async => throw Exception('réseau'),
      );

      expect(await moteur.synchroniser(), 0);
      expect(repo.marquages.last.statut, SyncStatut.echec);
      expect(repo.marquages.last.tentatives, 1);
    });

    test('plafonne les tentatives sans rejouer au-delà de maxTentatives', () async {
      final repo = _FakeRepo([_entree(tentatives: 5)]);
      var rejouees = 0;
      final moteur = SyncEngine(
        repository: repo,
        estConnecte: () async => true,
        rejouer: (_) async => rejouees++,
        maxTentatives: 5,
      );

      expect(await moteur.synchroniser(), 0);
      expect(rejouees, 0);
      expect(repo.marquages.last.statut, SyncStatut.echec);
    });
  });

  group('SyncEngine.delaiReessai', () {
    test('est exponentiel et plafonné', () {
      final moteur = SyncEngine(
        repository: _FakeRepo([]),
        estConnecte: () async => true,
        rejouer: (_) async {},
        delaiBase: const Duration(seconds: 2),
        delaiMax: const Duration(seconds: 6),
      );

      expect(moteur.delaiReessai(0), const Duration(seconds: 2));
      expect(moteur.delaiReessai(1), const Duration(seconds: 4));
      expect(moteur.delaiReessai(2), const Duration(seconds: 6)); // 8 s plafonné à 6 s
    });
  });
}
