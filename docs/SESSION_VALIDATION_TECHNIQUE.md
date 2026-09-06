# Session de validation technique — Socle M0 → M7

> Check-list opérationnelle, étape par étape, pour valider l'ensemble du socle
> backend (migrations, RLS, seeds, helpers, fonctions IA) dès que Docker est
> disponible. À exécuter **avant la clôture du sprint M7** (ou à l'ouverture de
> M8 si Docker arrive plus tôt).

## 1. Prérequis

| Outil | Vérification | Attendu |
|---|---|---|
| Docker Desktop | `docker --version` puis `docker info` | ≥ 24.x, démon actif (backend WSL2 sur Windows) |
| Supabase CLI | `supabase --version` | ≥ 2.x (2.116.0 installé sur ce poste) |
| pgTAP / pg_prove | `pg_prove --version` | installé (sinon `cpan TAP::Parser::SourceHandler::pgTAP` ou paquet système) |
| psql | `psql --version` | ≥ 15 (fourni par l'image Postgres locale) |
| Node | `node --version` | ≥ 20 |
| Flutter | `flutter --version` | ≥ 3.44 |

**Point bloquant actuel** : Docker Desktop absent sur ce poste → installer
Docker Desktop (activer WSL2), démarrer, puis poursuivre.

## 2. Démarrage de la stack

```bash
supabase start            # Postgres + Auth + Storage + Edge Functions
supabase status           # vérifier API URL, DB URL, anon/service keys
docker ps                 # 6+ conteneurs actifs
```

Premier lancement : téléchargement des images (~2-5 min). En cas d'échec de
port (54322/54321 occupés) : `supabase stop` puis libérer les ports.

## 3. Migrations (ordre exact)

```bash
supabase db reset
```

Applique dans l'ordre lexicographique du dossier `supabase/migrations/` :

1. `20260904000000_core_schema.sql` — M0 (profiles, etablissements, RLS cœur)
2. `20260906000100_fix_core_security.sql` — correctifs C1-C4 (escalade, récursion RLS, hook JWT, handle_new_user)
3. `20260906000200_m1_schema_avance.sql` — M1 (multi-tenant, permissions, années)
4. `20260906000300_m2_auth_federation.sql` — M2 (identifiants, invitations, liaison)
5. `20260906000400_m4_referentiel_pedagogique.sql` — M4 (référentiel CEDEAO/ISCED)
6. `20260906000500_m5_administration_scolarite.sql` — M5 (structures, inscriptions, sélecteur d'enfant)
7. `20260906000600_m6_notes_evaluations.sql` — M6 (évaluations, notes, bulletins)
8. `20260906000700_m7_absences_vie_scolaire.sql` — M7 (présences, sanctions, alertes, IA)

> M3 (OTP/coquille) est côté client Flutter — aucune migration.

`supabase db reset` exécute aussi automatiquement `supabase/seed.sql` (M0).

## 4. Seeds complémentaires (ordre exact)

Les seeds M4→M7 sont des fichiers séparés **non exécutés automatiquement**.
Les appliquer dans l'ordre via psql :

```bash
DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
psql "$DB" -f supabase/seed_referentiel_pedagogique.sql      # M4
psql "$DB" -f supabase/seed_administration_scolarite.sql    # M5
psql "$DB" -f supabase/seed_notes_evaluations.sql           # M6
psql "$DB" -f supabase/seed_vie_scolaire.sql                # M7
```

**Action recommandée** : consolider ces quatre fichiers dans `supabase/seed.sql`
(ou un script `supabase/seed_all.sql` avec `\i`) pour un reset en une commande.

## 5. Tests pgTAP (01 → 15)

```bash
pg_prove -d "$DB" tests/rls/*.sql
```

Attendu : 15 fichiers, ~68 assertions, **zéro échec**. Couverture :

- 01-03 : anti-élévation, récursion RLS, hook JWT
- 04-06 : anti-brute-force, isolation multi-tenant, invitations
- 07-09 : M5 (isolation structures, lien parent, affectations)
- 10-12 : M6 (visibilité notes, saisie, évaluations + moyenne)
- 13-15 : M7 (visibilité vie scolaire, pointage, fonctions IA)

## 6. Vérification ciblée (helpers, fonctions, permissions)

```sql
-- Permissions introduites par M6/M7
select code from public.permissions where code like 'scolarite.%';

-- Fonctions IA M7 (substituer les UUID du seed)
select public.calculer_score_decrochage('<fiche_aicha>', '<annee_2026-2027>');
select public.analyse_comportement('<fiche_aicha>', '<annee_2026-2027>');
select public.recommander_sanction_educative('<fiche_aicha>', '<annee_2026-2027>');
select public.predire_presence('<etab_lycee>', current_date);
select public.generer_alertes_decrochage('<etab_lycee>', '<annee_2026-2027>', 0.4); -- service_role

-- Moyennes M6
select public.calculer_moyenne_eleve('<fiche_ibrahima>', null, null);

-- Isolation multi-tenant (doit retourner 0)
set role authenticated;
select set_config('request.jwt.claims', '{"sub":"<uuid_etranger>","role":"authenticated"}', true);
select count(*) from public.notes;      -- 0 pour un compte sans fiche
select count(*) from public.presences;  -- 0 pour un compte sans fiche
reset role;
```

## 7. Correctifs rapides (procédure)

| Situation | Action |
|---|---|
| Échec d'une migration | Corriger le fichier de migration fautif, puis `supabase db reset` (les migrations sont immuables une fois appliquées ; en dev on reset) |
| Échec d'un test pgTAP | Identifier le test, corriger la fonction/policy ou le test, puis `psql "$DB" -f tests/rls/<fichier>.sql` (ré-exécution partielle) |
| Rollback complet | `supabase db reset` (repart de zéro, migrations + seed.sql) |
| État incohérent des seeds | `supabase db reset` puis ré-exécuter §4 |

## 8. Rapport de validation (template)

```markdown
# Rapport de validation technique — [date]
## Statut global : GO / NO-GO
## Environnement
- Docker : [version] | Supabase CLI : [version] | pg_prove : [version]
## Migrations
- [liste] appliquées : OK / KO
## Seeds
- M0 (auto) / M4 / M5 / M6 / M7 : OK / KO
## Tests pgTAP
- 01→15 : [X]/68 assertions, [n] échecs
- Échecs : [liste fichier → assertion → cause]
## Vérifications ciblées
- Fonctions IA M7 : OK / KO
- Moyennes M6 : OK / KO
- Isolation multi-tenant : OK / KO
## Anomalies & actions correctives
- [anomalie] → [correctif appliqué]
## Décision
- [GO si zéro échec ; sinon NO-GO + liste des correctifs avant nouvelle passe]
```

## 9. Vérification client Flutter (complément)

```bash
cd apps/client_flutter
flutter analyze
flutter test
```

## 10. Critères de sortie

- [ ] `supabase db reset` sans erreur
- [ ] 4 seeds M4→M7 appliqués sans erreur
- [ ] `pg_prove` 15/15 fichiers verts, 0 échec
- [ ] Vérifications ciblées §6 toutes conformes
- [ ] Rapport de validation renseigné et archivé
