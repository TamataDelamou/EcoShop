# EcoShop — Mise en service (production)

> Kit de mise en service, 2026-10-22. Objectif : passer d'un projet
> Supabase vide à une école en service en une demi-journée. Tout ce qui
> peut être automatisé l'est (`scripts/deployer_supabase.ps1`,
> `scripts/construire_android.ps1`) ; le reste tient en quelques clics
> décrits ci-dessous. Aucune valeur secrète ne doit apparaître dans le
> dépôt ni dans une conversation.

## Vue d'ensemble

| Étape | Qui | Durée |
|---|---|---|
| 1. Créer le projet Supabase | Achille | 5 min |
| 2. Installer l'outil Supabase sur le PC | Achille | 5 min |
| 3. Remplir les secrets | Achille | 15 min |
| 4. Lancer le script de déploiement | Achille | 10 min |
| 5. Réglages d'authentification (tableau de bord) | Achille | 10 min |
| 6. Construire l'application Android | Achille | 15 min |
| 7. Contrôle final et premier établissement | Achille + Direction | 30 min |

## 1. Créer le projet Supabase

- **Répétition gratuite possible** : un projet en pause ne compte pas dans
  la limite des deux projets gratuits. Mettre AssoShop ou PharmaConnect en
  pause permet de créer EcoShop gratuitement et de tout répéter. Pour une
  vraie école, passer en **Pro** : un projet gratuit est mis en pause
  après une semaine sans activité et n'a pas de sauvegarde quotidienne.
- Compte : `globalservicegroupe.gsg@gmail.com` (compte GSG, pas personnel).
- Nom `EcoShop`, région **West EU (Paris) `eu-west-3`** : il n'existe pas
  de région en Afrique, Paris est la plus proche de Conakry.
- Noter le **mot de passe de la base** (demandé par le script) et le
  **Reference ID** (Settings → General).

## 2. Installer l'outil Supabase (une fois)

Dans PowerShell :

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
irm get.scoop.sh | iex
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase
supabase login
```

## 3. Remplir les secrets

Depuis la racine du dépôt :

```powershell
powershell -ExecutionPolicy Bypass -File scripts\deployer_supabase.ps1
```

Au premier lancement, le script crée
`supabase\mise_en_service\secrets.local.env` (ignoré par git) et l'ouvre
dans le Bloc-notes. Chaque ligne y est expliquée ; une ligne vide désactive
simplement la fonction concernée, on peut compléter plus tard et relancer.

| Ligne | Où la trouver |
|---|---|
| `PROJET_REF` | Supabase → Settings → General → Reference ID |
| `BREVO_API_KEY` | Brevo → SMTP & API → Clés API (`docs/DEPLOIEMENT_COURRIEL.md`) |
| `FCM_COMPTE_SERVICE_FICHIER` | chemin du JSON téléchargé dans Firebase → Comptes de service (`docs/DEPLOIEMENT_PUSH.md`) |
| `ORANGE_SMS_CLIENT_ID` / `_SECRET` | Orange Developer → application SMS Guinée |
| `SEND_SMS_HOOK_SECRETS` | rempli à l'étape 5 |
| `ADMIN_GSG_COURRIEL` | adresse du compte qui administrera EcoShop |

Les deux secrets des tâches planifiées sont **générés par le script**.

## 4. Déployer

Relancer la même commande. Le script, sans jamais afficher de secret :

1. relie le PC au projet (mot de passe de la base demandé) ;
2. applique toutes les migrations ;
3. envoie les secrets aux fonctions ;
4. déploie toutes les Edge Functions ;
5. range l'adresse du projet et les secrets dans le coffre (Vault), active
   `pg_cron` et `pg_net` et crée les **8 tâches planifiées** :

   | Tâche | Fréquence |
   |---|---|
   | Courriels et SMS (`envoyer-notifications`) | chaque minute |
   | Notifications push (`envoyer-push`) | chaque minute |
   | Paiements Orange Money en suspens | toutes les 5 min |
   | Absences au portail | toutes les 10 min |
   | Places d'inscription non confirmées | chaque heure |
   | Décrochage et risque de réussite, toutes les écoles | chaque nuit, 2 h 30 |
   | Ménage des notifications (90 jours) et de l'historique des tâches (7 jours) | chaque nuit |
   | Export vers le Kernel GSG | chaque heure, seulement si son secret est fourni |

6. désigne l'administrateur GSG (si le compte existe déjà) ;
7. affiche le **contrôle de préparation** (`etat_mise_en_service()`) :
   chaque ligne `OK` ou `A FAIRE`.

On peut le relancer à tout moment (après avoir complété un secret, par
exemple) : rien n'est dupliqué. Options : `-SansMigrations`,
`-SansFonctions` pour ne refaire que les secrets et les tâches.

## 5. Réglages d'authentification (tableau de bord Supabase)

1. **Authentication → Hooks → Customize Access Token** : activer, type
   Postgres, fonction `public.custom_access_token_hook` (rôle de
   l'utilisateur dans son jeton).
2. **Authentication → Hooks → Send SMS** : activer, type **HTTPS**,
   adresse `https://<ref>.supabase.co/functions/v1/envoyer_sms_auth`,
   **Generate secret**, copier ce secret dans `SEND_SMS_HOOK_SECRETS`, puis
   relancer le script avec `-SansMigrations -SansFonctions`.
   Les codes de connexion partent alors par **Orange SMS Guinée** (même
   contrat que les SMS des écoles) au lieu de Twilio (environ 0,25 USD par
   code). Numéros hors Guinée : message invitant à se connecter par e-mail.
3. **Authentication → Sign In / Providers → Phone** : activer ; ne pas
   choisir de fournisseur (le crochet le remplace). **Email** : activé.
4. **Authentication → Rate Limits** : SMS envoyés par heure, par exemple
   100 (protège le budget SMS contre les abus).
5. **Authentication → Emails → SMTP Settings** : Brevo
   (`docs/DEPLOIEMENT_COURRIEL.md`, étape 5).
6. **Authentication → URL Configuration** : Site URL = adresse publique
   d'EcoShop ; Redirect URL `io.gsg.ecoshop://login-callback`.

**Coût des codes SMS** : chaque connexion par téléphone consomme un SMS
du contrat Orange de GSG. La connexion par e-mail est gratuite. À
arbitrer : laisser le téléphone ouvert à tous, ou le réserver aux parents
sans adresse e-mail.

## 6. Construire l'application Android

Prérequis : Android Studio installé (il fournit Java et `keytool`),
`google-services.json` déposé (`docs/DEPLOIEMENT_PUSH.md`).

```powershell
powershell -ExecutionPolicy Bypass -File scripts\construire_android.ps1
```

- Premier lancement : le script crée `apps\client_flutter\config\production.json`
  (ignoré par git) à remplir avec l'adresse du projet et la **clé
  publiable** (Settings → API Keys, `sb_publishable_…`) ; puis il crée la
  **clé de signature de GSG** dans `%USERPROFILE%\cles-gsg\` et demande son
  mot de passe. **Sauvegarder ce fichier `.jks` et son mot de passe hors
  du PC** : ils signent toutes les futures mises à jour.
- Résultat : `app-release.aab`, à téléverser dans la Google Play Console
  (compte développeur 25 USD, une fois). Pour installer directement sur
  quelques téléphones du pilote sans passer par le Play Store :
  `-Format apk`.
- Nom affiché sur le téléphone : **EcoShop**. Identifiant :
  `com.gsg.ecoshop_client` (celui déclaré dans Firebase, à ne plus changer).

## 7. Contrôle final et premier établissement

1. Créer son compte dans l'application (e-mail), relancer le script pour
   le désigner administrateur GSG.
2. Relancer le script : toutes les lignes du contrôle de préparation
   doivent être `OK`, sauf les packs SMS tant que leurs prix ne sont pas
   fixés (écran **Crédits SMS GSG**).
3. La direction de Bambino Emmaüs fait sa **demande d'ouverture
   d'établissement** dans l'application ; l'équipe GSG la valide (REG-04).
4. Essai réel Orange Money avec un petit montant (REG-02), puis scan d'une
   carte au portail : le parent reçoit la notification push.

## Ce qui reste manuel, et pourquoi

| Point | Raison |
|---|---|
| Création du projet et passage en Pro | décision et paiement |
| Réglages d'authentification (étape 5) | non pilotables par le script sans risque d'écraser d'autres réglages |
| Compte Orange SMS, contrat Orange Money par école | contrats avec Orange |
| Compte Google Play | identité et paiement de GSG |
