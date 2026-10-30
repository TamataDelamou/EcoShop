import 'package:drift/native.dart';
import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/features/auth/application/auth_providers.dart';
import 'package:ecoshop_client/features/accueil/application/accueil_providers.dart';
import 'package:ecoshop_client/features/accueil/domain/catalogue_fonctions.dart';
import 'package:ecoshop_client/features/accueil/domain/fonction.dart';
import 'package:ecoshop_client/features/accueil/presentation/ecran_accueil.dart';
import 'package:ecoshop_client/features/auth/domain/profil.dart';
import 'package:ecoshop_client/features/etablissement/domain/etablissement.dart';
import 'package:ecoshop_client/features/scolarite/domain/fiche_eleve.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// REG-21, étape 2 : accueil par rôle.
final _ecole = Etablissement.depuisJson({'id': 'e1', 'nom': 'École Bambino', 'slug': 'b', 'devise_code': 'GNF'});
final _fiche = FicheEleve(
    id: 'f1', etablissementId: 'e1', matricule: 'M1', nom: 'SOW', prenom: 'Aïcha', dateNaissance: DateTime(2016));

ContexteAccueil _ctx(RoleRacine role, {Set<String> droits = const {}, bool chauffeur = false}) => ContexteAccueil(
  profil: Profil(id: 'c1', identifiantCanonique: 'a@b.org', statutCompte: StatutCompte.actif, roleRacine: role, prenom: 'Awa'),
  etablissement: _ecole,
  droits: droits,
  enfant: role == RoleRacine.parent ? _fiche : null,
  maFiche: role == RoleRacine.eleve ? _fiche : null,
  anneeId: 'a1',
  chauffeur: chauffeur,
);

List<String> _ids(ContexteAccueil c) => [for (final f in fonctionsVisibles(c)) f.id];

void main() {
  group('pastilles visibles selon le rôle et les droits', () {
    test('parent : l’ordre des maquettes, rien de l’école', () {
      final ids = _ids(_ctx(RoleRacine.parent));
      expect(ids.take(9), ['annonces', 'cahier_liaison', 'emploi_du_temps', 'notes_bulletins', 'scolarite', 'bus',
        'parent_ia', 'inscriptions_famille', 'boutique']);
      expect(ids, isNot(contains('encaissements')));
      expect(ids, isNot(contains('comptes_lies')));
      expect(ids, isNot(contains('groupes_classe')), reason: 'aucun parent dans les groupes de classe (REG-34)');
    });

    test('élève : emploi du temps, notes, Scan-Exercice, bibliothèque', () {
      final ids = _ids(_ctx(RoleRacine.eleve));
      expect(ids.take(5), ['emploi_du_temps', 'notes_bulletins', 'annonces', 'groupes_classe', 'scan_exercice']);
      expect(ids, containsAll(['bibliotheque_famille', 'mes_rapports', 'bus']));
      expect(ids, isNot(contains('cahier_liaison')));
    });

    test('enseignant : appel, notes, cahier, classes, progression, dossier RH', () {
      final ids = _ids(_ctx(RoleRacine.enseignant));
      expect(ids.take(7),
          ['faire_appel', 'notes_enseignant', 'cahier_liaison', 'groupes_classe', 'mes_classes', 'annonces', 'progression']);
      expect(ids, isNot(contains('encaissements')));
      expect(ids, isNot(contains('postes')));
    });

    test('direction : chaque groupe des maquettes', () {
      final c = _ctx(RoleRacine.direction);
      final parGroupe = <String, List<String>>{};
      for (final f in fonctionsVisibles(c)) {
        parGroupe.putIfAbsent(f.groupe, () => []).add(f.id);
      }
      expect(parGroupe['Vie de l’école'], containsAll(['annonces', 'cahier_liaison', 'groupes_classe', 'presence_portail', 'alertes_decrochage']));
      expect(parGroupe['Élèves'], ['inscriptions_en_ligne', 'nouvelle_inscription', 'reinscription', 'comptes_lies']);
      expect(parGroupe['Finances'], containsAll(['encaissements', 'relances', 'comptabilite', 'orange_money',
        'parametres_financiers', 'credits_sms']));
      expect(parGroupe['Personnel'], containsAll(['invitations_personnel', 'personnel_rh', 'numeros_a_confirmer']));
      expect(parGroupe['Organisation'], containsAll(['classes_emploi', 'salles', 'bibliotheque', 'transport', 'structures']));
      expect(parGroupe['Établissement'], containsAll(['identite_visuelle', 'rapports', 'ouvrir_etablissement']));
    });

    test('personnel : selon le poste — caissier, agent du portail, chauffeur', () {
      final caissier = _ids(_ctx(RoleRacine.personnel, droits: {'scolarite.encaissement.gerer', 'scolarite.encaissement.lire'}));
      expect(caissier, contains('encaissements'));
      expect(caissier, isNot(contains('comptabilite')));
      expect(caissier, isNot(contains('relances')), reason: 'relances : direction');
      final portail = _ids(_ctx(RoleRacine.personnel, droits: {'portail.scanner'}));
      expect(portail, contains('portail_scanner'));
      expect(portail, isNot(contains('presence_portail')));
      expect(portail, isNot(contains('encaissements')));
      expect(portail, isNot(contains('cahier_liaison')));
      final chauffeur = _ids(_ctx(RoleRacine.personnel, chauffeur: true));
      expect(chauffeur, contains('conduire_circuit'));
      expect(chauffeur, isNot(contains('portail_scanner')));
      final surveillant = _ids(_ctx(RoleRacine.personnel,
          droits: {'scolarite.presence.gerer', 'scolarite.liaison.ecrire', 'portail.scanner'}));
      expect(surveillant, containsAll(['presence_portail', 'portail_scanner', 'cahier_liaison']));
      final comptable = _ids(_ctx(RoleRacine.personnel, droits: {'comptabilite.lire', 'scolarite.encaissement.lire'}));
      expect(comptable, containsAll(['comptabilite', 'encaissements']));
    });

    test('administrateur GSG : la plateforme, pas l’école', () {
      final ids = _ids(_ctx(RoleRacine.adminGsg));
      expect(ids, containsAll(['gsg_etablissements', 'gsg_reseaux', 'gsg_sms', 'gsg_vendeurs', 'gsg_debloquer']));
      expect(ids, isNot(contains('boutique')));
    });

    test('identifiants uniques (raccourcis gardés sur l’appareil)', () {
      final ids = [for (final f in catalogueFonctions) f.id];
      expect(ids.toSet().length, ids.length);
    });
  });

  group('recherche « Que voulez-vous faire ? »', () {
    test('« reçu » et « recu » trouvent Encaissements', () {
      final tout = fonctionsVisibles(_ctx(RoleRacine.direction));
      expect(rechercher(tout, 'reçu').map((f) => f.id), contains('encaissements'));
      expect(rechercher(tout, 'RECU').map((f) => f.id), contains('encaissements'));
      expect(rechercher(tout, 'liaison').map((f) => f.id), containsAll(['cahier_liaison', 'comptes_lies']));
      expect(rechercher(tout, 'zzz'), isEmpty);
    });
  });

  group('écran', () {
    Future<void> monter(WidgetTester tester, ContexteAccueil c, Map<String, int> resume) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          contexteAccueilProvider.overrideWithValue(c),
          resumeAccueilProvider.overrideWith((ref) async => resume),
          aujourdhuiProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: Scaffold(body: EcranAccueil())),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('direction : « À faire » des maquettes, groupes, badges', (tester) async {
      await monter(tester, _ctx(RoleRacine.direction),
          {'liaisons_a_valider': 3, 'numeros_a_confirmer': 5, 'familles_en_retard': 12, 'annonces_non_lues': 4});
      expect(find.text('3 demandes de liaison à valider'), findsOneWidget);
      expect(find.text('5 numéros à confirmer'), findsOneWidget);
      expect(find.text('12 familles en retard de paiement'), findsOneWidget);
      expect(find.text('4 annonces à lire'), findsNothing, reason: 'les annonces ont déjà leur badge');
      expect(find.text('VIE DE L’ÉCOLE'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('FINANCES'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('FINANCES'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('raccourci_relances')), matching: find.text('12')), findsOneWidget,
          reason: 'badge Relances (raccourci)');
    });

    testWidgets('badge lu par TalkBack : « Annonces, 4 nouvelles »', (tester) async {
      final s = tester.ensureSemantics();
      await monter(tester, _ctx(RoleRacine.direction), {'annonces_non_lues': 4});
      expect(find.bySemanticsLabel('Annonces, 4 nouvelles'), findsWidgets);
      s.dispose();
    });

    testWidgets('élève : « À ne pas manquer »', (tester) async {
      await monter(tester, _ctx(RoleRacine.eleve), {'nouvelles_notes': 1, 'livres_a_rendre': 1});
      expect(find.text('À NE PAS MANQUER'), findsOneWidget);
      expect(find.text('Nouvelle note'), findsOneWidget);
      expect(find.text('1 livre à rendre à la bibliothèque'), findsOneWidget);
    });

    testWidgets('agent du portail : pas de ligne pour un compteur qu’il ne peut pas ouvrir', (tester) async {
      await monter(tester, _ctx(RoleRacine.personnel, droits: {'portail.scanner'}), {'familles_en_retard': 9});
      expect(find.textContaining('familles en retard'), findsNothing);
      expect(find.byKey(const Key('pastille_portail_scanner')), findsOneWidget);
      expect(find.text('MON TRAVAIL'), findsOneWidget);
    });

    testWidgets('hors connexion, aucune valeur connue : les pastilles s’affichent quand même', (tester) async {
      await monter(tester, _ctx(RoleRacine.parent), const {});
      expect(find.text('À FAIRE'), findsNothing);
      expect(find.byKey(const Key('pastille_annonces')), findsOneWidget);
      expect(find.byKey(const Key('pastille_scolarite')), findsOneWidget);
    });

    testWidgets('pastilles : vrais boutons, au moins 48 × 48', (tester) async {
      await monter(tester, _ctx(RoleRacine.parent), const {});
      final taille = tester.getSize(find.byKey(const Key('pastille_annonces')));
      expect(taille.width, greaterThanOrEqualTo(48));
      expect(taille.height, greaterThanOrEqualTo(48));
    });
  });

  group('raccourcis et recherche (étape 4)', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.pourTests(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> monter(WidgetTester tester, ContexteAccueil c) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          contexteAccueilProvider.overrideWithValue(c),
          resumeAccueilProvider.overrideWith((ref) async => const {}),
          aujourdhuiProvider.overrideWith((ref) async => const []),
          profilProvider.overrideWith((ref) async => c.profil),
          storeRaccourcisProvider.overrideWithValue(CacheDocumentStore(db, 'preferences_accueil')),
        ],
        child: const MaterialApp(home: Scaffold(body: EcranAccueil())),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('direction : quatre raccourcis par défaut (maquette)', (tester) async {
      await monter(tester, _ctx(RoleRacine.direction));
      for (final id in ['encaissements', 'annonces', 'relances', 'rapports']) {
        expect(find.byKey(Key('raccourci_$id')), findsOneWidget, reason: id);
      }
    });

    testWidgets('« Modifier » : le choix est gardé sur l’appareil', (tester) async {
      await monter(tester, _ctx(RoleRacine.direction));
      await tester.tap(find.byKey(const Key('bouton_modifier_raccourcis')));
      await tester.pumpAndSettle();
      Future<void> toucher(String cle) async {
        await tester.scrollUntilVisible(find.byKey(Key(cle)), 120, scrollable: find.descendant(of: find.byKey(const Key('liste_choix_raccourcis')), matching: find.byType(Scrollable)));
        // La liste construit d'avance les cases juste sous le bord : les
        // amener à l'écran avant de toucher.
        await tester.ensureVisible(find.byKey(Key(cle)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(cle)));
        await tester.pump();
      }
      await toucher('choix_raccourci_relances');
      await toucher('choix_raccourci_transport');
      await toucher('bouton_valider_raccourcis');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('raccourci_transport')), findsOneWidget);
      expect(find.byKey(const Key('raccourci_relances')), findsNothing);
      // Réouverture de l'application : relu sur l'appareil.
      await tester.pumpWidget(const SizedBox());
      await monter(tester, _ctx(RoleRacine.direction));
      expect(find.byKey(const Key('raccourci_transport')), findsOneWidget);
      expect(find.byKey(const Key('raccourci_relances')), findsNothing);
    });

    testWidgets('plus de quatre raccourcis : impossible', (tester) async {
      await monter(tester, _ctx(RoleRacine.direction));
      await tester.tap(find.byKey(const Key('bouton_modifier_raccourcis')));
      await tester.pumpAndSettle();
      expect(find.text('Choisissez jusqu’à 4 raccourcis (4/4)'), findsOneWidget);
      final libre = tester.widget<CheckboxListTile>(find.byKey(const Key('choix_raccourci_cahier_liaison')));
      expect(libre.onChanged, isNull);
    });

    testWidgets('recherche : « reçu » → Encaissements ; rien → message', (tester) async {
      await monter(tester, _ctx(RoleRacine.direction));
      await tester.enterText(find.byKey(const Key('recherche_accueil')), 'reçu');
      await tester.pumpAndSettle();
      expect(find.text('RÉSULTATS'), findsOneWidget);
      expect(find.byKey(const Key('pastille_encaissements')), findsOneWidget);
      expect(find.byKey(const Key('pastille_salles')), findsNothing);
      await tester.enterText(find.byKey(const Key('recherche_accueil')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recherche_vide')), findsOneWidget);
    });

    testWidgets('personnel : recherche et raccourcis parmi ses seules pastilles', (tester) async {
      await monter(tester, _ctx(RoleRacine.personnel, droits: {'portail.scanner'}));
      expect(find.byKey(const Key('recherche_accueil')), findsOneWidget);
      expect(find.byKey(const Key('raccourci_encaissements')), findsNothing);
      await tester.enterText(find.byKey(const Key('recherche_accueil')), 'reçu');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pastille_encaissements')), findsNothing);
    });

    testWidgets('parent : ni recherche ni raccourcis', (tester) async {
      await monter(tester, _ctx(RoleRacine.parent));
      expect(find.byKey(const Key('recherche_accueil')), findsNothing);
      expect(find.byKey(const Key('bouton_modifier_raccourcis')), findsNothing);
    });
  });
}
