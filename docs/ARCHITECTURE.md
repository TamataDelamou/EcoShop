# EcoShop — Architecture technique (Module 0)

## 1. Principes

- **Supabase = backend applicatif** : Postgres + RLS, Auth natif, Storage,
  Realtime, Edge Functions.
- **GSG Platform Kernel = externe** : `src/` du dépôt sert de contrat de
  référence (DTOs/API) pour la fédération d'identité GSG ID. Aucune logique
  métier EcoShop n'y est portée.
- **Client Flutter hors-ligne prioritaire** : Riverpod pour l'état, Drift/SQLite
  pour le local, file de synchronisation outbox.
- **Port Paiement agnostique** : adaptateurs interchangeables (CinetPay,
  Mobile Money local).
- **Le serveur fait foi** : toute permission est revérifiée à chaque requête
  (RLS + Edge Functions), jamais uniquement à l'affichage.

## 2. Frontières applicatives

```
┌ apps/client_flutter ────────────────────────────────────────────────┐
│ presentation/  (écrans, widgets)                                    │
│ application/   (use-cases, état Riverpod)                           │
│ domain/        (entités, règles métier, ports)                      │
│ data/          (supabase client, drift local, sync)                 │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ supabase_flutter
┌──────────────────────────────▼──────────────────────────────────────┐
│ Supabase                                                            │
│  auth.users → public.profiles (RLS)                                 │
│  Custom Access Token Hook : custom_access_token_hook()              │
│  Edge Functions : gsg-id-federate, (paiement, IA, notifications…)   │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ fédération additive (JWT/JWKS)
                        GSG Platform Kernel (GSG ID)
```

## 3. Identité & permissions

Modèle de rôles **à deux niveaux** (ch. 4) :

- **Niveau 1 — rôle racine**, porté par `profiles.role_racine` : l'identité du
  compte (élève, parent, enseignant, direction, vendeur, fondateur de réseau,
  et les deux rôles plateforme). Fixé une seule fois, via
  `choisir_role_racine()` pour les rôles auto-inscriptibles, via
  `accepter_invitation()` pour les autres. **Jamais** par un `UPDATE` client :
  un trigger restaure les colonnes à privilège.
- **Niveau 2 — poste déclaré**, porté par `etablissements_membres.poste_id` :
  agrège des permissions fines (`permissions` → `poste_permissions`) et n'a de
  sens que dans un établissement.

Tables structurantes :

| Table | Rôle |
|---|---|
| `profiles` | Source de vérité des attributs de compte (+ `etablissement_actif_id`) |
| `identifiants_comptes` | Identifiant canonique + canaux secondaires (ch. 5.4) |
| `etablissements` | Racine multi-tenant |
| `unites_operationnelles` | Campus et annexes d'un établissement |
| `annees_scolaires` | Cadre temporel (une seule courante par établissement) |
| `postes` / `poste_permissions` | Permissions fines par établissement |
| `etablissements_membres` | Rattachement compte ↔ établissement (+ unité, mandat) |
| `invitations` / `demandes_adhesion` | Voies d'entrée des rôles à privilège |
| `fiches_eleves` / `tentatives_liaison` | Liaison compte ↔ fiche et anti-brute-force |

**Fonctions d'autorisation** (toutes `SECURITY DEFINER`, `search_path` figé) :
`mes_etablissements()`, `est_membre_actif()`, `mon_role_racine()`,
`est_admin_gsg()`, `mes_permissions()`, `a_permission()`, `est_direction()`.

Elles sont `SECURITY DEFINER` pour une raison précise : une policy sur
`etablissements_membres` qui interrogerait directement `etablissements_membres`
déclenche une récursion RLS (`42P17`). Une fonction `SECURITY DEFINER`
n'évalue pas les policies des tables qu'elle lit, ce qui rompt la boucle.

**`custom_access_token_hook()`** recopie `role_racine`, `gsg_id` et
`statut_compte` dans le JWT à l'émission et au rafraîchissement. Ces claims
sont un **cache de confort pour l'affichage** ; toute décision d'autorisation
relit `public.profiles` côté serveur.

### Côté client

Le client n'applique aucune règle métier de son propre chef :

- `GardeSession` (fonction pure) décide de l'écran à afficher — c'est de
  l'ergonomie, pas de la sécurité : contourner un écran ne donne accès à
  aucune donnée que RLS refuse ;
- `AuthRepository` est un **port** ; seule son implémentation Supabase connaît
  `supabase_flutter`, ce qui rend le parcours testable sans réseau ;
- les codes d'erreur levés par les fonctions Postgres (`TROP_DE_TENTATIVES`,
  `ROLE_DEJA_DEFINI`…) sont transportés tels quels jusqu'à l'affichage.

## 4. Hors-ligne (SQLite/Drift)

- Base locale Drift : cache applicatif + **table `sync_queue`** (outbox).
- Toute écriture locale est journalisée dans `sync_queue` puis rejouée au
  retour réseau ; résolution de conflits par entité (voir `ANALYSE_GLOBALE.md`
  §3.4).
- `connectivity_plus` déclenche la resynchronisation proactive.

## 5. Conventions de nommage des migrations

`supabase/migrations/<horodatage>_<slug>.sql` — une migration = une unité
cohérente, idempotente, réversible documentée.
