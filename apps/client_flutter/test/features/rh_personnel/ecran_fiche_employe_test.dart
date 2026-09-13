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
import 'package:ecoshop_client/features/rh_personnel/presentation/ecran_fiche_employe.dart';

/// Faux port [RhRepository] — ce test couvre uniquement l'édition du contact
/// (D5 : téléphone usage interne, email affiché sur le bulletin).
class _FauxRhRepository implements RhRepository {
  final List<Employe> appelsModification = [];

  @override
  Future<List<Employe>> employesEtablissement(String etablissementId) async => const [];
  @override
  Future<Employe?> employeParProfil(String profileId) async => null;
  @override
  Future<Employe?> employe(String employeId) async => null;
  @override
  Future<List<Contrat>> contratsDeEmploye(String employeId) async => const [];
  @override
  Future<List<Conge>> congesDeEmploye(String employeId) async => const [];
  @override
  Future<List<AbsencePersonnel>> absencesDeEmploye(String employeId) async => const [];
  @override
  Future<List<BulletinPaie>> bulletinsDeEmploye(String employeId) async => const [];
  @override
  Future<int> chargeHoraire(String employeId) async => 0;
  @override
  Future<List<EffectifCategorie>> analyserEffectifs(String etablissementId) async => const [];
  @override
  Future<double> scoreTurnover(String employeId) async => 0;
  @override
  Future<List<RecommandationFormation>> recommanderFormation(String employeId, String anneeScolaireId) async =>
      const [];
  @override
  Future<List<RemplacementSuggere>> optimiserRemplacements(String etablissementId, DateTime date) async => const [];
  @override
  Future<void> creerOuModifierEmploye(Employe employe) async => appelsModification.add(employe);
  @override
  Future<Contrat> creerContrat(Contrat contrat) => throw UnimplementedError();
  @override
  Future<bool> demanderConge(Conge conge) async => true;
  @override
  Future<void> validerConge(String congeId, {required String statut, required String valideePar}) async {}
  @override
  Future<bool> pointerAbsence(AbsencePersonnel absence) async => true;
}

final _employe = Employe(
  id: 'e1',
  etablissementId: 'et1',
  profileId: 'p1',
  matricule: 'MAT-001',
  categorie: CategorieEmploye.enseignant,
  dateEmbauche: DateTime(2020, 9, 1),
  nomAffiche: 'Mory Camara',
  telephone: '+224600000001',
  email: 'mory.camara@ecole-test.gn',
);

void main() {
  Future<_FauxRhRepository> monter(WidgetTester tester, {RoleRacine role = RoleRacine.direction}) async {
    final depot = _FauxRhRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rhRepositoryProvider.overrideWithValue(depot),
          profilProvider.overrideWith(
            (ref) async => Profil(
              id: 'direction1',
              identifiantCanonique: '+224600000099',
              statutCompte: StatutCompte.actif,
              roleRacine: role,
            ),
          ),
        ],
        child: MaterialApp(home: EcranFicheEmploye(employe: _employe)),
      ),
    );
    await tester.pumpAndSettle();
    return depot;
  }

  testWidgets('direction : la section Contact affiche téléphone (interne) et email (bulletin)', (tester) async {
    await monter(tester);

    expect(find.textContaining('+224600000001'), findsOneWidget);
    expect(find.textContaining('mory.camara@ecole-test.gn'), findsOneWidget);
    expect(find.text('Contact'), findsOneWidget);
  });

  testWidgets('rôle non-direction : la section Contact est masquée', (tester) async {
    await monter(tester, role: RoleRacine.enseignant);

    expect(find.text('Contact'), findsNothing);
  });

  testWidgets('modifier le contact : enregistrer appelle creerOuModifierEmploye et met à jour l\'écran',
      (tester) async {
    final depot = await monter(tester);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.edit_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Téléphone'), '+224600009999');
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'nouveau.mail@ecole-test.gn');
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.pumpAndSettle();

    expect(depot.appelsModification, hasLength(1));
    expect(depot.appelsModification.single.telephone, '+224600009999');
    expect(depot.appelsModification.single.email, 'nouveau.mail@ecole-test.gn');
    // Les autres champs du dossier ne sont jamais altérés par cette édition.
    expect(depot.appelsModification.single.matricule, 'MAT-001');
    expect(find.textContaining('+224600009999'), findsOneWidget);
    expect(find.textContaining('nouveau.mail@ecole-test.gn'), findsOneWidget);
  });

  testWidgets('modifier le contact : annuler n\'appelle pas creerOuModifierEmploye', (tester) async {
    final depot = await monter(tester);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
    await tester.pumpAndSettle();

    expect(depot.appelsModification, isEmpty);
  });
}
