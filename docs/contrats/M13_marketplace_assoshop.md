# M13 — Marketplace AssoShop (mono-vendeur) — Contrat d'interface Flutter

> Migration : `supabase/migrations/20260906001300_m13_marketplace_assoshop.sql`.
> Source de vérité : SQL + tests RLS associés.
> Périmètre : commerçants externes, catalogue produits, panier **mono-vendeur**, commandes, paiements (port agnostique CinetPay / Mobile Money), sous-comptes par établissement.

## 1. Enums

| Enum | Valeurs |
|---|---|
| `public.type_fournisseur_paiement` | `cinetpay`, `mobile_money` |
| `public.statut_commande` | `brouillon`, `confirmee`, `payee`, `expediee`, `livree`, `annulee` |
| `public.statut_paiement` | `initie`, `en_attente`, `reussi`, `echoue`, `rembourse` |

## 2. Tables (DTOs)

### `public.commercants`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| nom | text | NOT NULL |
| raison_sociale | text | nullable |
| telephone | text | nullable |
| email | text | nullable |
| actif | boolean | NOT NULL DEFAULT true |
| created_at / updated_at | timestamptz | NOT NULL DEFAULT now() |
| deleted_at | timestamptz | soft-delete |

Unique partiel `idx_commercants_nom_unique` sur `(nom)` où `deleted_at is null`.

### `public.catalogues_produits`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| commercant_id | uuid | NOT NULL, FK → `commercants(id)` CASCADE |
| libelle | text | NOT NULL |
| description | text | nullable |
| prix | numeric(12,2) | NOT NULL CHECK >= 0 |
| devise | text | NOT NULL DEFAULT `'XOF'` |
| actif | boolean | NOT NULL DEFAULT true |
| created_at / updated_at / deleted_at | — | standard |

Unique partiel `(commercant_id, libelle)` où `deleted_at is null`.

### `public.paniers`
- `id uuid` PK, `etablissement_id uuid` NOT NULL FK→`etablissements`, `profile_id uuid` FK→`profiles`, `commercant_id uuid` NOT NULL FK→`commercants`, `statut`, timestamps.
- Contrainte métier : **un panier = un seul commerçant** (mono-vendeur).

### `public.lignes_paniers`
- `id uuid` PK, `panier_id uuid` NOT NULL FK→`paniers` CASCADE, `catalogue_produit_id uuid` NOT NULL FK→`catalogues_produits`, `quantite int` NOT NULL CHECK > 0, `prix_unitaire numeric(12,2)` (snapshot).
- Trigger `lignes_paniers_verifie_commercant` : le produit doit appartenir au commerçant du panier.

### `public.commandes`
- `id uuid` PK, `etablissement_id`, `profile_id`, `commercant_id`, `statut statut_commande`, `total numeric(12,2)`, `devise`, timestamps.
- Trigger `commandes_verifie_panier` : cohérence panier → commande.

### `public.lignes_commandes`
- `id uuid` PK, `commande_id uuid` NOT NULL FK→`commandes` CASCADE, `catalogue_produit_id`, `libelle_snapshot text`, `quantite int`, `prix_unitaire numeric(12,2)`, `total_ligne numeric(12,2)`.
- Trigger `lignes_commandes_verifie_commercant`.

### `public.paiements`
- `id uuid` PK, `commande_id uuid` NOT NULL FK→`commandes`, `fournisseur type_fournisseur_paiement` NOT NULL, `statut statut_paiement`, `montant numeric(12,2)`, `reference_fournisseur text`, `sous_compte_etablissement text`, timestamps.
- Trigger `paiements_verifie_fournisseur` : le sous-compte doit correspondre au fournisseur choisi.

## 3. RPC client

- `detecter_anomalies_commandes(p_etablissement uuid)` — `security definer`, grant `authenticated, service_role`. Détecte les incohérences commandes/paiements (montants, statuts) ; signaux IA à valider.

Les autres fonctions (`lignes_paniers_verifie_commercant`, `commandes_verifie_panier`, `lignes_commandes_verifie_commercant`, `paiements_verifie_fournisseur`) sont des **triggers**, pas des RPC client.

## 4. RLS

| Table | Commande | Règle |
|---|---|---|
| commercants | SELECT | public (actif, non supprimé) |
| commercants | ALL | back-office / service_role |
| catalogues_produits | SELECT | public (actif, non supprimé) |
| catalogues_produits | ALL | back-office |
| paniers | SELECT | `profile_id = auth.uid()` |
| paniers | ALL | `profile_id = auth.uid()` |
| lignes_paniers | SELECT/ALL | propriétaire du panier |
| commandes | SELECT | `profile_id = auth.uid()` |
| commandes | ALL | `profile_id = auth.uid()` |
| lignes_commandes | SELECT | propriétaire de la commande |
| paiements | SELECT | propriétaire de la commande |
| paiements | INSERT/UPDATE | via Edge Function paiement (service_role) |

## 5. Conventions transverses

- **Mono-vendeur** : un panier appartient à un unique `commercant_id` ; le client doit empêcher d'ajouter des produits de commerçants différents.
- Flux panier → commande : création de `commandes` + snapshot des lignes dans `lignes_commandes`.
- Paiement **agnostique** : aucune colonne spécifique fournisseur ; les adaptateurs (CinetPay, Mobile Money) sont des Edge Functions.
- Soft-delete : filtrer `deleted_at is null`.
- Sous-comptes marchands par établissement pour isoler les encaissements.
