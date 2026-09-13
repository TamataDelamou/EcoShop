import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:ecoshop_client/features/rh_personnel/application/rh_providers.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/absence_personnel.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/bulletin_paie.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/conge.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/contrat.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/effectif_categorie.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/employe.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/enums_rh.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/recommandation_formation.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/remplacement_suggere.dart';
import 'package:ecoshop_client/features/rh_personnel/domain/rh_repository.dart';
import 'package:ecoshop_client/features/rh_personnel/presentation/ecran_annuaire_personnel.dart';
import 'package:ecoshop_client/features/rh_personnel/presentation/ecran_fiche_employe.dart';

/// Faux port [RhRepository] — ce test couvre uniquement la galerie
/// interactive de profils (D2) : bascule liste/grille/cartes, filtrage
/// combiné catégorie + statut, accordéon en mode liste et animation Hero
/// vers la fiche complète. Les RPC IA/paie ne sont pas exercées ici.
class _FauxRhRepository implements RhRepository {
  _FauxRhRepository(this._employes);

  final List<Employe> _employes;

  @override
  Future<List<Employe>> employesEtablissement(String etablissementId) async => List.of(_employes);

  @override
  Future<Employe?> employeParProfil(String profileId) async => null;

  @override
  Future<Employe?> employe(String employeId) async =>
      _employes.where((e) => e.id == employeId).firstOrNull;

  @override
  Future<List<Contrat>> contratsDeEmploye(String employeId) async => [];

  @override
  Future<List<Conge>> congesDeEmploye(String employeId) async => [];

  @override
  Future<List<AbsencePersonnel>> absencesDeEmploye(String employeId) async => [];

  @override
  Future<List<BulletinPaie>> bulletinsDeEmploye(String employeId) async => [];

  @override
  Future<int> chargeHoraire(String employeId) async => 0;

  @override
  Future<List<EffectifCategorie>> analyserEffectifs(String etablissementId) async => [];

  @override
  Future<double> scoreTurnover(String employeId) async => 0;

  @override
  Future<List<RecommandationFormation>> recommanderFormation(String employeId, String anneeScolaireId) async => [];

  @override
  Future<List<RemplacementSuggere>> optimiserRemplacements(String etablissementId, DateTime date) async => [];

  @override
  Future<void> creerOuModifierEmploye(Employe employe) async {}

  @override
  Future<Contrat> creerContrat(Contrat contrat) async => throw UnimplementedError();

  @override
  Future<bool> demanderConge(Conge conge) async => true;

  @override
  Future<void> validerConge(String congeId, {required String statut, required String valideePar}) async {}

  @override
  Future<bool> pointerAbsence(AbsencePersonnel absence) async => true;
}

final _employes = [
  Employe(
    id: 'e1',
    etablissementId: 'etab1',
    profileId: 'p1',
    matricule: 'M001',
    categorie: CategorieEmploye.enseignant,
    statut: StatutEmploye.actif,
    dateEmbauche: DateTime(2022, 9, 1),
    nomAffiche: 'Fatoumata Camara',
  ),
  Employe(
    id: 'e2',
    etablissementId: 'etab1',
    profileId: 'p2',
    matricule: 'M002',
    categorie: CategorieEmploye.administratif,
    statut: StatutEmploye.suspendu,
    dateEmbauche: DateTime(2021, 1, 15),
    nomAffiche: 'Ousmane Diallo',
  ),
];

Future<void> _monter(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        rhRepositoryProvider.overrideWithValue(_FauxRhRepository(_employes)),
        profilProvider.overrideWith(
          (ref) async => Profil(
            id: 'direction1',
            identifiantCanonique: '+224600000001',
            statutCompte: StatutCompte.actif,
            roleRacine: RoleRacine.direction,
          ),
        ),
      ],
      child: const MaterialApp(home: EcranAnnuairePersonnel(etablissementId: 'etab1')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Mode par défaut « liste » : un accordéon fermé par employé', (tester) async {
    await _monter(tester);

    expect(find.text('Fatoumata Camara'), findsOneWidget);
    expect(find.text('Ousmane Diallo'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNWidgets(2));
    expect(find.text('Voir la fiche complète'), findsNothing);
    expect(find.byType(GridView), findsNothing);
  });

  testWidgets('Déplier une ligne affiche poste/statut et l\'action vers la fiche', (tester) async {
    await _monter(tester);

    await tester.tap(find.text('Fatoumata Camara'));
    await tester.pumpAndSettle();

    expect(find.text('Poste : Enseignant'), findsOneWidget);
    expect(find.text('Voir la fiche complète'), findsOneWidget);

    await tester.tap(find.text('Voir la fiche complète'));
    await tester.pumpAndSettle();

    expect(find.byType(EcranFicheEmploye), findsOneWidget);
  });

  testWidgets('Filtre statut combiné à la catégorie : masque les non-correspondants', (tester) async {
    await _monter(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Suspendu'));
    await tester.pumpAndSettle();

    expect(find.text('Ousmane Diallo'), findsOneWidget);
    expect(find.text('Fatoumata Camara'), findsNothing);
  });

  testWidgets('Recherche par nom filtre la liste', (tester) async {
    await _monter(tester);

    await tester.enterText(find.byType(TextField), 'diallo');
    await tester.pumpAndSettle();

    expect(find.text('Ousmane Diallo'), findsOneWidget);
    expect(find.text('Fatoumata Camara'), findsNothing);
  });

  testWidgets('Bascule vers « grille » : GridView avec une tuile par employé', (tester) async {
    await _monter(tester);

    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Fatoumata Camara'), findsOneWidget);
    expect(find.text('Ousmane Diallo'), findsOneWidget);
  });

  testWidgets('Bascule vers « cartes » : poste et matricule visibles sans dépliage', (tester) async {
    await _monter(tester);

    await tester.tap(find.byIcon(Icons.view_agenda_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Poste : Enseignant'), findsOneWidget);
    expect(find.textContaining('Matricule M001'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
  });
}
