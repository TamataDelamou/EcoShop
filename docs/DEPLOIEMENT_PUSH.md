# Notifications push — mise en service (Firebase Cloud Messaging)

> REG-09 (envoi par le serveur) et REG-11 (réception dans l'application).
> Le code est livré ; il reste à créer le projet Firebase. Aucune clé ne
> doit apparaître dans le dépôt ni dans une conversation.

## Ce qui part en notification push

| Événement | Destinataire |
|---|---|
| Arrivée et sortie de l'élève au portail (si le parent l'a activé) | Parents |
| Absence constatée, sortie avant l'heure | Parents |
| Relance de scolarité en retard | Payeur (parent, ou l'élève dès le collège) |
| Étapes d'un dossier d'inscription (pièce demandée, accepté, place offerte…) | Famille |

Chaque notification reste lisible dans la boîte de notifications de
l'application, même sans téléphone enregistré ou sans réseau. Le push est
gratuit (Firebase Cloud Messaging) ; seuls les SMS sont payants (crédits
SMS des établissements).

## Étape 1 — Créer le projet Firebase (10 minutes, une seule fois)

Avec le compte Google de GSG (`globalservicegroupe.gsg@gmail.com`), pas un
compte personnel :

1. Ouvrir <https://console.firebase.google.com>, **Créer un projet**, nom
   `EcoShop GSG`. Google Analytics : **non** (inutile ici).
2. Dans le projet : **Ajouter une application** → icône **Android**.
   - Nom du package Android : `com.gsg.ecoshop_client` (exactement).
   - Surnom : `EcoShop Android`. Le certificat SHA-1 n'est pas nécessaire.
3. Télécharger **`google-services.json`** et le déposer dans
   `apps/client_flutter/android/app/` sur le poste de construction.
   Ce fichier est ignoré par git : il ne part jamais sur GitHub. Les
   étapes suivantes de la console (ajout du SDK) sont déjà faites dans le
   code : cliquer sur **Suivant** jusqu'à la fin.

À partir de là, l'application construite pour Android reçoit les
notifications. Sans ce fichier, elle fonctionne normalement, sans push.

## Étape 2 — Autoriser le serveur à envoyer (au déploiement Supabase)

1. Console Firebase → ⚙ **Paramètres du projet** → **Comptes de service** →
   **Générer une nouvelle clé privée**. Un fichier JSON est téléchargé :
   c'est un secret, à ne jamais envoyer par messagerie ni courriel.
2. **Avec le script de mise en service (recommandé)** : dans
   `supabase\mise_en_service\secrets.local.env`, indiquer le **chemin** du
   fichier à la ligne `FCM_COMPTE_SERVICE_FICHIER`, puis lancer
   `scripts\deployer_supabase.ps1` (`docs/MISE_EN_SERVICE.md` §3 et §4).
   Le script vérifie que c'est bien un compte de service Firebase, l'envoie
   aux fonctions sous le nom `FCM_COMPTE_SERVICE` sans jamais l'afficher, et
   crée lui-même la tâche `envoyer-push` (chaque minute). Ranger ensuite le
   fichier hors du PC (ou le supprimer : une nouvelle clé se génère au
   besoin).
3. **Sans le script** : coller le contenu du fichier **tel quel** dans les
   secrets du projet Supabase EcoShop sous le nom `FCM_COMPTE_SERVICE`
   (Supabase → Edge Functions → Secrets), puis supprimer le fichier.
   Vérifier que `NOTIFICATIONS_DECLENCHEUR_SECRET` est défini (le même
   que pour les courriels, `docs/DEPLOIEMENT_COURRIEL.md` étape 4, déjà
   rangé dans le coffre Vault), puis planifier l'envoi chaque minute dans
   l'éditeur SQL Supabase, en remplaçant `<ref>` :

```sql
select cron.schedule('envoyer-push', '* * * * *', $$
  select net.http_post(
    url := 'https://<ref>.supabase.co/functions/v1/envoyer_push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-declencheur-secret', (select decrypted_secret from vault.decrypted_secrets
                               where name = 'notifications_declencheur_secret')),
    body := '{}'::jsonb);
$$);
```

L'API « Firebase Cloud Messaging API (V1) » est activée par défaut sur les
nouveaux projets ; si l'envoi répond 403, l'activer dans **Paramètres du
projet → Cloud Messaging**.

## Étape 3 — Vérifier sur un téléphone Android

1. Installer l'application construite avec `google-services.json`, se
   connecter avec un compte parent, **autoriser les notifications**.
2. Dans Supabase, table `jetons_push` : une ligne apparaît pour ce compte
   (identifiant de 22 caractères, plateforme `android`).
3. Scanner la carte d'un enfant de ce parent au portail : la
   notification « Arrivée à l'école » arrive en moins d'une minute.

## iPhone (plus tard)

Le code est prêt, mais Apple impose un compte développeur (99 USD/an), une
clé APNs à déposer dans Firebase (**Paramètres → Cloud Messaging → Apple**)
et le fichier `GoogleService-Info.plist` dans `ios/Runner/` (lui aussi
ignoré par git). À faire quand l'application sera publiée sur l'App Store.

## Choix techniques

- **Identifiant d'installation Firebase (FID)** plutôt que l'ancien jeton
  d'appareil, déclaré obsolète par Google en 2026 : l'application utilise
  `register()` / `onRegistered`, le serveur envoie dans `message.fid` et
  accepte encore `message.token` pour d'éventuels anciens téléphones.
- **Hors connexion d'abord** : le rattachement du téléphone au compte est
  retenté à chaque ouverture et à chaque retour du réseau ; les
  notifications non remises sont réessayées pendant deux jours par le
  serveur, puis restent dans la boîte de l'application.
- **Déconnexion** : le téléphone est désinscrit, pour qu'une tablette
  partagée ou un téléphone prêté ne reçoive plus les alertes du compte.
