# Courriels transactionnels — mise en service (Brevo + globalservicegroupe.com)

> REG-04 (fin). Code livré le 2026-10-17 ; mise en service le jour où la base
> Supabase EcoShop existera. Aucune clé ne doit apparaître dans le dépôt ni
> dans une conversation : tout passe par les secrets Supabase.

## Ce qui est envoyé

| Événement | Destinataire | Modèle |
|---|---|---|
| Demande d'ouverture soumise | Fondateur (adresse de la demande, sinon du compte) | `demande_etablissement_recue` |
| Demande d'ouverture soumise | Équipe GSG (`COURRIEL_ADMIN_GSG`) | `demande_etablissement_a_traiter` |
| Demande acceptée | Fondateur | `demande_etablissement_acceptee` |
| Demande refusée (motif inclus) | Fondateur | `demande_etablissement_refusee` |

Un fondateur inscrit uniquement par téléphone ne reçoit pas de courriel
(le canal SMS est prévu dans la file mais pas encore branché — voir REG-04
dans `docs/REGISTRE.md`).

## Fonctionnement

1. L'événement (soumission, décision) écrit le message dans
   `notifications_sortantes` **dans la même transaction** (migration
   `20260906001533`). Pas de message perdu, pas de message fantôme.
2. L'Edge Function `envoyer_notifications`, appelée chaque minute, réserve
   jusqu'à 25 messages, les envoie à Brevo et enregistre le résultat.
3. Échec temporaire (réseau, Brevo saturé) : nouvel essai après 1 min, 5 min,
   30 min, 2 h, 12 h. Échec définitif (adresse refusée) : arrêt, visible dans
   `indicateurs_notifications()`.
4. Les messages terminés sont purgés après 90 jours (`purger_notifications`).

## Étape 1 — Authentifier le domaine dans Brevo (une seule fois)

Dans Brevo : **Paramètres → Expéditeurs, domaines et IP dédiées → Domaines →
Ajouter un domaine** → `globalservicegroupe.com`.

Brevo affiche des enregistrements DNS à ajouter chez l'hébergeur du domaine :

- **Code Brevo** (TXT) — preuve de propriété ;
- **DKIM** (TXT ou CNAME) — signature des messages ;
- **DMARC** (TXT `_dmarc`) — si aucun n'existe, commencer par
  `v=DMARC1; p=none; rua=mailto:contact@globalservicegroupe.com` ;
- **SPF** — s'il existe déjà un enregistrement `v=spf1 …` (messagerie
  actuelle du domaine), **ne pas en créer un second** : ajouter
  `include:spf.brevo.com` dans l'existant.

Puis créer l'expéditeur `ne-pas-repondre@globalservicegroupe.com`
(nom affiché « EcoShop »). Vérifier que `contact@globalservicegroupe.com`
(ou l'adresse de support choisie) reçoit bien le courrier : c'est l'adresse
« Répondre à ».

## Étape 2 — Clé API Brevo

**Paramètres → SMTP & API → Clés API → Générer une clé** (nom :
`ecoshop-prod`). Dans **Sécurité → IP autorisées**, désactiver le blocage
des IP inconnues **pour cette clé** : les Edge Functions Supabase n'ont pas
d'adresse IP fixe. Sinon Brevo répond 401 et les messages attendent en file
(alerte « Brevo refuse la clé API » dans les journaux de la fonction).

## Étape 3 — Secrets Supabase (Git Bash, dossier EcoShop)

```bash
supabase secrets set BREVO_API_KEY=<clé copiée depuis Brevo>
supabase secrets set NOTIFICATIONS_DECLENCHEUR_SECRET=$(openssl rand -hex 32)
supabase secrets set COURRIEL_EXPEDITEUR=ne-pas-repondre@globalservicegroupe.com
supabase secrets set COURRIEL_SUPPORT=contact@globalservicegroupe.com
supabase secrets set COURRIEL_ADMIN_GSG=<adresse(s) de l'équipe, séparées par des virgules>
supabase secrets set URL_APPLICATION=https://globalservicegroupe.com
supabase functions deploy envoyer_notifications
```

Premier essai sans rien envoyer : `supabase secrets set BREVO_BAC_A_SABLE=1`
(Brevo valide les messages et répond 201 sans les distribuer), puis
`supabase secrets unset BREVO_BAC_A_SABLE` pour passer en réel.

## Étape 4 — Planification (chaque minute)

Dans l'éditeur SQL Supabase (extensions `pg_cron` et `pg_net` activées),
en remplaçant `<ref>` et `<secret>` (le secret est rangé dans le coffre
Vault, pas en clair dans la tâche) :

```sql
select vault.create_secret('<secret>', 'notifications_declencheur_secret');

select cron.schedule('envoyer-notifications', '* * * * *', $$
  select net.http_post(
    url := 'https://<ref>.supabase.co/functions/v1/envoyer_notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-declencheur-secret', (select decrypted_secret from vault.decrypted_secrets
                               where name = 'notifications_declencheur_secret')),
    body := '{}'::jsonb);
$$);

select cron.schedule('purger-notifications', '15 3 * * *', $$ select public.purger_notifications(90); $$);
```

## Étape 5 — Courriels d'authentification Supabase via Brevo (recommandé)

Le serveur d'envoi intégré de Supabase est réservé aux essais (débit très
limité). Dans **Authentication → Emails → SMTP Settings** :

- hôte `smtp-relay.brevo.com`, port `587` ;
- identifiant et mot de passe : **Brevo → SMTP & API → onglet SMTP**
  (clé SMTP, distincte de la clé API) ;
- expéditeur `ne-pas-repondre@globalservicegroupe.com`, nom « EcoShop ».

## Supervision

```sql
select public.indicateurs_notifications();
-- {"a_envoyer":0,"en_cours":0,"envoyees_24h":12,"echecs_definitifs_7j":0,...}
```

`plus_ancienne_en_attente` ancienne de plus de quelques minutes = la
planification ou la clé Brevo est en panne.
