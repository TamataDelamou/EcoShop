import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;

import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/notes/application/notes_providers.dart';
import 'package:ecoshop_client/features/notes/domain/appreciation.dart';
import 'package:ecoshop_client/features/notes/domain/bulletin.dart';
import 'package:ecoshop_client/features/notes/domain/classement_eleve.dart';
import 'package:ecoshop_client/features/notes/domain/enums_notes.dart';
import 'package:ecoshop_client/features/notes/domain/evaluation.dart';
import 'package:ecoshop_client/features/notes/domain/note.dart';
import 'package:ecoshop_client/features/notes/domain/notes_repository.dart';
import 'package:ecoshop_client/features/notes/presentation/ecran_generation_bulletins_classe.dart';
import 'package:ecoshop_client/features/referentiel/application/referentiel_providers.dart';
import 'package:ecoshop_client/features/scolarite/application/scolarite_providers.dart';
import 'package:ecoshop_client/features/scolarite/domain/affectation_enseignant.dart';
import 'package:ecoshop_client/features/scolarite/domain/classe.dart';
import 'package:ecoshop_client/features/scolarite/domain/encaissement_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/enums_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/fiche_eleve.dart';
import 'package:ecoshop_client/features/scolarite/domain/frais_scolarite_config.dart';
import 'package:ecoshop_client/features/scolarite/domain/inscription.dart';
import 'package:ecoshop_client/features/scolarite/domain/palier_paiement_config.dart';
import 'package:ecoshop_client/features/scolarite/domain/periode_scolaire.dart';
import 'package:ecoshop_client/features/scolarite/domain/relation_parent_eleve.dart';
import 'package:ecoshop_client/features/scolarite/domain/scolarite_repository.dart';
import 'package:ecoshop_client/features/scolarite/domain/solde_scolarite.dart';
import 'package:ecoshop_client/features/scolarite/domain/structure_etablissement.dart';
import 'package:ecoshop_client/features/scolarite/domain/verifications_reinscription.dart';

/// Faux port [ScolariteRepository] — ce test ne couvre que le câblage de
/// l'écran de génération des bulletins (D5) : seuls [structureEtablissement]
/// (périodes de la classe) et [inscriptionsDeClasse] (fiches à apparier avec
/// les bulletins pour l'export PDF) sont utiles ici.
class _FauxScolariteRepository implements ScolariteRepository {
  _FauxScolariteRepository({this.periodes = const [], this.inscriptions = const []});

  final List<PeriodeScolaire> periodes;
  final List<Inscription> inscriptions;

  @override
  Future<StructureEtablissement> structureEtablissement(String etablissementId, {String? anneeScolaireId}) async {
    return StructureEtablissement(unites: const [], anneesScolaires: const [], classes: const [], periodes: periodes);
  }

  @override
  Future<List<Inscription>> inscriptionsDeClasse(String classeId) async => inscriptions;

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
  Future<String> lierEnfant({
    required String matricule,
    required DateTime dateNaissance,
    TypeRelationParentale type = TypeRelationParentale.parent,
  }) async =>
      '';
  @override
  Future<FicheEleve?> ficheParMatricule({required String etablissementId, required String matricule}) async => null;
  @override
  Future<String> creerInscriptionNouvelEleve({
    required String etablissementId,
    required String nom,
    required String prenom,
    required DateTime dateNaissance,
    required String classeId,
    required String anneeScolaireId,
    String? sexe,
  }) async =>
      '';
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
  }) async =>
      '';
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
  Future<SoldeScolarite> soldeScolarite(String inscriptionId) => throw UnimplementedError();
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

/// Faux port [NotesRepository] — seul [genererBulletinsClasse] (D5) est
/// exercé par cet écran ; [classerElevesClasse] n'est jamais appelé
/// directement par l'écran (encapsulé dans [genererBulletinsClasse] côté
/// implémentation Supabase), volontairement absent de la logique testée ici.
class _FauxNotesRepository implements NotesRepository {
  _FauxNotesRepository({this.bulletinsAGenerer = const [], this.leverErreur = false});

  final List<Bulletin> bulletinsAGenerer;
  final bool leverErreur;
  final List<({String classeId, String? periodeId, TypeBulletin type})> appelsGeneration = [];

  @override
  Future<List<Bulletin>> genererBulletinsClasse({
    required String classeId,
    required String etablissementId,
    required String anneeScolaireId,
    String? periodeId,
    TypeBulletin type = TypeBulletin.trimestriel,
  }) async {
    appelsGeneration.add((classeId: classeId, periodeId: periodeId, type: type));
    if (leverErreur) throw const ErreurNotes('ERREUR_RESEAU');
    return bulletinsAGenerer;
  }

  @override
  Future<List<ClassementEleve>> classerElevesClasse(
    String classeId, {
    String? programmeMatiereId,
    String? periodeId,
  }) async =>
      const [];

  @override
  Future<List<Evaluation>> evaluationsDeClasse(String classeId, {String? periodeId}) async => const [];
  @override
  Future<List<Note>> notesDeEvaluation(String evaluationId) async => const [];
  @override
  Future<List<Note>> notesDeFiche(String ficheEleveId, {String? periodeId}) async => const [];
  @override
  Future<double?> moyenneEleve(String ficheEleveId, {String? programmeMatiereId, String? periodeId}) async => null;
  @override
  Future<double?> moyenneClasse(String classeId, {String? programmeMatiereId, String? periodeId}) async => null;
  @override
  Future<List<Appreciation>> appreciationsDeFiche(String ficheEleveId, {String? periodeId}) async => const [];
  @override
  Future<List<Bulletin>> bulletinsDeFiche(String ficheEleveId) async => const [];
  @override
  Future<Evaluation> creerEvaluation(Evaluation evaluation) => throw UnimplementedError();
  @override
  Future<void> publierEvaluation(String evaluationId) async {}
  @override
  Future<bool> saisirNote(Note note) async => true;
}

final _classe = const Classe(
  id: 'classe1',
  etablissementId: 'et1',
  anneeScolaireId: 'annee1',
  code: '5A',
  nom: '5e A',
);

final _periodeT1 = PeriodeScolaire(
  id: 'p1',
  etablissementId: 'et1',
  anneeScolaireId: 'annee1',
  code: 'T1',
  libelle: '1er trimestre',
  ordre: 1,
  dateDebut: DateTime(2026, 10, 1),
  dateFin: DateTime(2026, 12, 23),
  type: TypePeriode.trimestre,
);

Bulletin _bulletin(String ficheId) => Bulletin(
      id: 'b-$ficheId',
      etablissementId: 'et1',
      anneeScolaireId: 'annee1',
      classeId: 'classe1',
      ficheEleveId: ficheId,
      periodeId: 'p1',
      type: TypeBulletin.trimestriel,
      statut: StatutBulletin.publie,
      contenu: const {'moyenne_generale': 15.0, 'rang': 1, 'effectif_classe': 1},
    );

void main() {
  final etablissement = const Etablissement(id: 'et1', nom: 'École Test', slug: 'ecole-test', paysCode: 'GN');

  Future<void> monter(
    WidgetTester tester, {
    required _FauxScolariteRepository scolarite,
    required _FauxNotesRepository notes,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scolariteRepositoryProvider.overrideWithValue(scolarite),
          notesRepositoryProvider.overrideWithValue(notes),
          etablissementActifProvider.overrideWithValue(etablissement),
          paysPedagogiquesProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(home: EcranGenerationBulletinsClasse(classe: _classe)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('affiche « Bulletin annuel » et les périodes de la classe dans le sélecteur', (tester) async {
    await monter(
      tester,
      scolarite: _FauxScolariteRepository(periodes: [_periodeT1]),
      notes: _FauxNotesRepository(),
    );

    expect(find.text('Bulletin annuel (aucune période)'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    expect(find.text('1er trimestre'), findsOneWidget);
  });

  testWidgets('Générer sans période sélectionnée appelle genererBulletinsClasse(periodeId: null, type: annuel)',
      (tester) async {
    final notes = _FauxNotesRepository(bulletinsAGenerer: [_bulletin('f1')]);
    await monter(tester, scolarite: _FauxScolariteRepository(periodes: [_periodeT1]), notes: notes);

    await tester.tap(find.widgetWithText(FilledButton, 'Générer les bulletins de la classe'));
    await tester.pumpAndSettle();

    expect(notes.appelsGeneration, hasLength(1));
    expect(notes.appelsGeneration.single.periodeId, isNull);
    expect(notes.appelsGeneration.single.type, TypeBulletin.annuel);
    expect(find.text('1 bulletin(s) généré(s) et publié(s).'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Exporter en PDF (classe entière)'), findsOneWidget);
  });

  testWidgets('sélectionner une période appelle genererBulletinsClasse avec son id et le type trimestriel',
      (tester) async {
    final notes = _FauxNotesRepository(bulletinsAGenerer: [_bulletin('f1'), _bulletin('f2')]);
    final inscriptions = [
      Inscription(
        id: 'i1',
        etablissementId: 'et1',
        ficheEleveId: 'f1',
        classeId: 'classe1',
        anneeScolaireId: 'annee1',
        dateInscription: DateTime(2026, 10, 1),
        fiche: FicheEleve(
          id: 'f1',
          etablissementId: 'et1',
          matricule: 'GN-0001',
          nom: 'CAMARA',
          prenom: 'Mory',
          dateNaissance: DateTime(2011, 4, 12),
        ),
      ),
    ];
    await monter(
      tester,
      scolarite: _FauxScolariteRepository(periodes: [_periodeT1], inscriptions: inscriptions),
      notes: notes,
    );

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1er trimestre').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Générer les bulletins de la classe'));
    await tester.pumpAndSettle();

    expect(notes.appelsGeneration.single.periodeId, 'p1');
    expect(notes.appelsGeneration.single.type, TypeBulletin.trimestriel);
    expect(find.text('2 bulletin(s) généré(s) et publié(s).'), findsOneWidget);
  });

  testWidgets('aucun élève classable : message dédié, pas de bouton export', (tester) async {
    final notes = _FauxNotesRepository(bulletinsAGenerer: const []);
    await monter(tester, scolarite: _FauxScolariteRepository(), notes: notes);

    await tester.tap(find.widgetWithText(FilledButton, 'Générer les bulletins de la classe'));
    await tester.pumpAndSettle();

    expect(find.text('Aucun élève avec une moyenne calculable sur cette période.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Exporter en PDF (classe entière)'), findsNothing);
  });

  testWidgets('panne réseau : message d\'erreur affiché, aucun bulletin annoncé', (tester) async {
    final notes = _FauxNotesRepository(leverErreur: true);
    await monter(tester, scolarite: _FauxScolariteRepository(), notes: notes);

    await tester.tap(find.widgetWithText(FilledButton, 'Générer les bulletins de la classe'));
    await tester.pumpAndSettle();

    expect(find.text('Impossible de générer les bulletins de la classe — réessayez.'), findsOneWidget);
    expect(find.textContaining('généré(s) et publié(s)'), findsNothing);
  });
}
