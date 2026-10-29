import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/suppression_compte/application/suppression_compte_providers.dart';
import 'package:ecoshop_client/features/suppression_compte/domain/suppression_compte.dart';
import 'package:ecoshop_client/features/suppression_compte/presentation/ecran_suppression_compte.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FauxDepot implements SuppressionCompteRepository {
  _FauxDepot({this.directionSeule = const []});

  final List<String> directionSeule;
  EtatSuppressionCompte etatCourant = const EtatSuppressionCompte.aucune();
  String? motifRecu;
  int demandes = 0;
  int annulations = 0;

  @override
  Future<EtatSuppressionCompte> etat() async => etatCourant;

  @override
  Future<ReponseSuppression> demander({String? motif}) async {
    demandes++;
    motifRecu = motif;
    if (directionSeule.isNotEmpty) return DirectionSeule(directionSeule);
    final date = DateTime.now().add(delaiReflexionSuppression);
    etatCourant = EtatSuppressionCompte(demandee: true, effectiveLe: date);
    return SuppressionProgrammee(date);
  }

  @override
  Future<bool> annuler() async {
    annulations++;
    etatCourant = const EtatSuppressionCompte.aucune();
    return true;
  }
}

/// REG-31 : suppression du compte depuis l'application (règle Google Play).
void main() {
  group('réponses du serveur', () {
    test('suppression programmée', () {
      final r = ReponseSuppression.depuisJson({'effective_le': '2026-11-05T08:00:00Z'});
      expect(r, isA<SuppressionProgrammee>());
      expect((r as SuppressionProgrammee).effectiveLe.toUtc(), DateTime.utc(2026, 11, 5, 8));
    });

    test('seule direction : les écoles sont nommées', () {
      final r = ReponseSuppression.depuisJson({
        'erreur': 'DIRECTION_SEULE',
        'ecoles': [
          {'id': 'e1', 'nom': 'Bambino Emmaüs'},
        ],
      });
      expect((r as DirectionSeule).ecoles, ['Bambino Emmaüs']);
    });

    test('état : aucune demande, ou une date', () {
      expect(EtatSuppressionCompte.depuisJson({'demandee': false}).demandee, isFalse);
      final e = EtatSuppressionCompte.depuisJson({'demandee': true, 'effective_le': '2026-11-05T08:00:00Z'});
      expect(e.demandee, isTrue);
      expect(e.effectiveLe, isNotNull);
    });
  });

  Future<_FauxDepot> monter(WidgetTester tester, {List<String> directionSeule = const [], bool enLigne = true}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final depot = _FauxDepot(directionSeule: directionSeule);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        suppressionCompteRepositoryProvider.overrideWithValue(depot),
        etatSuppressionCompteProvider.overrideWith((ref) => depot.etat()),
        estEnLigneProvider.overrideWithValue(enLigne),
      ],
      child: const MaterialApp(home: EcranSuppressionCompte()),
    ));
    await tester.pumpAndSettle();
    return depot;
  }

  Future<void> descendreJusqua(WidgetTester tester, Finder cible) =>
      tester.scrollUntilVisible(cible, 300, scrollable: find.byType(Scrollable).first);

  testWidgets('dit ce qui est effacé et gardé ; confirmation obligatoire ; puis « Garder mon compte »', (tester) async {
    final depot = await monter(tester);
    expect(find.text('Ce qui sera effacé'), findsOneWidget);
    expect(find.text('Ce qui sera gardé, et pourquoi'), findsOneWidget);
    expect(find.text('7 jours pour changer d’avis'), findsOneWidget);

    await descendreJusqua(tester, find.byKey(const Key('bouton_confirmer_suppression')));
    final bouton = find.byKey(const Key('bouton_confirmer_suppression'));
    expect(tester.widget<FilledButton>(bouton).onPressed, isNull, reason: 'case « J’ai compris » non cochée');

    await tester.enterText(find.byKey(const Key('champ_motif_suppression')), 'Mon enfant a changé d’école');
    await tester.tap(find.byKey(const Key('case_compris_suppression')));
    await tester.pump();
    await tester.tap(bouton);
    await tester.pumpAndSettle();

    expect(depot.demandes, 1);
    expect(depot.motifRecu, 'Mon enfant a changé d’école');
    expect(find.byKey(const Key('suppression_programmee')), findsOneWidget);
    expect(find.textContaining('Suppression prévue le'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bouton_garder_compte')));
    await tester.pumpAndSettle();
    expect(depot.annulations, 1);
    expect(find.byKey(const Key('suppression_programmee')), findsNothing);
  });

  testWidgets('seule direction d’une école : refus expliqué, l’école nommée', (tester) async {
    await monter(tester, directionSeule: ['Bambino Emmaüs']);
    await descendreJusqua(tester, find.byKey(const Key('case_compris_suppression')));
    await tester.tap(find.byKey(const Key('case_compris_suppression')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('bouton_confirmer_suppression')));
    await tester.pumpAndSettle();
    await descendreJusqua(tester, find.byKey(const Key('erreur_suppression')));
    expect(find.textContaining('Bambino Emmaüs'), findsOneWidget);
    expect(find.byKey(const Key('suppression_programmee')), findsNothing);
  });

  testWidgets('sans connexion : bouton grisé, explication', (tester) async {
    await monter(tester, enLigne: false);
    await descendreJusqua(tester, find.textContaining('Connectez-vous à Internet'));
    await tester.tap(find.byKey(const Key('case_compris_suppression')));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('bouton_confirmer_suppression'))).onPressed, isNull);
  });
}
