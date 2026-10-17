import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/paiement_mobile/application/lanceur_url.dart';
import 'package:ecoshop_client/features/paiement_mobile/application/paiement_mobile_providers.dart';
import 'package:ecoshop_client/features/paiement_mobile/domain/paiement_mobile_repository.dart';
import 'package:ecoshop_client/features/paiement_mobile/domain/rapprochement_mobile_money.dart';
import 'package:ecoshop_client/features/paiement_mobile/domain/transaction_mobile_money.dart';
import 'package:ecoshop_client/features/paiement_mobile/presentation/ecran_orange_money_etablissement.dart';
import 'package:ecoshop_client/features/paiement_mobile/presentation/ecran_paiement_orange_money.dart';
import 'package:ecoshop_client/features/paiement_mobile/presentation/ecran_suivi_paiement.dart';

/// Faux port — aucun réseau, aucun Supabase. La sécurité réelle (droits,
/// montant borné, idempotence) est vérifiée côté base par
/// tests/rls/58_orange_money_gn.sql ; ici on vérifie le câblage des écrans.
class _FauxDepot implements PaiementMobileRepository {
  _FauxDepot({
    this.statuts = const [StatutTransactionMobile.reussi],
    this.erreurInitiation,
    this.etat = const EtatOrangeMoney.inactif(),
    this.transactions = const [],
  });

  final List<StatutTransactionMobile> statuts;
  final ErreurPaiementMobile? erreurInitiation;
  final EtatOrangeMoney etat;
  final List<TransactionMobileMoney> transactions;

  int lectures = 0;
  double? montantDemande;
  ObjetPaiementMobile? objetDemande;
  Map<String, Object>? activation;

  @override
  Future<InitiationPaiementMobile> initierPaiementOrange({
    required ObjetPaiementMobile objet,
    required String cibleId,
    double? montant,
  }) async {
    if (erreurInitiation != null) throw erreurInitiation!;
    objetDemande = objet;
    montantDemande = montant;
    return InitiationPaiementMobile(
      transactionId: 'tx-1',
      urlPaiement: Uri.parse('https://paiement.orange.test/tx-1'),
      montant: montant ?? 125000,
      devise: 'GNF',
    );
  }

  @override
  Future<TransactionMobileMoney> lireTransaction(String transactionId) async {
    final statut = statuts[lectures < statuts.length ? lectures : statuts.length - 1];
    lectures++;
    return TransactionMobileMoney(
      id: transactionId,
      objet: ObjetPaiementMobile.scolarite,
      montant: 500000,
      devise: 'GNF',
      statut: statut,
      creeLe: DateTime(2026, 10, 17, 9, 30),
      referenceOperateur: statut == StatutTransactionMobile.reussi ? 'MP261017.0930.A12345' : null,
      traiteLe: statut.estFinal ? DateTime(2026, 10, 17, 9, 31) : null,
    );
  }

  @override
  Future<List<TransactionMobileMoney>> transactionsEtablissement(String etablissementId, {int limite = 50}) async =>
      transactions;

  @override
  Future<void> activerOrangeMoney({
    required String etablissementId,
    required String clientId,
    required String clientSecret,
    required String merchantKey,
    required bool production,
  }) async {
    activation = {
      'etablissementId': etablissementId,
      'clientId': clientId,
      'clientSecret': clientSecret,
      'merchantKey': merchantKey,
      'production': production,
    };
  }

  @override
  Future<EtatOrangeMoney> etatOrangeMoney(String etablissementId) async => etat;

  List<AnomalieRapprochement> anomalies = const [];

  @override
  Future<RapprochementMobileMoney> rapprochement(String etablissementId, DateTime jour) async =>
      RapprochementMobileMoney(
        jour: jour,
        devise: 'GNF',
        nombreConfirmes: 1,
        montantConfirme: 500000,
        montantScolarite: 500000,
        montantMarketplace: 0,
        nonAboutis: 0,
        enCours: 0,
        anomalies: anomalies,
      );
}

class _FauxLanceur implements LanceurUrl {
  final List<Uri> ouvertes = [];

  @override
  Future<bool> ouvrir(Uri url) async {
    ouvertes.add(url);
    return true;
  }
}

Widget _app(Widget ecran, _FauxDepot depot, _FauxLanceur lanceur) => ProviderScope(
      overrides: [
        paiementMobileRepositoryProvider.overrideWithValue(depot),
        lanceurUrlProvider.overrideWithValue(lanceur),
        intervalleSuiviPaiementProvider.overrideWithValue(const Duration(milliseconds: 10)),
      ],
      child: MaterialApp(home: ecran),
    );

Future<void> _avancer(WidgetTester tester, [int fois = 12]) async {
  for (var i = 0; i < fois; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1080, 2400);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  group('Domaine', () {
    test('TransactionMobileMoney.depuisJson lit les colonnes exposées', () {
      final tx = TransactionMobileMoney.depuisJson({
        'id': 't1',
        'objet': 'commande_marketplace',
        'montant': 125000,
        'devise': 'GNF',
        'statut': 'reussi',
        'reference_operateur': 'MP1',
        'message': null,
        'created_at': '2026-10-17T09:30:00Z',
        'traite_le': '2026-10-17T09:31:00Z',
      });
      expect(tx.objet, ObjetPaiementMobile.commandeMarketplace);
      expect(tx.statut.estFinal, isTrue);
      expect(tx.montant, 125000);
      expect(tx.traiteLe, isNotNull);
    });

    test('seuls « confirmé » et « non abouti » arrêtent le suivi', () {
      expect(StatutTransactionMobile.initie.estFinal, isFalse);
      expect(StatutTransactionMobile.enAttente.estFinal, isFalse);
      expect(StatutTransactionMobile.reussi.estFinal, isTrue);
      expect(StatutTransactionMobile.echoue.estFinal, isTrue);
    });

    test('les codes serveur sont traduits en messages compréhensibles', () {
      expect(const ErreurPaiementMobile('ORANGE_MONEY_NON_ACTIVE').messageUtilisateur, contains('pas encore activé'));
      expect(const ErreurPaiementMobile('CODE_INCONNU').messageUtilisateur, contains('Vérifiez votre connexion'));
    });

    test('indicateurs du jour : seules les transactions confirmées du jour sont sommées', () {
      final maintenant = DateTime(2026, 10, 17, 12);
      TransactionMobileMoney tx(double m, StatutTransactionMobile s, DateTime d) => TransactionMobileMoney(
            id: '$m$s$d',
            objet: ObjetPaiementMobile.scolarite,
            montant: m,
            devise: 'GNF',
            statut: s,
            creeLe: d,
          );
      final indicateurs = IndicateursMobileMoney.depuis([
        tx(500000, StatutTransactionMobile.reussi, DateTime(2026, 10, 17, 9)),
        tx(250000, StatutTransactionMobile.reussi, DateTime(2026, 10, 17, 10)),
        tx(900000, StatutTransactionMobile.reussi, DateTime(2026, 10, 16, 10)),
        tx(100000, StatutTransactionMobile.initie, DateTime(2026, 10, 17, 11)),
        tx(100000, StatutTransactionMobile.echoue, DateTime(2026, 10, 17, 11)),
      ], maintenant);
      expect(indicateurs.montantConfirmeDuJour, 750000);
      expect(indicateurs.confirmeesDuJour, 2);
      expect(indicateurs.enCours, 1);
      expect(indicateurs.nonAbouties, 1);
    });
  });

  group('Écran de paiement', () {
    testWidgets('scolarité : un montant au-delà du reste à payer bloque le paiement', (tester) async {
      final depot = _FauxDepot();
      await tester.pumpWidget(_app(
        EcranPaiementOrangeMoney.scolarite(inscriptionId: 'i1', nomEleve: 'Aïssatou BAH', resteAPayer: 1500000),
        depot,
        _FauxLanceur(),
      ));
      await _avancer(tester);

      await tester.tap(find.text('Autre montant'));
      await _avancer(tester, 4);
      await tester.enterText(find.byKey(const Key('montant_libre')), '2000000');
      await _avancer(tester, 2);

      final bouton = tester.widget<FilledButton>(find.byKey(const Key('bouton_payer_orange')));
      expect(bouton.onPressed, isNull);
      expect(find.textContaining('Maximum'), findsOneWidget);
    });

    testWidgets("scolarité : paiement partiel, ouverture d'Orange Money puis confirmation", (tester) async {
      final depot = _FauxDepot(statuts: const [StatutTransactionMobile.initie, StatutTransactionMobile.reussi]);
      final lanceur = _FauxLanceur();
      var succes = 0;
      await tester.pumpWidget(_app(
        EcranPaiementOrangeMoney.scolarite(
          inscriptionId: 'i1',
          nomEleve: 'Aïssatou BAH',
          resteAPayer: 1500000,
          auSucces: (_) => succes++,
        ),
        depot,
        lanceur,
      ));
      await _avancer(tester);

      await tester.tap(find.text('Autre montant'));
      await _avancer(tester, 4);
      await tester.enterText(find.byKey(const Key('montant_libre')), '500000');
      await _avancer(tester, 2);
      await tester.tap(find.byKey(const Key('bouton_payer_orange')));
      await _avancer(tester, 20);

      expect(depot.objetDemande, ObjetPaiementMobile.scolarite);
      expect(depot.montantDemande, 500000);
      expect(lanceur.ouvertes.single.toString(), 'https://paiement.orange.test/tx-1');
      expect(find.text('Paiement confirmé'), findsWidgets);
      expect(find.text('MP261017.0930.A12345'), findsOneWidget);
      expect(succes, 1, reason: 'le rafraîchissement du solde est demandé une seule fois');
    });

    testWidgets("commande : le montant n'est pas modifiable et n'est pas envoyé par le client", (tester) async {
      final depot = _FauxDepot();
      await tester.pumpWidget(_app(
        EcranPaiementOrangeMoney.commande(commandeId: 'c1', referenceCommande: 'CMD-001', montant: 125000),
        depot,
        _FauxLanceur(),
      ));
      await _avancer(tester);

      expect(find.text('Autre montant'), findsNothing);
      await tester.tap(find.byKey(const Key('bouton_payer_orange')));
      await _avancer(tester, 20);

      expect(depot.objetDemande, ObjetPaiementMobile.commandeMarketplace);
      expect(depot.montantDemande, isNull);
    });

    testWidgets("erreur serveur : message clair, aucune page Orange ouverte", (tester) async {
      final depot = _FauxDepot(erreurInitiation: const ErreurPaiementMobile('ORANGE_MONEY_NON_ACTIVE'));
      final lanceur = _FauxLanceur();
      await tester.pumpWidget(_app(
        EcranPaiementOrangeMoney.scolarite(inscriptionId: 'i1', nomEleve: 'Mory CAMARA', resteAPayer: 800000),
        depot,
        lanceur,
      ));
      await _avancer(tester);
      await tester.tap(find.byKey(const Key('bouton_payer_orange')));
      await _avancer(tester, 6);

      expect(find.textContaining("n'a pas encore activé"), findsOneWidget);
      expect(lanceur.ouvertes, isEmpty);
    });
  });

  group('Suivi du paiement', () {
    testWidgets('paiement non abouti : écran explicite, suivi arrêté', (tester) async {
      final depot = _FauxDepot(statuts: const [StatutTransactionMobile.echoue]);
      await tester.pumpWidget(_app(
        EcranSuiviPaiement(
          transactionId: 'tx-9',
          urlPaiement: Uri.parse('https://paiement.orange.test/tx-9'),
          titre: 'Frais de scolarité',
          montant: 500000,
          devise: 'GNF',
          objet: ObjetPaiementMobile.scolarite,
        ),
        depot,
        _FauxLanceur(),
      ));
      await _avancer(tester, 15);

      expect(find.text("Le paiement n'a pas abouti"), findsOneWidget);
      final lectures = depot.lectures;
      await _avancer(tester, 10);
      expect(depot.lectures, lectures, reason: 'plus aucune lecture après un statut final');
    });

    testWidgets('en attente : la page Orange Money peut être rouverte', (tester) async {
      final depot = _FauxDepot(statuts: const [StatutTransactionMobile.initie]);
      final lanceur = _FauxLanceur();
      await tester.pumpWidget(_app(
        EcranSuiviPaiement(
          transactionId: 'tx-2',
          urlPaiement: Uri.parse('https://paiement.orange.test/tx-2'),
          titre: 'Frais de scolarité',
          montant: 500000,
          devise: 'GNF',
          objet: ObjetPaiementMobile.scolarite,
        ),
        depot,
        lanceur,
      ));
      await _avancer(tester, 3);

      expect(find.text('Validez le paiement sur Orange Money'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bouton_rouvrir')));
      await _avancer(tester, 2);
      expect(lanceur.ouvertes, hasLength(1));

      // Démonte l'écran pour arrêter le suivi (statut jamais final ici).
      await tester.pumpWidget(const SizedBox.shrink());
      await _avancer(tester, 2);
    });
  });

  group('Espace Orange Money de la Direction', () {
    testWidgets('activation : les identifiants partent au serveur, en mode test par défaut', (tester) async {
      final depot = _FauxDepot(transactions: [
        TransactionMobileMoney(
          id: 't1',
          objet: ObjetPaiementMobile.scolarite,
          montant: 500000,
          devise: 'GNF',
          statut: StatutTransactionMobile.reussi,
          creeLe: DateTime.now(),
          referenceOperateur: 'MP1',
        ),
      ]);
      await tester.pumpWidget(_app(const EcranOrangeMoneyEtablissement(etablissementId: 'e1'), depot, _FauxLanceur()));
      await _avancer(tester, 15);

      expect(find.textContaining('Non activé'), findsOneWidget);
      expect(find.text('MP1'), findsNothing, reason: 'la référence est dans le sous-titre de la ligne');
      expect(find.textContaining('MP1'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('champ_client_id')), 'client-bambino');
      await tester.enterText(find.byKey(const Key('champ_client_secret')), 'secret-xyz');
      await tester.enterText(find.byKey(const Key('champ_merchant_key')), 'MK-0001');
      await tester.ensureVisible(find.byKey(const Key('bouton_activer_orange')));
      await tester.tap(find.byKey(const Key('bouton_activer_orange')));
      await _avancer(tester, 6);

      expect(depot.activation, {
        'etablissementId': 'e1',
        'clientId': 'client-bambino',
        'clientSecret': 'secret-xyz',
        'merchantKey': 'MK-0001',
        'production': false,
      });
    });

    testWidgets('rapprochement : cas nominal puis écart signalé en clair', (tester) async {
      final depot = _FauxDepot(etat: const EtatOrangeMoney(active: true, referencePublique: 'OM-0001'));
      await tester.pumpWidget(_app(const EcranOrangeMoneyEtablissement(etablissementId: 'e1'), depot, _FauxLanceur()));
      await _avancer(tester, 15);
      expect(find.textContaining('Aucun écart'), findsOneWidget);

      depot.anomalies = const [
        AnomalieRapprochement(type: 'ENCAISSEMENT_OM_ANNULE', montant: 400000, reference: 'MP-A'),
      ];
      await tester.tap(find.byTooltip('Jour précédent'));
      await _avancer(tester, 6);
      expect(find.textContaining('1 écart(s) à vérifier'), findsOneWidget);
      expect(find.textContaining('annulé alors que'), findsOneWidget);
    });

    testWidgets('compte déjà actif : formulaire replié, identifiants jamais réaffichés', (tester) async {
      final depot = _FauxDepot(etat: const EtatOrangeMoney(active: true, referencePublique: 'OM-0001'));
      await tester.pumpWidget(_app(const EcranOrangeMoneyEtablissement(etablissementId: 'e1'), depot, _FauxLanceur()));
      await _avancer(tester, 15);

      expect(find.textContaining('OM-0001'), findsOneWidget);
      expect(find.byKey(const Key('champ_client_id')), findsNothing);
      expect(find.text('Remplacer les identifiants'), findsOneWidget);
    });
  });
}
