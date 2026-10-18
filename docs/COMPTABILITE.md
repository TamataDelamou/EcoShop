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

## 10. Référentiel au choix de l'établissement (REG-03, lot C1)

Depuis le 2026-10-17, le plan ouvert décrit ci-dessus n'est plus que le
référentiel **simplifié**. L'établissement choisit (menu Comptabilité >
Référentiel comptable) entre :

| Référentiel | Plan de comptes |
|---|---|
| Simplifié | Ouvert (ce document, §1-9) |
| SYSCOHADA — Système minimal de trésorerie | Plan SYSCOHADA révisé, verrouillé |
| SYSCOHADA — Système normal | Plan SYSCOHADA révisé, verrouillé |
| SYCEBNL | Plan des entités à but non lucratif, verrouillé |

Détails, sources et réserves : `docs/propositions/REG-03_COMPTABILITE.md`,
`docs/REGISTRE.md` (REG-03) et la migration `20260906001534_referentiel_comptable.sql`.
Les plans de référence doivent être relus par un expert-comptable inscrit
en Guinée avant la mise en production.

## 11. Pièces, validation et clôtures (REG-03, lot C2)

Saisie par **pièces à plusieurs lignes** (brouillard → validée), numérotation
continue à la validation, irréversibilité, correction par contre-passation en
négatif, exercices et clôtures (période, exercice, à-nouveaux). Obligatoire en
référentiel OHADA ; disponible aussi en simplifié, où l'écriture rapide à deux
comptes reste possible hors période clôturée. Détail : `docs/REGISTRE.md`
(REG-03) et `supabase/migrations/20260906001535_pieces_exercices_clotures.sql`.

## 12. Paie en comptabilité (REG-03, lot C5)

Chaque bulletin de paie validé produit sa pièce de constatation (charges de
personnel / salaires dus / retenues), chaque bulletin payé sa pièce de
règlement (salaires dus / trésorerie), dans le journal PAIE. Toute
modification ultérieure du bulletin est reportée par contre-passation puis
nouvelle pièce. Détail : `docs/REGISTRE.md` (REG-03) et
`supabase/migrations/20260906001538_paie_comptabilisation.sql`.

## 13. Dons et donateurs (REG-03, lot C5)

Registre des donateurs, dons avec reçus numérotés par année, campagnes et
projets à fonds affectés, engagements de parrainage, synthèse annuelle et
relances. Chaque don est comptabilisé automatiquement (SYCEBNL : 704x selon
la nature, 165 pour un projet, 7925 à l'emploi des fonds). Détail :
`docs/REGISTRE.md` (REG-03) et
`supabase/migrations/20260906001540_registre_donateurs.sql`.

## 14. Tableau des flux de trésorerie et notes annexes (REG-03, lot C5)

TFT au modèle du référentiel (SYSCOHADA : méthode indirecte ZA à ZH ;
SYCEBNL : méthode directe ZA à ZG ; simplifié), chaque mouvement de
trésorerie étant classé selon la contrepartie de sa pièce, avec contrôle
« trésorerie de clôture = bilan ». Notes annexes calculées et notes rédigées
par l'école, jointes au PDF des états financiers. Détail :
`docs/REGISTRE.md` (REG-03) et
`supabase/migrations/20260906001541_flux_tresorerie_notes_annexes.sql`.

## 15. Changement de plan avec historique (REG-03, lot C6)

Un établissement qui a déjà des écritures change de référentiel au premier
jour d'un exercice, au moyen d'une table de correspondance relue par la
Direction. Les pièces ne sont jamais modifiées : l'historique est lu dans
le nouveau plan (N-1 comparable) et les états publiés à l'origine sont
archivés. Détail : `docs/REGISTRE.md` (REG-03) et
`supabase/migrations/20260906001542_changement_plan_historique.sql`.
