# EcoShop — État de la Phase A (M0 → M3)

> Point de contrôle documentaire. Ce fichier dit ce qui est livré, ce qui a été
> **vérifié par exécution**, et ce qui ne l'a pas été.

## 1. Correctifs appliqués au code existant (M0)

Migration `20260906000100_fix_core_security.sql`.

| # | Défaut constaté dans `20260904000000_core_schema.sql` | Correctif |
|---|---|---|
| C1 | **Escalade de privilège.** La policy `profiles_update_own` autorisait un compte à modifier sa propre ligne, `role_racine` compris : un élève pouvait se promouvoir `admin_gsg`. | Trigger `profiles_protege_colonnes` : les colonnes à privilège sont restaurées à leur valeur antérieure pour tout appel non-serveur. Le rôle ne se fixe que par `choisir_role_racine()`, restreinte aux rôles auto-inscriptibles. |
| C2 | **Récursion RLS (`42P17`).** Les policies de `etablissements`, `etablissements_membres` et `postes` interrogeaient `etablissements_membres`, dont la policy `SELECT` interroge à son tour `etablissements_membres`. | Fonctions `SECURITY DEFINER` `mes_etablissements()` / `est_membre_actif()` : elles n'évaluent pas les policies des tables lues, ce qui casse la boucle. |
| C3 | **Hook JWT inopérant.** `custom_access_token_hook` lisait `public.profiles` sans `security definer`, et `supabase_auth_admin` n'avait ni accès au schéma ni droit de lecture : aucun claim n'aurait jamais été émis. | Fonction passée en `security definer`, `grant usage on schema public` et `grant execute` à `supabase_auth_admin`. |
| C4 | **Violation `NOT NULL` possible.** `handle_new_user` insérait `coalesce(new.phone, new.email)` dans une colonne non nulle : un utilisateur créé sans ni l'un ni l'autre faisait échouer l'inscription. | Repli sur un identifiant technique `uid:<uuid>`, puis (M2) alimentation conjointe de `identifiants_comptes`. |
| C5 | Soft-delete et `statut_compte` déclarés dans les conventions mais absents des policies. | `deleted_at is null` et `statut_compte = 'actif'` appliqués dans les policies et dans `mes_etablissements()`. |
| C6 | Fonctions sans `search_path` figé (vecteur d'injection par schéma). | `set search_path` sur toutes les fonctions. |
| C7 | `README.md` documentait `SUPABASE_ANON_KEY`, le code lit `SUPABASE_PUBLISHABLE_KEY`. | README corrigé. |

Correctifs Edge Function `gsg-id-federate` :

- dépendances `npm:` **épinglées** (`@supabase/supabase-js@2.48.1`, `jose@5.9.6`) — un import non versionné suit silencieusement les publications amont ;
- `createRemoteJWKSet` **hissé au niveau module** : il était recréé à chaque requête, ce qui annulait son cache de clés et provoquait un appel réseau par appel ;
- `AbortSignal.timeout` sur l'appel Kernel : sans délai, une lenteur amont bloquait la fonction jusqu'au timeout de la plateforme ;
- CORS restreint à une liste blanche (`CORS_ORIGINES`) au lieu de `*` ;
- `gsgId` validé comme UUID avant écriture ;
- aucun détail interne renvoyé au client ; journalisation structurée.

## 2. Livrables par module

### M1 — Schéma Supabase avancé
`20260906000200_m1_schema_avance.sql`

- `unites_operationnelles` (hiérarchie, cohérence de tenant par trigger).
- `annees_scolaires` — au plus une courante par établissement, garantie par un
  **index unique partiel** plutôt que par du code applicatif.
- Permissions fines : `permissions` (catalogue) + `poste_permissions`
  (jonction). La colonne `postes.permissions` jsonb de M0 devient obsolète.
- `etablissements_membres` enrichi : unité, période de mandat, soft-delete.
- `profiles.etablissement_actif_id` + validation d'appartenance.
- Résolution serveur : `mes_permissions()`, `a_permission()`, `est_direction()`.
- RLS d'écriture ouverte à la direction via permission, jamais via rôle en dur.

### M2 — Auth & fédération GSG ID
`20260906000300_m2_auth_federation.sql`

- `identifiants_comptes` : un seul identifiant canonique par compte (index
  unique partiel), format E.164 / e-mail vérifié par contrainte `CHECK`.
- `ajouter_identifiant_secondaire()` — refuse hors session active (ch. 5.4).
- `invitations` : jeton stocké en **SHA-256 uniquement**, nominatif, expirant.
  `accepter_invitation()` n'écrase jamais un rôle racine déjà établi.
- `demandes_adhesion` : une seule en attente par couple compte/établissement.
- `fiches_eleves` + `lier_compte_a_fiche()` : double facteur matricule + date de
  naissance, **5 tentatives par heure**, réponse d'erreur indifférenciée pour
  ne pas transformer la RPC en oracle d'énumération des matricules.
- `definir_etablissement_actif()`.
- Edge Function `gsg-id-federate` durcie (§1).

### M3 — Socle applicatif Flutter

- `features/auth/domain` : `CanalOtp` (2 entrées × 4 canaux), `Profil`,
  `GardeSession`, port `AuthRepository`.
- `features/auth/data/supabase_auth_repository.dart` : seule classe qui connaît
  `supabase_flutter`. Les codes d'erreur métier levés par Postgres sont
  transportés tels quels, sans réinterprétation côté client.
- `features/auth/application` : `ConnexionController` (normalisation E.164
  **avant** tout appel), providers de session.
- Écrans : connexion OTP, choix de rôle, liaison de fiche, sélection
  d'établissement, compte bloqué.
- `features/coquille` : navigation adaptative (barre / rail à 720 px), bandeau
  hors-ligne, onglets filtrés par rôle, `RacineApp` déclarative.

## 3. Vérification — ce qui a été exécuté, ce qui ne l'a pas été

| Élément | Vérification |
|---|---|
| `flutter analyze` | ✅ exécuté — aucun problème |
| `flutter test` | ✅ exécuté — **52 tests** passent |
| Migrations SQL M0-fix / M1 / M2 | ❌ **non exécutées** |
| Edge Function `gsg-id-federate` | ❌ **non exécutée** |
| Policies RLS | ❌ **non testées à l'exécution** |

**Aucun outil backend n'est installé sur ce poste** : ni `supabase` CLI, ni
Docker, ni `psql`, ni `deno`. Le SQL et le TypeScript Deno de la Phase A sont
donc relus mais **jamais exécutés**. Avant de considérer M1 et M2 clos au sens
de la règle d'or du séquençage, il faut :

```bash
supabase start          # nécessite Docker Desktop
supabase db reset       # rejoue migrations + seed
supabase functions serve gsg-id-federate
```

puis écrire les tests d'intégration RLS annoncés par `docs/CONVENTIONS.md`
(pgTAP), qui restent à produire. Les points à couvrir en priorité, parce qu'ils
portent des règles de sécurité et non de simple structure :

1. un compte non-serveur ne peut pas modifier son `role_racine` par `UPDATE`
   direct (C1), **et** `choisir_role_racine()` y parvient bien — le trigger de
   protection est traversé par les RPC de confiance grâce au rôle Postgres
   effectif sous `SECURITY DEFINER`, pas grâce au rôle du jeton ;
2. `select` sur `etablissements_membres` ne provoque pas de récursion (C2) ;
3. `custom_access_token_hook` émet bien les claims sous `supabase_auth_admin` (C3) ;
4. `lier_compte_a_fiche` bloque à la 6ᵉ tentative dans l'heure ;
5. un membre d'un établissement ne lit aucune ligne d'un autre établissement ;
6. `accepter_invitation` refuse un jeton destiné à quelqu'un d'autre.

## 4. Écart connu sur le périmètre M3

`ANALYSE_GLOBALE.md` §4.3 annonce pour M3 les « sélecteurs établissement/**enfant** ».
Le sélecteur d'établissement est livré ; le **sélecteur d'enfant ne l'est pas** :
il suppose le lien parent ↔ élève (tuteurs légaux), qui appartient au périmètre
de M5 — Administration & Scolarité. Le créer ici aurait signifié inventer une
table de rattachement familial hors du module qui la définit.

## 5. Reste à faire

M4 à M15 sont **livrés par migrations SQL** (cf. `ANALYSE_GLOBALE.md` §4.4) et
leurs contrats d'interface sont spécifiés dans [`docs/contrats/`](./contrats/README.md).
Le socle M0 → M15 est validé en CI : migrations + seeds + 36 tests RLS passent
sur `main` (hook JWT, modèle de rôles, multi-tenant, audit des RPC).

Reste à replanifier puis livrer (M16 → M20) : Port Paiement hexagonal, moteur de
questions & quiz, profil de maîtrise & gamification, préparation aux examens,
IA à rôles, bibliothèque, transport scolaire, réseau & backoffice GSG,
reporting/Premium. Un module à la fois, chacun clos et validé avant le suivant.
