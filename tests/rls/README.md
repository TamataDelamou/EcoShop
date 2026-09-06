# Tests RLS — Phase A (pgTAP)

Suite de tests **pgTAP** couvrant les **6 points RLS prioritaires** identifiés
dans `docs/ETAT_PHASE_A.md`. Ces scripts sont autonomes (chaque fichier crée ses
propres données puis annule tout par `ROLLBACK`) et prêts à être exécutés dès que
l'outillage Postgres/Supabase sera disponible.

## Couverture

| Fichier | Point contrôlé | Correspondance |
|---|---|---|
| `01_anti_elevation.sql` | Escalade de privilège impossible via `UPDATE` direct ; rôle fixé uniquement par `choisir_role_racine()`, restreint aux rôles auto-inscriptibles | C1 |
| `02_recursion_rls.sql` | Lecture des tables multi-tenant sans récursion RLS (`42P17`) | C2 |
| `03_hook_jwt.sql` | `custom_access_token_hook()` émet réellement `app_metadata.role_racine` et `app_metadata.gsg_id` | C3 |
| `04_anti_brute_force.sql` | `lier_compte_a_fiche()` verrouille après 5 échecs/heure, même avec de bons identifiants | C4 / ch. 5.8 |
| `05_isolation_multi_tenant.sql` | Un membre ne voit que les données de ses propres établissements | multi-tenant |
| `06_invitations.sql` | Une invitation nominative n'est acceptée que par son destinataire | ch. 5.2 |
| `07_m5_isolation_structures.sql` | Isolation multi-tenant des structures M5 (périodes, classes, inscriptions, fiches) | M5 |
| `08_m5_lien_parent.sql` | Liaison parent ↔ élève : double facteur, rôle requis, visibilité limitée à l'enfant | M5 |
| `09_m5_affectations.sql` | Visibilité des affectations (enseignant, direction, élève exclu) | M5 |

## Prérequis

1. **Migrations appliquées** : `20260904000000_core_schema.sql`,
   `20260906000100_fix_core_security.sql`, `20260906000200_m1_schema_avance.sql`,
   `20260906000300_m2_auth_federation.sql` (dans cet ordre).
2. **Extension pgTAP installée** : `create extension if not exists pgtap;`
   (`supabase test db` l'installe automatiquement).
3. **Rôle d'exécution superutilisateur** (`postgres`) : les tests simulent les
   appels clients via `SET LOCAL ROLE authenticated` + `request.jwt.claims`,
   ce qui exige de pouvoir changer de rôle.

## Exécution

### Option A — `pg_prove` (Postgres accessible)

```bash
# PG* : variables de connexion vers la base du projet
export PGHOST=localhost PGPORT=54322 PGDATABASE=postgres PGUSER=postgres
pg_prove tests/rls/*.sql
```

### Option B — `supabase test db` (CLI Supabase + Docker)

Copier les fichiers sous `supabase/tests/rls/`, puis :

```bash
supabase test db --linked
```

### Option C — fichier par fichier (psql)

```bash
psql -v ON_ERROR_STOP=1 -f tests/rls/01_anti_elevation.sql
```

## Conventions des scripts

- Chaque script s'exécute dans une transaction (`BEGIN` / `ROLLBACK`) : aucune
  donnée résiduelle après passage.
- Le helper `pg_temp.creer_compte(phone, role)` crée un compte `auth.users` ;
  le trigger `handle_new_user` génère le profil associé. C'est le point unique
  d'adaptation si le schéma `auth.users` local diffère.
- La simulation d'un utilisateur connecté se fait par :
  `SET LOCAL ROLE authenticated;` puis
  `SELECT set_config('request.jwt.claims', json_build_object('sub', <uuid>, 'role', 'authenticated')::text, true);`
- Un script qui échoue ne doit jamais laisser un état modifié : tout est
  remis à zéro par le `ROLLBACK` final.
