import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/cgu/application/cgu_providers.dart';
import 'package:ecoshop_client/features/cgu/domain/cgu_repository.dart';
import 'package:ecoshop_client/features/cgu/domain/cgu_statut.dart';
import 'package:ecoshop_client/features/cgu/presentation/ecran_cgu.dart';

/// Faux port [CguRepository] — la couche SQL (RLS, `cgu_statut()`, registre
/// immuable des acceptations) a déjà été vérifiée en local (pgTAP,
/// `tests/rls/54`) ; ce test-ci vérifie uniquement le câblage de l'écran.
class _FauxCguRepository implements CguRepository {
  _FauxCguRepository(this._statut);

  CguStatut? _statut;
  bool accepterAppele = false;

  @override
  Future<CguStatut?> statut() async => _statut;

  @override
  Future<void> accepter(String cguVersionId) async {
    accepterAppele = true;
    final statut = _statut;
    if (statut == null) return;
    _statut = CguStatut(
      cguVersionId: statut.cguVersionId,
      parcours: statut.parcours,
      numeroVersion: statut.numeroVersion,
      contenu: statut.contenu,
      publieeLe: statut.publieeLe,
      acceptee: true,
    );
  }
}

CguStatut _statutTest({required bool acceptee}) => CguStatut(
      cguVersionId: 'v1',
      parcours: 'simplifie',
      numeroVersion: '2026-09-15-v1',
      contenu: 'Texte des CGU pour le test.',
      publieeLe: DateTime(2026, 9, 15),
      acceptee: acceptee,
    );

void main() {
  Future<void> monter(WidgetTester tester, {required CguRepository depot}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [cguRepositoryProvider.overrideWithValue(depot)],
        child: const MaterialApp(home: EcranCgu()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('CGU non acceptées : affiche le contenu et un bouton Accepter actif', (tester) async {
    final depot = _FauxCguRepository(_statutTest(acceptee: false));
    await monter(tester, depot: depot);

    expect(find.text('Texte des CGU pour le test.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Accepter'), findsOneWidget);
    expect(find.text('Acceptées.'), findsNothing);
  });

  testWidgets('Accepter appelle le port et fait disparaître le bouton', (tester) async {
    final depot = _FauxCguRepository(_statutTest(acceptee: false));
    await monter(tester, depot: depot);

    await tester.tap(find.widgetWithText(FilledButton, 'Accepter'));
    await tester.pumpAndSettle();

    expect(depot.accepterAppele, isTrue);
    expect(find.text('Acceptées.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Accepter'), findsNothing);
  });

  testWidgets('CGU déjà acceptées : aucun bouton, message de confirmation', (tester) async {
    final depot = _FauxCguRepository(_statutTest(acceptee: true));
    await monter(tester, depot: depot);

    expect(find.text('Acceptées.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Accepter'), findsNothing);
  });

  testWidgets('Aucune CGU à accepter (rôle hors périmètre ou non choisi) : message explicite', (tester) async {
    final depot = _FauxCguRepository(null);
    await monter(tester, depot: depot);

    expect(find.text('Aucune condition à accepter pour ce compte.'), findsOneWidget);
  });
}
