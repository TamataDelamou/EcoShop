import 'package:drift/native.dart';
import 'package:ecoshop_client/core/auth/role_racine.dart';
import 'package:ecoshop_client/core/auth/supabase_auth_provider.dart';
import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/offline/amorcage.dart';
import 'package:ecoshop_client/core/providers.dart';
import 'package:ecoshop_client/core/sync/sync_providers.dart';
import 'package:ecoshop_client/features/coquille/application/amorcage_controller.dart';
import 'package:ecoshop_client/features/coquille/application/plan_amorcage.dart';
import 'package:ecoshop_client/features/coquille/application/sync_composition.dart';
import 'package:ecoshop_client/features/notes/application/notes_providers.dart';
import 'package:ecoshop_client/features/notes/domain/enums_notes.dart';
import 'package:ecoshop_client/features/notes/domain/evaluation.dart';
import 'package:ecoshop_client/features/notes/domain/note.dart';
import 'package:ecoshop_client/features/rh_personnel/application/rh_providers.dart';
import 'package:ecoshop_client/features/scolarite/application/scolarite_providers.dart';
import 'package:ecoshop_client/features/vie_scolaire/application/vie_scolaire_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;

import '../support/serveur_simule.dart';

/// REG-35 lot 6 — le hors-connexion joué de bout en bout, rôle par rôle,
/// avec les vrais dépôts de l'application contre un serveur simulé :
/// réseau normal, lent (2G), coupé, coupé en cours de route, réponse perdue.
const _ecole = 'ecole';

Map<String, dynamic> _fiche(String id, String prenom, {String? profil}) => {
      'id': id,
      'etablissement_id': _ecole,
      'matricule': 'GN-$id',
      'nom': 'CAMARA',
      'prenom': prenom,
      'date_naissance': '2014-05-06',
      'profile_id': profil,
    };

Map<String, dynamic> _evaluation(String id, String classe) => {
      'id': id,
      'etablissement_id': _ecole,
      'annee_scolaire_id': 'a1',
      'classe_id': classe,
      'enseignant_profile_id': 'prof',
      'libelle': 'Devoir de mathématiques',
      'date_evaluation': '2026-10-20',
      'coefficient': 2,
      'bareme': 20,
    };

/// Une école : deux classes, une élève inscrite, un enseignant, une mère,
/// une note, une demande de congé.
ServeurSimule _ecoleSimulee() {
  final s = ServeurSimule();
  s.table('annees_scolaires').add({
    'id': 'a1',
    'etablissement_id': _ecole,
    'libelle': '2026-2027',
    'date_debut': '2026-10-01',
    'date_fin': '2027-06-30',
    'courante': true,
  });
  for (final (id, nom) in [('c1', '6e A'), ('c2', '6e B')]) {
    s.table('classes').add({
      'id': id,
      'etablissement_id': _ecole,
      'annee_scolaire_id': 'a1',
      'code': id,
      'nom': nom,
      'actif': true,
    });
  }
  s.table('fiches_eleves').add(_fiche('f1', 'Fanta', profil: 'eleve'));
  s.table('inscriptions').add({
    'id': 'i1',
    'etablissement_id': _ecole,
    'fiche_eleve_id': 'f1',
    'classe_id': 'c1',
    'annee_scolaire_id': 'a1',
    'date_inscription': '2026-10-02',
    'statut': 'active',
    'fiches_eleves': _fiche('f1', 'Fanta', profil: 'eleve'),
    'classes': {'id': 'c1', 'etablissement_id': _ecole, 'annee_scolaire_id': 'a1', 'code': 'c1', 'nom': '6e A'},
  });
  s.table('affectations_enseignants').add({
    'id': 'af1',
    'etablissement_id': _ecole,
    'annee_scolaire_id': 'a1',
    'enseignant_profile_id': 'prof',
    'classe_id': 'c1',
  });
  s.table('relations_parent_eleve').add({
    'id': 'r1',
    'etablissement_id': _ecole,
    'parent_profile_id': 'mere',
    'fiche_eleve_id': 'f1',
    'statut': 'confirmee',
    'autorise': true,
    'fiches_eleves': _fiche('f1', 'Fanta', profil: 'eleve'),
  });
  s.table('evaluations').add(_evaluation('ev0', 'c1'));
  s.table('notes').add({
    'id': 'n0',
    'etablissement_id': _ecole,
    'evaluation_id': 'ev0',
    'fiche_eleve_id': 'f1',
    'saisi_par': 'prof',
    'valeur': 15,
    'evaluations': _evaluation('ev0', 'c1'),
  });
  s.table('conges').add({
    'id': 'cg1',
    'etablissement_id': _ecole,
    'employe_id': 'emp1',
    'date_debut': '2026-11-03',
    'date_fin': '2026-11-05',
    'nb_jours': 3,
    'statut': 'demande',
  });
  return s;
}

final _enLigne = StateProvider<bool>((ref) => true);
final _sources = Provider<SourcesAmorcage>((ref) => sourcesAmorcage(ref));

/// Téléphone d'un compte : base locale, client relié au serveur simulé.
class _Telephone {
  _Telephone._(this.container, this.db);

  final ProviderContainer container;
  final AppDatabase db;

  static Future<_Telephone> de(ServeurSimule serveur, String compte) async {
    final db = AppDatabase.pourTests(NativeDatabase.memory());
    final client = await serveur.client(compte: compte);
    final container = ProviderContainer(overrides: [
      supabaseClientProvider.overrideWithValue(client),
      databaseProvider.overrideWithValue(db),
      estEnLigneProvider.overrideWith((ref) => ref.watch(_enLigne)),
    ]);
    return _Telephone._(container, db);
  }

  T lire<T>(ProviderListenable<T> p) => container.read(p);

  set enLigne(bool v) => container.read(_enLigne.notifier).state = v;

  Future<EtatAmorcage> amorcer(RoleRacine role, String compte) => executerAmorcage(
        planAmorcage(role: role, etablissementId: _ecole, profileId: compte, sources: lire(_sources)),
      );

  Future<int> synchroniser() => lire(syncEngineProvider).synchroniser();

  Future<void> fermer() async {
    container.dispose();
    await db.close();
  }
}

void main() {
  late ServeurSimule serveur;

  setUp(() => serveur = _ecoleSimulee());

  test('Enseignant : journée sans réseau — consulter, créer un devoir, noter ; tout part au retour, une seule fois',
      () async {
    final tel = await _Telephone.de(serveur, 'prof');
    addTearDown(tel.fermer);

    // Le matin, avec réseau : l'application prépare ses classes.
    final amorcage = await tel.amorcer(RoleRacine.enseignant, 'prof');
    expect(amorcage.issue, IssueAmorcage.termine);
    expect(amorcage.refusees, 0);

    // En classe, sans réseau.
    serveur.reseau = Reseau.coupe;
    tel.enLigne = false;
    final eleves = await tel.lire(scolariteRepositoryProvider).inscriptionsDeClasse('c1');
    expect(eleves.single.ficheEleveId, 'f1', reason: 'liste de la classe lue sur le téléphone');
    final devoirs = await tel.lire(notesRepositoryProvider).evaluationsDeClasse('c1');
    expect(devoirs.map((e) => e.id), contains('ev0'));

    final devoir = await tel.lire(notesRepositoryProvider).creerEvaluation(Evaluation(
          id: '',
          etablissementId: _ecole,
          anneeScolaireId: 'a1',
          classeId: 'c1',
          enseignantProfileId: 'prof',
          libelle: 'Interrogation surprise',
          dateEvaluation: DateTime(2026, 10, 30),
          type: TypeEvaluation.values.first,
          coefficient: 1,
          bareme: 20,
        ));
    expect(devoir.id, isNotEmpty, reason: 'identifiant tiré sur le téléphone');
    final envoyee = await tel.lire(notesRepositoryProvider).saisirNote(Note(
          id: 'n-hors-ligne',
          etablissementId: _ecole,
          evaluationId: devoir.id,
          ficheEleveId: 'f1',
          saisiPar: 'prof',
          valeur: 17,
        ));
    expect(envoyee, isFalse, reason: 'gardée en file, pas perdue');
    expect(serveur.table('evaluations').length, 1, reason: 'rien n’est parti sans réseau');

    // Retour du réseau.
    serveur.reseau = Reseau.normal;
    tel.enLigne = true;
    await tel.synchroniser();
    await tel.synchroniser(); // un second passage ne crée rien de plus

    expect(serveur.table('evaluations').where((e) => e['id'] == devoir.id).length, 1);
    final note = serveur.table('notes').singleWhere((n) => n['evaluation_id'] == devoir.id);
    expect(note['valeur'], 17);
    expect(await tel.lire(syncRepositoryProvider).entreesEnAttente(), isEmpty);
  });

  test('Enseignant : réponse du serveur perdue après la création — jamais deux devoirs', () async {
    final tel = await _Telephone.de(serveur, 'prof');
    addTearDown(tel.fermer);

    serveur.reponsesPerdues = 1; // le serveur enregistre, la réponse se perd
    final devoir = await tel.lire(notesRepositoryProvider).creerEvaluation(Evaluation(
          id: '',
          etablissementId: _ecole,
          anneeScolaireId: 'a1',
          classeId: 'c1',
          enseignantProfileId: 'prof',
          libelle: 'Devoir maison',
          dateEvaluation: DateTime(2026, 10, 30),
          type: TypeEvaluation.values.first,
        ));
    await tel.synchroniser();

    expect(serveur.table('evaluations').where((e) => e['id'] == devoir.id).length, 1);
    expect(await tel.lire(syncRepositoryProvider).entreesEnAttente(), isEmpty);
  });

  test('Direction : réseau 2G — la liste s’affiche en moins de 4 s depuis le téléphone', () async {
    final tel = await _Telephone.de(serveur, 'dir');
    addTearDown(tel.fermer);
    expect((await tel.amorcer(RoleRacine.direction, 'dir')).issue, IssueAmorcage.termine);

    serveur
      ..reseau = Reseau.lent
      ..latence = const Duration(seconds: 6);
    final chrono = Stopwatch()..start();
    final eleves = await tel.lire(scolariteRepositoryProvider).inscriptionsDeClasse('c1');
    chrono.stop();
    expect(eleves, hasLength(1));
    expect(chrono.elapsed, lessThan(const Duration(seconds: 4)));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('Direction : congé validé sans réseau mais refusé entre-temps par un autre — refus visible, rien d’écrasé',
      () async {
    final tel = await _Telephone.de(serveur, 'dir');
    addTearDown(tel.fermer);

    serveur.reseau = Reseau.coupe;
    tel.enLigne = false;
    await tel.lire(rhRepositoryProvider).validerConge('cg1', statut: 'valide', valideePar: 'dir');

    // Pendant ce temps, l'adjoint refuse le congé depuis le bureau.
    serveur.table('conges').single['statut'] = 'refuse';

    serveur.reseau = Reseau.normal;
    tel.enLigne = true;
    await tel.synchroniser();

    expect(serveur.table('conges').single['statut'], 'refuse');
    final refus = await tel.lire(journalRejetsProvider).lister();
    expect(refus.single.code, 'CONGE_DEJA_TRAITE');
    expect(refus.single.libelle, 'Décision sur un congé');
  });

  test('Parent : coupure au milieu de la préparation — reprise au retour, puis consultation sans réseau', () async {
    final tel = await _Telephone.de(serveur, 'mere');
    addTearDown(tel.fermer);

    serveur.coupureApres = 3;
    final premiere = await tel.amorcer(RoleRacine.parent, 'mere');
    expect(premiere.issue, IssueAmorcage.interrompu);

    serveur
      ..coupureApres = null
      ..reseau = Reseau.normal;
    expect((await tel.amorcer(RoleRacine.parent, 'mere')).issue, IssueAmorcage.termine);

    serveur.reseau = Reseau.coupe;
    tel.enLigne = false;
    final notes = await tel.lire(notesRepositoryProvider).notesDeFiche('f1');
    expect(notes.single.valeur, 15, reason: 'note de l’enfant lue sur le téléphone');
    expect(await tel.lire(vieScolaireRepositoryProvider).presencesDeFiche('f1'), isEmpty);
  });

  test('Élève : ses notes restent lisibles en mode avion', () async {
    final tel = await _Telephone.de(serveur, 'eleve');
    addTearDown(tel.fermer);
    expect((await tel.amorcer(RoleRacine.eleve, 'eleve')).issue, IssueAmorcage.termine);

    serveur.reseau = Reseau.coupe;
    tel.enLigne = false;
    expect((await tel.lire(notesRepositoryProvider).notesDeFiche('f1')).single.valeur, 15);
  });
}

