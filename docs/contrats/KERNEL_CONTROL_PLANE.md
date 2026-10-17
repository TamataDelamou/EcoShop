# Contrat EcoShop ↔ Kernel GSG — Control Plane (KER-MUT)

**Statut** : proposition d'EcoShop, implémentée côté EcoShop le 2026-10-17,
**à valider et implémenter côté Kernel**. Registre : `docs/REGISTRE.md`
REG-01. Toute divergence décidée côté Kernel (chemins, noms de champs) se
corrige dans `supabase/functions/kernel-export` et `kernel-control-plane`
sans toucher au schéma.

## 1. Rôles

| Sens | Qui appelle | Pour quoi | Mécanisme |
|---|---|---|---|
| Poussée | EcoShop → Kernel | Journaux d'audit, métriques techniques, instantané des métriques clés | `kernel-export`, lancé par planification |
| Lecture | Kernel → EcoShop | Tableau de bord central : santé, métriques, audit à la demande | `kernel-control-plane`, lecture seule |

Le Kernel **ne fournit plus** ni identité, ni sessions, ni référentiels à
EcoShop, et n'a **aucun accès en écriture** à EcoShop.

## 2. Sécurité : jetons inter-services

JWT **ES256** (ECDSA P-256), asymétriques des deux côtés — aucun secret
partagé entre les deux systèmes.

| | EcoShop → Kernel | Kernel → EcoShop |
|---|---|---|
| Signé par | clé privée EcoShop | clé privée Kernel |
| Vérifié avec | `GET {ecoshop}/functions/v1/kernel-control-plane/jwks.json` | JWKS du Kernel (`GSG_KERNEL_JWKS_URL`) |
| `iss` | `ecoshop` | valeur de `GSG_KERNEL_ISSUER` |
| `aud` | `gsg-kernel` | `ecoshop` |
| `scope` | `kernel:ingestion` | doit contenir `ecoshop:lecture` |
| Durée de vie | 60 s | ≤ 300 s (au-delà : refus `JETON_TROP_LONG`) |
| Claims obligatoires | `iat`, `exp`, `nbf`, `jti`, `sub` | `iat`, `exp`, `jti` |
| En-tête | `kid` présent | `kid` recommandé |

mTLS écarté : les Edge Functions Supabase ne terminent pas le TLS et
n'exposent pas le certificat client.

Rotation : EcoShop publie sa clé avec un `kid` daté
(`supabase/scripts/generer_cle_interservices.ts`). Le Kernel doit mettre en
cache le JWKS (5 min, `Cache-Control` fourni) et le recharger sur `kid`
inconnu.

## 3. Poussée EcoShop → Kernel (endpoints à fournir par le Kernel)

Base : `GSG_KERNEL_AGGREGATION_URL`. Tous en `POST`, `Content-Type:
application/json`, `Authorization: Bearer <jeton EcoShop>`,
`Idempotency-Key: <sha256 hex>`.

| Chemin | Corps |
|---|---|
| `/v1/aggregation/produits/ecoshop/audit-logs` | `{ produit, flux: "audit", lot_id, apres, lignes: LigneAudit[] }` |
| `/v1/aggregation/produits/ecoshop/metrics` | `{ produit, flux: "metriques", lot_id, apres, lignes: LigneMetrique[] }` |
| `/v1/aggregation/produits/ecoshop/snapshots` | `MetriquesCles` (§5) |

Réponse attendue : **2xx = lot acquitté** (le curseur EcoShop avance). Tout
autre statut ou délai dépassé : le même lot est renvoyé au passage suivant,
**avec la même `Idempotency-Key`**. Livraison « au moins une fois » : le
Kernel **doit** dédoublonner sur `Idempotency-Key` (lot) ou sur `id` (ligne).

`LigneAudit` — **minimisée** (aucune valeur avant/après, aucun identifiant
d'élève ni de groupe) :

```json
{ "id": "uuid", "horodatage": "2026-10-17T02:30:00.123456Z",
  "etablissement_id": "uuid|null", "entite": "sanction", "entite_id": "uuid",
  "champ": "statut", "auteur_id": "uuid|null", "origine": "utilisateur|service" }
```

`LigneMetrique` :

```json
{ "id": "123", "horodatage": "…Z", "etablissement_id": "uuid|null",
  "metrique": "latence_ms", "valeur": 412, "source": "client", "contexte": {} }
```

Ordre garanti dans un lot : `(horodatage, id)` croissant. Seules les lignes de
plus de 2 minutes sont exportées (cohérence transactionnelle).

## 4. Lecture Kernel → EcoShop

Base : `{SUPABASE_URL}/functions/v1/kernel-control-plane`. Tous en `GET`.

| Route | Jeton | Réponse |
|---|---|---|
| `/jwks.json` | aucun | `{ keys: [JWK public EcoShop] }` |
| `/sante` | requis | `{ success, produit, sante }` (taille base, connexions, uptime) |
| `/metriques` | requis | `{ success, metriques: MetriquesCles }` |
| `/audit?apres_horodatage=&apres_id=&limite=` | requis | `{ success, lignes: LigneAudit[], suivant }` |
| `/metriques-techniques?…` | requis | `{ success, lignes: LigneMetrique[], suivant }` |

`limite` ≤ 1000 (500 par défaut). `suivant` se repasse tel quel pour la page
suivante ; `null` = fin. Erreurs : `401 AUTH_REQUISE | JETON_INVALIDE |
JETON_TROP_LONG`, `403 SCOPE_INSUFFISANT`, `503 NON_CONFIGURE`.

## 5. `MetriquesCles`

Agrégats uniquement, montants **jamais additionnés entre devises** :

```json
{ "produit": "ecoshop", "collecte_le": "…Z",
  "etablissements_actifs": 12, "comptes_actifs": 3400,
  "comptes_par_role": { "eleve": 2900, "parent": 400, "…": 0 },
  "inscriptions_annee_courante": 2800,
  "encaissements_scolarite_30j": { "GNF": { "nombre": 310, "montant": 95000000 } },
  "transactions_paiement_30j": { "reussi": 40, "echoue": 3 },
  "commandes_marketplace_30j": { "payee": 22, "livree": 18 },
  "sante_base": { "…": "…" },
  "export": { "audit": { "lignes_exportees": 0, "derniere_reussite": null, "derniere_erreur": null } } }
```

## 6. Planification de l'export (côté EcoShop)

Appel `POST {SUPABASE_URL}/functions/v1/kernel-export` avec l'en-tête
`x-declencheur-secret: <KERNEL_EXPORT_DECLENCHEUR_SECRET>`, toutes les
5 minutes recommandé (pg_cron + pg_net, ou planificateur externe). Le mode
de planification retenu en production est à configurer au déploiement.

## 7. Points ouverts

1. Le Kernel doit-il recevoir davantage que les journaux d'audit minimisés
   (valeurs avant/après) ? Défaut retenu : **non** (protection des mineurs).
2. Chemins exacts des endpoints d'agrégation à confirmer côté Kernel.
3. Rétention des données reçues côté Kernel à définir.
