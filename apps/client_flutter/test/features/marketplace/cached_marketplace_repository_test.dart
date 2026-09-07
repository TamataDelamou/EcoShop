import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/core/db/app_database.dart';
import 'package:ecoshop_client/core/db/cache_document_store.dart';
import 'package:ecoshop_client/core/sync/drift_sync_repository.dart';
import 'package:ecoshop_client/features/marketplace/data/cached_marketplace_repository.dart';
import 'package:ecoshop_client/features/marketplace/domain/anomalie_commande.dart';
import 'package:ecoshop_client/features/marketplace/domain/catalogue_produit.dart';
import 'package:ecoshop_client/features/marketplace/domain/commande.dart';
import 'package:ecoshop_client/features/marketplace/domain/commercant.dart';
import 'package:ecoshop_client/features/marketplace/domain/ligne_commande.dart';
import 'package:ecoshop_client/features/marketplace/domain/ligne_panier.dart';
import 'package:ecoshop_client/features/marketplace/domain/marketplace_repository.dart';
import 'package:ecoshop_client/features/marketplace/domain/paiement.dart';
import 'package:ecoshop_client/features/marketplace/domain/panier.dart';
import 'package:ecoshop_client/features/marketplace/domain/sous_compte_marchand.dart';

Panier _panier({String id = 'p1', String profileId = 'pr1'}) => Panier(
      id: id,
      etablissementId: 'et1',
      profileId: profileId,
      commercantId: 'c1',
    );

class _FauxDistant implements MarketplaceRepository {
  bool horsLigne = false;
  String? codeErreur;

  @override
  Future<List<Commercant>> commercants() async {
    if (horsLigne) throw const ErreurMarketplace('ERREUR_RESEAU');
    return const [Commercant(id: 'c1', nom: 'Librairie Conakry')];
  }

  @override
  Future<List<CatalogueProduit>> produits({String? commercantId}) async {
    if (horsLigne) throw const ErreurMarketplace('ERREUR_RESEAU');
    return const [];
  }

  @override
  Future<Panier?> panierActifPourProfil(String profileId, String etablissementId) async {
    if (horsLigne) throw const ErreurMarketplace('ERREUR_RESEAU');
    return _panier(profileId: profileId);
  }

  @override
  Future<bool> enregistrerPanier(Panier panier) async {
    final code = codeErreur;
    if (code != null) throw ErreurMarketplace(code);
    return true;
  }

  @override
  Future<List<LignePanier>> lignesDuPanier(String panierId) async {
    if (horsLigne) throw const ErreurMarketplace('ERREUR_RESEAU');
    return [LignePanier(id: 'l1', panierId: panierId, catalogueProduitId: 'cp1', quantite: 2)];
  }

  @override
  Future<bool> enregistrerLignePanier(LignePanier ligne) async {
    final code = codeErreur;
    if (code != null) throw ErreurMarketplace(code);
    return true;
  }

  @override
  Future<void> supprimerLignePanier(String ligneId) async {}

  @override
  Future<Commande> creerCommande(Commande commande) async => commande;

  @override
  Future<void> enregistrerLignesCommande(List<LigneCommande> lignes) async {}

  @override
  Future<List<Commande>> mesCommandes(String profileId) async {
    if (horsLigne) throw const ErreurMarketplace('ERREUR_RESEAU');
    return [
      Commande(id: 'cmd1', etablissementId: 'et1', commercantId: 'c1', profileId: profileId, reference: 'CMD-0001'),
    ];
  }

  @override
  Future<List<LigneCommande>> lignesDeCommande(String commandeId) async => const [];

  @override
  Future<List<SousCompteMarchand>> sousComptesEtablissement(String etablissementId) async => const [];

  @override
  Future<bool> enregistrerSousCompte(SousCompteMarchand sousCompte) async => true;

  @override
  Future<Paiement> initierPaiement(Paiement paiement) async => paiement;

  @override
  Future<List<Paiement>> paiementsDeCommande(String commandeId) async => const [];

  @override
  Future<List<AnomalieCommande>> detecterAnomalies(String etablissementId) async => const [];
}

void main() {
  late AppDatabase db;
  late _FauxDistant distant;
  late CachedMarketplaceRepository repository;

  setUp(() {
    db = AppDatabase.pourTests(NativeDatabase.memory());
    distant = _FauxDistant();
    repository = CachedMarketplaceRepository(distant, CacheDocumentStore(db, 'marketplace'), DriftSyncRepository(db));
  });

  tearDown(() => db.close());

  group('lecture', () {
    test('commercants retombe sur le cache hors ligne', () async {
      await repository.commercants();
      distant.horsLigne = true;

      final liste = await repository.commercants();
      expect(liste.single.nom, 'Librairie Conakry');
    });

    test('mesCommandes retombe sur le cache hors ligne', () async {
      await repository.mesCommandes('pr1');
      distant.horsLigne = true;

      final liste = await repository.mesCommandes('pr1');
      expect(liste.single.reference, 'CMD-0001');
    });
  });

  group('enregistrerPanier', () {
    test('renvoie true sans rien enfiler quand le réseau réussit', () async {
      final synchronise = await repository.enregistrerPanier(_panier());

      expect(synchronise, isTrue);
      expect(await DriftSyncRepository(db).entreesEnAttente(), isEmpty);
    });

    test('enfile le panier et renvoie false sur une panne réseau non métier', () async {
      distant.codeErreur = 'ERREUR_RESEAU';

      final synchronise = await repository.enregistrerPanier(_panier());

      expect(synchronise, isFalse);
      final enAttente = await DriftSyncRepository(db).entreesEnAttente();
      expect(enAttente, hasLength(1));
      expect(enAttente.single.entite, 'paniers');
    });

    test('remonte une erreur métier authentique sans l\'enfiler', () async {
      distant.codeErreur = 'PANIER_MONO_VENDEUR';

      await expectLater(
        repository.enregistrerPanier(_panier()),
        throwsA(isA<ErreurMarketplace>().having((e) => e.code, 'code', 'PANIER_MONO_VENDEUR')),
      );
      expect(await DriftSyncRepository(db).entreesEnAttente(), isEmpty);
    });
  });

  group('panierActifPourProfil — superposition de la file d\'attente', () {
    test('un panier en attente apparaît immédiatement', () async {
      distant.codeErreur = 'ERREUR_RESEAU';
      await repository.enregistrerPanier(_panier(id: 'p2', profileId: 'pr2'));
      distant.codeErreur = null;

      final panier = await repository.panierActifPourProfil('pr2', 'et1');
      expect(panier?.id, 'p2');
    });
  });
}
