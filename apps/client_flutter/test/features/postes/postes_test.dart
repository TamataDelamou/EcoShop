import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/securite/delais_verrouillage.dart';
import 'package:ecoshop_client/features/invitations/domain/invitation.dart';
import 'package:ecoshop_client/features/postes/application/postes_providers.dart';
import 'package:ecoshop_client/features/postes/data/postes_repository.dart';
import 'package:ecoshop_client/features/postes/presentation/ecran_postes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// REG-22, partie C : postes du personnel côté application.
class _FauxPostes implements PostesRepository {
  final appels = <String>[];
  List<Poste> liste = const [
    Poste(id: 'p1', nom: 'Caissier', modeleCode: 'caissier', codes: ['scolarite.encaissement.gerer', 'scolarite.encaissement.lire'],
        membres: 2, actif: true),
    Poste(id: 'p2', nom: 'Agent du portail', modeleCode: 'agent_portail', codes: ['portail.scanner'], membres: 0, actif: true),
  ];

  @override
  Future<List<Poste>> postes(String etablissementId) async => liste;

  @override
  Future<List<ModelePoste>> modeles() async => const [
    ModelePoste(code: 'caissier', nom: 'Caissier', description: 'Encaissements de scolarité et reçus.', role: 'personnel',
        codes: ['scolarite.encaissement.gerer', 'scolarite.encaissement.lire']),
    ModelePoste(code: 'enseignant', nom: 'Enseignant', description: 'Ses classes.', role: 'enseignant', codes: []),
  ];

  @override
  Future<List<DroitCatalogue>> catalogue() async => const [
    DroitCatalogue(code: 'comptabilite.valider', domaine: 'comptabilite', libelle: 'Valider et clôturer'),
    DroitCatalogue(code: 'scolarite.encaissement.gerer', domaine: 'scolarite', libelle: 'Encaisser la scolarité'),
    DroitCatalogue(code: 'scolarite.encaissement.lire', domaine: 'scolarite', libelle: 'Lire les encaissements'),
  ];

  @override
  Future<String> creerPoste({required String etablissementId, String? modele, required String nom, required List<String> codes}) async {
    appels.add('creer:$modele:$nom:${(codes..sort()).join(',')}');
    return 'p3';
  }

  @override
  Future<void> modifierPoste({required String posteId, required String nom, required List<String> codes, bool actif = true}) async =>
      appels.add('modifier:$posteId');

  @override
  Future<List<MembrePersonnel>> personnel(String etablissementId) async =>
      const [MembrePersonnel(profileId: 'm1', nomComplet: 'Fatou Camara', role: 'personnel', posteId: 'p1', poste: 'Caissier')];

  @override
  Future<void> modifierMembre({required String etablissementId, required String compteId, required String role, String? posteId}) async {
    if (role == 'personnel' && posteId == null) throw const ErreurPostes('POSTE_OBLIGATOIRE');
    appels.add('membre:$compteId:$role:$posteId');
  }

  @override
  Future<Set<String>> mesPermissions(String etablissementId) async => const {};
}

Future<_FauxPostes> _monter(WidgetTester tester, Widget ecran) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final repo = _FauxPostes();
  await tester.pumpWidget(ProviderScope(
    overrides: [postesRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(home: ecran),
  ));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  test('rôle « personnel » invitable ; la direction réservée au fondateur et au directeur', () {
    expect(rolesInvitables, contains(RoleRacine.personnel));
    expect(libelleRoleInvitation('personnel'), 'Personnel administratif et technique');
    expect(libelleRoleInvitation('direction'), 'Direction (fondateur, directeur)');
    expect(RoleRacine.depuisCode('personnel'), RoleRacine.personnel);
    expect(DelaisVerrouillage.pour(['personnel']), const Duration(minutes: 5));
  });

  testWidgets('postes : nombre de personnes et de droits', (tester) async {
    await _monter(tester, const EcranPostes(etablissementId: 'e1'));
    expect(find.text('Caissier'), findsOneWidget);
    expect(find.text('2 personnes · 2 droit(s)'), findsOneWidget);
    expect(find.text('Personne · 1 droit(s)'), findsOneWidget);
  });

  testWidgets('créer à partir d’un modèle : droits pré-cochés ; cumul encaissement + validation empêché', (tester) async {
    final repo = await _monter(tester, const EcranPostes(etablissementId: 'e1'));
    await tester.tap(find.byKey(const Key('bouton_creer_poste')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('modele_enseignant')), findsNothing, reason: 'les enseignants n’ont pas de poste à droits');
    await tester.tap(find.byKey(const Key('modele_caissier')));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('droit_scolarite.encaissement.gerer'))).value, isTrue);
    await tester.tap(find.byKey(const Key('droit_comptabilite.valider')));
    await tester.pump();
    expect(find.byKey(const Key('avertissement_cumul')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('bouton_enregistrer_poste'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('droit_comptabilite.valider')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('champ_nom_poste')), 'Caissier du soir');
    await tester.tap(find.byKey(const Key('bouton_enregistrer_poste')));
    await tester.pumpAndSettle();
    expect(repo.appels, contains('creer:caissier:Caissier du soir:scolarite.encaissement.gerer,scolarite.encaissement.lire'));
  });

  testWidgets('fiche d’un membre : rôle et poste ; le personnel garde un poste', (tester) async {
    final repo = await _monter(tester, const EcranPersonnel(etablissementId: 'e1'));
    expect(find.text('Personnel · Caissier'), findsOneWidget);
    await tester.tap(find.byKey(const Key('membre_m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choix_poste_membre')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agent du portail').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bouton_enregistrer_membre')));
    await tester.pumpAndSettle();
    expect(repo.appels, contains('membre:m1:personnel:p2'));
  });
}
