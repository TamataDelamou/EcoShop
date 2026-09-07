# M05 — Administration & Scolarité — Contrat d'interface Flutter

> Migration : `supabase/migrations/20260906000500_m5_administration_scolarite.sql`.
> Source de vérité : SQL + tests RLS associés.
> Périmètre : périodes scolaires, classes, inscriptions, relations parent↔élève, affectations enseignants, enrichissement des fiches élèves.

## 1. Enums

| Enum | Valeurs |
|---|---|
| `public.type_periode` | `trimestre`, `semestre`, `terme` |
| `public.statut_inscription` | `active`, `retiree`, `redoublante`, `en_attente` |
| `public.type_relation_parentale` | `tuteur_legal`, `parent`, `autre` |
| `public.statut_relation` | `en_attente`, `confirmee`, `refusee` |
| `public.role_affectation` | `titulaire`, `enseignant`, `suppleant` |

## 2. Tables (DTOs)

Toutes les tables portent `etablissement_id` (tenant) + `created_at`/`updated_at` + `deleted_at` (soft-delete), sauf mention contraire.

### `public.periodes_scolaires`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| annee_scolaire_id | uuid | NOT NULL, FK → `annees_scolaires(id)` CASCADE |
| code | text | NOT NULL |
| libelle | text | NOT NULL |
| type | type_periode | NOT NULL DEFAULT `'trimestre'` |
| ordre | int | NOT NULL CHECK > 0 |
| date_debut | date | NOT NULL |
| date_fin | date | NOT NULL |
| created_at / updated_at | timestamptz | NOT NULL DEFAULT now() |
| deleted_at | timestamptz | nullable |

Unique `(annee_scolaire_id, code)`, `(annee_scolaire_id, ordre)` ; CHECK `date_fin > date_debut`.

### `public.classes`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| annee_scolaire_id | uuid | NOT NULL, FK → `annees_scolaires(id)` CASCADE |
| unite_id | uuid | FK → `unites_operationnelles(id)` SET NULL |
| niveau_id | uuid | FK → `niveaux_educatifs(id)` SET NULL |
| code | text | NOT NULL |
| nom | text | NOT NULL |
| capacite | int | CHECK > 0 |
| enseignant_principal_id | uuid | FK → `profiles(id)` SET NULL |
| actif | boolean | NOT NULL DEFAULT true |
| created_at / updated_at | timestamptz | NOT NULL DEFAULT now() |
| deleted_at | timestamptz | nullable |

Unique `(annee_scolaire_id, code)`.

### `public.inscriptions`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| fiche_eleve_id | uuid | NOT NULL, FK → `fiches_eleves(id)` CASCADE |
| classe_id | uuid | NOT NULL, FK → `classes(id)` CASCADE |
| annee_scolaire_id | uuid | NOT NULL, FK → `annees_scolaires(id)` CASCADE |
| statut | statut_inscription | NOT NULL DEFAULT `'active'` |
| date_inscription | date | NOT NULL DEFAULT current_date |
| date_retrait | date | nullable |
| motif_retrait | text | nullable |
| created_at / updated_at | timestamptz | NOT NULL DEFAULT now() |
| deleted_at | timestamptz | nullable |

Unique `(fiche_eleve_id, annee_scolaire_id)` — une fiche = une inscription par année.

### `public.relations_parent_eleve`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| parent_profile_id | uuid | NOT NULL, FK → `profiles(id)` CASCADE |
| fiche_eleve_id | uuid | NOT NULL, FK → `fiches_eleves(id)` CASCADE |
| type_relation | type_relation_parentale | NOT NULL DEFAULT `'parent'` |
| statut | statut_relation | NOT NULL DEFAULT `'confirmee'` |
| autorise | boolean | NOT NULL DEFAULT true |
| created_at | timestamptz | NOT NULL DEFAULT now() |
| deleted_at | timestamptz | nullable |

Unique `(parent_profile_id, fiche_eleve_id)`.

### `public.affectations_enseignants`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| annee_scolaire_id | uuid | NOT NULL, FK → `annees_scolaires(id)` CASCADE |
| enseignant_profile_id | uuid | NOT NULL, FK → `profiles(id)` CASCADE |
| classe_id | uuid | NOT NULL, FK → `classes(id)` CASCADE |
| programme_matiere_id | uuid | FK → `programmes_matieres(id)` SET NULL |
| role_affectation | role_affectation | NOT NULL DEFAULT `'enseignant'` |
| volume_horaire_hebdo | int | CHECK > 0 |
| created_at / updated_at | timestamptz | NOT NULL DEFAULT now() |
| deleted_at | timestamptz | nullable |

Unique `(annee_scolaire_id, enseignant_profile_id, classe_id, programme_matiere_id)`.

### `public.fiches_eleves` (enrichissement M5)
Colonnes ajoutées : `sexe text CHECK ('M','F')`, `lieu_naissance text`, `nationalite text`, `statut text NOT NULL DEFAULT 'actif' CHECK ('actif','retire')`, `est_supervise boolean NOT NULL DEFAULT false`.

## 3. RPC client

### `public.lier_parent_a_fiche`
- Signature : `lier_parent_a_fiche(p_matricule text, p_date_naissance date, p_type type_relation_parentale DEFAULT 'parent') returns uuid`
- Langage / sécurité : plpgsql, SECURITY DEFINER, `set search_path = public`
- Rôle : crée/confirme la liaison parent↔fiche (double facteur matricule + date de naissance, anti-brute-force 5 échecs/heure via `tentatives_liaison`). Retourne l'`id` de la relation.
- Appelable par le client : **oui** (`grant to authenticated`), réservé au rôle `parent` (`ROLE_PARENT_REQUIS`).
- Erreurs : `AUTH_REQUISE` (28000), `ROLE_PARENT_REQUIS` (42501), `TROP_DE_TENTATIVES` (54000), `LIAISON_IMPOSSIBLE` (42501).

### Helpers de visibilité (utilisables en prédicat client, security definer)
- `est_personnel(p_etablissement uuid) returns boolean` — membre actif non élève/parent.
- `est_parent_confirme(p_fiche uuid) returns boolean` — parent confirmé+autorisé.
- `fiche_visible(p_fiche uuid) returns boolean` — personnel, élève lié ou parent confirmé.
- `classe_visible(p_classe uuid) returns boolean` — personnel, ou élève/parent d'un inscrit.

## 4. RLS

| Table | Commande | Règle |
|---|---|---|
| periodes_scolaires | SELECT | `deleted_at is null` et `est_personnel(etablissement_id)` |
| periodes_scolaires | ALL (écriture) | permission `scolarite.periode.gerer` |
| classes | SELECT | `classe_visible(id)` |
| classes | ALL | permission `scolarite.classe.gerer` |
| inscriptions | SELECT | `fiche_visible(fiche_eleve_id)` |
| inscriptions | ALL | permission `scolarite.inscription.gerer` |
| relations_parent_eleve | SELECT | `parent_profile_id = auth.uid()` et `deleted_at is null` |
| relations_parent_eleve | ALL | permission `scolarite.relation.gerer` |
| affectations_enseignants | SELECT | `deleted_at is null` et (`est_personnel(etablissement_id)` ou `enseignant_profile_id = auth.uid()`) |
| affectations_enseignants | ALL | permission `rh.enseignant.affecter` |
| fiches_eleves | SELECT | remplace `fiches_select_propre` par `fiches_select_visible` = `fiche_visible(id)` |

## 5. Conventions transverses

- Garde-fous multi-tenant (triggers BEFORE INSERT/UPDATE, errcode `23514`) : `periodes_verifie_tenant`, `classes_verifie_tenant`, `inscriptions_verifie_tenant`, `relations_verifie_tenant`, `affectations_verifie_tenant` (messages `ANNEE_AUTRE_ETABLISSEMENT`, `UNITE_AUTRE_ETABLISSEMENT`, `FICHE_AUTRE_ETABLISSEMENT`, `CLASSE_AUTRE_ETABLISSEMENT`, `ENSEIGNANT_NON_MEMBRE`).
- Soft-delete : toujours filtrer `deleted_at is null` côté client.
- Permissions seedées : `scolarite.classe.gerer`, `scolarite.inscription.gerer`, `scolarite.periode.gerer`, `scolarite.relation.gerer`, `rh.enseignant.affecter`.
- Un parent lié ne devient jamais membre de l'établissement ; sa visibilité passe par `est_parent_confirme`/`fiche_visible`.
