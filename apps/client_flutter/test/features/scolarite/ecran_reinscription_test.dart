import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/scolarite/application/scolarite_providers.dart';
import 'package:ecoshop_client/features/scolarite/domain/affectation_enseignant.dart';
import 'package:ecoshop_client/features/scolarite/domain/annee_scolaire.dart';
import 'package:ecoshop_client/features/scolarite/domain/classe.dart';
import 'package:ecoshop_client/features/scolarite/domain/encaissement_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/fiche_eleve.dart';
import 'package:ecoshop_client/features/scolarite/domain/frais_scolarite_config.dart';
import 'package:ecoshop_client/features/scolarite/domain/inscription.dart';
import 'package:ecoshop_client/features/scolarite/domain/palier_paiement_config.dart';
import 'package:ecoshop_client/features/scolarite/domain/relation_parent_eleve.dart';
import 'package:ecoshop_client/features/scolarite/domain/scolarite_repository.dart';
import 'package:ecoshop_client/features/scolarite/domain/solde_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/structure_etablissement.dart';
import 'package:ecoshop_client/features/scolarite/domain/verifications_reinscription.dart';
import 'package:ecoshop_client/features/scolarite/presentation/ecran_reinscription.dart';

FicheEleve _fiche(String id, String matricule, String nom, String prenom) => FicheEleve(
      id: id,
      etablissementId: 'et1',
      matricule: matricule,
      nom: nom,
      prenom: prenom,
      dateNaissance: DateTime(2013, 4, 12),
    );

final _classe = const Classe(id: 'c1', etablissementId: 'et1', anneeScolaireId: 'a2', code: '6A', nom: '6e A');

/// Faux port [ScolariteRepository] — n'exerce que le fast-track D6 (cahier
/// §7.1) et le chemin matricule secondaire ; le reste renvoie des valeurs
/// neutres (non exercé par ces tests).
class _FauxScolariteRepository implements ScolariteRepository {
  _FauxScolariteRepository({this.enfantsParTelephone = const [], this.ficheParMatriculeResultat});

  final List<FicheEleve> enfantsParTelephone;
  final FicheEleve? ficheParMatriculeResultat;
  final List<({String telephone})> appelsTelephone = [];
  final List<String> appelsMatricule = [];
  final List<({String ficheEleveId, String classeId, String anneeScolaireId})> appelsReinscription = [];

  @override
  Future<List<FicheEleve>> rechercherEnfantsParTelephoneParent({
    required String etablissementId,
    required String telephone,
  }) async {
    appelsTelephone.add((telephone: telephone));
    return enfantsParTelephone;
  }

  @override
  Future<FicheEleve?> ficheParMatricule({required String etablissementId, required String matricule}) async {
    appelsMatricule.add(matricule);
    return ficheParMatriculeResultat;
  }

  @override
  Future<List<Inscription>> inscriptionsDeFiche(String ficheEleveId) async => const [];

  @override
  Future<VerificationsReinscription> verificationsReinscription({
    required String ficheEleveId,
    required String anneePrecedenteId,
  }) async =>
      const VerificationsReinscription(impaye: false, sanctionActive: false, boursierPrecedent: false);

  @override
  Future<String> creerReinscription({
    required String ficheEleveId,
    required String classeId,
    required String anneeScolaireId,
  }) async {
    appelsReinscription.add((ficheEleveId: ficheEleveId, classeId: classeId, anneeScolaireId: anneeScolaireId));
    return 'insc-nouvelle';
  }

  @override
  Future<StructureEtablissement> structureEtablissement(String etablissementId, {String? anneeScolaireId}) async {
    return StructureEtablissement(
      unites: const [],
      anneesScolaires: [
        AnneeScolaire(id: 'a2', etablissementId: 'et1', libelle: '2026-2027', dateDebut: DateTime(2026, 10, 1), dateFin: DateTime(2027, 6, 30), courante: true),
      ],
      classes: [_classe],
      periodes: const [],
    );
  }

  // --- Non exercé par ces tests --------------------------------------------
  @override
  Future<List<Inscription>> inscriptionsDeClasse(String classeId) async => const [];
  @override
  Future<FicheEleve?> maFiche() async => null;
  @override
  Future<List<AffectationEnseignant>> affectationsDeClasse(String classeId) async => const [];
  @override
  Future<List<AffectationEnseignant>> mesAffectations() async => const [];
  @override
  Future<List<RelationParentEleve>> mesEnfants() async => const [];
  @override
  Future<FicheEleve?> ficheEleve(String ficheId) async => null;
  @override
  Future<int?> classeIsced(String classeId) async => null;
  @override
  Future<String> lierEnfant({
    required String matricule,
    required DateTime dateNaissance,
    dynamic type,
  }) =>
      throw UnimplementedError();
  @override
  Future<String> creerInscriptionNouvelEleve({
    required String etablissementId,
    required String nom,
    required String prenom,
    required DateTime dateNaissance,
    required String classeId,
    required String anneeScolaireId,
    String? sexe,
  }) =>
      throw UnimplementedError();
  @override
  Future<bool> verifierDoublonEleve({
    required String nom,
    required String prenom,
    required DateTime dateNaissance,
  }) async =>
      false;
  @override
  Future<void> definirStatutBoursier({required String inscriptionId, required bool boursier}) async {}
  @override
  Future<void> mettreAJourFicheAdmin(FicheEleve fiche) async {}
  @override
  Future<List<FraisScolariteConfig>> fraisScolariteConfig({
    required String etablissementId,
    required String anneeScolaireId,
  }) async =>
      const [];
  @override
  Future<void> enregistrerFraisScolariteConfig(FraisScolariteConfig config) async {}
  @override
  Future<List<PalierPaiementConfig>> paliersPaiementConfig({
    required String etablissementId,
    required String anneeScolaireId,
  }) async =>
      const [];
  @override
  Future<void> enregistrerPalierPaiement(PalierPaiementConfig palier) async {}
  @override
  Future<SoldeScolarite> soldeScolarite(String inscriptionId) =>
      throw UnimplementedError();
  @override
  Future<List<EncaissementScolarite>> encaissementsDeInscription(String inscriptionId) async => const [];
  @override
  Future<List<EncaissementScolarite>> encaissementsRecents(String etablissementId, {int limite = 100}) async =>
      const [];
  @override
  Future<EncaissementScolarite> enregistrerEncaissement(EncaissementScolarite encaissement) =>
      throw UnimplementedError();
  @override
  Future<void> annulerEncaissement({required String encaissementId, required String motif}) async {}
}

void main() {
  const etablissement = Etablissement(id: 'et1', nom: 'École Test', slug: 'ecole-test', paysCode: 'GN');

  Future<void> monter(WidgetTester tester, _FauxScolariteRepository depot) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scolariteRepositoryProvider.overrideWithValue(depot),
          etablissementActifProvider.overrideWithValue(etablissement),
        ],
        child: const MaterialApp(home: EcranReinscription()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('téléphone est le mode par défaut, matricule est atteignable en secondaire', (tester) async {
    await monter(tester, _FauxScolariteRepository());

    expect(find.text('Téléphone du parent'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Matricule de l\'élève'), findsNothing);

    await tester.tap(find.text('Rechercher plutôt par matricule'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Matricule de l\'élève'), findsOneWidget);
    expect(find.text('Téléphone du parent'), findsNothing);
  });

  testWidgets('un seul enfant trouvé par téléphone : sélection automatique, pas de liste de choix', (tester) async {
    final depot = _FauxScolariteRepository(enfantsParTelephone: [_fiche('f1', 'GN-0001', 'CAMARA', 'Mory')]);
    await monter(tester, depot);

    await tester.enterText(find.widgetWithText(TextField, 'Numéro'), '620 00 00 01');
    await tester.tap(find.widgetWithText(FilledButton, 'Chercher'));
    await tester.pumpAndSettle();

    expect(depot.appelsTelephone.single.telephone, '+224620000001');
    expect(find.text('Mory CAMARA'), findsOneWidget);
    expect(find.text('Plusieurs enfants partagent ce numéro — choisissez :'), findsNothing);
  });

  testWidgets('fratrie : plusieurs enfants proposent une vraie sélection (pas de eleves.first)', (tester) async {
    final depot = _FauxScolariteRepository(enfantsParTelephone: [
      _fiche('f1', 'GN-0001', 'CAMARA', 'Mory'),
      _fiche('f2', 'GN-0002', 'CAMARA', 'Aïcha'),
    ]);
    await monter(tester, depot);

    await tester.enterText(find.widgetWithText(TextField, 'Numéro'), '620 00 00 01');
    await tester.tap(find.widgetWithText(FilledButton, 'Chercher'));
    await tester.pumpAndSettle();

    expect(find.text('Plusieurs enfants partagent ce numéro — choisissez :'), findsOneWidget);
    expect(find.text('Mory CAMARA'), findsOneWidget);
    expect(find.text('Aïcha CAMARA'), findsOneWidget);

    await tester.tap(find.text('Aïcha CAMARA'));
    await tester.pumpAndSettle();

    // La fiche choisie (Aïcha) est bien celle retenue pour la suite du flux,
    // pas la première de la liste.
    expect(find.text('Matricule GN-0002'), findsOneWidget);
    expect(find.text('Plusieurs enfants partagent ce numéro — choisissez :'), findsNothing);
  });

  testWidgets('aucun enfant trouvé par téléphone : message dédié', (tester) async {
    await monter(tester, _FauxScolariteRepository());

    await tester.enterText(find.widgetWithText(TextField, 'Numéro'), '699 99 99 99');
    await tester.tap(find.widgetWithText(FilledButton, 'Chercher'));
    await tester.pumpAndSettle();

    expect(find.text('Aucun enfant trouvé pour ce numéro.'), findsOneWidget);
  });

  testWidgets('numéro invalide : refusé avant tout appel réseau', (tester) async {
    final depot = _FauxScolariteRepository();
    await monter(tester, depot);

    await tester.enterText(find.widgetWithText(TextField, 'Numéro'), 'abc');
    await tester.tap(find.widgetWithText(FilledButton, 'Chercher'));
    await tester.pumpAndSettle();

    expect(find.text('Numéro de téléphone invalide.'), findsOneWidget);
    expect(depot.appelsTelephone, isEmpty);
  });

  testWidgets('recherche par matricule (secondaire) puis confirmation de réinscription', (tester) async {
    final depot = _FauxScolariteRepository(ficheParMatriculeResultat: _fiche('f1', 'GN-0001', 'CAMARA', 'Mory'));
    await monter(tester, depot);

    await tester.tap(find.text('Rechercher plutôt par matricule'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Matricule de l\'élève'), 'GN-0001');
    await tester.tap(find.widgetWithText(FilledButton, 'Chercher'));
    await tester.pumpAndSettle();

    expect(depot.appelsMatricule.single, 'GN-0001');
    expect(find.text('Mory CAMARA'), findsOneWidget);

    await tester.tap(find.text('Non choisie'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6e A'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Confirmer la réinscription'));
    await tester.pumpAndSettle();

    expect(depot.appelsReinscription.single.ficheEleveId, 'f1');
    expect(depot.appelsReinscription.single.classeId, 'c1');
  });
}
