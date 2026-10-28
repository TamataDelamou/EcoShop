import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/referentiel/application/referentiel_providers.dart';
import 'package:ecoshop_client/features/themes/application/theme_providers.dart';
import 'package:ecoshop_client/features/themes/data/identite_visuelle_repository.dart';
import 'package:ecoshop_client/features/themes/presentation/ecran_identite_visuelle.dart';

/// Faux port — la sécurité (Direction seule, dossier du logo, format de la
/// couleur) est vérifiée côté base par tests/rls/60.
class _FauxDepot implements IdentiteVisuelleRepository {
  String? couleurEnregistree;
  String? logoEnregistre;
  int enregistrements = 0;
  int televersements = 0;
  ErreurIdentiteVisuelle? erreur;

  @override
  Future<String> televerserLogo(String etablissementId, Uint8List octets, String extension) async {
    televersements++;
    return '$etablissementId/logo-test.$extension';
  }

  @override
  Future<void> enregistrer({required String etablissementId, String? couleurHex, String? logoChemin, String? slogan}) async {
    if (erreur != null) throw erreur!;
    enregistrements++;
    couleurEnregistree = couleurHex;
    logoEnregistre = logoChemin;
  }
}

// PNG 1×1 valide.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

const _etablissement = Etablissement(id: 'e1', nom: 'Bambino Emmaüs', slug: 'bambino');

Future<void> _monter(WidgetTester tester, _FauxDepot depot) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        identiteVisuelleRepositoryProvider.overrideWithValue(depot),
        selecteurLogoProvider.overrideWithValue(() async => (octets: _png, extension: 'png')),
        etablissementActifProvider.overrideWithValue(_etablissement),
        paysPedagogiquesProvider.overrideWith((ref) async => const []),
        mesEtablissementsProvider.overrideWith((ref) async => const [_etablissement]),
      ],
      child: const MaterialApp(home: EcranIdentiteVisuelle(etablissement: _etablissement)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('couleur du nuancier + logo : déposé puis enregistré en #RRGGBB', (tester) async {
    final depot = _FauxDepot();
    await _monter(tester, depot);

    expect(find.text('Aperçu'), findsOneWidget);
    expect(find.text('Clair'), findsOneWidget);
    expect(find.text('Sombre'), findsOneWidget);

    await tester.tap(find.byKey(const Key('couleur_#15803D')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('champ_hex'))).controller!.text, '#15803D');

    await tester.tap(find.byKey(const Key('bouton_choisir_logo')));
    await tester.pumpAndSettle();
    expect(find.text('Retirer le logo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bouton_enregistrer_identite')));
    await tester.pumpAndSettle();

    expect(depot.televersements, 1);
    expect(depot.couleurEnregistree, '#15803D');
    expect(depot.logoEnregistre, 'e1/logo-test.png');
    expect(find.textContaining('Identité enregistrée'), findsOneWidget);

    // Second enregistrement sans nouvelle image : aucun nouveau dépôt.
    await tester.tap(find.byKey(const Key('bouton_enregistrer_identite')));
    await tester.pumpAndSettle();
    expect(depot.televersements, 1);
    expect(depot.enregistrements, 2);
  });

  testWidgets('une couleur trop claire est signalée comme ajustée pour rester lisible', (tester) async {
    await _monter(tester, _FauxDepot());

    await tester.enterText(find.byKey(const Key('champ_hex')), '#FFE600');
    await tester.pumpAndSettle();

    expect(find.textContaining('ajustée automatiquement'), findsOneWidget);
  });

  testWidgets('retour à la charte du pays : couleur effacée', (tester) async {
    final depot = _FauxDepot();
    await _monter(tester, depot);

    await tester.tap(find.byKey(const Key('couleur_#B91C1C')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('couleur_defaut')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bouton_enregistrer_identite')));
    await tester.pumpAndSettle();

    expect(depot.couleurEnregistree, isNull);
  });

  testWidgets('refus serveur : message clair', (tester) async {
    final depot = _FauxDepot()..erreur = const ErreurIdentiteVisuelle('ACCES_REFUSE');
    await _monter(tester, depot);

    await tester.tap(find.byKey(const Key('bouton_enregistrer_identite')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Seule la Direction'), findsOneWidget);
  });
}
