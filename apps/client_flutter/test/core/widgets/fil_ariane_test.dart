import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/widgets/fil_ariane.dart';

void main() {
  testWidgets('Sans contexte : affiche "Onglet > Écran"', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(bottom: const FilAriane(onglet: 'Scolarité', ecran: 'Sanctions')),
        ),
      ),
    );

    final texte = tester.widget<Text>(find.byType(Text));
    final span = texte.textSpan as TextSpan;
    final texteComplet = span.toPlainText();

    expect(texteComplet, contains('Scolarité'));
    expect(texteComplet, contains('Sanctions'));
    expect(texteComplet, isNot(contains('—')));
  });

  testWidgets('Avec contexte : affiche "Onglet > Écran — Entité"', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            bottom: const FilAriane(onglet: 'Scolarité', ecran: 'Sanctions', contexte: 'Aissatou'),
          ),
        ),
      ),
    );

    final texte = tester.widget<Text>(find.byType(Text));
    final texteComplet = (texte.textSpan as TextSpan).toPlainText();

    expect(texteComplet, contains('Scolarité'));
    expect(texteComplet, contains('Sanctions'));
    expect(texteComplet, contains('— '));
    expect(texteComplet, contains('Aissatou'));
    // Ordre attendu : onglet avant écran avant contexte.
    expect(
      texteComplet.indexOf('Scolarité') < texteComplet.indexOf('Sanctions') &&
          texteComplet.indexOf('Sanctions') < texteComplet.indexOf('Aissatou'),
      isTrue,
    );
  });
}
