# EcoShop — Monorepo (v4.1)

Application de gestion scolaire + marketplace scolaire intégrée + moteur de
révision et de réussite aux examens, éditée par **Global Service Groupe (GSG)**.

- **Client** : Flutter (Android / iOS / Windows) — gestion d'état Riverpod,
  stockage hors-ligne SQLite/Drift.
- **Backend** : Supabase (Postgres + RLS, Auth natif, Storage, Realtime,
  Edge Functions).
- **Identité fédérée** : GSG ID via le GSG Platform Kernel (couche additive).

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
│           └── features/        # Verticaux : auth, etablissement, coquille…
├── supabase/
│   ├── migrations/              # Migrations SQL Postgres (schéma, RLS)
│   ├── functions/               # Edge Functions (fédération GSG ID, paiement, IA…)
│   ├── config.toml              # Configuration projet Supabase
│   └── seed.sql                 # Données de développement
├── docs/                        # Documentation maître (architecture, conventions)
├── ANALYSE_GLOBALE.md           # Analyse globale & vision d'architecture
├── Cahier_de_Conception_EcoShop_v4.1.md  # Cahier de conception de référence
└── README.md
```

## Démarrage rapide

Prérequis : Flutter ≥ 3.44, Dart ≥ 3.12, Node ≥ 20, Supabase CLI, un projet Supabase.

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
supabase functions deploy gsg-id-federate
supabase functions deploy creer_profil_marketplace
```

Après le premier `db push`, activer le **Custom Access Token Hook** :
`Authentication > Hooks > Custom Access Token` → `public.custom_access_token_hook`
(déjà déclaré dans `supabase/config.toml` pour l'environnement local).

Secrets attendus par l'Edge Function `gsg-id-federate` :

| Secret | Rôle |
|---|---|
| `GSG_KERNEL_BASE_URL` | URL du GSG Platform Kernel |
| `GSG_KERNEL_API_KEY` | Clé client GSG ID |
| `GSG_KERNEL_TIMEOUT_MS` | Délai avant abandon (défaut : 5000) |
| `CORS_ORIGINES` | Origines web autorisées, séparées par des virgules |

En leur absence, la fédération est simplement ignorée : elle est **additive et
non bloquante**, aucune connexion n'en dépend.

### 3. Tests & analyse statique

```bash
cd apps/client_flutter
flutter analyze
flutter test
```

## État d'avancement des modules

| Module | Intitulé | Statut |
|---|---|---|
| M0 | Initialisation & Socle Supabase/Flutter | ✅ livré |
| M1 | Schéma Supabase avancé | ✅ livré |
| M2 | Auth & fédération GSG ID | ✅ livré |
| M3 | Socle applicatif Flutter | ✅ livré |
| M4 | Référentiel pédagogique CEDEAO | ✅ livré |
| M5 | Administration & Scolarité | ✅ livré |
| M6 | Notes & Évaluations | ✅ livré |
| M7 | Absences & Vie scolaire | ✅ livré |
| M8 | RH (personnel, contrats, paie) | ✅ livré |
| M9 | Communication & Notifications | ✅ livré |
| M10 | Rapports & Statistiques | ✅ livré |
| M11 | Planification & Agenda | ✅ livré |
| M12 | Intégration & Déploiement continu | ✅ livré |
| M13 | Marketplace AssoShop mono-vendeur | ✅ livré |
| M14 | Comptabilité sans OHADA | ✅ livré |
| M15 | Marketplace sans authentification | ✅ livré |
| M15bis | Thèmes internationaux & Dark Mode | ✅ livré |
| M15ter | Export PDF (bulletins & reçus) | ✅ livré |
| M16-M20 | IA à rôles, bibliothèque, transport, réseau, reporting | ⏳ à venir |

**Phases A et B (M0-M12) closes, Phase C engagée (M13-M15ter livrés).**
M15bis et M15ter n'ont pas de migration SQL propre (modules purement
client) — insérés entre M15 et M16 conformément à `ANALYSE_GLOBALE.md` §4.4.
Un patch de sécurité d'urgence a également été appliqué à M9 (messagerie de
groupe scolaire — protection des mineurs, voir
`docs/contrats/M09_communication_notifications.md` §6 et
`docs/AUDIT_ECOSHOP_FLUTTER.md` §0.1). **M16 reste bloqué** tant que le
reste de l'audit d'écart rétroactif M0→M15
([`docs/AUDIT_ECOSHOP_FLUTTER.md`](./docs/AUDIT_ECOSHOP_FLUTTER.md)) n'a pas
été arbitré par le porteur de projet. Le détail du périmètre de chaque module figure dans
[`ANALYSE_GLOBALE.md`](./ANALYSE_GLOBALE.md) §4.3, et l'état de vérification de
la Phase A dans [`docs/ETAT_PHASE_A.md`](./docs/ETAT_PHASE_A.md).

Le tableau ci-dessus trace la livraison **SQL** (migrations + RLS). Le
**client Flutter** (`apps/client_flutter`) est un chantier distinct, construit
module par module sur ce socle déjà livré :

| Module | Client Flutter | Tests (`flutter test`) |
|---|---|---|
| M13 | Marketplace AssoShop mono-vendeur | ✅ livré et vérifié |
| M14 | Comptabilité sans OHADA | ✅ livré et vérifié |
| M15 | Marketplace sans authentification | ✅ livré et vérifié (périmètre reconsidéré, cf. `docs/ETAT_PHASE_C.md` §2) |
| M15bis | Thèmes internationaux & Dark Mode | ✅ livré et vérifié (233 tests, `flutter analyze` propre) |
| M15ter | Export PDF (bulletins & reçus) | ✅ livré et vérifié (246 tests, `flutter analyze` propre) |

État détaillé, écarts doc/DDL corrigés et réserve technique (exécution
locale des migrations) dans [`docs/ETAT_PHASE_C.md`](./docs/ETAT_PHASE_C.md).
M15bis est documenté dans
[`docs/contrats/M15bis_themes_dark_mode.md`](./docs/contrats/M15bis_themes_dark_mode.md),
M15ter dans
[`docs/contrats/M15ter_export_pdf.md`](./docs/contrats/M15ter_export_pdf.md).

*Chaque module est clos, testé et validé avant le passage au suivant
(règle d'or du séquençage strict).*
