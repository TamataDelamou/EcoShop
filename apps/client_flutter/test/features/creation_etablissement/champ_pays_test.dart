import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/features/creation_etablissement/presentation/ecran_demande_etablissement.dart';
import 'package:ecoshop_client/features/referentiel/application/referentiel_providers.dart';
import 'package:ecoshop_client/features/referentiel/data/cached_referentiel_repository.dart';
import 'package:ecoshop_client/features/referentiel/data/referentiel_cache_store.dart';
import 'package:ecoshop_client/features/referentiel/domain/arborescence_niveau.dart';
import 'package:ecoshop_client/features/referentiel/domain/arborescence_pays.dart';
import 'package:ecoshop_client/features/referentiel/domain/paquet_referentiel.dart';
import 'package:ecoshop_client/features/referentiel/domain/pays_pedagogique.dart';
import 'package:ecoshop_client/features/referentiel/domain/referentiel_repository.dart';
import 'package:ecoshop_client/features/referentiel/domain/systeme_educatif.dart';

const _guinee = PaysPedagogique(
  codeIso: 'GN',
  nom: 'Guinée',
  typeSysteme: 'francophone_cfa',
  langueEnseignementPrincipale: 'fr',
);

/// Serveur simulé : en ligne (avec ou sans pays) ou injoignable.
class _Serveur implements ReferentielRepository {
  List<PaysPedagogique> pays = const [_guinee];
  ErreurReferentiel? panne;

  @override
  Future<List<PaysPedagogique>> paysPedagogiques() async {
    if (panne != null) throw panne!;
    return pays;
  }

  @override
  Future<List<SystemeEducatif>> systemesEducatifs() async => const [];
  @override
  Future<ArborescencePays> arborescencePays(String paysCode) async =>
      const ArborescencePays(cycles: [], niveaux: [], examens: []);
  @override
  Future<ArborescenceNiveau> arborescenceNiveau(String niveauId) async =>
      const ArborescenceNiveau(filieres: [], programmes: [], matieres: []);
  @override
  Future<List<PaquetReferentiel>> paquetsDisponibles({required String paysCode, String? niveauId}) async => const [];
}

void main() {
  late AppDatabase db;
  late _Serveur serveur;
  late CachedReferentielRepository depot;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    serveur = _Serveur();
    depot = CachedReferentielRepository(serveur, ReferentielCacheStore(db));
  });

  tearDown(() => db.close());

  Future<void> monter(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [referentielRepositoryProvider.overrideWithValue(depot)],
        child: const MaterialApp(home: EcranDemandeEtablissement()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('liste vide sur le serveur : on le dit, sans parler de connexion', (tester) async {
    serveur.pays = const [];
    await monter(tester);

    expect(find.byKey(const Key('avis_pays_vide')), findsOneWidget);
    expect(find.textContaining('Aucun pays n’est encore ouvert'), findsOneWidget);
    expect(find.textContaining('connexion'), findsNothing);
    expect(find.byKey(const Key('champ_pays')), findsNothing);
  });

  testWidgets('hors connexion sans copie sur le téléphone : message de connexion', (tester) async {
    serveur.panne = const ErreurReferentiel(ErreurReferentiel.horsLigne);
    await monter(tester);

    expect(find.byKey(const Key('avis_pays_hors_ligne')), findsOneWidget);
    expect(find.textContaining('Pas de connexion'), findsOneWidget);
  });

  testWidgets('refus du serveur : message d’erreur, pas de connexion', (tester) async {
    serveur.panne = const ErreurReferentiel('ERREUR_RESEAU');
    await monter(tester);

    expect(find.byKey(const Key('avis_pays_erreur')), findsOneWidget);
    expect(find.textContaining('Pas de connexion'), findsNothing);
  });

  testWidgets('hors connexion après un premier chargement : pays servis par le téléphone', (tester) async {
    await depot.paysPedagogiques(); // une visite en ligne garde la liste sur le téléphone
    serveur.panne = const ErreurReferentiel(ErreurReferentiel.horsLigne);
    await monter(tester);

    expect(find.byKey(const Key('champ_pays')), findsOneWidget);
    await tester.tap(find.byKey(const Key('champ_pays')));
    await tester.pumpAndSettle();
    expect(find.text('Guinée'), findsWidgets);
  });

  testWidgets('« Réessayer » recharge la liste une fois le serveur rempli', (tester) async {
    serveur.pays = const [];
    await monter(tester);
    expect(find.byKey(const Key('avis_pays_vide')), findsOneWidget);

    serveur.pays = const [_guinee];
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('avis_pays_vide')), findsNothing);
    expect(find.byKey(const Key('champ_pays')), findsOneWidget);
  });
}
