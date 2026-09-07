# M07 — Absences & Vie scolaire — Contrat d'interface Flutter

> Migration : `supabase/migrations/20260906000700_m7_absences_vie_scolaire.sql`.
> Source de vérité : SQL + tests RLS associés.
> Périmètre : présences/absences, retards, sanctions éducatives, alertes décrochage, événements scolaires.

## 1. Enums

| Enum | Valeurs |
|---|---|
| `public.statut_presence` | `present`, `absent`, `retard`, `exclu`, `dispense` |
| `public.type_seance` | `demi_journee`, `cours` |
| `public.type_sanction` | `avertissement`, `blame`, `retenue`, `travail_interet`, `exclusion_temporaire`, `conseil_discipline`, `entretien_famille_et_tutorat` |
| `public.statut_sanction` | `proposee`, `notifiee`, `executee`, `annulee` |
| `public.origine_sanction` | `humaine`, `ia` |
| `public.statut_alerte` | `ouverte`, `transmise`, `traitee`, `ignoree` |
| `public.type_evenement` | `ferie`, `vacances`, `greve`, `meteo`, `manifestation`, `examen`, `sortie` |

## 2. Tables (DTOs)

Toutes portent `etablissement_id` + `deleted_at` (soft-delete) + `created_at`/`updated_at`.

### `public.presences`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| fiche_eleve_id | uuid | NOT NULL, FK → `fiches_eleves(id)` CASCADE |
| date_presence | date | NOT NULL DEFAULT current_date |
| type_seance | type_seance | NOT NULL DEFAULT `'demi_journee'` |
| seance_id | uuid | FK → `seances_agenda(id)` SET NULL |
| statut | statut_presence | NOT NULL DEFAULT `'present'` |
| justifie | boolean | NOT NULL DEFAULT false |
| motif | text | nullable |
| constate_par | uuid | FK → `profiles(id)` RESTRICT |
| saisi_hors_ligne | boolean | NOT NULL DEFAULT false |
| device_id | text | nullable (LWW) |
| client_ts | timestamptz | nullable (LWW) |

Unique `(fiche_eleve_id, date_presence, type_seance, seance_id)`.

### `public.retards`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| fiche_eleve_id | uuid | NOT NULL, FK → `fiches_eleves(id)` CASCADE |
| date_retard | date | NOT NULL DEFAULT current_date |
| minutes_retard | int | NOT NULL CHECK > 0 |
| justifie | boolean | NOT NULL DEFAULT false |
| motif | text | nullable |
| constate_par | uuid | FK → `profiles(id)` RESTRICT |
| saisi_hors_ligne | boolean | NOT NULL DEFAULT false |
| device_id | text | nullable |
| client_ts | timestamptz | nullable |

### `public.sanctions`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| fiche_eleve_id | uuid | NOT NULL, FK → `fiches_eleves(id)` CASCADE |
| type | type_sanction | NOT NULL |
| motif | text | NOT NULL |
| origine | origine_sanction | NOT NULL DEFAULT `'humaine'` |
| statut | statut_sanction | NOT NULL DEFAULT `'proposee'` |
| proposee_par | uuid | FK → `profiles(id)` RESTRICT |
| validee_par | uuid | FK → `profiles(id)` SET NULL |
| date_proposee | date | NOT NULL DEFAULT current_date |
| date_decision | date | nullable |

### `public.alertes_decrochage`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| fiche_eleve_id | uuid | NOT NULL, FK → `fiches_eleves(id)` CASCADE |
| score | numeric(4,3) | NOT NULL CHECK 0..1 |
| facteurs | jsonb | NOT NULL DEFAULT `'{}'` |
| statut | statut_alerte | NOT NULL DEFAULT `'ouverte'` |
| recommandation | text | nullable |
| generee_le | timestamptz | NOT NULL DEFAULT now() |
| traitee_par | uuid | FK → `profiles(id)` SET NULL |
| traitee_le | timestamptz | nullable |

### `public.evenements_scolaires`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| etablissement_id | uuid | NOT NULL, FK → `etablissements(id)` CASCADE |
| type | type_evenement | NOT NULL |
| libelle | text | NOT NULL |
| date_debut | date | NOT NULL |
| date_fin | date | NOT NULL CHECK >= date_debut |
| lieu | text | nullable |
| affecte_presence | boolean | NOT NULL DEFAULT false |

## 3. RPC client

### Prédicats de visibilité (security definer)
- `peut_pointer(p_classe uuid) returns boolean` — membre enseignant affecté à la classe.
- `presence_visible(p_id uuid)`, `retard_visible(p_id uuid)`, `sanction_visible(p_id uuid)`, `alerte_visible(p_id uuid)` — retournent `boolean` (personnel ou fiche visible).
- `concerne_etablissement(p_etab uuid) returns boolean` — membre actif de l'établissement.

### Fonctions IA (signaux, non bloquants)
- `analyse_comportement(p_fiche uuid, p_annee uuid)` — niveau descriptif (absences, retards, sanctions agrégées).
- `calculer_score_decrochage(p_fiche uuid, p_annee uuid) returns numeric` — score 0..1 croisant M6 × M7.
- `recommander_sanction_educative(p_fiche uuid, p_annee uuid)` — niveau prescriptif, validation humaine obligatoire.
- `predire_presence(p_etab uuid, p_date date)` — prédiction de présence (événements, météo, historique).
- `generer_alertes_decrochage(...)` — **`service_role` uniquement**, jamais appelée depuis le client.

## 4. RLS

| Table | Commande | Règle |
|---|---|---|
| presences | SELECT | `presence_visible(id)` |
| presences | INSERT | `peut_pointer(classe_id)` |
| presences | UPDATE | `peut_pointer(classe_id)` |
| presences | DELETE | `peut_pointer(classe_id)` |
| retards | SELECT | `retard_visible(id)` |
| retards | ALL (écriture) | permission `scolarite.presence.gerer` |
| sanctions | SELECT | `sanction_visible(id)` |
| sanctions | ALL (écriture) | permission `scolarite.sanction.gerer` |
| alertes_decrochage | SELECT | `alerte_visible(id)` |
| alertes_decrochage | (aucune) | pas d'écriture client |
| evenements_scolaires | SELECT | `concerne_etablissement(etablissement_id)` |
| evenements_scolaires | ALL (écriture) | permission `scolarite.evenement.gerer` |

## 5. Conventions transverses

- Garde-fous triggers (`23514`) : `presences_verifie_tenant`, `retards_verifie_tenant`, `sanctions_verifie_tenant`, `sanctions_verifie_validation`, `alertes_verifie_tenant`, `evenements_verifie_tenant`.
- Éthique IA : `origine='ia'` et alertes décrochage exigent validation humaine — afficher « proposition IA, à valider ».
- Hors-ligne : `device_id` + `client_ts` (LWW) sur `presences`/`retards`.
- Permissions seedées : `scolarite.presence.gerer`, `scolarite.sanction.gerer`, `scolarite.evenement.gerer`.
- Soft-delete : filtrer `deleted_at is null`.
