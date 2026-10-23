import 'package:ecoshop_client/features/liaisons_comptes/application/liaisons_providers.dart';
import 'package:ecoshop_client/features/liaisons_comptes/domain/liaison_compte.dart';
import 'package:ecoshop_client/features/liaisons_comptes/presentation/ecran_liaisons_comptes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// REG-18, partie E : la direction voit les comptes liés à ses élèves,
/// décide des liaisons en attente, révoque, règle le plafond.
class _FauxLiaisons implements LiaisonsRepository {
  _FauxLiaisons(this.lignes);

  List<LiaisonCompte> lignes;
  int valeurPlafond = 2;
  final List<String> appels = [];
  ErreurLiaisons? erreur;

  @override
  Future<List<LiaisonCompte>> liaisons(String etablissementId, {int jours = 30}) async => lignes;

  @override
  Future<StatutLiaison> decider(String relationId, {required bool accepter}) async {
    appels.add('decider:$relationId:$accepter');
    final e = erreur;
    if (e != null) throw e;
    return accepter ? StatutLiaison.confirmee : StatutLiaison.refusee;
  }

  @override
  Future<void> revoquer(LiaisonCompte liaison) async {
    appels.add('revoquer:${liaison.nature.code}:${liaison.nature == NatureLiaison.eleve ? liaison.ficheEleveId : liaison.liaisonId}');
  }

  @override
  Future<int> plafond(String etablissementId) async => valeurPlafond;

  @override
  Future<int> definirPlafond(String etablissementId, int plafond) async {
    appels.add('plafond:$plafond');
    return valeurPlafond = plafond;
  }
}

LiaisonCompte _ligne(String id, NatureLiaison nature, StatutLiaison statut, {String compte = 'Mamadou Diallo'}) =>
    LiaisonCompte(
      nature: nature,
      liaisonId: id,
      ficheEleveId: 'fiche-$id',
      eleve: 'Awa Bah',
      compteId: 'compte-$id',
      compte: compte,
      identifiantEcoshop: 'EC-7K4M-2QM',
      statut: statut,
      lieeLe: DateTime(2026, 10, 23),
    );

void main() {
  late _FauxLiaisons faux;

  Future<void> ouvrir(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [liaisonsRepositoryProvider.overrideWithValue(faux)],
      child: const MaterialApp(home: EcranLiaisonsComptes(etablissementId: 'etab-1')),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    faux = _FauxLiaisons([
      _ligne('r1', NatureLiaison.parent, StatutLiaison.enAttente),
      _ligne('r2', NatureLiaison.parent, StatutLiaison.confirmee, compte: ''),
      _ligne('f3', NatureLiaison.eleve, StatutLiaison.confirmee),
      _ligne('r4', NatureLiaison.parent, StatutLiaison.revoquee),
    ]);
  });

  testWidgets('demandes en attente séparées des liaisons récentes', (tester) async {
    await ouvrir(tester);

    expect(find.text('En attente de votre accord (1)'), findsOneWidget);
    expect(find.text('Accepter'), findsOneWidget);
    expect(find.text('Refuser'), findsOneWidget);
    // Révoquer seulement sur les liaisons actives (pas sur la révoquée).
    expect(find.text('Révoquer'), findsNWidgets(2));
    // Compte sans nom : son identifiant EcoShop est affiché.
    expect(find.text('Compte parent : EC-7K4M-2QM'), findsOneWidget);
  });

  testWidgets('accepter une liaison en attente', (tester) async {
    await ouvrir(tester);
    await tester.tap(find.text('Accepter'));
    await tester.pumpAndSettle();

    expect(faux.appels, ['decider:r1:true']);
    expect(find.text('Liaison acceptée. Le parent est prévenu.'), findsOneWidget);
  });

  testWidgets('demande déjà traitée ailleurs : message clair', (tester) async {
    faux.erreur = const ErreurLiaisons('LIAISON_DEJA_TRAITEE');
    await ouvrir(tester);
    await tester.tap(find.text('Refuser'));
    await tester.pumpAndSettle();

    expect(faux.appels, ['decider:r1:false']);
    expect(find.textContaining('déjà été traitée'), findsOneWidget);
  });

  testWidgets('révoquer un compte élève passe par sa fiche, après confirmation', (tester) async {
    await ouvrir(tester);
    final carte = find.byKey(const ValueKey('liaison_eleve_f3'));
    final bouton = find.descendant(of: carte, matching: find.text('Révoquer'));
    await tester.ensureVisible(bouton);
    await tester.pumpAndSettle();
    await tester.tap(bouton);
    await tester.pumpAndSettle();
    expect(find.text('Révoquer cette liaison ?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Révoquer'));
    await tester.pumpAndSettle();

    expect(faux.appels, ['revoquer:eleve:fiche-f3']);
  });

  testWidgets('annuler la confirmation ne révoque rien', (tester) async {
    await ouvrir(tester);
    final carte = find.byKey(const ValueKey('liaison_parent_r2'));
    final bouton = find.descendant(of: carte, matching: find.text('Révoquer'));
    await tester.ensureVisible(bouton);
    await tester.pumpAndSettle();
    await tester.tap(bouton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(faux.appels, isEmpty);
  });

  testWidgets('plafond réglable de 1 à 10', (tester) async {
    await ouvrir(tester);
    expect(find.byKey(const Key('plafond_valeur')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('plafond_valeur'))).data, '2');

    await tester.tap(find.byTooltip('Plus'));
    await tester.pumpAndSettle();

    expect(faux.appels, ['plafond:3']);
    expect(tester.widget<Text>(find.byKey(const Key('plafond_valeur'))).data, '3');
  });

  test('lecture des lignes du serveur', () {
    final l = LiaisonCompte.depuisJson({
      'nature': 'eleve',
      'liaison_id': 'f1',
      'fiche_eleve_id': 'f1',
      'eleve': ' Awa Bah ',
      'compte_id': 'c1',
      'compte': '',
      'identifiant_ecoshop': 'EC-7K4M-2QM',
      'statut': 'confirmee',
      'liee_le': '2026-10-23T10:00:00Z',
    });
    expect(l.nature, NatureLiaison.eleve);
    expect(l.eleve, 'Awa Bah');
    expect(l.compteAffiche, 'EC-7K4M-2QM');
    expect(l.peutEtreRevoquee, isTrue);
    expect(l.peutEtreDecidee, isFalse);
    expect(StatutLiaison.depuisCode('inconnu'), StatutLiaison.refusee);
  });
}
