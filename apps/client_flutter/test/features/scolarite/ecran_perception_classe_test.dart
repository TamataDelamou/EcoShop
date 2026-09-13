import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/scolarite/application/scolarite_providers.dart';
import 'package:ecoshop_client/features/scolarite/domain/affectation_enseignant.dart';
import 'package:ecoshop_client/features/scolarite/domain/classe.dart';
import 'package:ecoshop_client/features/scolarite/domain/encaissement_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/enums_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/fiche_eleve.dart';
import 'package:ecoshop_client/features/scolarite/domain/frais_scolarite_config.dart';
import 'package:ecoshop_client/features/scolarite/domain/inscription.dart';
import 'package:ecoshop_client/features/scolarite/domain/palier_paiement_config.dart';
import 'package:ecoshop_client/features/scolarite/domain/relation_parent_eleve.dart';
import 'package:ecoshop_client/features/scolarite/domain/scolarite_repository.dart';
import 'package:ecoshop_client/features/scolarite/domain/solde_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/structure_etablissement.dart';
import 'package:ecoshop_client/features/scolarite/domain/verifications_reinscription.dart';
import 'package:ecoshop_client/features/scolarite/presentation/ecran_encaissement_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/presentation/ecran_perception_classe.dart';

const _classe = Classe(id: 'c1', etablissementId: 'et1', anneeScolaireId: 'a1', code: '6A', nom: '6e A');

Inscription _inscription(String id, String ficheId, String matricule, String nom, String prenom) => Inscription(
      id: id,
      etablissementId: 'et1',
      ficheEleveId: ficheId,
      classeId: 'c1',
      anneeScolaireId: 'a1',
      dateInscription: DateTime(2026, 10, 1),
      statut: StatutInscription.active,
      fiche: FicheEleve(
        id: ficheId,
        etablissementId: 'et1',
        matricule: matricule,
        nom: nom,
        prenom: prenom,
        dateNaissance: DateTime(2013, 4, 12),
      ),
    );

/// Faux port [ScolariteRepository] — ne couvre que le câblage de la
/// perception par classe (D6) : [inscriptionsDeClasse] et [soldeScolarite].
class _FauxScolariteRepository implements ScolariteRepository {
  _FauxScolariteRepository({this.inscriptions = const [], this.soldes = const {}});

  final List<Inscription> inscriptions;
  final Map<String, SoldeScolarite> soldes;
  final List<String> appelsSolde = [];

  @override
  Future<List<Inscription>> inscriptionsDeClasse(String classeId) async => inscriptions;

  @override
  Future<SoldeScolarite> soldeScolarite(String inscriptionId) async {
    appelsSolde.add(inscriptionId);
    return soldes[inscriptionId] ?? const SoldeScolarite(montantDu: 0, montantPaye: 0, solde: 0);
  }

  @override
  Future<List<EncaissementScolarite>> encaissementsDeInscription(String inscriptionId) async => const [];

  // --- Non exercé par ces tests --------------------------------------------
  @override
  Future<StructureEtablissement> structureEtablissement(String etablissementId, {String? anneeScolaireId}) =>
      throw UnimplementedError();
  @override
  Future<List<Inscription>> inscriptionsDeFiche(String ficheEleveId) async => const [];
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
  Future<FicheEleve?> ficheParMatricule({required String etablissementId, required String matricule}) async => null;
  @override
  Future<List<FicheEleve>> rechercherEnfantsParTelephoneParent({
    required String etablissementId,
    required String telephone,
  }) async =>
      const [];
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
  Future<VerificationsReinscription> verificationsReinscription({
    required String ficheEleveId,
    required String anneePrecedenteId,
  }) =>
      throw UnimplementedError();
  @override
  Future<String> creerReinscription({
    required String ficheEleveId,
    required String classeId,
    required String anneeScolaireId,
  }) =>
      throw UnimplementedError();
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
  Future<List<EncaissementScolarite>> encaissementsRecents(String etablissementId, {int limite = 100}) async =>
      const [];
  @override
  Future<EncaissementScolarite> enregistrerEncaissement(EncaissementScolarite encaissement) =>
      throw UnimplementedError();
  @override
  Future<void> annulerEncaissement({required String encaissementId, required String motif}) async {}
}

void main() {
  Future<void> monter(WidgetTester tester, _FauxScolariteRepository depot) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [scolariteRepositoryProvider.overrideWithValue(depot)],
        child: const MaterialApp(home: EcranPerceptionClasse(classe: _classe)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('liste les élèves de la classe avec leur solde (soldé / reste à payer)', (tester) async {
    final depot = _FauxScolariteRepository(
      inscriptions: [
        _inscription('i1', 'f1', 'GN-0001', 'CAMARA', 'Mory'),
        _inscription('i2', 'f2', 'GN-0002', 'DIALLO', 'Aïcha'),
      ],
      soldes: {
        'i1': const SoldeScolarite(montantDu: 500000, montantPaye: 500000, solde: 0),
        'i2': const SoldeScolarite(montantDu: 500000, montantPaye: 200000, solde: 300000),
      },
    );
    await monter(tester, depot);

    expect(find.text('Mory CAMARA'), findsOneWidget);
    expect(find.text('Aïcha DIALLO'), findsOneWidget);
    expect(find.text('Soldé'), findsOneWidget);
    expect(find.textContaining('Doit'), findsOneWidget);
    // Aucun recalcul client : le solde vient exclusivement de soldeScolarite.
    expect(depot.appelsSolde, unorderedEquals(['i1', 'i2']));
  });

  testWidgets('toucher un élève ouvre son encaissement individuel existant (pas de saisie groupée)', (tester) async {
    final depot = _FauxScolariteRepository(
      inscriptions: [_inscription('i1', 'f1', 'GN-0001', 'CAMARA', 'Mory')],
      soldes: {'i1': const SoldeScolarite(montantDu: 500000, montantPaye: 0, solde: 500000)},
    );
    await monter(tester, depot);

    await tester.tap(find.text('Mory CAMARA'));
    await tester.pumpAndSettle();

    expect(find.byType(EcranEncaissementScolarite), findsOneWidget);
    expect(find.text('Encaissement de scolarité'), findsOneWidget);
  });

  testWidgets('classe sans élève : message dédié, pas de crash', (tester) async {
    await monter(tester, _FauxScolariteRepository());

    expect(find.text('Aucun élève inscrit pour le moment.'), findsOneWidget);
  });
}
