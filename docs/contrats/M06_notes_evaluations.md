# M06 — Notes & Évaluations — Contrat d'interface Flutter

> Migration : `supabase/migrations/20260906000600_m6_notes_evaluations.sql`.
> Source de vérité : SQL + tests RLS associés.
> Périmètre : évaluations, notes (saisie hors-ligne), appréciations, bulletins signés, statistiques/signaux IA pré-calculés.

## 1. Enums

| Enum | Valeurs |
|---|---|
| `public.type_evaluation` | `devoir`, `interrogation`, `controle`, `examen_blanc`, `composition`, `tp`, `autre` |
| `public.statut_evaluation` | `brouillon`, `publiee`, `cloturee` |
| `public.type_bulletin` | `trimestriel`, `semestriel`, `annuel` |
| `public.statut_bulletin` | `brouillon`, `publie`, `archive` |
| `public.type_appreciation` | `generale`, `matiere`, `conseil` |
| `public.ton_appreciation` | `positif`, `neutre`, `negatif` |
| `public.type_agregat` | `moyenne_matiere`, `moyenne_classe`, `moyenne_generale`, `rang_eleve`, `risque_reussite`, `anomalie_note`, `recommandation_contenu` |

## 2. Tables (DTOs)

Toutes portent `etablissement_id` (tenant) + `deleted_at` (soft-delete) + `created_at`/`updated_at` (sauf `bulletins` qui n'a pas `updated_at`, et `statistiques_agregats` qui n'a ni l'un ni l'autre).

### `public.evaluations`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| annee_scolaire_id | uuid | NOT NULL, FK → `annees_scolaires(id)` CASCADE |
| periode_id | uuid | FK → `periodes_scolaires(id)` SET NULL |
| classe_id | uuid | NOT NULL, FK → `classes(id)` CASCADE |
| programme_matiere_id | uuid | FK → `programmes_matieres(id)` SET NULL |
| enseignant_profile_id | uuid | NOT NULL, FK → `profiles(id)` CASCADE |
| type | type_evaluation | NOT NULL DEFAULT `'controle'` |
| libelle | text | NOT NULL |
| date_evaluation | date | NOT NULL DEFAULT current_date |
| coefficient | numeric(5,2) | NOT NULL DEFAULT 1 CHECK > 0 |
| bareme | numeric(5,2) | NOT NULL DEFAULT 20 CHECK > 0 |
| statut | statut_evaluation | NOT NULL DEFAULT `'brouillon'` |
| publie_le | timestamptz | nullable |
| cloture_le | timestamptz | nullable |

### `public.notes`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| evaluation_id | uuid | NOT NULL, FK → `evaluations(id)` CASCADE |
| fiche_eleve_id | uuid | NOT NULL, FK → `fiches_eleves(id)` CASCADE |
| valeur | numeric(5,2) | CHECK >= 0, nullable si absent |
| absent | boolean | NOT NULL DEFAULT false |
| commentaire | text | nullable |
| saisi_par | uuid | NOT NULL, FK → `profiles(id)` RESTRICT |
| saisi_hors_ligne | boolean | NOT NULL DEFAULT false |
| device_id | text | nullable (LWW) |
| client_ts | timestamptz | nullable (LWW) |

Unique `(evaluation_id, fiche_eleve_id)` ; CHECK `(absent AND valeur IS NULL) OR (NOT absent AND valeur IS NOT NULL)`.

### `public.appreciations`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| fiche_eleve_id | uuid | NOT NULL, FK → `fiches_eleves(id)` CASCADE |
| annee_scolaire_id | uuid | NOT NULL, FK → `annees_scolaires(id)` CASCADE |
| periode_id | uuid | FK → `periodes_scolaires(id)` SET NULL |
| programme_matiere_id | uuid | FK → `programmes_matieres(id)` SET NULL |
| type | type_appreciation | NOT NULL DEFAULT `'generale'` |
| texte | text | NOT NULL |
| ton | ton_appreciation | nullable |
| points_forts | text[] | nullable |
| points_faibles | text[] | nullable |
| redige_par | uuid | NOT NULL, FK → `profiles(id)` RESTRICT |

### `public.bulletins`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| annee_scolaire_id | uuid | NOT NULL, FK → `annees_scolaires(id)` CASCADE |
| periode_id | uuid | FK → `periodes_scolaires(id)` SET NULL |
| classe_id | uuid | NOT NULL, FK → `classes(id)` CASCADE |
| fiche_eleve_id | uuid | NOT NULL, FK → `fiches_eleves(id)` CASCADE |
| type | type_bulletin | NOT NULL DEFAULT `'trimestriel'` |
| statut | statut_bulletin | NOT NULL DEFAULT `'brouillon'` |
| contenu | jsonb | NOT NULL DEFAULT `'{}'` |
| signature_sha256 | text | nullable (intégrité) |
| genere_le / publie_le | timestamptz | nullable |
| created_at | timestamptz | NOT NULL DEFAULT now() |
| deleted_at | timestamptz | nullable |

Unique partiel `(fiche_eleve_id, periode_id, type)` si `periode_id` non nul, sinon `(fiche_eleve_id, type)`.

### `public.statistiques_agregats`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| annee_scolaire_id | uuid | NOT NULL, FK → `annees_scolaires(id)` CASCADE |
| periode_id | uuid | FK → `periodes_scolaires(id)` SET NULL |
| classe_id | uuid | FK → `classes(id)` CASCADE |
| programme_matiere_id | uuid | FK → `programmes_matieres(id)` CASCADE |
| fiche_eleve_id | uuid | FK → `fiches_eleves(id)` CASCADE |
| type_agregat | type_agregat | NOT NULL |
| valeur_numeric | numeric(10,4) | nullable |
| valeur_texte | text | nullable |
| valeur_jsonb | jsonb | nullable |
| calcule_le | timestamptz | NOT NULL DEFAULT now() |
| version | int | NOT NULL DEFAULT 1 |

Lecture seule côté client (aucune policy d'écriture).

## 3. RPC client

### RPC de calcul (lecture)
- `calculer_moyenne_eleve(p_fiche uuid, p_matiere uuid DEFAULT null, p_periode uuid DEFAULT null) returns numeric` — moyenne pondérée ramenée sur 20 (notes non-brouillon, non-absentes).
- `calculer_moyenne_classe(p_classe uuid, p_matiere uuid DEFAULT null, p_periode uuid DEFAULT null) returns numeric` — moyenne des moyennes élèves.

### Helpers de visibilité/droits (security definer, utilisables en prédicat client)
- `est_enseignant_affecte(p_classe uuid) returns boolean`
- `peut_gerer_evaluation(p_eval uuid) returns boolean` — permission `scolarite.evaluation.gerer` ou auteur.
- `peut_saisir_notes(p_eval uuid) returns boolean` — permission `scolarite.note.gerer` ou auteur, et évaluation non clôturée.
- `evaluation_visible(p_eval uuid) returns boolean` — personnel, ou élève/parent si `publiee`/`cloturee`.
- `note_visible(p_note uuid) returns boolean` — personnel, ou élève/parent si publiée/clôturée.
- `appreciation_visible(p_app uuid) returns boolean` — personnel ou fiche visible.
- `bulletin_visible(p_bul uuid) returns boolean` — personnel ou `statut='publie'` + fiche visible.

## 4. RLS

| Table | Commande | Règle |
|---|---|---|
| evaluations | SELECT | `evaluation_visible(id)` |
| evaluations | INSERT | permission `scolarite.evaluation.gerer` OU (auteur + `est_enseignant_affecte(classe_id)`) |
| evaluations | UPDATE/DELETE | `peut_gerer_evaluation(id)` |
| notes | SELECT | `note_visible(id)` |
| notes | INSERT/UPDATE/DELETE | `peut_saisir_notes(evaluation_id)` |
| appreciations | SELECT | `appreciation_visible(id)` |
| appreciations | ALL | permission `scolarite.appreciation.gerer` OU `redige_par = auth.uid()` |
| bulletins | SELECT | `bulletin_visible(id)` |
| bulletins | ALL | permission `scolarite.bulletin.gerer` |
| statistiques_agregats | SELECT | `est_personnel(etablissement_id)` OU `fiche_visible(fiche_eleve_id)` |

## 5. Conventions transverses

- Garde-fous triggers (`23514`) : `evaluations_verifie_tenant`, `notes_verifie_tenant` (`EVALUATION_INTROUVABLE`, `EVALUATION_AUTRE_ETABLISSEMENT`, `NOTE_SUP_BAREME`, `ELEVE_NON_INSCRIT`), `appreciations_verifie_tenant`, `bulletins_verifie_tenant`, `statistiques_verifie_tenant`.
- Hors-ligne : les notes portent `saisi_hors_ligne`, `device_id`, `client_ts` (LWW) ; les moyennes ne sont JAMAIS calculées hors-ligne — toujours via les RPC `calculer_moyenne_*`.
- Permissions seedées : `scolarite.evaluation.gerer`, `scolarite.note.gerer`, `scolarite.appreciation.gerer`, `scolarite.bulletin.gerer`.
- Soft-delete : filtrer `deleted_at is null`.
