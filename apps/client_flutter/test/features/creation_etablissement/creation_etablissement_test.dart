import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/creation_etablissement/application/creation_etablissement_providers.dart';
import 'package:ecoshop_client/features/creation_etablissement/domain/demande_etablissement.dart';
import 'package:ecoshop_client/features/creation_etablissement/presentation/carte_demande_etablissement.dart';
import 'package:ecoshop_client/features/creation_etablissement/presentation/ecran_validation_etablissements_gsg.dart';
import 'package:ecoshop_client/features/referentiel/application/referentiel_providers.dart';
import 'package:ecoshop_client/features/referentiel/domain/pays_pedagogique.dart';

/// Faux port — droits, unicité de la demande, création de l'établissement et
/// attribution du rôle Direction sont vérifiés côté base (tests/rls/61).
class _FauxDepot implements CreationEtablissementRepository {
  _FauxDepot({this.demande, this.aTraiter = const []});

  DemandeEtablissement? demande;
  List<DemandeATraiter> aTraiter;
  SaisieDemandeEtablissement? saisie;
  final List<({String id, bool accepter, String? motif})> decisions = [];

  @override
  Future<String> soumettre(SaisieDemandeEtablissement s) async {
    saisie = s;
    demande = DemandeEtablissement(
      id: 'd1',
      nomEtablissement: s.nom,
      paysCode: s.paysCode,
      ville: s.ville,
      statut: StatutDemandeEtablissement.enAttente,
      creeLe: DateTime(2026, 10, 17),
    );
    return 'd1';
  }

  @override
  Future<DemandeEtablissement?> maDerniereDemande() async => demande;

  @override
  Future<List<DemandeATraiter>> demandesATraiter() async => aTraiter;

  @override
  Future<void> traiter({required String demandeId, required bool accepter, String? motif}) async {
    decisions.add((id: demandeId, accepter: accepter, motif: motif));
    aTraiter = aTraiter.where((d) => d.id != demandeId).toList();
  }
}

const _guinee = PaysPedagogique(
  codeIso: 'GN',
  nom: 'Guinée',
  typeSysteme: 'francophone_cfa',
  langueEnseignementPrincipale: 'fr',
  deviseCode: 'GNF',
);

Future<void> _monter(WidgetTester tester, _FauxDepot depot, Widget ecran) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        creationEtablissementRepositoryProvider.overrideWithValue(depot),
        paysPedagogiquesProvider.overrideWith((ref) async => const [_guinee]),
      ],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ecran))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('fondateur : demande envoyée puis suivie sur la carte', (tester) async {
    final depot = _FauxDepot();
    await _monter(tester, depot, const CarteDemandeEtablissement());

    expect(find.text('Vous dirigez une école ?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bouton_creer_etablissement')));
    await tester.pumpAndSettle();

    // Formulaire incomplet : rien n'est envoyé.
    await tester.tap(find.byKey(const Key('bouton_envoyer_demande')));
    await tester.pumpAndSettle();
    expect(depot.saisie, isNull);
    expect(find.text('Au moins 3 caractères'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('champ_nom_etablissement')), 'Groupe Scolaire Bambino Emmaüs');
    await tester.tap(find.byKey(const Key('champ_pays')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guinée').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('champ_ville')), 'Conakry');
    await tester.enterText(find.byKey(const Key('champ_telephone')), '+224 620 11 22 33');
    await tester.tap(find.byKey(const Key('bouton_envoyer_demande')));
    await tester.pumpAndSettle();

    expect(depot.saisie?.nom, 'Groupe Scolaire Bambino Emmaüs');
    expect(depot.saisie?.paysCode, 'GN');
    expect(depot.saisie?.telephone, '+224 620 11 22 33');
    expect(find.text('Examen par Global Service Groupe'), findsOneWidget);
  });

  testWidgets('demande refusée : motif affiché et nouvelle demande proposée', (tester) async {
    final depot = _FauxDepot(
      demande: DemandeEtablissement(
        id: 'd2',
        nomEtablissement: 'École Lumière',
        paysCode: 'GN',
        ville: 'Kindia',
        statut: StatutDemandeEtablissement.refusee,
        creeLe: DateTime(2026, 10, 1),
        motifRefus: "Numéro d'autorisation manquant",
      ),
    );
    await _monter(tester, depot, const CarteDemandeEtablissement());

    expect(find.textContaining("Numéro d'autorisation manquant"), findsOneWidget);
    expect(find.text('Soumettre une nouvelle demande'), findsOneWidget);
  });

  testWidgets('backoffice GSG : valider et refuser (motif obligatoire)', (tester) async {
    final depot = _FauxDepot(aTraiter: [
      DemandeATraiter(
        id: 'a',
        nomEtablissement: 'Groupe Scolaire Bambino Emmaüs',
        paysCode: 'GN',
        paysNom: 'Guinée',
        ville: 'Conakry',
        telephone: '+224 620 11 22 33',
        creeLe: DateTime(2026, 10, 17),
        numeroAutorisation: 'AUT-2026-001',
        demandeurNom: 'Mamadou Diallo',
      ),
      DemandeATraiter(
        id: 'b',
        nomEtablissement: 'École Lumière',
        paysCode: 'GN',
        ville: 'Kindia',
        telephone: '+224 621 00 00 01',
        creeLe: DateTime(2026, 10, 17),
      ),
    ]);
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [creationEtablissementRepositoryProvider.overrideWithValue(depot)],
      child: const MaterialApp(home: EcranValidationEtablissementsGsg()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Mamadou Diallo'), findsOneWidget);
    expect(find.textContaining('AUT-2026-001'), findsOneWidget);
    expect(find.textContaining("Aucun numéro d'autorisation"), findsOneWidget);

    await tester.tap(find.byKey(const Key('accepter_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Valider').last);
    await tester.pumpAndSettle();
    expect(depot.decisions.single, (id: 'a', accepter: true, motif: null));

    await tester.tap(find.byKey(const Key('refuser_b')));
    await tester.pumpAndSettle();
    // Motif vide : le dialogue reste ouvert.
    await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
    await tester.pumpAndSettle();
    expect(depot.decisions, hasLength(1));
    await tester.enterText(find.byKey(const Key('champ_motif_refus')), 'Dossier incomplet');
    await tester.tap(find.widgetWithText(FilledButton, 'Refuser'));
    await tester.pumpAndSettle();

    expect(depot.decisions.last, (id: 'b', accepter: false, motif: 'Dossier incomplet'));
    expect(find.text('Aucune demande en attente.'), findsOneWidget);
  });
}
