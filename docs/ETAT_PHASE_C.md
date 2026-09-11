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
| Tests pgTAP 31-33 rejoués **localement** sur ce poste | ✅ **rejoués et confirmés le 2026-09-11** — 12/12 assertions passent (§4, mis à jour) |

## 4. Réserve technique — exécution locale des migrations (héritée de la Phase A) — RÉSOLUE le 2026-09-11

`docs/ETAT_PHASE_A.md` notait : *« Aucun outil backend n'est installé sur ce
poste : ni `supabase` CLI, ni Docker, ni `psql`, ni `deno`. »* Puis, à la
clôture de M14, ce poste disposait de la CLI mais ni Docker ni Podman
n'étaient installables (pas de droits administrateur, pas de WSL2) :

```text
$ supabase status
{"error":{"code":"LegacyStatusDbInspectError",
  "message":"failed to inspect container health: docker: command not found
  (podman also not found) — install Docker Desktop or Podman and ensure it
  is on PATH"}}
```

**Résolu le 2026-09-11** : Docker Desktop reste bloqué sur ce poste (son
installeur exige une élévation UAC interactive, impossible en session
automatisée — échec confirmé, code de sortie `4294967291`), mais **Podman
CLI 5.8.3 s'installe et fonctionne sans élévation**, et `podman machine
start` (backend WSL2) a été rendu fonctionnel sur ce poste — voir
`ANALYSE_GLOBALE.md`/mémoire de session pour le détail des tentatives. Avec
Podman sur le `PATH`, `supabase start` / `supabase db reset` /
`supabase test db --local tests/rls` s'exécutent normalement en local.

**Exécution réelle du 2026-09-11** (pas seulement CI) :

```text
$ supabase db reset
[...19 migrations appliquées...]
Finished supabase db reset on branch main.

$ supabase test db --local tests/rls
tests/rls/31_m14_plans_journaux.sql .................. ok
tests/rls/32_m14_ecritures.sql ....................... ok
tests/rls/33_m14_fonctions_comptables.sql ............ ok
[... 35 autres fichiers, tous ok ...]
All tests successful.
```

**Pour M14 précisément : les 12 assertions des tests 31-33 (verrouillage/
intégrité des écritures, contraintes de partie double, isolation RLS
multi-tenant sur `plans_comptables`/`journaux`/`ecritures_comptables`/
`balances`) sont désormais confirmées indépendamment sur une instance
Postgres locale réelle, pas seulement en CI.** Aucun défaut trouvé côté M14.

Pour reproduire sur un autre poste :

```bash
winget install --id RedHat.Podman   # pas Docker Desktop (exige admin)
podman machine init && podman machine start
supabase start
supabase db reset
supabase test db --local tests/rls
```

## 4bis. Addendum — M15quater : première exécution locale réelle, deux défauts trouvés et corrigés (2026-09-11)

Ce document couvre nominalement M13→M15 ; cet addendum documente M15quater
(module suivant, cf. `docs/contrats/M15quater_inscription_encaissement.md`)
parce que c'est le déblocage de l'outillage local ci-dessus (§4) qui a rendu
possible sa découverte — et parce que l'historique complet, pas seulement
la conclusion, est la preuve que cette vérification a servi à quelque
chose.

**Constat de départ** : `main` local avait alors 13 commits d'avance sur
`origin/main`, jamais poussés (règle du projet : pas de push sans accord
explicit). La CI GitHub Actions n'avait donc **jamais exécuté** M15quater
ni son test pgTAP (`tests/rls/38_m15quater_inscription_encaissement.sql`).
« CI verte » n'a jamais été vrai pour ce module — c'était sa toute première
exécution réelle, nulle part.

**Échec initial** (`supabase test db --local tests/rls`, avant tout
correctif) :

```text
# Failed test 9: "statut boursier : boursier_modifie_par enregistré automatiquement"
#         have: NULL
#         want: f6452be7-0b92-4b59-909e-4b13c11e43d3
# Failed test 10: "statut boursier : boursier_modifie_le enregistré automatiquement"
ERROR:  new row violates row-level security policy for table "encaissements_scolarite"
Parse errors: Bad plan.  You planned 25 tests but ran 13.
Result: FAIL
```
13 assertions exécutées sur 25 planifiées, 2 échecs explicites puis arrêt
sur erreur RLS bloquante.

**Cause racine 1 — bascule boursier bloquée pour une direction sans poste
RH.** La policy UPDATE de `inscriptions` (`inscriptions_ecriture_scolarite`,
héritée de M5) n'autorisait que
`a_permission(etablissement_id, 'scolarite.inscription.gerer')` — sans le
repli `est_direction(etablissement_id)` que portent pourtant les RPC
`creer_inscription_nouvel_eleve`/`creer_reinscription`. Un compte direction
sans poste RH explicite ne pouvait donc pas faire
`UPDATE inscriptions SET boursier = ...` : `UPDATE 0`, sans erreur, échec
silencieux (confirmé par test isolé : `est_direction()` renvoyait pourtant
`true`).

**Cause racine 2 — `INSERT ... RETURNING` sur `encaissements_scolarite`
cassé pour tout le monde.** La policy SELECT `encaissements_select_visible`
s'appuyait sur `encaissement_visible(id)`, une fonction qui **re-interroge
`encaissements_scolarite` par id** — cette relecture auto-référentielle ne
voit pas la ligne tout juste insérée au moment où Postgres vérifie
implicitement la policy SELECT pour construire le résultat de `RETURNING`
(confirmé par test manuel isolé, transaction annulée : le même `INSERT`
sans `RETURNING` réussit ; remplacer la policy par la forme inline
`est_personnel(etablissement_id) OR fiche_visible(fiche_eleve_id)` fait
réussir `RETURNING`). **C'est le chemin de code réel de l'app** —
`SupabaseScolariteRepository.enregistrerEncaissement()` fait
`.insert(...).select().single()` — un vrai encaissement saisi dans l'app
aurait échoué de la même façon, pour n'importe quel utilisateur, direction
comprise. Défaut bloquant, pas un simple cas limite de permissions.

**Recherche systémique** (même anti-pattern — policy SELECT basée sur une
fonction `xxx_visible(id)` auto-référentielle — combiné à un
`.insert(...).select()` client réel) : trouvé également sur `notifications`
(M9), `sanctions` (M7), `evaluations` (M6), `contrats` (M8) ; et, sans
exposition client actuelle (aucun code Flutter n'appelle encore
`groupes_discussion`/`messages_groupe`), sur `groupes_discussion` (M9-patch).
**Signalé ici, volontairement non corrigé dans ce patch** — portée limitée
à M15quater le 2026-09-11 ; à traiter dans un patch dédié après décision du
porteur de projet.

**Défaut annexe trouvé en poussant le test plus loin** : la fixture de test
liant un parent à un élève (§8c du test 38) s'exécutait par erreur avec les
claims JWT d'un tiers non affilié (reliquat de l'assertion précédente),
révélant que `relations_verifie_tenant()` (M5) n'est pas `SECURITY
DEFINER` — comme la majorité des triggers `*_verifie_tenant` du projet,
seuls M9-patch et M15quater dérogent avec justification explicite — donc
son lookup RLS-filtré renvoie `FICHE_AUTRE_ETABLISSEMENT` au lieu d'un
refus propre pour un acteur sans visibilité. Corrigé comme **bug de test**
(remise à `RESET ROLE` pour cette fixture, même précédent que
`frais_scolarite_config` en §7) — pas un défaut applicatif : en usage réel,
cet INSERT brut sur `relations_parent_eleve` est fait par un acteur qui a
déjà la permission `scolarite.relation.gerer` (également sans repli
`est_direction()`, même famille de défaut que la cause racine 1 — signalé,
non corrigé, même portée que ci-dessus).

**Correctif appliqué** : migration
`supabase/migrations/20260906001502_m15quater_patch_rls_boursier_encaissement.sql`
(policy `inscriptions_ecriture_scolarite` avec repli `est_direction()` ;
policy `encaissements_select_visible` sous forme inline). Test 38 renforcé
avec 2 assertions de non-régression explicites (précondition « ce compte
direction n'a aucun poste RH ») — plan porté de 25 à **27**.

**Confirmation finale** (`supabase test db --local tests/rls`, après
correctifs) :

```text
tests/rls/31_m14_plans_journaux.sql .................. ok
tests/rls/32_m14_ecritures.sql ....................... ok
tests/rls/33_m14_fonctions_comptables.sql ............ ok
[...]
tests/rls/38_m15quater_inscription_encaissement.sql .. ok
All tests successful.
Files=38, Tests=206, Result: PASS
```
**27/27 pour le test 38, et les 37 autres fichiers (dont 31-33) toujours
tous verts** — les deux correctifs n'ont rien cassé ailleurs.

**Reste ouvert, hors périmètre de ce patch** : le même anti-pattern
auto-référentiel sur `notifications`/`sanctions`/`evaluations`/`contrats`
(et `groupes_discussion`, non exposé), ainsi que l'absence de repli
`est_direction()` sur `relations_parent_eleve`. Le point de contrôle
M15quater proprement dit (rapport d'écart fonctionnel, etc.) reste à
statuer séparément.

## 5. Reste à faire

Module suivant en séquence stricte : **M16 — IA à rôles**, à condition que
le point de contrôle de fin de M14 (ce document + `ANALYSE_GLOBALE.md` §4.4)
soit positif et vérifiable — voir la réponse explicite dans le message de
clôture du module.
