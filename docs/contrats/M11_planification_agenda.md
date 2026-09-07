# M11 — Planification & Agenda — Contrat d'interface Flutter

> Migration : `supabase/migrations/20260906001100_m11_planification_agenda.sql`.
> Source de vérité : SQL + tests RLS associés.
> Périmètre : salles, emplois du temps, événements d'agenda, progression pédagogique, contraintes de planification + IA (placement, conflits, charge, rattrapage).

## 1. Enums

Aucun (`create type ... as enum` absent). Vocabulaires en `CHECK` :
- `emplois_du_temps.type` : `cours`, `td`, `tp`, `examen`, `soutien` (vérifier les valeurs exactes dans la migration).
- `evenements_agenda.type`, `progression_pedagogique.statut`, `contraintes_emploi.type` : listes `CHECK` inline.

## 2. Tables (DTOs)

Toutes portent `etablissement_id` + `created_at`/`updated_at` + `deleted_at` (soft-delete).

### `public.salles`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| code | text | NOT NULL |
| nom | text | NOT NULL DEFAULT `''` |
| capacite | int | CHECK > 0 |
| actif | boolean | NOT NULL DEFAULT true |

Unique `(etablissement_id, code)`.

### `public.emplois_du_temps`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| annee_scolaire_id | uuid | NOT NULL, FK → `annees_scolaires(id)` CASCADE |
| classe_id | uuid | NOT NULL, FK → `classes(id)` CASCADE |
| salle_id | uuid | FK → `salles(id)` SET NULL |
| enseignant_profile_id | uuid | FK → `profiles(id)` SET NULL |
| programme_matiere_id | uuid | FK → `programmes_matieres(id)` SET NULL |
| jour_semaine | int | NOT NULL (1..7) |
| heure_debut | time | NOT NULL |
| heure_fin | time | NOT NULL CHECK > heure_debut |
| type | text | NOT NULL (CHECK) |
| modifie_le | timestamptz | NOT NULL DEFAULT now() (LWW) |
| device_id | text | nullable (LWW) |

### `public.evenements_agenda`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| annee_scolaire_id | uuid | NOT NULL, FK → `annees_scolaires(id)` CASCADE |
| classe_id | uuid | FK → `classes(id)` CASCADE |
| type | text | NOT NULL (CHECK) |
| libelle | text | NOT NULL |
| date_debut / date_fin | timestamptz | NOT NULL |
| lieu | text | nullable |
| modifie_le / device_id | — | LWW |

### `public.progression_pedagogique`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| annee_scolaire_id | uuid | NOT NULL, FK → `annees_scolaires(id)` CASCADE |
| classe_id | uuid | FK → `classes(id)` CASCADE |
| programme_matiere_id | uuid | FK → `programmes_matieres(id)` CASCADE |
| statut | text | NOT NULL (CHECK) |
| avancement | int | CHECK 0..100 |
| modifie_le / device_id | — | LWW |

### `public.contraintes_emploi`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| type | text | NOT NULL (CHECK) |
| libelle | text | NOT NULL |
| enseignant_profile_id | uuid | FK → `profiles(id)` SET NULL |
| salle_id | uuid | FK → `salles(id)` SET NULL |
| details | jsonb | NOT NULL DEFAULT `'{}'` |

## 3. RPC client (security definer, `grant authenticated`)

- `suggerer_placement_seance(p_etab uuid, p_annee uuid, ...)` — placement CSP glouton d'une séance (salle libre, enseignant dispo, contraintes).
- `detecter_conflits_emploi(p_etab uuid, p_annee uuid) returns table(...)` — séances en chevauchement (même classe, même salle, même enseignant).
- `charger_travail_enseignant(p_etab uuid, p_annee uuid, p_enseignant uuid) returns jsonb` — `{heures_hebdo, nb_seances, volume_contractuel_hebdo, surcharge}`.
- `charger_travail_eleve(p_classe uuid) returns jsonb` — heures hebdo de la classe, seuil 35 h.
- `recommander_seances(p_etab uuid, p_annee uuid) returns table(...)` — séances de rattrapage proposées.

## 4. RLS

| Table | Commande | Règle |
|---|---|---|
| salles | SELECT | `planification.consulter` OU membre |
| salles | ALL | `planification.generer` |
| emplois_du_temps | SELECT | `planification.consulter` OU membre |
| emplois_du_temps | ALL | `planification.generer` |
| evenements_agenda | SELECT | membre |
| evenements_agenda | ALL | `planification.generer` |
| progression_pedagogique | SELECT | membre OU `planification.consulter` |
| progression_pedagogique | ALL | `planification.generer` |
| contraintes_emploi | SELECT | membre |
| contraintes_emploi | ALL | `planification.administrer` |

## 5. Conventions transverses

- Garde-fous triggers (`23514`) : `salles_verifie_tenant`, `emplois_verifie_tenant` (`EMPLOI_CLASSE_AUTRE_ETABLISSEMENT`, `EMPLOI_SALLE_AUTRE_ETABLISSEMENT`, `EMPLOI_ENSEIGNANT_NON_MEMBRE`, `EMPLOI_CLASSE_AUTRE_ANNEE`), `evenements_agenda_verifie_tenant`, etc.
- Hors-ligne (LWW) : `modifie_le` + `device_id` sur `emplois_du_temps`, `evenements_agenda`, `progression_pedagogique` (pas sur `salles`/`contraintes_emploi`).
- Permissions seedées : `planification.consulter`, `planification.generer`, `planification.administrer`.
- Soft-delete : filtrer `deleted_at is null`.
- IA : les propositions de placement/rattrapage sont des suggestions à valider par un humain.
