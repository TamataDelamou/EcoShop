import 'package:drift/native.dart';
import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/erreurs/gestion_erreurs.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/core/theme/app_theme_variant.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/cgu/application/cgu_providers.dart';
import 'package:ecoshop_client/features/cgu/domain/cgu_statut.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/referentiel/application/referentiel_providers.dart';
import 'package:ecoshop_client/features/referentiel/data/cached_referentiel_repository.dart';
import 'package:ecoshop_client/features/referentiel/data/referentiel_cache_store.dart';
import 'package:ecoshop_client/features/referentiel/domain/arborescence_niveau.dart';
import 'package:ecoshop_client/features/referentiel/domain/arborescence_pays.dart';
import 'package:ecoshop_client/features/referentiel/domain/paquet_referentiel.dart';
import 'package:ecoshop_client/features/referentiel/domain/pays_pedagogique.dart';
import 'package:ecoshop_client/features/referentiel/domain/referentiel_repository.dart';
import 'package:ecoshop_client/features/referentiel/domain/systeme_educatif.dart';
import 'package:ecoshop_client/features/regionalisation/application/regionalisation_providers.dart';
import 'package:ecoshop_client/features/themes/application/theme_providers.dart';
import 'package:ecoshop_client/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../support/faux_auth_repository.dart';

/// Défaut constaté sur l'APK (journal du 25/10) : sans réseau, la liste des
/// pays échoue (« Failed host lookup ») ; le thème la lisait avec `.value`,
/// qui relance l'erreur jusqu'à la racine : écran gris, sur le profil comme
/// sur l'accueil.

/// Serveur du référentiel injoignable : même erreur que sur le téléphone.
class _ReferentielSansReseau implements ReferentielRepository {
  Never _panne() => throw http.ClientException(
      "Failed host lookup: 'nlydvaszgdtjohneggqt.supabase.co'");

  @override
  Future<List<PaysPedagogique>> paysPedagogiques() async => _panne();
  @override
  Future<List<SystemeEducatif>> systemesEducatifs() async => _panne();
  @override
  Future<ArborescencePays> arborescencePays(String paysCode) async => _panne();
  @override
  Future<ArborescenceNiveau> arborescenceNiveau(String niveauId) async => _panne();
  @override
  Future<List<PaquetReferentiel>> paquetsDisponibles({required String paysCode, String? niveauId}) async => _panne();
}

class _RegionalisationVue extends OnboardingRegionalisationNotifier {
  @override
  Future<bool> build() async => true;
}

class _CguRienAAccepter extends CguStatutNotifier {
  @override
  Future<CguStatut?> build() async => null;
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.pourTests(NativeDatabase.memory()));
  tearDown(() => db.close());

  const ecoleGuinee = Etablissement(id: 'e1', nom: 'Bambino', slug: 'bambino', paysCode: 'GN');

  List<Override> sansReseau() => [
        authRepositoryProvider.overrideWithValue(FauxAuthRepository(
          profil: profilTest(role: RoleRacine.parent, etablissementActifId: 'e1'),
          etablissements: const [ecoleGuinee],
        )),
        sessionOuverteProvider.overrideWithValue(true),
        databaseProvider.overrideWithValue(db),
        estEnLigneProvider.overrideWithValue(false),
        onboardingRegionalisationVuProvider.overrideWith(_RegionalisationVue.new),
        cguStatutProvider.overrideWith(_CguRienAAccepter.new),
        // Aucune copie du référentiel sur le téléphone, serveur injoignable.
        referentielRepositoryProvider.overrideWith(
          (ref) => CachedReferentielRepository(_ReferentielSansReseau(), ReferentielCacheStore(db)),
        ),
      ];

  testWidgets('sans réseau ni copie du référentiel : accueil, profil, accueil — sans plantage', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: sansReseau(),
      child: const EcoShopApp(configure: true),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Accueil'), findsWidgets, reason: 'la coquille est affichée');

    // Profil, puis retour à l'accueil.
    await tester.tap(find.byKey(const Key('raccourci_profil')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Accueil').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ecran_erreur_inattendue')), findsNothing);

    // Charte par défaut tant que le pays n'est pas connu sur le téléphone.
    final conteneur = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    expect(conteneur.read(themeVariantProvider), AppThemeVariant.francophoneCfa);
  });

  testWidgets('écran d’erreur lisible à la place de l’écran gris, retour à l’accueil', (tester) async {
    final builderAvant = ErrorWidget.builder;
    final onErrorAvant = FlutterError.onError;
    final navigateur = GlobalKey<NavigatorState>();
    GestionErreurs.installer(navigateur: navigateur);

    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigateur,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _PageQuiPlante()),
            ),
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    tester.takeException();

    expect(find.text('Un problème est survenu'), findsOneWidget);
    expect(GestionErreurs.dernieres.last, contains('EcoShop-ERREUR'));

    await tester.tap(find.byKey(const Key('bouton_revenir_accueil')));
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir'), findsOneWidget, reason: 'retour à la première page');

    // flutter_test exige ses propres gestionnaires à la fin du corps du test.
    ErrorWidget.builder = builderAvant;
    FlutterError.onError = onErrorAvant;
  });
}

class _PageQuiPlante extends StatelessWidget {
  const _PageQuiPlante();

  @override
  Widget build(BuildContext context) => throw StateError('panne simulée');
}
