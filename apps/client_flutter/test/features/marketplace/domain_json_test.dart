import 'package:flutter_test/flutter_test.dart';

import 'package:ecoshop_client/features/marketplace/domain/commande.dart';
import 'package:ecoshop_client/features/marketplace/domain/enums_marketplace.dart';
import 'package:ecoshop_client/features/marketplace/domain/ligne_panier.dart';
import 'package:ecoshop_client/features/marketplace/domain/panier.dart';
import 'package:ecoshop_client/features/marketplace/domain/panier_brouillon_local.dart';

void main() {
  group('Panier', () {
    test('versJsonEcriture/depuisJsonEcriture font un aller-retour fidèle', () {
      final panier = Panier(
        id: 'p1',
        etablissementId: 'et1',
        profileId: 'pr1',
        commercantId: 'c1',
        deviceId: 'dev1',
        clientTs: DateTime(2026, 3, 1),
      );

      final relu = Panier.depuisJsonEcriture(panier.versJsonEcriture());

      expect(relu.etablissementId, 'et1');
      expect(relu.commercantId, 'c1');
      expect(relu.deviceId, 'dev1');
    });
  });

  group('LignePanier', () {
    test('versJsonEcriture/depuisJsonEcriture font un aller-retour fidèle', () {
      final ligne = LignePanier(id: 'l1', panierId: 'p1', catalogueProduitId: 'cp1', quantite: 3);

      final relue = LignePanier.depuisJsonEcriture(ligne.versJsonEcriture());

      expect(relue.panierId, 'p1');
      expect(relue.catalogueProduitId, 'cp1');
      expect(relue.quantite, 3);
    });

    test('versJsonEcriture n\'expose pas les champs d\'affichage', () {
      final ligne = LignePanier(id: 'l1', panierId: 'p1', catalogueProduitId: 'cp1', libelleProduit: 'Cahier');

      expect(ligne.versJsonEcriture().containsKey('libelle_produit'), isFalse);
    });
  });

  group('Commande', () {
    test('versJsonCache/depuisJsonCache font un aller-retour fidèle', () {
      final commande = Commande(
        id: 'cmd1',
        etablissementId: 'et1',
        commercantId: 'c1',
        profileId: 'pr1',
        reference: 'CMD-0001',
        statut: StatutCommande.confirmee,
        montantTotal: 5000,
        devise: 'GNF',
      );

      final relue = Commande.depuisJsonCache(commande.versJsonCache());

      expect(relue.statut, StatutCommande.confirmee);
      expect(relue.montantTotal, 5000);
      expect(relue.devise, 'GNF');
    });
  });

  group('PanierBrouillonLocal', () {
    test('ajouter incrémente la quantité existante', () {
      var brouillon = PanierBrouillonLocal.vide;
      brouillon = brouillon.ajouter(commercantId: 'c1', catalogueProduitId: 'cp1');
      brouillon = brouillon.ajouter(commercantId: 'c1', catalogueProduitId: 'cp1');

      expect(brouillon.quantites['cp1'], 2);
      expect(brouillon.nombreArticles, 2);
    });

    test('ajouter un produit d\'un autre commerçant lève une exception mono-vendeur', () {
      var brouillon = PanierBrouillonLocal.vide;
      brouillon = brouillon.ajouter(commercantId: 'c1', catalogueProduitId: 'cp1');

      expect(
        () => brouillon.ajouter(commercantId: 'c2', catalogueProduitId: 'cp2'),
        throwsA(isA<PanierBrouillonMonoVendeurException>()),
      );
    });

    test('definirQuantite à zéro retire la ligne et vide le panier si dernier article', () {
      var brouillon = PanierBrouillonLocal.vide.ajouter(commercantId: 'c1', catalogueProduitId: 'cp1');
      brouillon = brouillon.definirQuantite('cp1', 0);

      expect(brouillon.estVide, isTrue);
      expect(brouillon.commercantId, isNull);
    });

    test('depuisJsonCache/versJsonCache font un aller-retour fidèle', () {
      final brouillon = PanierBrouillonLocal.vide.ajouter(commercantId: 'c1', catalogueProduitId: 'cp1', quantite: 4);
      final relu = PanierBrouillonLocal.depuisJsonCache(brouillon.versJsonCache());

      expect(relu.commercantId, 'c1');
      expect(relu.quantites['cp1'], 4);
    });
  });
}
