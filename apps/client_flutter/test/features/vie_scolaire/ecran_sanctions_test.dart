import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:ecoshop_client/features/scolarite/domain/fiche_eleve.dart';
import 'package:ecoshop_client/features/vie_scolaire/application/vie_scolaire_providers.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/alerte_decrochage.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/enums_vie_scolaire.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/evenement_scolaire.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/presence.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/retard.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/sanction.dart';
import 'package:ecoshop_client/features/vie_scolaire/domain/vie_scolaire_repository.dart';
import 'package:ecoshop_client/features/vie_scolaire/presentation/ecran_sanctions.dart';

/// Faux port [VieScolaireRepository] — ce test ne couvre que le câblage de
/// l'écran (déclaration manuelle + changement de statut, complément écart
/// #5 de l'audit) : `proposerSanction()`/`changerStatutSanction()` et la
/// policy RLS `sanctions_ecriture_scolarite` sont déjà couverts par
/// `tests/rls/13_m7_presences_visibilite.sql`.
class _FauxVieScolaireRepository implements VieScolaireRepository {
  _FauxVieScolaireRepository({List<Sanction> sanctionsInitiales = const []})
      : _sanctions = List.of(sanctionsInitiales);

  final List<Sanction> _sanctions;
  final List<Sanction> propositions = [];
  final List<(String, String)> changementsStatut = [];
  int _compteur = 0;

  @override
  Future<List<Sanction>> sanctionsDeFiche(String ficheEleveId) async => List.of(_sanctions);

  @override
  Future<Sanction> proposerSanction(Sanction sanction) async {
    propositions.add(sanction);
    _compteur++;
    final creee = Sanction(
      id: 's$_compteur',
      etablissementId: sanction.etablissementId,
      ficheEleveId: sanction.ficheEleveId,
      anneeScolaireId: sanction.anneeScolaireId,
      typeSanction: sanction.typeSanction,
      motif: sanction.motif,
      dateDebut: sanction.dateDebut,
      dateFin: sanction.dateFin,
      decisionnaireId: sanction.decisionnaireId,
      contexteEducatif: sanction.contexteEducatif,
      origine: sanction.origine,
      statut: sanction.statut,
    );
    _sanctions.add(creee);
    return creee;
  }

  @override
  Future<void> changerStatutSanction(String sanctionId, String statut) async {
    changementsStatut.add((sanctionId, statut));
    final i = _sanctions.indexWhere((s) => s.id == sanctionId);
    if (i == -1) return;
    final s = _sanctions[i];
    _sanctions[i] = Sanction(
      id: s.id,
      etablissementId: s.etablissementId,
      ficheEleveId: s.ficheEleveId,
      anneeScolaireId: s.anneeScolaireId,
      typeSanction: s.typeSanction,
      motif: s.motif,
      dateDebut: s.dateDebut,
      dateFin: s.dateFin,
      decisionnaireId: s.decisionnaireId,
      contexteEducatif: s.contexteEducatif,
      origine: s.origine,
      valideePar: s.valideePar,
      valideeLe: s.valideeLe,
      statut: StatutSanction.depuisCode(statut),
    );
  }

  @override
  Future<void> validerSanction(String sanctionId, {required String valideePar}) async {}

  @override
  Future<List<Presence>> presencesDeClasse(String classeId, DateTime date) async => const [];
  @override
  Future<List<Presence>> presencesDeFiche(String ficheEleveId) async => const [];
  @override
  Future<List<Retard>> retardsDeFiche(String ficheEleveId) async => const [];
  @override
  Future<List<AlerteDecrochage>> alertesDeFiche(String ficheEleveId) async => const [];
  @override
  Future<List<AlerteDecrochage>> alertesEtablissement(String etablissementId) async => const [];
  @override
  Future<List<EvenementScolaire>> evenementsEtablissement(String etablissementId) async => const [];
  @override
  Future<Map<String, dynamic>> analyseComportement(String ficheEleveId, String anneeScolaireId) async => const {};
  @override
  Future<double> scoreDecrochage(String ficheEleveId, String anneeScolaireId) async => 0;
  @override
  Future<Map<String, dynamic>> recommandationSanction(String ficheEleveId, String anneeScolaireId) async => const {};
  @override
  Future<double> predirePresence(String etablissementId, DateTime date) async => 0;
  @override
  Future<bool> saisirPresence(Presence presence) async => true;
  @override
  Future<bool> saisirRetard(Retard retard) async => true;
}

final _fiche = FicheEleve(
  id: 'fiche1',
  etablissementId: 'et1',
  matricule: 'M-001',
  nom: 'SYLLA',
  prenom: 'Aissatou',
  dateNaissance: DateTime(2012, 5, 1),
);

Sanction _sanctionHumaine({StatutSanction statut = StatutSanction.notifiee}) => Sanction(
      id: 'existante',
      etablissementId: 'et1',
      ficheEleveId: 'fiche1',
      anneeScolaireId: 'annee1',
      typeSanction: TypeSanction.retenue,
      motif: 'Retard répété',
      dateDebut: DateTime(2026, 3, 1),
      decisionnaireId: 'direction1',
      statut: statut,
    );

void main() {
  Future<void> monter(
    WidgetTester tester, {
    required _FauxVieScolaireRepository depot,
    RoleRacine role = RoleRacine.direction,
    String? anneeScolaireId = 'annee1',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vieScolaireRepositoryProvider.overrideWithValue(depot),
          profilProvider.overrideWith(
            (ref) async => Profil(
              id: 'direction1',
              identifiantCanonique: '+224600000001',
              statutCompte: StatutCompte.actif,
              roleRacine: role,
            ),
          ),
        ],
        child: MaterialApp(
          home: EcranSanctions(fiche: _fiche, anneeScolaireId: anneeScolaireId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    "Déclaration manuelle (écart #5) : masqué pour un rôle non-direction",
    (tester) async {
      await monter(tester, depot: _FauxVieScolaireRepository(), role: RoleRacine.enseignant);
      expect(find.text('Déclarer une sanction'), findsNothing);
    },
  );

  testWidgets(
    "Déclaration manuelle : masqué tant que l'année scolaire n'est pas résolue",
    (tester) async {
      await monter(tester, depot: _FauxVieScolaireRepository(), anneeScolaireId: null);
      expect(find.text('Déclarer une sanction'), findsNothing);
    },
  );

  testWidgets(
    'Déclaration manuelle : visible pour la direction avec une année scolaire résolue',
    (tester) async {
      await monter(tester, depot: _FauxVieScolaireRepository());
      expect(find.text('Déclarer une sanction'), findsOneWidget);
    },
  );

  testWidgets(
    'Déclaration manuelle : soumettre le formulaire appelle proposerSanction() avec les bons champs',
    (tester) async {
      final depot = _FauxVieScolaireRepository();
      await monter(tester, depot: depot);

      await tester.tap(find.text('Déclarer une sanction'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Motif'), 'Bavardage répété en classe');
      await tester.tap(find.widgetWithText(FilledButton, 'Déclarer'));
      await tester.pumpAndSettle();

      expect(depot.propositions, hasLength(1));
      final envoyee = depot.propositions.single;
      expect(envoyee.etablissementId, 'et1');
      expect(envoyee.ficheEleveId, 'fiche1');
      expect(envoyee.anneeScolaireId, 'annee1');
      expect(envoyee.decisionnaireId, 'direction1');
      expect(envoyee.motif, 'Bavardage répété en classe');
      expect(envoyee.origine, OrigineSanction.humaine);
      expect(envoyee.statut, StatutSanction.notifiee);

      // La liste se rafraîchit : la nouvelle sanction apparaît.
      expect(find.text('Bavardage répété en classe'), findsOneWidget);
    },
  );

  testWidgets('Déclaration manuelle : le motif est obligatoire, aucun appel sans lui', (tester) async {
    final depot = _FauxVieScolaireRepository();
    await monter(tester, depot: depot);

    await tester.tap(find.text('Déclarer une sanction'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Déclarer'));
    await tester.pumpAndSettle();

    expect(depot.propositions, isEmpty);
    expect(find.text('Le motif est obligatoire.'), findsOneWidget);
  });

  testWidgets(
    'Changement de statut (levée incluse) : sélectionner « Annulée » appelle changerStatutSanction()',
    (tester) async {
      final depot = _FauxVieScolaireRepository(sanctionsInitiales: [_sanctionHumaine()]);
      await monter(tester, depot: depot);

      expect(find.text('Changer le statut'), findsOneWidget);
      await tester.tap(find.text('Changer le statut'));
      await tester.pumpAndSettle();

      expect(find.text('Annulée (levée)'), findsOneWidget);
      // 'Proposée' n'est jamais une cible valide pour un changement manuel.
      expect(find.text('Proposée'), findsNothing);

      await tester.tap(find.text('Annulée (levée)'));
      await tester.pumpAndSettle();

      expect(depot.changementsStatut, [('existante', 'annulee')]);
    },
  );

  testWidgets(
    'Une proposition IA non validée ne propose jamais de changement de statut direct',
    (tester) async {
      final propositionIa = Sanction(
        id: 'prop-ia',
        etablissementId: 'et1',
        ficheEleveId: 'fiche1',
        anneeScolaireId: 'annee1',
        typeSanction: TypeSanction.avertissement,
        motif: 'Signal IA',
        dateDebut: DateTime(2026, 3, 1),
        decisionnaireId: 'direction1',
        origine: OrigineSanction.ia,
      );
      final depot = _FauxVieScolaireRepository(sanctionsInitiales: [propositionIa]);
      await monter(tester, depot: depot);

      expect(find.text('Valider la proposition'), findsOneWidget);
      expect(find.text('Changer le statut'), findsNothing);
    },
  );
}
