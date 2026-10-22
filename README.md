# EcoShop — Monorepo (v4.1)

Application de gestion scolaire + marketplace scolaire intégrée + moteur de
révision et de réussite aux examens, éditée par **Global Service Groupe (GSG)**.

- **Client** : Flutter (Android / iOS / Windows) — gestion d'état Riverpod,
  stockage hors-ligne SQLite/Drift.
- **Backend** : Supabase (Postgres + RLS, Auth natif, Storage, Realtime,
  Edge Functions).
- **Identité** : Supabase Auth natif uniquement (la fédération GSG ID a été
  retirée — directive KER-MUT).
- **GSG Platform Kernel** : Control Plane externe (tableaux de bord centraux),
  alimenté par EcoShop — voir [`docs/REGISTRE.md`](./docs/REGISTRE.md) REG-01.
- **Paiements** : Orange Money Guinée en direct (argent toujours détenu par
  l'opérateur, jamais par GSG) et CinetPay — REG-02.
- **Courriels** : Brevo, domaine `globalservicegroupe.com` — REG-04.

> **Où en est le projet ?** Le suivi des décisions et chantiers en cours est
> tenu dans un registre unique : [`docs/REGISTRE.md`](./docs/REGISTRE.md).
> Ce README donne la vue d'ensemble ; le registre fait foi.

## Traçabilité — projet source original

Ce dépôt est la reconstruction du projet source original situé localement à :

```
C:\Users\delam\ProjetsFlutter\ecoshop_flutter
```

Ce projet source reste la **référence fonctionnelle et réglementaire** du
périmètre métier (modules, règles de gestion, écrans). L'architecture cible
diffère (migration Firebase → Supabase, découpage modulaire strict) et est
décrite dans [`ANALYSE_GLOBALE.md`](./ANALYSE_GLOBALE.md) et
[`Cahier_de_Conception_EcoShop_v4.1.md`](./Cahier_de_Conception_EcoShop_v4.1.md).

## Structure du monorepo

```
.
├── apps/
│   └── client_flutter/          # Application Flutter (Riverpod, Drift/SQLite)
│       └── lib/
│           ├── core/            # Socle : config, thème, base locale, sync, auth
│           └── features/        # Verticaux : scolarité, notes, boutique, paiement…
├── supabase/
│   ├── migrations/              # Migrations SQL Postgres (schéma, RLS) — 50 fichiers
│   ├── functions/               # Edge Functions (IA, paiements, courriels, Kernel)
│   ├── config.toml              # Configuration projet Supabase
│   └── seed.sql                 # Données de développement
├── tests/rls/                   # Tests pgTAP (sécurité RLS et règles métier)
├── docs/                        # Registre, contrats de modules, guides d'exploitation
├── ANALYSE_GLOBALE.md           # Analyse globale & vision d'architecture
├── Cahier_de_Conception_EcoShop_v4.1.md  # Cahier de conception de référence
└── README.md
```

## Démarrage rapide

Prérequis : Flutter ≥ 3.44, Dart ≥ 3.12, Node ≥ 20, Supabase CLI, Deno 2
(tests des Edge Functions), un projet Supabase.

> **Base de production** : pas encore créée. Elle le sera au lancement du
> pilote (établissement Bambino Emmaüs), en formule Supabase **Pro**
> (sauvegardes quotidiennes, pas de mise en pause), région `eu-west-3`
> (Paris) — voir [`docs/OPERATIONS.md`](./docs/OPERATIONS.md) §3.

### 1. Application Flutter

```bash
cd apps/client_flutter
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=<url> \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<clé publique>
```

Sans ces deux `--dart-define`, l'application démarre en **mode diagnostic** :
aucun appel réseau n'est tenté et l'écran de socle s'affiche.

### 2. Base Supabase (via Supabase CLI)

```bash
supabase login
supabase link --project-ref <ref>
supabase db push                    # applique supabase/migrations dans l'ordre

# Edge Functions
supabase functions deploy creer_profil_marketplace
supabase functions deploy envoyer_message_ia
supabase functions deploy demarrer_analyse_risque_echec
supabase functions deploy demarrer_scan_exercice
supabase functions deploy analyser_usage_parent_ia
supabase functions deploy initier_paiement_cinetpay
supabase functions deploy recevoir_webhook_cinetpay
supabase functions deploy initier_paiement_orange_money
supabase functions deploy recevoir_notification_orange_money
supabase functions deploy relancer_paiements_orange_money
supabase functions deploy envoyer_notifications
supabase functions deploy kernel-export
supabase functions deploy kernel-control-plane
```

Après le premier `db push`, activer le **Custom Access Token Hook** :
`Authentication > Hooks > Custom Access Token` → `public.custom_access_token_hook`
(déjà déclaré dans `supabase/config.toml` pour l'environnement local).

Aucun secret n'est jamais versionné : tout passe par `supabase secrets set`.

#### Courriels (Brevo)

Guide complet : [`docs/DEPLOIEMENT_COURRIEL.md`](./docs/DEPLOIEMENT_COURRIEL.md)
(domaine déjà authentifié, clé API, planification, SMTP de Supabase Auth).

| Secret | Rôle |
|---|---|
| `BREVO_API_KEY` | Clé API Brevo (compte GSG) |
| `NOTIFICATIONS_DECLENCHEUR_SECRET` | Secret de l'appel planifié à `envoyer_notifications` (chaque minute) |
| `COURRIEL_EXPEDITEUR` / `COURRIEL_EXPEDITEUR_NOM` | `ne-pas-repondre@globalservicegroupe.com` / « EcoShop » |
| `COURRIEL_SUPPORT` | `contact@globalservicegroupe.com` — adresse publique, « Répondre à » |
| `COURRIEL_ADMIN_GSG` | `direction@globalservicegroupe.com` — alertes backoffice |
| `URL_APPLICATION` | Lien des boutons des courriels |

#### Paiements

- **Orange Money Guinée** (REG-02) : les identifiants marchands ne sont
  **pas** des secrets de projet — chaque établissement enregistre les siens
  (`enregistrer_identifiants_orange_money`) ; GSG ne détient jamais l'argent.
  Variable optionnelle : `ORANGE_MONEY_URL_RETOUR` (défaut
  `io.gsg.ecoshop://paiement/retour`). La relance planifiée
  (`relancer_paiements_orange_money`, toutes les 5 min) attend le secret
  `PAIEMENTS_DECLENCHEUR_SECRET` dans l'en-tête `x-declencheur-secret`.
- **CinetPay** : abonnements et quotas (chantier facturation, étapes a-d).

#### Control Plane du Kernel GSG

Contrat : [`docs/contrats/KERNEL_CONTROL_PLANE.md`](./docs/contrats/KERNEL_CONTROL_PLANE.md).

| Secret | Rôle |
|---|---|
| `KERNEL_INTERSERVICES_CLE_PRIVEE_JWK` | Clé privée EC P-256 d'EcoShop (JWK avec `kid`) — signe les envois, sa partie publique est servie à `/kernel-control-plane/jwks.json` |
| `GSG_KERNEL_AGGREGATION_URL` | URL de base des endpoints d'agrégation du Kernel |
| `GSG_KERNEL_JWKS_URL` | JWKS du Kernel (vérifie les jetons entrants) |
| `GSG_KERNEL_ISSUER` | Émetteur attendu des jetons du Kernel |
| `KERNEL_EXPORT_DECLENCHEUR_SECRET` | Secret de l'appel planifié à `kernel-export` |
| `GSG_KERNEL_TIMEOUT_MS` | Délai avant abandon d'un envoi (défaut : 10000) |

En leur absence, l'export est ignoré et la lecture répond 503 : rien d'autre
dans EcoShop n'en dépend.

### 3. Tests & analyse statique

```bash
# Client Flutter — 440 tests
cd apps/client_flutter
flutter analyze
flutter test

# Edge Functions (Deno) — inter-services, Orange Money, courriels
deno test --allow-env supabase/functions/_shared/

# Base de données — 62 scripts pgTAP (exécutés par la CI)
#   voir tests/rls/README.md
```

La CI GitHub Actions (`.github/workflows/ci.yml`) rejoue les migrations, les
tests pgTAP, les tests Deno, la vérification de types des Edge Functions et
`flutter analyze` / `flutter test`.

## État d'avancement

État au **17 octobre 2026**. *Chaque module est clos, testé et validé avant
le passage au suivant (règle d'or du séquençage strict).*

### Modules du cahier de conception

| Module | Intitulé | Statut |
|---|---|---|
| M0 | Initialisation & Socle Supabase/Flutter | ✅ livré |
| M1 | Schéma Supabase avancé | ✅ livré |
| M2 | Authentification (Supabase Auth natif) | ✅ livré — fédération GSG ID retirée (REG-01) |
| M3 | Socle applicatif Flutter | ✅ livré |
| M4 | Référentiel pédagogique CEDEAO | ✅ livré |
| M5 | Administration & Scolarité | ✅ livré |
| M6 | Notes & Évaluations | ✅ livré |
| M7 | Absences & Vie scolaire | ✅ livré |
| M8 | RH (personnel, contrats, paie) | ✅ livré |
| M9 | Communication & Notifications | ✅ livré (patch de protection des mineurs appliqué) |
| M10 | Rapports & Statistiques | ✅ livré |
| M11 | Planification & Agenda | ✅ livré |
| M12 | Intégration & Déploiement continu | ✅ livré |
| M13 | Marketplace AssoShop mono-vendeur | ✅ livré |
| M14 | Comptabilité (plan simplifié) | ✅ livré — option SYSCOHADA par établissement décidée (REG-03), à construire |
| M15 | Marketplace sans authentification | ✅ livré |
| M15bis | Thèmes internationaux & Dark Mode | ✅ livré |
| M15ter | Export PDF (bulletins & reçus) | ✅ livré |
| M15quater | Inscription, réinscription & encaissement de scolarité | ✅ livré |
| M16 | IA à rôles (Tuteur IA, Directeur-Adviser, Parent IA, risque d'échec, scan d'exercice) | ✅ livré (7 sous-livrables, clôture formelle 2026-09-12) |
| M17 | Bibliothèque & Ressources | ⏳ à venir |
| M18 | Transport scolaire | ⏳ à venir |
| M19 | Réseau d'établissements & Backoffice GSG | 🟡 partiel — réseaux d'établissements livrés (2026-10-22 : demande validée par GSG, invitations, tableau de bord consolidé, circulaires, calendrier commun, retrait et dissolution) ; validation des vendeurs et des établissements livrées ; paramètres globaux et CMS pédagogique à venir |
| M20 | Reporting, Tableaux de bord & Premium | 🟡 partiel — Premium élève et quotas Tuteur IA livrés (facturation) ; tableaux de bord centraux portés par le Control Plane du Kernel |

### Chantiers transverses livrés

| Chantier | Contenu | Livré |
|---|---|---|
| D1-D6 | Navigation et en-tête dynamique, galerie de profils, onboarding et régionalisation, accessibilité (contraste, taille de texte), bulletins PDF de classe entière, perception des frais par classe | 2026-09-12 → 13 |
| Facturation (a-d) | Droits par établissement, brique CinetPay, abonnement Premium élève, quota Tuteur IA | 2026-09-14 → 15 |
| Journalisation & audit | §34.3 du cahier | 2026-09-15 |
| Bloquant lancement (1/4-4/4) | CGU et consentement, verrou définitif des notes et mention d'examen, validation des vendeurs, sauvegarde et plan de reprise | 2026-09-17 |
| REG-01 Kernel | Mutation du Kernel GSG en Control Plane : délestage, export des métriques et de l'audit, jetons inter-services ES256 | 2026-10-17 |
| REG-02 Orange Money | Paiement en direct, suivi temps réel, relance automatique, rapprochement, espace Direction | 2026-10-17 |
| REG-04 Établissements | Demande d'ouverture par le fondateur, validation GSG, courriels de confirmation | 2026-10-17 |
| REG-07 Thèmes | Charte arabophone, identité visuelle par établissement (logo, couleur), ambiances personnelles | 2026-10-17 |

### Prochaines étapes

1. **REG-03** — comptabilité au choix de l'établissement : plan simplifié
   actuel **ou** SYSCOHADA révisé.
2. **Pilote Bambino Emmaüs** — création de la base de production, test réel
   Orange Money, mise en service des courriels et des tâches planifiées.
3. **M17 → M19** selon l'ordre arbitré par le porteur de projet.

## Documentation

| Document | Contenu |
|---|---|
| [`docs/REGISTRE.md`](./docs/REGISTRE.md) | Registre unique des décisions et chantiers (fait foi) |
| [`ANALYSE_GLOBALE.md`](./ANALYSE_GLOBALE.md) | Vision d'architecture, découpage des modules, historique narratif |
| [`docs/contrats/`](./docs/contrats/) | Contrat détaillé de chaque module et du Control Plane Kernel |
| [`docs/OPERATIONS.md`](./docs/OPERATIONS.md) | Exploitation, sauvegardes, plan de reprise |
| [`docs/DEPLOIEMENT_COURRIEL.md`](./docs/DEPLOIEMENT_COURRIEL.md) | Mise en service des courriels Brevo |
| [`docs/AUDIT_ECOSHOP_FLUTTER.md`](./docs/AUDIT_ECOSHOP_FLUTTER.md) | Audit d'écart rétroactif M0→M15 et ses arbitrages |
| [`tests/rls/README.md`](./tests/rls/README.md) | Inventaire des tests pgTAP |
