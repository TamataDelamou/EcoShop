import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/widgets/page_header.dart';

void main() {
  testWidgets('Affiche le titre et le descriptif fournis', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PageHeader(titre: 'Scolarité', descriptif: 'Inscriptions, notes et absences'),
        ),
      ),
    );

    expect(find.text('Scolarité'), findsOneWidget);
    expect(find.text('Inscriptions, notes et absences'), findsOneWidget);
  });
}
