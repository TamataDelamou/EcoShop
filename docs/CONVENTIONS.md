# EcoShop — Conventions de développement

## Général

- Langue du code et des commentaires : **français** (identifiants en anglais
  quand c'est un terme technique standard : `sync_queue`, `auth`, `profile`).
- Pas de configuration codée en dur (seuils, commissions, barèmes) : tout passe
  par des paramètres (Postgres `parametres_globaux` / variables d'environnement).
- **Soft-delete** : jamais de `DELETE` physique sur une donnée pédagogique ou
  financière ; colonne `deleted_at` + filtrage RLS/requête.

## Flutter (`apps/client_flutter`)

- Structure en couches : `presentation/`, `application/`, `domain/`, `data/`.
- État : **Riverpod** (providers = un fichier `providers.dart` par feature).
- Accès base locale : **Drift** (schéma dans `data/db/`).
- Couleurs : uniquement via `AppColors` (charte « Innovation & Énergie »),
  jamais de valeurs hexadécimales en dur dans les widgets.
- Une écriture hors-ligne = un enregistrement dans `sync_queue`.

## Supabase

- Une migration = un changement ; ne jamais modifier une migration déjà
  appliquée (ajouter une nouvelle migration).
- RLS activée sur **toutes** les tables exposées au client ; `security
  definer` réservé aux fonctions contrôlées (hooks, triggers, Edge Functions).
- Secrets (Twilio, Resend, CinetPay, service_role, GSG ID) : coffre-fort Edge
  Functions / paramètres Supabase, jamais en dur ni dans le dépôt.

## Edge Functions (Deno/TypeScript)

- Une fonction = une responsabilité (`gsg-id-federate`, `paiement`, `ia`…).
- Vérification de signature JWT (JWKS) avant toute fédération d'identité.
- Journalisation structurée ; erreurs domaine → codes HTTP explicites
  (404/400), jamais de 500 silencieux.

## Tests

- Unitaires : logique pure (validateurs E.164, rôles, sync queue, tokens).
- Intégration : RLS (pgTAP ou tests Supabase), Edge Functions (Deno test),
  widgets Flutter pour les écrans critiques.
