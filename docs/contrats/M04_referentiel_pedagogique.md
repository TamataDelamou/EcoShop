# M04 — Référentiel pédagogique CEDEAO — Contrat d'interface Flutter

> Migration : `supabase/migrations/20260906000400_m4_referentiel_pedagogique.sql`.
> Source de vérité : SQL + tests RLS associés.
> Objectif : documenter DTOs, RPC et règles RLS pour le développement des écrans Flutter du module.
> Nature du module : référentiel **en lecture seule pour le client** (aucune RPC, aucune policy d'écriture — l'écriture passe par le back-office/service_role).

## 1. Enums

| Enum | Valeurs |
|---|---|
| `public.type_systeme_educatif` | `francophone_cfa`, `anglophone_waec`, `lusophone`, `arabophone_mixte` |
| `public.statut_referentiel` | `brouillon`, `publie`, `archive` |

Note : `pays_pedagogiques.statut_deploiement` est un `text` avec `CHECK ('brouillon','deploye')` (pas un enum SQL).

## 2. Tables (DTOs)

### `public.systemes_educatifs`
| Colonne | Type | Contraintes |
|---|---|---|
| code | text | PK |
| nom | text | NOT NULL |
| description | text | nullable |

### `public.pays_pedagogiques`
| Colonne | Type | Contraintes |
|---|---|---|
| code_iso | text | PK (ISO 3166-1 alpha-2) |
| nom | text | NOT NULL |
| type_systeme | text | NOT NULL, FK → `systemes_educatifs(code)` |
| langue_enseignement_principale | text | NOT NULL |
| organisme_examinateur | text | nullable |
| devise_code | text | NOT NULL, DEFAULT `'XOF'` |
| statut_deploiement | text | NOT NULL, DEFAULT `'brouillon'`, CHECK `brouillon|deploye` |
| created_at | timestamptz | NOT NULL DEFAULT now() |
| updated_at | timestamptz | NOT NULL DEFAULT now() |

### `public.cycles_educatifs`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| pays_code | text | NOT NULL, FK → `pays_pedagogiques(code_iso)` ON DELETE CASCADE |
| code | text | NOT NULL |
| nom | text | NOT NULL |
| ordre | int | NOT NULL |
| age_min | int | nullable |
| age_max | int | nullable |
| duree_annees | int | nullable |
| isced_min | int | NOT NULL, CHECK 0..8 |
| isced_max | int | NOT NULL, CHECK 0..8 |
| statut | statut_referentiel | NOT NULL DEFAULT `'brouillon'` |

Unique : `(pays_code, code)`.

### `public.niveaux_educatifs`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| cycle_id | uuid | NOT NULL, FK → `cycles_educatifs(id)` CASCADE |
| pays_code | text | NOT NULL, FK → `pays_pedagogiques(code_iso)` CASCADE |
| code | text | NOT NULL |
| nom | text | NOT NULL |
| grade_level_normalise | int | NOT NULL, CHECK > 0 (clé inter-pays, jamais affichée) |
| isced | int | NOT NULL, CHECK 0..8 |
| ordre | int | NOT NULL |
| statut | statut_referentiel | NOT NULL DEFAULT `'brouillon'` |

Unique : `(pays_code, code)` et `(pays_code, grade_level_normalise)`.

### `public.examens_nationaux`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| pays_code | text | NOT NULL, FK → `pays_pedagogiques(code_iso)` CASCADE |
| cycle_id | uuid | FK → `cycles_educatifs(id)` ON DELETE SET NULL |
| code | text | NOT NULL |
| nom | text | NOT NULL |
| organisme | text | nullable |
| mois_session | int | CHECK 1..12 |
| periodicite | text | nullable |
| statut | statut_referentiel | NOT NULL DEFAULT `'brouillon'` |

Unique : `(pays_code, code)`.

### `public.filieres_educatives`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| pays_code | text | NOT NULL, FK → `pays_pedagogiques(code_iso)` CASCADE |
| niveau_id | uuid | FK → `niveaux_educatifs(id)` CASCADE |
| code | text | NOT NULL |
| nom | text | NOT NULL |
| description | text | nullable |
| statut | statut_referentiel | NOT NULL DEFAULT `'brouillon'` |

Unique : `(pays_code, code)`.

### `public.programmes_officiels`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| pays_code | text | NOT NULL, FK → `pays_pedagogiques(code_iso)` CASCADE |
| niveau_id | uuid | NOT NULL, FK → `niveaux_educatifs(id)` CASCADE |
| filiere_id | uuid | FK → `filieres_educatives(id)` ON DELETE SET NULL |
| code | text | NOT NULL |
| nom | text | NOT NULL |
| annee_scolaire | text | nullable (ex. `'2026-2027'`) |
| version | int | NOT NULL DEFAULT 1 |
| statut | statut_referentiel | NOT NULL DEFAULT `'brouillon'` |

Unique : `(pays_code, code, version)`.

### `public.programmes_matieres`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| programme_id | uuid | NOT NULL, FK → `programmes_officiels(id)` CASCADE |
| code | text | NOT NULL |
| nom | text | NOT NULL |
| coefficient | int | CHECK > 0 |
| volume_horaire_annuel | int | nullable |
| ordre | int | NOT NULL DEFAULT 0 |
| statut | statut_referentiel | NOT NULL DEFAULT `'brouillon'` |

Unique : `(programme_id, code)`.

### `public.paquets_referentiel`
| Colonne | Type | Contraintes |
|---|---|---|
| id | uuid | PK DEFAULT gen_random_uuid() |
| pays_code | text | NOT NULL, FK → `pays_pedagogiques(code_iso)` CASCADE |
| niveau_id | uuid | FK → `niveaux_educatifs(id)` CASCADE |
| version | int | NOT NULL |
| empreinte_sha256 | text | NOT NULL |
| taille_octets | bigint | NOT NULL |
| url | text | nullable |
| publie_le | timestamptz | nullable |

Unique : `(pays_code, niveau_id, version)`.

## 3. RPC client

Aucune RPC définie dans cette migration.

## 4. RLS

| Table | Commande | Règle |
|---|---|---|
| systemes_educatifs | SELECT | `true` — lisible par tous (y compris anon) |
| pays_pedagogiques | SELECT | `statut_deploiement = 'deploye'` |
| cycles_educatifs | SELECT | `statut = 'publie'` |
| niveaux_educatifs | SELECT | `statut = 'publie'` |
| examens_nationaux | SELECT | `statut = 'publie'` |
| filieres_educatives | SELECT | `statut = 'publie'` |
| programmes_officiels | SELECT | `statut = 'publie'` |
| programmes_matieres | SELECT | `statut = 'publie'` |
| paquets_referentiel | SELECT | `publie_le IS NOT NULL` |

Aucune policy INSERT/UPDATE/DELETE : écriture `service_role` uniquement.

## 5. Conventions transverses

- Pas de soft-delete sur ces tables (aucune colonne `deleted_at`).
- Hors-ligne : téléchargement par `paquets_referentiel` (versionné, empreinte SHA-256) — le client vérifie l'empreinte avant mise en cache locale.
- `grade_level_normalise` ne doit jamais être affiché à l'utilisateur (seule l'appellation locale `nom` l'est).
- La continuité de `grade_level_normalise` (aucun trou par pays) est garantie par le back-office, pas par le schéma.
- Index utiles côté requêtes : `idx_niveaux_pays_grade(pays_code, grade_level_normalise)`, `idx_matieres_programme(programme_id)`, `idx_programmes_niveau(niveau_id)`.
