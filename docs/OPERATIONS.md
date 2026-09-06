# Guide opérationnel — EcoShop (M12)

Documentation d'exploitation du socle M0→M12 : installation, déploiement,
administration, sauvegarde/restauration, monitoring.

## 1. Installation et déploiement

### 1.1 Pré-requis

| Outil | Version | Rôle |
|---|---|---|
| Docker | ≥ 24 | `supabase start` (stack locale) |
| Supabase CLI | ≥ 2.x | migrations, seeds, fonctions, link/push |
| psql / pg_prove | — | tests RLS et audit |
| Flutter | ≥ 3.44 | client `apps/client_flutter` |

### 1.2 Démarrage local

```bash
supabase start                 # stack locale (Postgres + Auth + API)
supabase db reset              # migrations M0→M12 + seed M0
# seeds complémentaires M4→M11 (voir §2.2)
```

### 1.3 Déploiement staging → production

```bash
export SUPABASE_PROJECT_REF=<ref-projet>
export DATABASE_URL=<url-psql-cible>
./supabase/scripts/deploy.sh production
```

Le script est **idempotent** : il applique migrations, seeds, tests pgTAP et
audit de cohérence, et peut être relancé après une coupure réseau.

## 2. Administration

### 2.1 Gestion des utilisateurs et rôles

- Identité : `profiles` (M0) + fédération GSG ID (`gsg-id-federate`, M2).
- Rôles globaux : `role_racine` (élève, parent, personnel, direction, admin_gsg).
- Rôles par établissement : `etablissements_membres` + `postes` + `poste_permissions`.
- **Règle** : ne jamais coder de permission en dur côté client ; passer par le
  catalogue `permissions` (`domaine.objet.action`).

### 2.2 Établissements et seeds

Création d'un établissement : insérer `etablissements`, puis l'année scolaire,
les unités opérationnelles, les postes et les rattachements membres.

Seeds complémentaires (idempotents, ordre M4→M11) :

```bash
psql "$DATABASE_URL" -f supabase/seed_referentiel_pedagogique.sql     # M4
psql "$DATABASE_URL" -f supabase/seed_administration_scolarite.sql    # M5
psql "$DATABASE_URL" -f supabase/seed_notes_evaluations.sql           # M6
psql "$DATABASE_URL" -f supabase/seed_vie_scolaire.sql                # M7
psql "$DATABASE_URL" -f supabase/seed_rh_personnel.sql                # M8
psql "$DATABASE_URL" -f supabase/seed_communication_notifications.sql # M9
psql "$DATABASE_URL" -f supabase/seed_rapports_statistiques.sql       # M10
psql "$DATABASE_URL" -f supabase/seed_planification_agenda.sql        # M11
```

## 3. Reprise après sinistre

### 3.1 Sauvegarde

```bash
export DATABASE_URL=<url-psql>
./supabase/scripts/backup_restore.sh backup          # → backups/ecoshop_<horodatage>.dump
```

### 3.2 Restauration

```bash
./supabase/scripts/backup_restore.sh restore backups/ecoshop_20260906_120000.dump
# puis rejouer migrations + seeds + tests pour valider
./supabase/scripts/deploy.sh staging
```

Dumps au format custom compressé, restaurés sans owner (`--no-owner`), donc
transférables entre environnements.

## 4. Monitoring et alertes

### 4.1 Indicateurs de santé (APM minimal)

```sql
select public.indicateurs_sante_base();
-- => { taille_base, connexions_actives, connexions_totales,
--      transactions_en_attente, uptime }
```

### 4.2 Prédiction des pics de charge

```sql
select * from public.predire_pics_charge('<etablissement_id>', '<annee_id>');
-- => semaine, nb_evaluations, nb_examens, absences_30j, niveau_charge
```

### 4.3 Métriques applicatives

Le client enregistre latence/erreurs/saturation dans `journal_metriques`
(M12) ; la collecte est **différée** (rejouée quand le réseau revient), avec
RLS par établissement.

### 4.4 Seuils d'alerte recommandés

| Niveau | Condition | Réaction |
|---|---|---|
| Critique | `niveau_charge = 'critique'` ou connexions saturées | Scaling / intervention immédiate |
| Élevé | `niveau_charge = 'eleve'` | Surveillance rapprochée |
| Normal | sinon | Aucune |

**Aucune alerte ni scaling n'est déclenché automatiquement** : les fonctions
sont des aides à la décision (règle éthique du projet).

## 5. Sécurité — audit RLS

- Toutes les tables sensibles ont RLS activée (contrôlé par
  `tests/integration/audit_coherence.sql`).
- Les fonctions transverses sont `SECURITY DEFINER` avec `search_path = public`.
- Le trigger `profiles_protege_colonnes` protège les privilèges globaux.
- Référence : `docs/SESSION_VALIDATION_TECHNIQUE.md` (session Docker GO/NO-GO).
