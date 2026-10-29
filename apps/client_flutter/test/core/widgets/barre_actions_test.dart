import 'package:ecoshop_client/core/widgets/barre_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// REG-28 : les actions d'un écran sont posées sous le titre, avec leur
/// libellé, et non plus en icônes seules dans la barre de titre.
void main() {
  testWidgets('libellés visibles, actions appuyables, rien dans la barre de titre', (tester) async {
    final ouvertes = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Classe 6e A'),
          bottom: BarreActions(actions: [
            ActionEcran(cle: const Key('a_appel'), icone: Icons.fact_check_outlined, libelle: 'Appel', principale: true,
                onPressed: () => ouvertes.add('appel')),
            ActionEcran(icone: Icons.payments_outlined, libelle: 'Frais', onPressed: () => ouvertes.add('frais')),
            const ActionEcran(icone: Icons.gavel_outlined, libelle: 'Proclamation', onPressed: null),
          ]),
        ),
      ),
    ));

    expect(find.text('Appel'), findsOneWidget);
    expect(find.text('Frais'), findsOneWidget);
    expect(find.text('Proclamation'), findsOneWidget);
    expect(tester.widget<AppBar>(find.byType(AppBar)).actions, isNull);

    await tester.tap(find.byKey(const Key('a_appel')));
    await tester.tap(find.text('Frais'));
    await tester.tap(find.text('Proclamation'));
    expect(ouvertes, ['appel', 'frais'], reason: 'action grisée : sans effet');
  });

  testWidgets('avec des onglets : actions au-dessus, onglets dessous, hauteur additionnée', (tester) async {
    const onglets = TabBar(tabs: [Tab(text: 'Élèves'), Tab(text: 'Enseignants')]);
    final barre = BarreActions(
      actions: [ActionEcran(icone: Icons.edit_outlined, libelle: 'Modifier', onPressed: () {})],
      sousBarre: onglets,
    );
    expect(barre.preferredSize.height, greaterThan(onglets.preferredSize.height));
    expect(const BarreActions(actions: []).preferredSize.height, 0);

    await tester.pumpWidget(MaterialApp(
      home: DefaultTabController(
        length: 2,
        child: Scaffold(appBar: AppBar(title: const Text('Circuit'), bottom: barre)),
      ),
    ));
    expect(tester.getCenter(find.text('Modifier')).dy, lessThan(tester.getCenter(find.text('Élèves')).dy));
  });

  testWidgets('beaucoup d’actions sur un petit téléphone : la rangée défile, pas de débordement', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Présence du jour'),
          bottom: BarreActions(actions: [
            for (final l in ['Ouvrir le portail', 'Cartes élèves', 'Relancer les impayés', 'Crédits SMS', 'Réglages'])
              ActionEcran(icone: Icons.circle_outlined, libelle: l, onPressed: () {}),
          ]),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Réglages'), findsNothing, reason: 'hors écran au départ');
    // Fait défiler la rangée jusqu'à la dernière action, quelle que soit la
    // largeur réelle des boutons.
    await tester.scrollUntilVisible(
      find.text('Réglages'),
      200,
      scrollable: find.descendant(of: find.byKey(const Key('barre_actions')), matching: find.byType(Scrollable)),
    );
    expect(find.text('Réglages'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
