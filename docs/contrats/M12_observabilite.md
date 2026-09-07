# M12 — Intégration & Déploiement (Observabilité) — Contrat d'interface Flutter

> Migration : `supabase/migrations/20260906001200_m12_observabilite.sql`.
> Source de vérité : SQL + tests RLS associés.
> Périmètre : journal de métriques applicatives (collecte locale + rejeu), indicateurs de santé, prédiction de pics de charge.

## 1. Enums

Aucun. Les colonnes `metrique`, `source`, `niveau_charge` sont en `text` libre (valeurs conventionnelles : `niveau_charge` ∈ `critique|eleve|normal`).

## 2. Tables (DTOs)

### `public.journal_metriques`
| Colonne | Type | Contraintes |
|---|---|---|
| id | bigint | PK GENERATED ALWAYS AS IDENTITY |
| etablissement_id | uuid | FK → `etablissements(id)` ON DELETE CASCADE (nullable) |
| metrique | text | NOT NULL (ex. `latence_api`, `erreurs`, `saturation`) |
| valeur | numeric | nullable |
| contexte | jsonb | NOT NULL DEFAULT `'{}'` |
| source | text | nullable |
| created_at | timestamptz | NOT NULL DEFAULT now() |

Append-only côté client : aucune policy UPDATE/DELETE. Index : `(metrique)`, `(created_at)`, `(etablissement_id)`.

## 3. RPC client (security definer, `stable`)

- `indicateurs_sante_base() returns jsonb` — 6 clés APM (latence, erreurs, saturation, etc.) agrégées sur la fenêtre récente. Réservée aux rôles habilités (`observabilite.sante.lire`).
- `predire_pics_charge(p_etab uuid, p_annee uuid) returns table(...)` — prédiction de charge avec `niveau_charge` (`critique|eleve|normal`).

## 4. RLS

| Table | Commande | Règle |
|---|---|---|
| journal_metriques | SELECT | `est_admin_gsg()` OU permission `observabilite.metriques.lire` |
| journal_metriques | INSERT | client autorisé à journaliser (écriture métriques locale rejouée) |
| journal_metriques | UPDATE/DELETE | aucune policy (append-only) |

## 5. Conventions transverses

- Permissions seedées : `observabilite.metriques.lire`, `observabilite.sante.lire`, `observabilite.prediction.lire`.
- Collecte hors-ligne : le client journalise localement puis rejoue (`journal_metriques.created_at` = horodatage d'origine, pas d'insertion).
- RPC `stable` mais coûteuses : appel ponctuel (pull-to-refresh), pas de polling agressif.
- Helpers dépendants (définis ailleurs) : `est_admin_gsg()`, `est_appel_service()`, `est_membre_actif(uuid)`.
