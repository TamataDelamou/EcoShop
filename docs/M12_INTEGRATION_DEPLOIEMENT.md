# M12 — Intégration & Déploiement continu

Module de clôture du socle M0→M11 : il ne crée pas de nouveau domaine métier,
mais **intègre, sécurise, déploie et surveille** l'ensemble déjà livré.

## 1. Périmètre

### 1.1 Intégration technique

- **Cohérence inter-modules** (M0→M11) : clés étrangères, helpers, RLS,
  fonctions IA — vérifiée par `tests/integration/audit_coherence.sql`.
- **Optimisation des performances** : index existants conservés ; l'audit
  contrôle l'intégrité référentielle (prérequis à tout gain d'index) ; les
  recommandations d'index complémentaires sont listées en §5.
- **Tests d'intégration** : audit SQL + pipeline CI/CD + tests RLS 01→27.
- **Sécurité** : audit des RLS, permissions, fonctions `SECURITY DEFINER`.

### 1.2 Déploiement continu

- **Pipeline CI/CD** : `.github/workflows/ci.yml` (Supabase CLI, migrations,
  seeds, `pg_prove`, audit ; Flutter analyze + test).
- **Automatisation des migrations** : `supabase db reset` / `db push`.
- **Scripts de déploiement** : `supabase/scripts/deploy.sh` (staging→production).
- **Monitoring** : `indicateurs_sante_base()` + `journal_metriques` (M12).

### 1.3 Documentation opérationnelle

- `docs/OPERATIONS.md` : installation, administration, reprise, monitoring.

### 1.4 Exigence IA (supervision, jamais de décision automatique)

| Cas d'usage | Implémentation | Données croisées |
|---|---|---|
| Monitoring intelligent | `indicateurs_sante_base()` (APM minimal) | `pg_stat_activity`, taille base, uptime |
| Prédiction des pics de charge | `predire_pics_charge(etab, annee)` | M6 `evaluations`, M7 `presences` |
| Optimisation des migrations | Ordre M0→M12 séquencé + migration non invasive | `supabase/migrations/*.sql` |
| Rétroaction de pipeline | Historique GitHub Actions (à exploiter plus tard) | logs CI |

## 2. Livrables

| Livrable | Chemin |
|---|---|
| Migration observabilité | `supabase/migrations/20260906001200_m12_observabilite.sql` |
| Audit de cohérence | `tests/integration/audit_coherence.sql` + `README.md` |
| Pipeline CI/CD | `.github/workflows/ci.yml` |
| Déploiement | `supabase/scripts/deploy.sh` |
| Sauvegarde/restauration | `supabase/scripts/backup_restore.sh` |
| Guide opérationnel | `docs/OPERATIONS.md` |
| Recherche comparative §14 | `docs/RECHERCHE_COMPARATIVE.md` |

## 3. Audit de cohérence inter-modules

`audit_coherence.sql` contrôle (lecture seule, idempotent) :

1. **Tables structurantes** : 18 tables clés M0→M12 (`to_regclass`).
2. **Intégrité référentielle** : 8 contrôles d'orphelins (notes, évaluations,
   présences, permissions, membres) — 0 orphelin attendu.
3. **RLS activée** : 9 tables sensibles (`relrowsecurity`).
4. **Fonctions transverses/IA** : 8 fonctions présentes (helpers M1 + M12).
5. **Permissions M12** : 3 codes `observabilite.*` dans le catalogue.

**Verdict** : `0 KO → GO` ; `>0 KO → NO-GO`.

## 4. Pipeline CI/CD (`.github/workflows/ci.yml`)

- **Job `database`** : `supabase start` → `db reset` → seeds M4→M11 →
  `pg_prove tests/rls/*.sql` → audit de cohérence.
- **Job `flutter`** : `pub get` → `flutter analyze` → `flutter test`.
- Déclencheurs : push sur `main`, pull request, `workflow_dispatch`.
- Concurrency annulée en cas de re-push (évite les exécutions en double).

## 5. Optimisation des performances — recommandations

1. **Index de couverture** (à ajouter après mesure) :
   - `evaluations (etablissement_id, annee_scolaire_id, date_evaluation)`
     (déjà partiellement couvert par les index M6 ; à confirmer par `EXPLAIN`).
   - `presences (etablissement_id, date_presence) where statut = 'absent'`
     (accélère `predire_pics_charge`).
2. **Agrégats M10** : les KPI sont pré-calculés (pas de recalcul à la volée).
3. **Cache hors-ligne** : la file `sync_queue` (M0) + snapshots agendas (M11)
   évitent les allers-retours réseau inutiles.
4. **`VACUUM`/`ANALYZE`** : planifier après chaque chargement de seeds.

## 6. Plan de tests d'intégration

| Test | Commande | Attendu |
|---|---|---|
| Tests RLS | `pg_prove -d "$DB" tests/rls/*.sql` | 27/27 verts |
| Audit cohérence | `psql "$DB" -f tests/integration/audit_coherence.sql` | 0 KO → GO |
| Migration idempotente | rejouer `db reset` deux fois | sans erreur |
| Fonctions M12 | `select indicateurs_sante_base();` | jsonb valide |

## 7. Statut

M12 est **ouvert** sur `m12-integration-deploiement`. L'audit et le pipeline
s'exécutent à la session Docker (Docker absent de l'environnement local).
La migration M12 sera ajoutée à `docs/SESSION_VALIDATION_TECHNIQUE.md` lors de
la clôture de M12.
