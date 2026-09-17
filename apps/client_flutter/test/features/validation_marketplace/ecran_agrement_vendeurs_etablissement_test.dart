import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/validation_marketplace/application/validation_marketplace_providers.dart';
import 'package:ecoshop_client/features/validation_marketplace/domain/agrement_vendeur.dart';
import 'package:ecoshop_client/features/validation_marketplace/domain/validation_marketplace_repository.dart';
import 'package:ecoshop_client/features/validation_marketplace/domain/vendeur_validation.dart';
import 'package:ecoshop_client/features/validation_marketplace/presentation/ecran_agrement_vendeurs_etablissement.dart';

/// Faux port [ValidationMarketplaceRepository] — voir
/// `ecran_validation_vendeurs_gsg_test.dart` pour le rationnel (couverture
/// SQL déjà faite par `tests/rls/56`).
class _FauxValidationMarketplaceRepository implements ValidationMarketplaceRepository {
  _FauxValidationMarketplaceRepository(this._agrements);

  List<AgrementVendeur> _agrements;
  String? derniereDecision;
  String? dernierEtablissementId;

  @override
  Future<List<VendeurValidation>> vendeurs() async => const [];

  @override
  Future<void> validerVendeur({required String commercantId, required String decision, String? motif}) async {}

  @override
  Future<List<AgrementVendeur>> agrementsPourEtablissement(String etablissementId) async => _agrements;

  @override
  Future<void> deciderAgrement({
    required String commercantId,
    required String etablissementId,
    required String decision,
    String? motif,
  }) async {
    derniereDecision = decision;
    dernierEtablissementId = etablissementId;
    _agrements = [
      for (final a in _agrements)
        if (a.commercantId == commercantId)
          AgrementVendeur(
            commercantId: a.commercantId,
            nomVendeur: a.nomVendeur,
            statut: decision,
            motifRefus: decision == 'refuse' ? motif : null,
          )
        else
          a,
    ];
  }
}

void main() {
  Future<void> monter(WidgetTester tester, {required ValidationMarketplaceRepository depot}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [validationMarketplaceRepositoryProvider.overrideWithValue(depot)],
        child: const MaterialApp(
          home: EcranAgrementVendeursEtablissement(etablissementId: 'e1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('liste les vendeurs validés GSG avec leur statut d\'agrément, Agréer appelle le port pour CET établissement', (tester) async {
    final depot = _FauxValidationMarketplaceRepository([
      const AgrementVendeur(commercantId: 'c1', nomVendeur: 'Vendeur Un', statut: 'en_attente'),
    ]);
    await monter(tester, depot: depot);

    expect(find.text('Vendeur Un'), findsOneWidget);
    expect(find.text('En attente de décision'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Agréer'));
    await tester.pumpAndSettle();

    expect(depot.derniereDecision, 'valide');
    expect(depot.dernierEtablissementId, 'e1');
    expect(find.text('Agréé pour cet établissement'), findsOneWidget);
  });

  testWidgets('aucun vendeur validé GSG : message explicite', (tester) async {
    final depot = _FauxValidationMarketplaceRepository(const []);
    await monter(tester, depot: depot);

    expect(find.text('Aucun vendeur validé par GSG pour le moment.'), findsOneWidget);
  });
}
