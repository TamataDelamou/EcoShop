# M15 — Marketplace sans authentification — Contrat d'interface Flutter

> Migration : `supabase/migrations/20260906001500_m15_marketplace_sans_auth.sql`.
> Source de vérité : SQL + tests RLS associés.
> Périmètre : parcours invité (consultation + achat sans mot de passe), profil public minimal, écritures invitées **exclusivement** via Edge Function (service_role).

## 1. Enums

Aucun.

## 2. Tables (DTOs)

### `public.profils_publics`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| token_acces | uuid | NOT NULL DEFAULT gen_random_uuid(), **UNIQUE** (jeton invité opaque) |
| nom | text | nullable |
| email | text | nullable |
| telephone | text | nullable |
| role_voulu | text | NOT NULL DEFAULT `'visiteur_marketplace'` |
| etablissement_id | uuid | FK → `etablissements(id)` SET NULL |
| complet | boolean | NOT NULL DEFAULT false (calculé par trigger) |
| profile_id | uuid | FK → `profiles(id)` SET NULL (lien vers compte natif) |
| created_at / updated_at | timestamptz | NOT NULL DEFAULT now() |

Index unique partiel `idx_profils_publics_email` sur `(email)` où `email is not null`.

### Trigger
- `profils_publics_calcule_complet()` : `complet` = `nom` renseigné ET (`email` OU `telephone`) renseigné.

## 3. RPC client

Aucune RPC client exposée. Les écritures invitées passent par l'**Edge Function `creer_profil_marketplace`** (service_role, RLS contournée). Les paniers/commandes invités utilisent `visiteur_id` (pas `profile_id`).

## 4. RLS

| Table | Commande | Règle |
|---|---|---|
| profils_publics | SELECT | `profils_publics_select_admin` : back-office/service_role |
| profils_publics | SELECT | `profils_publics_select_owner` : `profile_id = auth.uid()` (compte natif lié) |
| profils_publics | (écriture) | **aucune policy** — pas d'écriture anon/authenticated directe |

## 5. Conventions transverses

- **Aucun chemin d'écriture RLS** : tout write invité (création profil, panier, commande) est proxé par Edge Function `service_role`.
- Le client invité porte `token_acces` (uuid) comme identifiant de session invité ; il n'est PAS un secret fort (c'est un jeton opaque de corrélation).
- Lien compte : quand l'invité s'authentifie, `profile_id` est renseigné (`creer_profil_marketplace` / `lier`) et le profil public est rattaché au compte natif.
- Permissions seedées : `marketplace.profil_public.lire`, `marketplace.profil_public.lier`.
- Hors-ligne invité : panier/commande portent `visiteur_id` + `device_id` + `client_ts` + `saisi_hors_ligne` (tables M13).
