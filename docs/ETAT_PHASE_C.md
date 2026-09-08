# EcoShop — État de la Phase C, côté client Flutter (M13 → M15)

> Point de contrôle documentaire, pendant de `docs/ETAT_PHASE_A.md` pour la
> Phase C. Ce fichier dit ce qui est livré côté **client Flutter**, ce qui a
> été **vérifié par exécution**, et ce qui ne l'a pas été. Le périmètre SQL
> (migrations, RLS, seeds) est lui déjà livré et tracé dans
> `ANALYSE_GLOBALE.md` §4.4 — ce document ne le reconstruit pas.

## 1. Séquençage

Règle d'or : un module n'est ouvert qu'une fois le précédent 100 % clos.
Ordre effectivement suivi côté client Flutter : M8 → M9 → M10 → M11 →
M13/M15 (fusionnés, cf. §2) → **M14**. M12 (observabilité/déploiement) est un
socle technique sans surface Flutter dédiée ; il n'a donc pas ouvert de
module client.

## 2. M13 / M15 — Marketplace AssoShop (mono-vendeur + sans authentification)

Livré sur `m13-m15-marketplace-frontend`, fusionné dans `main`
(fast-forward, commit `8939c52`).

Écart de conception arbitré avec l'utilisateur en cours de module : le
périmètre M15 « accès marketplace sans authentification » a été reconsidéré
— toute action au-delà du choix d'espace exige un compte authentifié (OTP,
même mécanisme que le reste de l'app), sans imposer de rattachement
établissement (`GardeSession.resoudre` ne force la sélection d'établissement
que si l'acheteur en a plus d'un). Le panier reste un brouillon 100 % local
tant que l'identifiant d'établissement n'est pas connu, promu vers
`paniers`/`lignes_paniers` (tolérant hors-ligne) au checkout.

Vérification exécutée : `flutter analyze` 0 issue, `flutter test` 187/187 au
moment de la clôture.

## 3. M14 — Comptabilité sans OHADA

Livré sur `m14-comptabilite-sans-ohada-frontend`. Réutilise tel quel le SQL
déjà livré (`20260906001400_m14_comptabilite_sans_ohada.sql`) et les tests
pgTAP 31-33 déjà présents — aucune migration réécrite.

### 3.1 Écarts doc/DDL corrigés (`docs/contrats/M14_comptabilite.md`)

Le contrat divergeait du SQL réel sur plusieurs points (même discipline que
pour M9-M13 : le `.sql` fait foi, jamais le contrat) :

- `ecritures_comptables.compte_debit`/`compte_credit` documentés → colonnes
  réelles `compte_debit_id`/`compte_credit_id`.
- `reference` documentée, inexistante → colonnes réelles
  `piece_justificative`, `numero_lot`, `user_id` absentes du contrat.
- `balances.annee_scolaire_id`/`calcule_le` documentés, inexistants →
  colonnes réelles `date_balance` (unique avec `compte_id`) et `created_at`.

### 3.2 Livré côté client

- Plan comptable et journaux : configuration en ligne uniquement (comme les
  salles en M11) — CRUD direction.
- Saisie d'écriture (partie double) : tolérante hors-ligne via `sync_queue`
  (entité `ecritures_comptables`, seule table du module à porter
  `device_id`/`client_ts`), garde-fou mono-compte vérifié côté client puis
  rejoué par le trigger serveur `ecritures_verifie_tenant` en dernier
  recours.
- Documents : journal comptable, grand livre, balance (+ génération/archivage
  via `generer_balance`) — RPC en ligne uniquement, agrégats non cachés.
- Supervision IA (4 signaux, badgés « validation humaine requise », jamais
  de décision automatique) : anomalies, prévision de trésorerie à 30 jours,
  écritures récurrentes recommandées, tendances charges/produits sur 12 mois.
- Accès gaté au rôle Direction côté client (ergonomique — `est_comptable`/
  `est_comptable_ecriture` restent l'unique frontière de sécurité réelle).

### 3.3 Problème hérité identifié et sa mitigation côté client

Le DDL M14 ne porte **aucun mécanisme de verrouillage d'écriture ou de
clôture de période** : pas de colonne `verrouille`/`cloture_le`, pas de
trigger interdisant l'`UPDATE`/`DELETE` d'une écriture déjà saisie. Seule la
RLS `est_comptable_ecriture` borne qui peut écrire — rien n'empêche un
compte autorisé de modifier ou supprimer une écriture ancienne, ce qui est
un risque réel pour l'intégrité d'un grand livre en partie double.

Ce n'est pas un défaut du client Flutter à corriger localement : ajouter un
verrou supposerait une migration SQL supplémentaire, hors périmètre de ce
module (réutilisation stricte du DDL existant demandée) et non vérifiable
sur ce poste (§4). **Mitigation retenue côté client** : l'écran des
écritures (`EcranEcrituresRecentes`) n'expose aucune action de modification
ou de suppression d'une écriture postée — seule la création est possible.
Cela réduit le risque d'altération accidentelle via l'app, sans le
supprimer : un appel PostgREST direct (hors app) reste possible tant que la
RLS seule ne l'interdit pas. **Reste à faire, hors ce module** : une future
migration portant un verrou de période (ex. `cloture_exercice`) est à
replanifier, probablement avec le Port Paiement dans M16-M20.

### 3.4 Vérification exécutée

| Élément | Vérification |
|---|---|
| `flutter analyze` | ✅ exécuté — 0 issue |
| `flutter test` | ✅ exécuté — **202 tests** passent (dont 15 nouveaux pour M14 : JSON de domaine + repository cache/sync_queue) |
| Tests pgTAP 31-33 (RLS plans/journaux, écritures, fonctions/IA) | ✅ passent en CI (GitHub Actions, `supabase db reset`) — voir historique CI sur `main` |
| Tests pgTAP 31-33 rejoués **localement** sur ce poste | ❌ **non exécutés** (§4) |

## 4. Réserve technique — exécution locale des migrations (héritée de la Phase A)

`docs/ETAT_PHASE_A.md` notait : *« Aucun outil backend n'est installé sur ce
poste : ni `supabase` CLI, ni Docker, ni `psql`, ni `deno`. »* Ce n'est plus
tout à fait exact : à la date de clôture de M14, ce poste dispose de
**Supabase CLI v2.116.0** (`supabase --version`). En revanche :

```text
$ supabase status
{"error":{"code":"LegacyStatusDbInspectError",
  "message":"failed to inspect container health: docker: command not found
  (podman also not found) — install Docker Desktop or Podman and ensure it
  is on PATH"}}

$ supabase db reset
{"error":{"code":"LegacyLocalDbRunningError","message":"failed to inspect service"}}
```

**Ni Docker ni Podman ne sont installés** : `supabase start`/`db reset`
exigent un runtime de conteneurs pour la Postgres locale, absent de ce
poste. La CLI seule ne suffit pas à lever la réserve.

**Conséquence pour M14 précisément** — ce qui reste vérifié uniquement en
CI, jamais rejoué en local sur ce poste :

1. **Verrouillage/intégrité des écritures** : au-delà du garde-fou
   applicatif côté client (§3.3), aucune exécution locale n'a confirmé le
   comportement RLS/trigger sous conditions de concurrence réelles
   (écritures simultanées, transactions longues).
2. **Contraintes de partie double** (`ECRITURE_TENANT_INCOHERENT`,
   `ECRITURE_COMPTES_IDENTIQUES`) : vérifiées par pgTAP (test 32) en CI
   uniquement ; le comportement exact de Postgres local (versions, réglages)
   n'a pas été confirmé identique sur ce poste.
3. **RLS multi-tenant sur les comptes** (`plans_comptables`, `journaux`,
   `ecritures_comptables`, `balances`) : isolation vérifiée par pgTAP
   (test 31) en CI uniquement, jamais rejouée localement.

**Pour lever cette réserve** (dès qu'un runtime de conteneurs est
disponible sur ce poste ou un autre) :

```bash
# 1. Installer Docker Desktop ou Podman, puis :
supabase start
supabase db reset          # rejoue migrations + seed, y compris M14
supabase test db           # ou : rejouer manuellement tests/rls/31_*.sql à 33_*.sql via pgTAP
```

Tant que cette commande n'a pas été exécutée sur un poste équipé, la
garantie d'intégrité du grand livre M14 repose **uniquement** sur la CI
GitHub Actions — un socle réel mais externe à ce poste de développement.

## 5. Reste à faire

Module suivant en séquence stricte : **M16 — IA à rôles**, à condition que
le point de contrôle de fin de M14 (ce document + `ANALYSE_GLOBALE.md` §4.4)
soit positif et vérifiable — voir la réponse explicite dans le message de
clôture du module.
