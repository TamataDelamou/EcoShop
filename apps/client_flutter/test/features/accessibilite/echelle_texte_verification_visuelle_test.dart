import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/coquille/presentation/coquille_app.dart';
import 'package:ecoshop_client/features/coquille/presentation/garde_session.dart';
import 'package:ecoshop_client/features/referentiel/application/referentiel_providers.dart';
import 'package:ecoshop_client/features/regionalisation/application/regionalisation_providers.dart';
import 'package:ecoshop_client/features/themes/presentation/ecran_preferences_apparence.dart';

import '../../support/faux_auth_repository.dart';

class _OnboardingRegionalisationToujoursVu extends OnboardingRegionalisationNotifier {
  @override
  Future<bool> build() async => true;
}

/// Vérification visuelle « aucun texte à taille fixe codée en dur ne casse »
/// (D4, §34.9) — à la plus grande échelle proposée (`tresGrand`, ×1.3), sur
/// les écrans les plus fréquentés plutôt qu'un balayage exhaustif de
/// l'application : la coquille (5 onglets racine, deux rôles aux périmètres
/// différents) et `EcranPreferencesApparence` lui-même, devenu l'écran le
/// plus chargé en sections depuis D3/D4. Un dépassement (`RenderFlex
/// overflowed`) remonte comme une erreur signalée par le framework — capturée
/// ici via `tester.takeException()`, qui échoue le test s'il y en a une.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.pourTests(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> monter(WidgetTester tester, {required FauxAuthRepository faux}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(faux),
          sessionOuverteProvider.overrideWithValue(true),
          databaseProvider.overrideWithValue(db),
          onboardingRegionalisationVuProvider.overrideWith(_OnboardingRegionalisationToujoursVu.new),
        ],
        child: MaterialApp(
          builder: (context, enfant) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(textScaler: const TextScaler.linear(1.3)),
              child: enfant!,
            );
          },
          home: const RacineApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Surface de test par défaut (800×600) : `large` (coquille_app.dart) est
  // vrai dès 720 px, donc c'est le `NavigationRail` qui est rendu, pas la
  // `NavigationBar` mobile — on cible le type précisément plutôt que le
  // texte seul (qui apparaît deux fois : libellé de navigation + PageHeader).
  Future<void> visiterTousLesOnglets(WidgetTester tester) async {
    for (final onglet in OngletCoquille.values) {
      final destination = find.widgetWithText(NavigationRailDestination, onglet.libelle);
      if (tester.any(destination)) {
        await tester.tap(destination);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'onglet ${onglet.libelle}');
      }
    }
  }

  testWidgets('rôle direction : les 4 onglets accessibles ne débordent pas à ×1.3', (tester) async {
    await monter(
      tester,
      faux: FauxAuthRepository(profil: profilTest(role: RoleRacine.direction)),
    );
    expect(tester.takeException(), isNull);

    await visiterTousLesOnglets(tester);
  });

  testWidgets('rôle élève : les 5 onglets (dont Révision) ne débordent pas à ×1.3', (tester) async {
    await monter(
      tester,
      faux: FauxAuthRepository(profil: profilTest(role: RoleRacine.eleve), fiche: true),
    );
    expect(tester.takeException(), isNull);

    await visiterTousLesOnglets(tester);
  });

  testWidgets('EcranPreferencesApparence (écran le plus chargé en sections) ne déborde pas à ×1.3', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          etablissementActifProvider.overrideWithValue(null),
          paysPedagogiquesProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          builder: (context, enfant) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(textScaler: const TextScaler.linear(1.3)),
              child: enfant!,
            );
          },
          home: const EcranPreferencesApparence(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
