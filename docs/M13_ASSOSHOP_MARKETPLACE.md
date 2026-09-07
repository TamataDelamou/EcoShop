# M13 — Marketplace AssoShop mono-vendeur

Module d'ouverture de la **Phase C** (Marketplace AssoShop, services &
monétisation). Il implémente le cadre **mono-vendeur** arbitré dans le cahier
v4.1 (ch. 27) : commandes restreintes à un seul commerçant, sous-comptes
marchands dédiés par établissement, port de paiement agnostique.

## 1. Règles métier arbitrées (intégrées strictement)

| # | Règle | Implémentation |
|---|---|---|
| 1 | **Panier mono-vendeur** : chaque commande est restreinte à un seul commerçant externe | Colonne `paniers.commercant_id` unique + trigger `lignes_paniers_verifie_commercant` (rejet `23514` si produit d'un autre commerçant) |
| 2 | **Comptes CinetPay dédiés** : isolation stricte des encaissements (scolarité, cantine) sur les identifiants propres de chaque établissement | Table `sous_comptes_marchands` (unique `(etablissement_id, fournisseur)`), RLS `est_membre_actif(etablissement_id)`, **secrets jamais stockés en clair** (Supabase Vault / secrets d'Edge Function) |
| 3 | **Port de paiement agnostique** : architecture prête pour un sous-jacent Mobile Money aux côtés de CinetPay | Enum `type_fournisseur_paiement` (`cinetpay`, `mobile_money`) + table `paiements` générique (`fournisseur`, `reference_fournisseur`, `statut`) — aucun schéma spécifique fournisseur |

## 2. Modèle de données

| Table | Rôle |
|---|---|
| `commercants` | Commerçants externes (vendeurs hors établissement) |
| `catalogues_produits` | Produits portés par un commerçant (prix, devise, actif) |
| `paniers` | Panier mono-vendeur (un `commercant_id`, propriétaire `profile_id`) |
| `lignes_paniers` | Lignes de panier (garde-fou mono-vendeur) |
| `commandes` | Commandes (référence unique, statut, montants, devise) |
| `lignes_commandes` | Snapshot des prix à la commande |
| `sous_comptes_marchands` | Identifiants de paiement par établissement (CinetPay / Mobile Money) |
| `paiements` | Paiements agnostiques (fournisseur, référence, statut) |

## 3. Garde-fous (multi-tenant + métier)

- `lignes_paniers_verifie_commercant` : le produit doit appartenir au commerçant du panier.
- `commandes_verifie_panier` : même commerçant et même établissement que le panier.
- `lignes_commandes_verifie_commercant` : le produit doit appartenir au commerçant de la commande.
- `paiements_verifie_fournisseur` : le fournisseur du paiement doit correspondre à celui du sous-compte.

## 4. RLS

- Catalogue (`commercants`, `catalogues_produits`) : lecture publique, gestion réservée `service_role`/`admin_gsg`.
- Panier/lignes : propriétaire uniquement (`profile_id = auth.uid()`).
- Commandes/paiements : propriétaire + membres actifs de l'établissement + service.
- Sous-comptes marchands : **isolation stricte** par établissement.

## 5. Fonction IA (aide à la décision)

`detecter_anomalies_commandes(etablissement)` signale les commandes au montant
élevé (> 1 000 000) ou aux paiements multiples en attente. Aucune action
automatique : les anomalies sont soumises à validation humaine.

## 6. Livrables

| Livrable | Chemin |
|---|---|
| DDL | `supabase/migrations/20260906001300_m13_marketplace_assoshop.sql` |
| Seed | `supabase/seed_marketplace_assoshop.sql` |
| Tests RLS | `tests/rls/28_m13_visibilite_catalogue.sql`, `29_m13_panier_mono_vendeur.sql`, `30_m13_commandes_paiement.sql` |
| Recherche comparative §15 | `docs/RECHERCHE_COMPARATIVE.md` |

## 7. Périmètre différé (modules suivants)

- M14 — Paiement (adaptateurs CinetPay + Mobile Money en Edge Functions, reçus, encaissements scolarité).
- Gestion des frais/commissions GSG (paramètre global `commission_marketplace_pct` déjà seedé en M0).
