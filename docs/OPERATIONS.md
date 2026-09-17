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

## 3. Reprise après sinistre (cahier §34.8)

### 3.1 Stratégie primaire — backups automatiques natifs Supabase Cloud

La production est hébergée sur **Supabase Cloud, palier Pro**. Le palier Pro
inclut par défaut des **backups automatiques quotidiens, rétention 7 jours**
(RPO ≈ 24 h — au pire, jusqu'à une journée de données perdues entre le
dernier backup automatique et l'incident). C'est la stratégie de reprise
**principale** de la plateforme, gérée entièrement par Supabase (aucun
mécanisme applicatif redondant à construire ou maintenir côté EcoShop).

Le **PITR** (Point-in-Time Recovery, granularité à la seconde) est un
add-on payant séparé sur le palier Pro (~100 $/mois pour une fenêtre de 7
jours, jusqu'à 400 $/mois pour 28 jours) et nécessite en plus un compute
add-on "Small" minimum. **Non souscrit à ce jour** — à réévaluer par le
porteur de projet si le RPO de 24 h s'avère insuffisant à l'usage réel
(ex. volume de transactions marketplace/scolarité justifiant un rattrapage
plus fin qu'une journée).

La restauration d'un backup natif Supabase (quotidien ou, le cas échéant,
PITR) se déclenche depuis le dashboard Supabase du projet ou via le support
Supabase — ce n'est **pas** une opération que l'équipe EcoShop exécute avec
ses propres identifiants Postgres : Supabase gère elle-même la
reconstruction de l'instance (schémas internes `auth`, `storage`,
`realtime`, event triggers PostgREST, etc. inclus), ce qu'un simple
`pg_restore` côté client ne peut pas reproduire (voir §3.3).

### 3.2 RTO — non mesuré en conditions réelles

**Aucun chiffre de RTO n'est documenté ici**, faute d'environnement de test
disponible pour ce chantier (pas d'instance Supabase de staging/branche
provisionnée à ce jour pour déclencher une restauration réelle via le
dashboard/support Supabase). Documenter un chiffre inventé serait plus
dangereux qu'utile en cas d'incident réel.

**À mesurer** lors d'un test dédié sur un environnement Supabase de staging
(déclencher une restauration réelle depuis le dashboard et chronométrer),
ou lors d'un premier incident réel documenté a posteriori. Tant que ce test
n'a pas été fait, considérer le RTO comme **inconnu**, pas comme "rapide"
ou "acceptable" par défaut.

### 3.3 Script `pg_dump`/`pg_restore` — usage complémentaire ciblé UNIQUEMENT

`./supabase/scripts/backup_restore.sh` (commandes `backup`/`restore`/`list`)
reste disponible pour des usages **ponctuels et ciblés** :

- export manuel avant une opération à risque (ex. migration lourde) ;
- transfert de données entre deux environnements Supabase **déjà
  provisionnés** (ex. copier un jeu de données de staging vers un autre
  projet de test).

```bash
export DATABASE_URL=<url-psql>
./supabase/scripts/backup_restore.sh backup          # → backups/ecoshop_<horodatage>.dump
./supabase/scripts/backup_restore.sh restore backups/ecoshop_20260906_120000.dump
# puis rejouer migrations + seeds + tests pour valider
./supabase/scripts/deploy.sh staging
```

**Ce script n'est PAS un plan de reprise complet et ne doit jamais être
utilisé comme tel.** Deux échecs réels, obtenus en testant ce script en
conditions réelles (conteneur Postgres local du projet, 2026-09-15/16, pas
une supposition) le démontrent et servent de mise en garde à l'équipe —
pour éviter de retenter la même chose en urgence, sous pression, pendant un
incident réel :

1. **Restauration complète (`--clean --if-exists`) contre l'instance déjà
   vivante** : échoue avec `must be owner of event trigger
   pgrst_drop_watch`. Le rôle `postgres` fourni par Supabase (local comme
   Cloud) n'est **pas** propriétaire des objets internes que Supabase
   installe lui-même (event triggers PostgREST, fonctions du schéma
   `realtime`, etc.) — un `pg_restore --clean` sur un dump complet de
   l'instance tente de les recréer et échoue sur les droits.
2. **Restauration du schéma `public` seul, vers une base neuve** : échoue
   avec `schema "auth" does not exist`. Les fonctions applicatives EcoShop
   (ex. `determiner_role_ia`) référencent `auth.uid()` — le schéma `public`
   n'est **pas autonome** et ne peut être restauré que contre une instance
   **déjà provisionnée par Supabase** (qui possède déjà les schémas
   `auth`/`storage`/`realtime`), jamais un Postgres vierge.

Conséquence pratique : `backup_restore.sh` ne peut restaurer utilement que
vers un projet Supabase existant, et seulement pour des données
applicatives (`public`) — jamais pour reconstruire une instance depuis
zéro. Pour toute reprise après un sinistre réel touchant la plateforme
entière, la seule voie fiable est le backup natif Supabase (§3.1).

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
