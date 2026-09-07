# M08 — RH & Personnel — Contrat d'interface Flutter

> Migration : `supabase/migrations/20260906000800_m8_rh_personnel.sql`.
> Source de vérité : SQL + tests RLS associés.
> Périmètre : dossiers employés, contrats, congés, absences personnel, paie légère, IA RH (descriptive/prédictive/prescriptive).

## 1. Enums

| Enum | Valeurs |
|---|---|
| `public.type_contrat` | `cdi`, `cdd`, `vacataire`, `stage`, `prestataire` |
| `public.statut_employe` | `actif`, `en_conge`, `suspendu`, `demissionnaire`, `retraite` |
| `public.type_conge` | `annuel`, `maladie`, `maternite`, `exceptionnel`, `sans_solde` |
| `public.statut_conge` | `demande`, `valide`, `refuse` |
| `public.statut_paie` | `brouillon`, `valide`, `paye` |
| `public.type_absence_personnel` | `maladie`, `injustifiee`, `autorisee`, `autre` |

Note : `employes.categorie` est un `text` + `CHECK ('enseignant','administratif','direction','personnel')` (pas un enum).

## 2. Tables (DTOs)

Toutes portent `etablissement_id` + `deleted_at` (soft-delete).

### `public.employes`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| profile_id | uuid | NOT NULL, FK → `profiles(id)` CASCADE |
| matricule | text | NOT NULL |
| categorie | text | NOT NULL DEFAULT `'personnel'`, CHECK enseignant/administratif/direction/personnel |
| date_embauche | date | NOT NULL DEFAULT current_date |
| statut | statut_employe | NOT NULL DEFAULT `'actif'` |
| created_at / updated_at | timestamptz | NOT NULL DEFAULT now() |
| deleted_at | timestamptz | nullable |

Unique `(etablissement_id, matricule)` et `(etablissement_id, profile_id)`.

### `public.contrats`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| employe_id | uuid | NOT NULL, FK → `employes(id)` CASCADE |
| type | type_contrat | NOT NULL DEFAULT `'cdd'` |
| date_debut | date | NOT NULL DEFAULT current_date |
| date_fin | date | nullable (null = CDI) |
| salaire_base | numeric(12,2) | NOT NULL CHECK >= 0 |
| renouvellement_auto | boolean | NOT NULL DEFAULT false |
| actif | boolean | NOT NULL DEFAULT true |

Unique `(employe_id, date_debut, type)` ; CHECK `date_fin >= date_debut`.

### `public.conges`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| employe_id | uuid | NOT NULL, FK → `employes(id)` CASCADE |
| type | type_conge | NOT NULL DEFAULT `'annuel'` |
| date_debut | date | NOT NULL |
| date_fin | date | NOT NULL |
| nb_jours | int | NOT NULL CHECK > 0 |
| statut | statut_conge | NOT NULL DEFAULT `'demande'` |
| motif | text | nullable |
| valide_par | uuid | FK → `profiles(id)` SET NULL |
| date_validation | timestamptz | nullable |

Unique `(employe_id, date_debut, type)`.

### `public.absences_personnel`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| employe_id | uuid | NOT NULL, FK → `employes(id)` CASCADE |
| date_absence | date | NOT NULL DEFAULT current_date |
| type | type_absence_personnel | NOT NULL DEFAULT `'injustifiee'` |
| justifie | boolean | NOT NULL DEFAULT false |
| motif | text | nullable |

Unique `(employe_id, date_absence)`.

### `public.paie_bulletins`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| employe_id | uuid | NOT NULL, FK → `employes(id)` CASCADE |
| contrat_id | uuid | NOT NULL, FK → `contrats(id)` RESTRICT |
| periode_debut / periode_fin | date | NOT NULL, CHECK fin >= debut |
| salaire_base | numeric(12,2) | NOT NULL CHECK >= 0 |
| primes | numeric(12,2) | NOT NULL DEFAULT 0 CHECK >= 0 |
| retenues | numeric(12,2) | NOT NULL DEFAULT 0 CHECK >= 0 |
| net | numeric(12,2) | NOT NULL CHECK >= 0 (recalculé serveur) |
| statut | statut_paie | NOT NULL DEFAULT `'brouillon'` |

Unique `(employe_id, periode_debut)`.

## 3. RPC client

### Helpers de visibilité (security definer, prédicats)
- `est_rh(p_etablissement uuid) returns boolean` — direction OU permission `rh.employe.gerer`.
- `est_employe_self(p_employe uuid) returns boolean` — l'appelant est l'employé (`profile_id = auth.uid()`).
- `employe_visible(p_employe uuid) returns boolean` — RH ou soi-même.
- `contrat_visible(p_contrat uuid) returns boolean` — RH ou l'employé concerné.
- `conge_visible(p_conge uuid) returns boolean` — RH ou l'employé concerné.
- `charge_horaire(p_employe uuid) returns int` — somme des `volume_horaire_hebdo` (M5), hors soft-delete.

### Fonctions IA (appel RH ou l'employé concerné, jamais automatisées)
- `analyser_effectifs(p_etablissement uuid) returns table(categorie text, effectif bigint, anciennete_moyenne_jours numeric, masse_salariale_base numeric)` — niveau descriptif. Gate `RH_REQUIS`.
- `calculer_score_turnover(p_employe uuid) returns numeric` — score 0..1 (absences ×2, ancienneté, charge, contrat). Gate `RH_REQUIS` sauf si c'est soi-même. Erreur `EMPLOYE_INTROUVABLE` (P0002).
- `recommander_formation(p_employe uuid, p_annee uuid) returns table(programme_matiere_id uuid, code text, libelle text, raison text)` — matières du référentiel (M4) non couvertes.
- `optimiser_remplacements(p_etablissement uuid, p_date date) returns table(employe_absent_id uuid, absent_matricule text, remplacant_id uuid, remplacant_matricule text)` — remplaçant actif le moins chargé.

## 4. RLS

| Table | Commande | Règle |
|---|---|---|
| employes | SELECT | `employe_visible(id)` |
| employes | ALL | `est_rh(etablissement_id)` |
| contrats | SELECT | `contrat_visible(id)` |
| contrats | ALL | `est_rh(etablissement_id)` |
| conges | SELECT | `conge_visible(id)` |
| conges | INSERT | `est_employe_self(employe_id)` OU `est_rh(etablissement_id)` |
| conges | UPDATE | `est_rh(etablissement_id)` (validation) |
| conges | DELETE | `est_rh(etablissement_id)` OU (soi-même ET `statut='demande'`) |
| absences_personnel | SELECT | `est_rh(etablissement_id)` OU `est_employe_self(employe_id)` |
| absences_personnel | ALL | `est_rh(etablissement_id)` |
| paie_bulletins | SELECT | `est_rh(etablissement_id)` OU `est_employe_self(employe_id)` |
| paie_bulletins | ALL | `est_rh(etablissement_id)` |

## 5. Conventions transverses

- Garde-fous triggers : `employes_verifie_tenant` (`EMPLOYE_NON_MEMBRE` 23514), `contrats/conges/absences/paie_verifie_tenant` (`EMPLOYE_AUTRE_ETABLISSEMENT`, `CONTRAT_AUTRE_ETABLISSEMENT`, `CONTRAT_AUTRE_EMPLOYE`).
- Validation humaine des congés : le trigger `conges_verifie_validation` exige `est_rh` pour passer à `valide`/`refuse` (`VALIDATION_RH_REQUISE` 42501) et renseigne `valide_par`/`date_validation`.
- Paie : `net` toujours recalculé serveur (`paie_calcule_net`, `NET_NEGATIF` 23514 si < 0) — le client affiche `net` sans jamais le calculer.
- Permissions seedées : `rh.employe.voir`, `rh.employe.gerer`, `rh.contrat.gerer`, `rh.conge.valider`, `rh.paie.gerer`.
- IA : signaux non bloquants ; le client affiche « proposition IA, à valider ».
- Soft-delete : filtrer `deleted_at is null`.
