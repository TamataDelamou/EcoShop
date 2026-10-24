import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/features/referentiel/data/cached_referentiel_repository.dart';
import 'package:ecoshop_client/features/referentiel/data/referentiel_cache_store.dart';
import 'package:ecoshop_client/features/referentiel/domain/arborescence_niveau.dart';
import 'package:ecoshop_client/features/referentiel/domain/arborescence_pays.dart';
import 'package:ecoshop_client/features/referentiel/domain/paquet_referentiel.dart';
import 'package:ecoshop_client/features/referentiel/domain/pays_pedagogique.dart';
import 'package:ecoshop_client/features/referentiel/domain/referentiel_repository.dart';
import 'package:ecoshop_client/features/referentiel/domain/systeme_educatif.dart';

class _FauxDistant implements ReferentielRepository {
  _FauxDistant();

  bool horsLigne = false;
  int appelsPays = 0;

  List<PaysPedagogique> pays = const [
    PaysPedagogique(
      codeIso: 'GN',
      nom: 'Guinée',
      typeSysteme: 'francophone_cfa',
      langueEnseignementPrincipale: 'fr',
    ),
  ];

  @override
  Future<List<SystemeEducatif>> systemesEducatifs() async {
    if (horsLigne) throw const ErreurReferentiel('ERREUR_RESEAU');
    return const [SystemeEducatif(code: 'francophone_cfa', nom: 'Francophone (CFA)')];
  }

  @override
  Future<List<PaysPedagogique>> paysPedagogiques() async {
    appelsPays++;
    if (horsLigne) throw const ErreurReferentiel('ERREUR_RESEAU');
    return pays;
  }

  @override
  Future<ArborescencePays> arborescencePays(String paysCode) async {
    if (horsLigne) throw const ErreurReferentiel('ERREUR_RESEAU');
    return const ArborescencePays(cycles: [], niveaux: [], examens: []);
  }

  @override
  Future<ArborescenceNiveau> arborescenceNiveau(String niveauId) async {
    if (horsLigne) throw const ErreurReferentiel('ERREUR_RESEAU');
    return const ArborescenceNiveau(filieres: [], programmes: [], matieres: []);
  }

  @override
  Future<List<PaquetReferentiel>> paquetsDisponibles({
    required String paysCode,
    String? niveauId,
  }) async {
    if (horsLigne) throw const ErreurReferentiel('ERREUR_RESEAU');
    return const [];
  }
}

void main() {
  late AppDatabase db;
  late _FauxDistant distant;
  late CachedReferentielRepository repository;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    distant = _FauxDistant();
    repository = CachedReferentielRepository(distant, ReferentielCacheStore(db));
  });

  tearDown(() => db.close());

  group('CachedReferentielRepository', () {
    test('sert le réseau et met à jour le cache (write-through)', () async {
      final liste = await repository.paysPedagogiques();
      expect(liste, hasLength(1));
      expect(liste.first.nom, 'Guinée');
      expect(distant.appelsPays, 1);
    });

    test('retombe sur le cache quand le réseau échoue', () async {
      await repository.paysPedagogiques(); // amorce le cache pendant qu'on est en ligne

      distant.horsLigne = true;
      final liste = await repository.paysPedagogiques();

      expect(liste, hasLength(1));
      expect(liste.first.codeIso, 'GN');
    });

    test('une réponse vide du serveur n\'efface pas la copie du téléphone', () async {
      await repository.paysPedagogiques();

      distant.pays = const [];
      final liste = await repository.paysPedagogiques();
      expect(liste.single.codeIso, 'GN');

      distant.horsLigne = true;
      expect((await repository.paysPedagogiques()).single.codeIso, 'GN');
    });

    test('serveur vide et rien sur le téléphone : liste vide, pas d\'erreur', () async {
      distant.pays = const [];
      expect(await repository.paysPedagogiques(), isEmpty);
    });

    test('propage l\'erreur si le cache est vide et le réseau indisponible', () async {
      distant.horsLigne = true;
      expect(repository.paysPedagogiques(), throwsA(isA<ErreurReferentiel>()));
    });
  });
}
