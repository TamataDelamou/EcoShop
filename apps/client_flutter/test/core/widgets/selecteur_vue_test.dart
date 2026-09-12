import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/widgets/selecteur_vue.dart';

void main() {
  testWidgets('Sélectionner un segment déclenche onChanged avec le bon mode', (tester) async {
    ModeAffichage? recu;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelecteurVue(
            mode: ModeAffichage.cartes,
            onChanged: (m) => recu = m,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pumpAndSettle();

    expect(recu, ModeAffichage.grille);
  });

  testWidgets('Les trois modes sont représentés (liste/grille/cartes)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelecteurVue(mode: ModeAffichage.liste, onChanged: (_) {}),
        ),
      ),
    );

    expect(find.byIcon(Icons.view_list_outlined), findsOneWidget);
    expect(find.byIcon(Icons.grid_view_outlined), findsOneWidget);
    expect(find.byIcon(Icons.view_agenda_outlined), findsOneWidget);
  });
}
