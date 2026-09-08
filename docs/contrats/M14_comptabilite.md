# M14 — Comptabilité sans OHADA — Contrat d'interface Flutter

> Migration : `supabase/migrations/20260906001400_m14_comptabilite_sans_ohada.sql`.
> Source de vérité : SQL + tests RLS associés.
> Périmètre : partie double (débit = crédit), plan comptable **ouvert** (pas de plan OHADA imposé), documents (Journal, Grand Livre, Balance, Livre banque/caisse), supervision IA, saisie hors-ligne.

## 1. Enums

Aucun (`create type ... as enum` absent). `type` en `text` libre : valeurs conventionnelles `'autre'` (défaut), `'banque'`, `'caisse'`, `'charge'`, `'produit'`. Journal par défaut `'operations'`.

## 2. Tables (DTOs)

### `public.plans_comptables` (plan de comptes, arbre)
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| code | text | NOT NULL |
| intitule | text | NOT NULL |
| type | text | NOT NULL DEFAULT `'autre'` |
| parent_id | uuid | FK → `plans_comptables(id)` SET NULL |
| actif | boolean | NOT NULL DEFAULT true |
| created_at / updated_at | timestamptz | NOT NULL DEFAULT now() |
| deleted_at | timestamptz | soft-delete |

Unique `(etablissement_id, code)` ; trigger `plans_comptables_verifie_parent` (le parent doit appartenir au même établissement).

### `public.journaux`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| code | text | NOT NULL |
| libelle | text | NOT NULL |
| type | text | NOT NULL DEFAULT `'operations'` |
| created_at / updated_at / deleted_at | — | standard |

Unique `(etablissement_id, code)`.

### `public.ecritures_comptables`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| journal_id | uuid | NOT NULL, FK → `journaux(id)` RESTRICT |
| date_ecriture | date | NOT NULL DEFAULT current_date |
| compte_debit_id | uuid | NOT NULL, FK → `plans_comptables(id)` RESTRICT |
| compte_credit_id | uuid | NOT NULL, FK → `plans_comptables(id)` RESTRICT |
| montant | numeric(14,2) | NOT NULL CHECK > 0 |
| libelle | text | NOT NULL |
| piece_justificative | text | nullable |
| numero_lot | text | nullable (regroupement d'une saisie multi-lignes côté appelant) |
| user_id | uuid | FK → `profiles(id)` SET NULL |
| saisi_hors_ligne | boolean | NOT NULL DEFAULT false |
| device_id | text | nullable (LWW) |
| client_ts | timestamptz | nullable (LWW) |
| created_at / updated_at / deleted_at | — | standard |

Trigger `ecritures_verifie_tenant` : débit/crédit/journal doivent appartenir au même établissement ; débit ≠ crédit.

**Aucun verrou/cloture** : le DDL ne porte ni colonne de verrouillage (`verrouille`,
`cloture_le`…) ni trigger interdisant l'UPDATE/DELETE d'une écriture déjà
saisie — seule la RLS `est_comptable_ecriture` borne qui peut écrire. Le
client Flutter n'expose donc, par choix délibéré, aucune action de
modification/suppression d'écriture postée (voir `docs/ETAT_PHASE_C.md`
pour le risque résiduel).

### `public.balances`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| compte_id | uuid | NOT NULL, FK → `plans_comptables(id)` CASCADE |
| date_balance | date | NOT NULL DEFAULT current_date |
| solde_debit | numeric(14,2) | NOT NULL DEFAULT 0 |
| solde_credit | numeric(14,2) | NOT NULL DEFAULT 0 |
| created_at | timestamptz | NOT NULL DEFAULT now() |

Unique `(compte_id, date_balance)`. Pas de `deleted_at` (recalculée par
`generer_balance`, upsert sur ce couple, jamais soft-supprimée).

## 3. RPC client (security definer, `grant authenticated, service_role`)

### Helpers
- `est_comptable(p_etablissement uuid) returns boolean` — direction OU permission comptabilité.
- `est_comptable_ecriture(p_etablissement uuid) returns boolean` — droit d'écriture.

### Documents comptables
- `journal_comptable(p_etab uuid, p_journal uuid, p_debut date, p_fin date)` — lignes du journal sur la période.
- `grand_livre(p_etab uuid, p_compte uuid, p_debut date, p_fin date)` — mouvements d'un compte.
- `balance_comptable(p_etablissement uuid, p_date date)` — balance à une date.
- `generer_balance(p_etablissement uuid, p_date date)` — recalcule et stocke `balances`.
- `exporter_journal_json(p_etab uuid, p_journal uuid, p_debut date, p_fin date) returns jsonb` — export.

### IA (signaux, validation humaine)
- `detecter_anomalies_comptables(p_etablissement uuid)` — anomalies (déséquilibres, doublons).
- `predire_tresorerie(p_etablissement uuid, p_jours int DEFAULT 30)` — projection de trésorerie.
- `recommander_ecritures(p_etablissement uuid)` — écritures de régularisation proposées.
- `analyser_tendances(p_etablissement uuid, p_mois int DEFAULT 12)` — tendances charges/produits.

## 4. RLS

| Table | Commande | Règle |
|---|---|---|
| plans_comptables | SELECT | `est_comptable(etablissement_id)` |
| plans_comptables | ALL | `est_comptable_ecriture(etablissement_id)` |
| journaux | SELECT | `est_comptable(etablissement_id)` |
| journaux | ALL | `est_comptable_ecriture(etablissement_id)` |
| ecritures_comptables | SELECT | `est_comptable(etablissement_id)` |
| ecritures_comptables | ALL | `est_comptable_ecriture(etablissement_id)` |
| balances | SELECT | `est_comptable(etablissement_id)` |

## 5. Conventions transverses

- **Partie double** : une écriture porte un unique `montant`, partagé par son débit et son crédit (égalité débit/crédit garantie par construction du schéma, pas par un calcul de somme) ; `montant > 0` est un `CHECK`, `compte_debit_id ≠ compte_credit_id` et le même établissement pour comptes/journal sont vérifiés par le trigger `ecritures_verifie_tenant`.
- Plan comptable **ouvert** : pas de plan OHADA imposé ; l'établissement construit son propre arbre.
- Hors-ligne (LWW) : `saisi_hors_ligne`, `device_id`, `client_ts` sur `ecritures_comptables` uniquement.
- Soft-delete : filtrer `deleted_at is null` (sauf `balances`, recalculée).
- Les RPC de documents filtrent déjà `deleted_at is null` en interne.
- Deux FK de `ecritures_comptables` pointent vers `plans_comptables`
  (`compte_debit_id`/`compte_credit_id`) : un embed PostgREST direct serait
  ambigu. Le client Flutter ne les embarque pas et résout les libellés depuis
  le plan comptable déjà chargé côté application.

## 6. Client Flutter (`apps/client_flutter/lib/features/comptabilite/`)

Livré : plan comptable et journaux (configuration en ligne uniquement, comme
les salles en M11) ; saisie d'écriture tolérante hors-ligne via `sync_queue`
(entité `ecritures_comptables`) ; journal comptable, grand livre et balance
(RPC, agrégats non cachés) ; les quatre signaux IA de supervision
(anomalies, prévision de trésorerie, écritures récurrentes, tendances),
chacun badgé « signal IA — validation humaine requise », jamais une écriture
générée automatiquement. Accès réservé au rôle Direction côté client
(gating ergonomique ; `est_comptable`/`est_comptable_ecriture` restent
l'unique frontière de sécurité réelle, côté RLS).

**Aucune action d'édition/suppression d'écriture postée** n'est exposée
côté client — choix délibéré compensant l'absence de verrou de période côté
serveur (§2, `ecritures_comptables`) : voir `docs/ETAT_PHASE_C.md` pour le
risque résiduel documenté.
- IA : anomalies/recommandations = propositions à valider, jamais d'écritures automatiques.
