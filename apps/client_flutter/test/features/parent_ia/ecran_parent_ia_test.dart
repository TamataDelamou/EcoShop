import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/parent_ia/application/parent_ia_providers.dart';
import 'package:ecoshop_client/features/parent_ia/domain/parent_ia_config.dart';
import 'package:ecoshop_client/features/parent_ia/domain/parent_ia_repository.dart';
import 'package:ecoshop_client/features/parent_ia/domain/restriction_parent_ia.dart';
import 'package:ecoshop_client/features/parent_ia/presentation/ecran_parent_ia_activation.dart';
import 'package:ecoshop_client/features/parent_ia/presentation/ecran_parent_ia_declaration_usage.dart';
import 'package:ecoshop_client/features/parent_ia/presentation/ecran_parent_ia_historique.dart';

/// Faux port [ParentIaRepository] — la couche SQL/Edge Function elle-même a
/// déjà été vérifiée en local (pgTAP + un vrai appel HTTP bout-en-bout,
/// M16 sous-livrable 4/7) ; ce test-ci vérifie uniquement le câblage des
/// écrans Flutter (consentement obligatoire, verrou affiché, déclaration).
class _FauxParentIaRepository implements ParentIaRepository {
  ParentIaConfig _config = ParentIaConfig.inactif();
  final List<RestrictionParentIa> _historique;
  bool activationAppelee = false;
  bool desactivationAppelee = false;
  String? dernierAppPrincipale;
  int? dernieresMinutes;

  _FauxParentIaRepository({this._historique = const []});

  @override
  Future<ParentIaConfig> configuration(String ficheEleveId) async => _config;

  @override
  Future<List<RestrictionParentIa>> historique(String ficheEleveId) async =>
      _historique;

  @override
  Future<ParentIaConfig> activer({
    required String ficheEleveId,
    required bool consentement,
  }) async {
    activationAppelee = true;
    _config = ParentIaConfig(
      actif: true,
      dateActivation: DateTime.now(),
      verrouilleJusquau: DateTime.now().add(const Duration(days: 30)),
      consentementEleve: consentement,
    );
    return _config;
  }

  @override
  Future<ParentIaConfig> desactiver(String ficheEleveId) async {
    desactivationAppelee = true;
    return _config;
  }

  @override
  Future<bool> declarerUsage({
    required String ficheEleveId,
    required String appPrincipale,
    required int minutes,
  }) async {
    dernierAppPrincipale = appPrincipale;
    dernieresMinutes = minutes;
    return true;
  }
}

void main() {
  Future<void> monter(
    WidgetTester tester,
    Widget ecran, {
    required ParentIaRepository depot,
  }) async {
    // Surface de test agrandie : ces écrans (ListView de plusieurs cartes)
    // dépassent la hauteur par défaut (600px), laissant le dernier bouton
    // hors de la zone que Scrollable.ensureVisible peut réellement amener
    // dans les bornes du canevas — plus simple et plus fiable que de
    // manipuler le défilement dans chaque test.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [parentIaRepositoryProvider.overrideWithValue(depot)],
        child: MaterialApp(home: ecran),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('EcranParentIaActivation', () {
    testWidgets(
      'bouton Activer désactivé tant que le consentement n\'est pas coché',
      (tester) async {
        final depot = _FauxParentIaRepository();
        await monter(
          tester,
          const EcranParentIaActivation(ficheEleveId: 'f1'),
          depot: depot,
        );

        expect(find.text('PARENT IA est désactivé'), findsOneWidget);
        final finderBouton = find.widgetWithText(
          FilledButton,
          'Activer PARENT IA',
        );

        final bouton = tester.widget<FilledButton>(finderBouton);
        expect(bouton.onPressed, isNull);

        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();

        final boutonActive = tester.widget<FilledButton>(finderBouton);
        expect(boutonActive.onPressed, isNotNull);

        await tester.tap(finderBouton);
        await tester.pumpAndSettle();

        expect(depot.activationAppelee, isTrue);
        expect(find.text('PARENT IA est actif'), findsOneWidget);
      },
    );

    testWidgets(
      'actif et verrouillé : le bouton de désactivation est désactivé et affiche le compte à rebours',
      (tester) async {
        final depot = _FauxParentIaRepository()
          .._config = ParentIaConfig(
            actif: true,
            dateActivation: DateTime.now(),
            verrouilleJusquau: DateTime.now().add(const Duration(days: 12)),
            consentementEleve: true,
          );

        await monter(
          tester,
          const EcranParentIaActivation(ficheEleveId: 'f1'),
          depot: depot,
        );

        expect(find.textContaining('j verrou'), findsOneWidget);
        // Le bouton affiche « Verrouillé — N j restants » et est désactivé.
        expect(find.textContaining('Verrouillé —'), findsOneWidget);
        final boutonDesactiver = tester.widget<OutlinedButton>(
          find.ancestor(
            of: find.textContaining('Verrouillé —'),
            matching: find.byType(OutlinedButton),
          ),
        );
        expect(boutonDesactiver.onPressed, isNull);
        expect(depot.desactivationAppelee, isFalse);
      },
    );

    testWidgets(
      'actif et déverrouillé : tenter de désactiver appelle le port',
      (tester) async {
        final depot = _FauxParentIaRepository()
          .._config = const ParentIaConfig(
            actif: true,
            consentementEleve: true,
          );

        await monter(
          tester,
          const EcranParentIaActivation(ficheEleveId: 'f1'),
          depot: depot,
        );

        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Désactiver PARENT IA'),
        );
        await tester.pumpAndSettle();

        expect(depot.desactivationAppelee, isTrue);
      },
    );

    testWidgets('actif : navigue vers la déclaration d\'usage', (tester) async {
      final depot = _FauxParentIaRepository()
        .._config = const ParentIaConfig(actif: true, consentementEleve: true);

      await monter(
        tester,
        const EcranParentIaActivation(ficheEleveId: 'f1'),
        depot: depot,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Déclarer mon usage'));
      await tester.pumpAndSettle();

      expect(find.byType(EcranParentIaDeclarationUsage), findsOneWidget);
    });
  });

  group('EcranParentIaDeclarationUsage', () {
    testWidgets('envoie l\'app choisie et les minutes du slider', (
      tester,
    ) async {
      final depot = _FauxParentIaRepository();
      await monter(
        tester,
        const EcranParentIaDeclarationUsage(ficheEleveId: 'f1'),
        depot: depot,
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'TikTok'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(FilledButton, 'Envoyer pour analyse'),
      );
      await tester.pumpAndSettle();

      expect(depot.dernierAppPrincipale, 'TikTok');
      expect(depot.dernieresMinutes, 60); // valeur initiale du slider
    });
  });

  group('EcranParentIaHistorique', () {
    testWidgets('affiche la configuration et la liste des restrictions', (
      tester,
    ) async {
      final depot = _FauxParentIaRepository(
        historique: [
          RestrictionParentIa(
            id: 'r1',
            appConcernee: 'TikTok',
            tempsUsageMinutes: 180,
            niveauRisqueEchec: 80,
            matiereARisque: 'Mathématiques',
            sourceDonnee: 'declaration_manuelle',
            createdAt: DateTime(2026, 3, 1),
          ),
        ],
      )..activer(ficheEleveId: 'f1', consentement: true);

      await monter(
        tester,
        const EcranParentIaHistorique(
          ficheEleveId: 'f1',
          nomEleve: 'Fatoumata',
        ),
        depot: depot,
      );

      expect(find.text('PARENT IA — Fatoumata'), findsOneWidget);
      expect(find.textContaining('TikTok — 180 min'), findsOneWidget);
      expect(find.textContaining('Mathématiques'), findsOneWidget);
    });

    testWidgets('historique vide affiche un message explicite', (tester) async {
      final depot = _FauxParentIaRepository();
      await monter(
        tester,
        const EcranParentIaHistorique(
          ficheEleveId: 'f1',
          nomEleve: 'Fatoumata',
        ),
        depot: depot,
      );

      expect(
        find.text('Aucune restriction déclenchée pour le moment.'),
        findsOneWidget,
      );
    });
  });
}
