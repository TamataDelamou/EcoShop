# M10 — Rapports & Statistiques — Contrat d'interface Flutter

> Migration : `supabase/migrations/20260906001000_m10_rapports_statistiques.sql`.
> Source de vérité : SQL + tests RLS associés.
> Périmètre : consolidation M6×M7×M8×M9 — indicateurs, exports différés, détection d'anomalies, recommandations, résumé exécutif NLG.

## 1. Enums

| Enum | Valeurs |
|---|---|
| `public.type_export` | `pdf`, `excel`, `csv`, `json` |
| `public.statut_rapport` | `demande`, `en_attente`, `genere`, `echec`, `expire` |
| `public.statut_anomalie` | `ouverte`, `confirmee`, `rejetee`, `traitee` |
| `public.statut_recommandation` | `proposee`, `validee`, `mise_en_oeuvre`, `rejetee` |

## 2. Tables (DTOs)

### `public.indicateurs_cles`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| annee_scolaire_id | uuid | NOT NULL, FK → `annees_scolaires(id)` CASCADE |
| periode_id | uuid | FK → `periodes_scolaires(id)` SET NULL |
| classe_id | uuid | FK → `classes(id)` CASCADE |
| code | text | NOT NULL (`effectifs`, `taux_reussite`, `absentisme`, `turnover`, `masse_salariale`, `engagement_parents`, …) |
| valeur_numeric | numeric(12,4) | nullable |
| valeur_texte | text | nullable |
| calcule_le | timestamptz | NOT NULL DEFAULT now() |
| version | int | NOT NULL DEFAULT 1 |

Unique `(etablissement_id, annee_scolaire_id, code)` (partiel selon `periode_id`/`classe_id`).

### `public.rapports`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| annee_scolaire_id | uuid | NOT NULL, FK → `annees_scolaires(id)` CASCADE |
| periode_id | uuid | FK → `periodes_scolaires(id)` SET NULL |
| classe_id | uuid | FK → `classes(id)` CASCADE |
| fiche_eleve_id | uuid | FK → `fiches_eleves(id)` CASCADE |
| format | type_export | NOT NULL DEFAULT `'pdf'` |
| statut | statut_rapport | NOT NULL DEFAULT `'demande'` |
| url_fichier | text | nullable |
| erreur | text | nullable |
| demande_par | uuid | FK → `profiles(id)` RESTRICT |
| demande_le | timestamptz | NOT NULL DEFAULT now() |
| genere_le | timestamptz | nullable |
| expire_le | timestamptz | nullable |
| demande_hors_ligne | boolean | NOT NULL DEFAULT false |
| cache_valide_jus | timestamptz | nullable |

### `public.anomalies_statistiques`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| annee_scolaire_id | uuid | NOT NULL, FK → `annees_scolaires(id)` CASCADE |
| periode_id / classe_id / fiche_eleve_id | uuid | FKs → périodes/classes/fiches (CASCADE) |
| type | text | NOT NULL CHECK `note|absence|retard|paie|autre` |
| severite | text | NOT NULL CHECK `faible|moyenne|elevee` |
| description | text | NOT NULL |
| valeur_observee | numeric(12,4) | nullable |
| valeur_attendue | numeric(12,4) | nullable |
| ecart | numeric(12,4) | nullable |
| contexte | jsonb | NOT NULL DEFAULT `'{}'` |
| signature | text | NOT NULL (déduplication) |
| statut | statut_anomalie | NOT NULL DEFAULT `'ouverte'` |
| detectee_le | timestamptz | NOT NULL DEFAULT now() |
| traitee_par | uuid | FK → `profiles(id)` SET NULL |
| traitee_le | timestamptz | nullable |

Unique `(etablissement_id, signature)`.

### `public.recommandations_strategiques`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| annee_scolaire_id | uuid | NOT NULL, FK → `annees_scolaires(id)` CASCADE |
| classe_id | uuid | FK → `classes(id)` CASCADE |
| type | text | NOT NULL CHECK `renforcement|tutorat|effectifs|autre` |
| titre | text | NOT NULL |
| description | text | NOT NULL |
| justification | jsonb | NOT NULL DEFAULT `'{}'` (traçabilité) |
| priorite | text | NOT NULL CHECK `basse|moyenne|haute` |
| statut | statut_recommandation | NOT NULL DEFAULT `'proposee'` |
| cree_le | timestamptz | NOT NULL DEFAULT now() |

## 3. RPC client (security definer, `grant authenticated`)

- `consolider_indicateurs_etablissement(p_etab uuid, p_annee uuid) returns void` — recalcule les 6 indicateurs (`effectifs`, `taux_reussite`, `absentisme`, `turnover`, `masse_salariale`, `engagement_parents`) et upsert `indicateurs_cles`.
- `detecter_anomalies(p_etab uuid, p_annee uuid) returns void` — détecte les anomalies (notes incohérentes, absences, paie…) et remplit `anomalies_statistiques`.
- `risque_classe(p_classe uuid) returns jsonb` — `{"score_risque": numeric, ...}` croisant moyennes + assiduité.
- `recommander_actions(p_etab uuid, p_annee uuid) returns bigint` — génère les recommandations (tutorat/renforcement) pour les classes à risque ; retourne le nombre créé.
- `generer_resume_executif(p_etab uuid, p_annee uuid) returns text` — résumé en langage naturel (NLG structurée, traçable).

## 4. RLS

| Table | Commande | Règle |
|---|---|---|
| indicateurs_cles | SELECT | `rapports.consulter` OU `est_direction(etablissement_id)` |
| rapports | SELECT | `rapports.consulter` OU `fiche_eleve_id` visible (parents/élèves) |
| rapports | INSERT | `rapports.generer` |
| rapports | UPDATE/DELETE | `rapports.generer` |
| anomalies_statistiques | SELECT | `rapports.consulter` |
| anomalies_statistiques | INSERT | `rapports.generer` (via RPC) |
| anomalies_statistiques | UPDATE/DELETE | `rapports.administrer` |
| recommandations_strategiques | SELECT | `rapports.consulter` |
| recommandations_strategiques | INSERT | `rapports.generer` (via RPC) |
| recommandations_strategiques | UPDATE/DELETE | `rapports.administrer` |

## 5. Conventions transverses

- Permissions seedées : `rapports.consulter`, `rapports.generer`, `rapports.administrer`.
- Génération différée : le client crée un `rapports` en `demande`, un worker le passe à `genere`/`echec` ; le client interroge `statut` + `url_fichier`.
- Hors-ligne : `rapports.demande_hors_ligne` + `cache_valide_jus` (cache client) ; les exports ne sont pas calculés localement.
- Soft-delete : filtrer `deleted_at is null` (sur les tables qui en portent une).
- IA : recommandations/anomalies = aides à la décision ; validation humaine requise pour `validee`/`confirmee`.
