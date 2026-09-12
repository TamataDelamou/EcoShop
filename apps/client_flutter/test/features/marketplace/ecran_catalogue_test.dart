import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/marketplace/application/marketplace_providers.dart';
import 'package:ecoshop_client/features/marketplace/domain/commercant.dart';
import 'package:ecoshop_client/features/marketplace/presentation/ecran_catalogue.dart';

const _commercants = [
  Commercant(id: 'c1', nom: 'Librairie du Savoir'),
  Commercant(id: 'c2', nom: 'Uniformes Sahel'),
];

Future<void> _monter(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        commercantsProvider.overrideWith((ref) async => _commercants),
      ],
      child: const MaterialApp(home: Scaffold(body: EcranCatalogue())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    "Mode par défaut « cartes » : rendu inchangé (Card + ListTile, un par commerçant)",
    (tester) async {
      await _monter(tester);

      expect(find.text('Librairie du Savoir'), findsOneWidget);
      expect(find.text('Uniformes Sahel'), findsOneWidget);
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.byType(GridView), findsNothing);
    },
  );

  testWidgets('Bascule vers « liste » : plus de Card, une ligne dense par commerçant', (tester) async {
    await _monter(tester);

    await tester.tap(find.byIcon(Icons.view_list_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Librairie du Savoir'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(Divider), findsWidgets);
  });

  testWidgets('Bascule vers « grille » : GridView avec une tuile par commerçant', (tester) async {
    await _monter(tester);

    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Librairie du Savoir'), findsOneWidget);
    expect(find.text('Uniformes Sahel'), findsOneWidget);
  });
}
