# Session de validation technique — Socle M0 → M15

> Check-list opérationnelle, étape par étape, pour valider l'ensemble du socle
> backend (migrations, RLS, seeds, helpers, fonctions IA) dès que Docker est
> disponible. À exécuter **à l'issue de M15** (ou dès que Docker est disponible).

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
9. `20260906000800_m8_rh_personnel.sql` — M8 (employés, contrats, congés, paie légère, IA RH)
10. `20260906000900_m9_communication_notifications.sql` — M9 (notifications, préférences canaux, logs, IA comm)
11. `20260906001000_m10_rapports_statistiques.sql` — M10 (rapports, KPI, anomalies, recommandations, NLG)
12. `20260906001100_m11_planification_agenda.sql` — M11 (emplois du temps, agenda, progression, contraintes, IA planification)
13. `20260906001200_m12_observabilite.sql` — M12 (observabilité, monitoring, prédiction de charge, permissions)
14. `20260906001400_m14_comptabilite_sans_ohada.sql` — M14 (plans comptables, journaux, écritures, balances, IA comptable)
15. `20260906001500_m15_marketplace_sans_auth.sql` — M15 (profils publics invités, panier/commande invité, RLS)

> M3 (OTP/coquille) est côté client Flutter — aucune migration.

`supabase db reset` exécute aussi automatiquement `supabase/seed.sql` (M0).

## 4. Seeds complémentaires (ordre exact)

Les seeds M4→M14 sont des fichiers séparés **non exécutés automatiquement**.
Les appliquer dans l'ordre via psql :

```bash
DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
psql "$DB" -f supabase/seed_referentiel_pedagogique.sql      # M4
psql "$DB" -f supabase/seed_administration_scolarite.sql    # M5
psql "$DB" -f supabase/seed_notes_evaluations.sql           # M6
psql "$DB" -f supabase/seed_vie_scolaire.sql                # M7
psql "$DB" -f supabase/seed_rh_personnel.sql                # M8
psql "$DB" -f supabase/seed_communication_notifications.sql # M9
psql "$DB" -f supabase/seed_rapports_statistiques.sql      # M10
psql "$DB" -f supabase/seed_planification_agenda.sql     # M11
psql "$DB" -f supabase/seed_marketplace_assoshop.sql   # M13
psql "$DB" -f supabase/seed_comptabilite.sql           # M14
```

**Action recommandée** : consolider ces dix fichiers dans `supabase/seed.sql`
(ou un script `supabase/seed_all.sql` avec `\i`) pour un reset en une commande.

## 5. Tests pgTAP (01 → 36)

```bash
pg_prove -d "$DB" tests/rls/*.sql
```

Attendu : 36 fichiers, ~151 assertions, **zéro échec**. Couverture :

- 01-03 : anti-élévation, récursion RLS, hook JWT
- 04-06 : anti-brute-force, isolation multi-tenant, invitations
- 07-09 : M5 (isolation structures, lien parent, affectations)
- 10-12 : M6 (visibilité notes, saisie, évaluations + moyenne)
- 13-15 : M7 (visibilité vie scolaire, pointage, fonctions IA)
- 16-18 : M8 (visibilité RH, congés & validation humaine, fonctions IA RH)
- 19-21 : M9 (visibilité notifications, lecture/écriture, fonctions IA comm)
- 22-24 : M10 (visibilité rapports, fonctions IA, validation anomalies/recommandations)
- 25-27 : M11 (visibilité agenda, fonctions IA planification, permissions d'écriture)
- 28-30 : M13 (visibilité catalogue/sous-comptes, panier mono-vendeur, commandes/paiement)
- 31-33 : M14 (plans/journaux, écritures + garde-fous, fonctions comptables + IA)
- 34-36 : M15 (profils publics, catalogue public, panier/commande invité)

## 5.1 Audit de cohérence inter-modules (M12)

```bash
psql "$DB" -v ON_ERROR_STOP=1 -f tests/integration/audit_coherence.sql
```

Attendu : **`0 KO → GO`**. Contrôle 18 tables, 8 intégrités référentielles,
9 activations RLS, 8 fonctions transverses/IA, 3 permissions M12.

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

```sql
-- Fonctions IA RH (M8) — substituer les UUID du seed
select public.analyser_effectifs('<etab_lycee>');
select public.calculer_score_turnover('<employe_ens2>');      -- attendu ~0.88 (risque élevé)
select public.calculer_score_turnover('<employe_direction>'); -- attendu ~0.12 (risque faible)
select public.recommander_formation('<employe_ens1>', '<annee_2026-2027>');
select public.optimiser_remplacements('<etab_lycee>', current_date);
```

```sql
-- Fonctions IA communication (M9) — substituer les UUID du seed
select public.choisir_canal('<profile_parent>', 'note');          -- canal préféré
select public.suggere_heure_envoi('<profile_parent>');            -- créneau d'envoi
select public.selectionner_variante('<profile_parent>', 'note');  -- variante A/B
select public.analyser_feedback('Merci, bien reçu');              -- sentiment
select public.analyser_envois('<etab_lycee>', '2026-01-01', '2026-12-31'); -- taux de lecture

-- Fonctions IA M10 (rapports & statistiques) — substituer les UUID du seed
select public.consolider_indicateurs_etablissement('<etab_lycee>', '<annee_2026-2027>');  -- 6 KPI
select public.detecter_anomalies('<etab_lycee>', '<annee_2026-2027>');                    -- anomalies
select public.risque_classe('<classe_7a>');                                              -- score de risque
select public.recommander_actions('<etab_lycee>', '<annee_2026-2027>');                   -- recommandations
select public.generer_resume_executif('<etab_lycee>', '<annee_2026-2027>');              -- résumé NLG

-- Permissions M10
select code from public.permissions where code like 'rapports.%';

-- Fonctions IA M11 (planification & agenda) — substituer les UUID du seed
select public.suggerer_placement_seance('<etab_lycee>', '<annee_2026-2027>', '<enseignant1>', '<classe_7a>', '<salle_a>');  -- créneau libre
select public.detecter_conflits_emploi('<etab_lycee>', '<annee_2026-2027>');                                                -- conflits
select public.charger_travail_enseignant('<etab_lycee>', '<annee_2026-2027>', '<enseignant1>');                            -- charge
select public.charger_travail_eleve('<classe_7a>');                                                                         -- charge élève
select public.recommander_seances('<etab_lycee>', '<annee_2026-2027>');                                                     -- rattrapages

-- Permissions M11
select code from public.permissions where code like 'planification.%';

-- Observabilité M12
select public.indicateurs_sante_base();                                      -- santé base (jsonb)
select public.predire_pics_charge('<etab_lycee>', '<annee_2026-2027>');      -- pics de charge hebdo

-- Permissions M12
select code from public.permissions where code like 'observabilite.%';

-- Fonctions comptables M14 (substituer les UUID du seed)
select public.journal_comptable('<etab_lycee>', '<journal_bq>', '2026-01-01', '2026-12-31');  -- journal
select public.grand_livre('<etab_lycee>', '<compte_520>', '2026-01-01', '2026-12-31');      -- grand livre
select public.balance_comptable('<etab_lycee>', '2026-12-31');                                -- balance
select public.detecter_anomalies_comptables('<etab_lycee>');                                  -- IA anomalies
select public.predire_tresorerie('<etab_lycee>', 30);                                          -- IA trésorerie

-- Permissions M14
select code from public.permissions where code like 'comptabilite.%';

-- Profils publics M15 (parcours invité)
select id, token_acces, complet from public.profils_publics limit 5;   -- profils invités
select count(*) from public.paniers where visiteur_id is not null;      -- paniers invités

-- Permissions M15
select code from public.permissions where code like 'marketplace.profil_public.%';
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
- M0 (auto) / M4 / M5 / M6 / M7 / M8 / M9 / M10 / M11 / M13 / M14 : OK / KO (M12 et M15 sans seed)
## Tests pgTAP
- 01→36 : [X]/151 assertions, [n] échecs
- Échecs : [liste fichier → assertion → cause]
## Vérifications ciblées
- Fonctions IA M7 : OK / KO
- Moyennes M6 : OK / KO
- Fonctions IA RH M8 (turnover, formation, remplacements) : OK / KO
- Fonctions IA comm M9 (canal, timing, A/B, sentiment) : OK / KO
- Fonctions IA M10 (KPI, anomalies, risque, recommandations, NLG) : OK / KO
- Fonctions IA M11 (placement, conflits, charge, rattrapage) : OK / KO
- Fonctions IA M12 (santé base, pics de charge) : OK / KO
- Audit de cohérence inter-modules : GO / NO-GO
- Fonctions IA M13 (détection anomalies commandes) : OK / KO
- Fonctions M14 (journal, grand livre, balance, IA comptable) : OK / KO
- Edge Function creer_profil_marketplace (déploiement + appel 200) : OK / KO
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
- [ ] 10 seeds appliqués sans erreur (M4-M11, M13, M14 ; M12 et M15 sans seed)
- [ ] `pg_prove` 36/36 fichiers verts, 0 échec
- [ ] Audit de cohérence inter-modules → GO (0 KO)
- [ ] Edge Function `creer_profil_marketplace` déployée et répondante
- [ ] Vérifications ciblées §6 toutes conformes
- [ ] Rapport de validation renseigné et archivé
