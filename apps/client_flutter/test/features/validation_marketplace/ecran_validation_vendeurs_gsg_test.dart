import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/validation_marketplace/application/validation_marketplace_providers.dart';
import 'package:ecoshop_client/features/validation_marketplace/domain/agrement_vendeur.dart';
import 'package:ecoshop_client/features/validation_marketplace/domain/validation_marketplace_repository.dart';
import 'package:ecoshop_client/features/validation_marketplace/domain/vendeur_validation.dart';
import 'package:ecoshop_client/features/validation_marketplace/presentation/ecran_validation_vendeurs_gsg.dart';

/// Faux port [ValidationMarketplaceRepository] — la couche SQL (RLS, ordre
/// des paliers GSG -> établissement) a déjà été vérifiée en local (pgTAP,
/// `tests/rls/56`) ; ce test-ci vérifie uniquement le câblage de l'écran.
class _FauxValidationMarketplaceRepository implements ValidationMarketplaceRepository {
  _FauxValidationMarketplaceRepository(this._vendeurs);

  List<VendeurValidation> _vendeurs;
  String? derniereDecision;
  String? dernierMotif;

  @override
  Future<List<VendeurValidation>> vendeurs() async => _vendeurs;

  @override
  Future<void> validerVendeur({required String commercantId, required String decision, String? motif}) async {
    derniereDecision = decision;
    dernierMotif = motif;
    _vendeurs = [
      for (final v in _vendeurs)
        if (v.commercantId == commercantId)
          VendeurValidation(
            commercantId: v.commercantId,
            nom: v.nom,
            statutValidation: decision,
            motifRefus: decision == 'refuse' ? motif : null,
          )
        else
          v,
    ];
  }

  @override
  Future<List<AgrementVendeur>> agrementsPourEtablissement(String etablissementId) async => const [];

  @override
  Future<void> deciderAgrement({
    required String commercantId,
    required String etablissementId,
    required String decision,
    String? motif,
  }) async {}
}

void main() {
  Future<void> monter(WidgetTester tester, {required ValidationMarketplaceRepository depot}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [validationMarketplaceRepositoryProvider.overrideWithValue(depot)],
        child: const MaterialApp(home: EcranValidationVendeursGsg()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('liste les vendeurs avec leur statut, Valider appelle le port', (tester) async {
    final depot = _FauxValidationMarketplaceRepository([
      const VendeurValidation(commercantId: 'c1', nom: 'Vendeur Un', statutValidation: 'en_attente'),
    ]);
    await monter(tester, depot: depot);

    expect(find.text('Vendeur Un'), findsOneWidget);
    expect(find.text('En attente'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Valider'));
    await tester.pumpAndSettle();

    expect(depot.derniereDecision, 'valide');
    expect(find.text('Validé'), findsOneWidget);
  });

  testWidgets('Refuser demande un motif puis appelle le port', (tester) async {
    final depot = _FauxValidationMarketplaceRepository([
      const VendeurValidation(commercantId: 'c1', nom: 'Vendeur Un', statutValidation: 'en_attente'),
    ]);
    await monter(tester, depot: depot);

    await tester.tap(find.widgetWithText(TextButton, 'Refuser'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'dossier incomplet');
    await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
    await tester.pumpAndSettle();

    expect(depot.derniereDecision, 'refuse');
    expect(depot.dernierMotif, 'dossier incomplet');
    expect(find.textContaining('Refusé'), findsOneWidget);
  });

  testWidgets('aucun vendeur : message explicite', (tester) async {
    final depot = _FauxValidationMarketplaceRepository(const []);
    await monter(tester, depot: depot);

    expect(find.text('Aucun vendeur enregistré.'), findsOneWidget);
  });
}
