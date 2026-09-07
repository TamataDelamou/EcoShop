# M14 — Comptabilité sans OHADA

Module d'enrichissement comptable : documents fondamentaux (Journal, Grand
Livre, Balance, livres de banque/caisse) sur une **structure ouverte** — aucun
plan OHADA imposé, l'utilisateur crée ses propres comptes.

## 1. Principes

- **Partie double** : chaque écriture = un débit + un crédit de montants égaux.
- **Structure ouverte** : `plans_comptables.type` est libre (`actif`, `passif`,
  `capitaux`, `produit`, `charge`, `banque`, `caisse`, `autre`…) ; seuls des
  comptes de base sont prédéfinis au seed.
- **États générés à la demande** : Journal, Grand Livre et Balance sont calculés
  par fonctions, jamais stockés (seule la balance est « snapshotée » pour
  l'export/le cache).

## 2. Modèle de données

| Table | Rôle |
|---|---|
| `plans_comptables` | Comptes (code, intitulé, type, parent) — arborescence ouverte |
| `journaux` | Livres chronologiques (opérations, banque, caisse) |
| `ecritures_comptables` | Écritures (débit/crédit, montant, pièce, journal, user, hors-ligne) |
| `balances` | Snapshots de balance (solde débit/crédit) à une date |

## 3. Garde-fous

- `plans_comptables_verifie_parent` : le parent d'un compte appartient au même établissement.
- `ecritures_verifie_tenant` : comptes débit/crédit et journal du même établissement ; débit ≠ crédit.

## 4. Fonctions

| Fonction | Rôle |
|---|---|
| `journal_comptable(etab, journal, début, fin)` | Enregistrements chronologiques d'un journal |
| `grand_livre(etab, compte, début, fin)` | Mouvements débit/crédit d'un compte |
| `balance_comptable(etab, date)` | Soldes par compte (total débit/crédit, solde) |
| `generer_balance(etab, date)` | Snapshot de balance dans `balances` |
| `exporter_journal_json(…)` | Export JSON prêt pour Excel/PDF (Edge Function) |

## 5. IA (supervision, jamais de décision automatique)

| Fonction | Rôle |
|---|---|
| `detecter_anomalies_comptables(etab)` | Montants élevés, doubles saisies |
| `predire_tresorerie(etab, jours)` | Projection de trésorerie (méthode directe, comptes banque/caisse) |
| `recommander_ecritures(etab)` | Écritures récurrentes (≥ 2 mois distincts) |
| `analyser_tendances(etab, mois)` | Évolution charges/produits par mois |

## 6. RLS

- Isolation stricte par établissement.
- Lecture : `est_comptable(etab)` = direction, ou permission `comptabilite.lire`, ou admin/service.
- Écriture : `est_comptable_ecriture(etab)` = direction, ou permission `comptabilite.ecrire`, ou admin/service.

## 7. Hors-ligne

- Saisie d'écritures en cache (Drift/`sync_queue`) avec résolution **LWW**
  (`client_ts` + `device_id`).
- Les totaux (balance, grand livre) ne sont jamais synchronisés, toujours
  recalculés côté serveur.

## 8. Livrables

| Livrable | Chemin |
|---|---|
| DDL | `supabase/migrations/20260906001400_m14_comptabilite_sans_ohada.sql` |
| Seed | `supabase/seed_comptabilite.sql` |
| Tests RLS | `tests/rls/31_m14_plans_journaux.sql`, `32_m14_ecritures.sql`, `33_m14_fonctions_comptables.sql` |
| Recherche comparative §16 | `docs/RECHERCHE_COMPARATIVE.md` |

## 9. Export Excel/PDF

Les fonctions retournent des ensembles de lignes ; la mise en forme
Excel/PDF est réalisée côté client ou par une Edge Function (à livrer en M14
complément ou M20 reporting), à partir de `exporter_journal_json(...)`.
