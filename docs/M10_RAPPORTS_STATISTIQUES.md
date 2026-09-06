# M10 — Rapports & Statistiques académiques

> Statut : **rédigé** · Branche : `m10-rapports-statistiques` · Migration :
> `20260906001000_m10_rapports_statistiques.sql`

## 1. Objectif

Consolider les données des modules M6→M9 en **tableaux de bord, exports et
signaux IA** à destination de quatre publics : direction, enseignants, parents
et élèves. Le module est pensé pour la **faible connectivité** (rapports en
cache, génération différée) et la **décision assistée, jamais automatisée**.

## 2. Périmètre fonctionnel

### 2.1 Consolidation (descriptif)

| Source | Indicateurs dérivés |
|---|---|
| M6 — Notes & Évaluations | taux de réussite, moyennes, répartitions, tendances |
| M7 — Absences & Vie scolaire | absentéisme, retards, sanctions, alertes décrochage |
| M8 — RH & Personnel | effectifs, turn-over, congés, masse salariale |
| M9 — Communication | taux d'ouverture, engagement parents |

### 2.2 Tableaux de bord

- **Direction** : effectifs, taux de réussite, absentéisme, turn-over, masse
  salariale, engagement parents (KPI `indicateurs_cles`).
- **Enseignants** : suivi des classes, performances, absences.
- **Parents** : suivi individuel de l'élève (notes, absences, alertes) — via
  les rapports individuels (`rapports.fiche_eleve_id`).
- **Élèves** : progression personnelle, prédiction de réussite.

### 2.3 Exports

- Bulletins scolaires (PDF) — snapshot signé déjà porté par M6 (`bulletins`).
- Relevés de notes par classe/période (PDF, Excel).
- Statistiques globales (CSV, JSON).
- Rapports personnalisables : filtres, périodes, groupes (`rapports.filtres`).

### 2.4 Hors-ligne

- Génération **différée** : une demande (`statut = demande`) est traitée côté
  serveur puis consultée (`genere`) ; la file d'attente client (Drift +
  `sync_queue` de M0) porte la demande.
- **Cache** : `cache_valide_jus` fixe la durée de validité du rapport en cache
  local ; `demande_hors_ligne` marque une génération demandée hors connexion.

## 3. Modèle de données

| Table | Rôle |
|---|---|
| `rapports` | Demandes de génération (bulletin, relevé, stats, personnalisé, résumé exécutif) avec format, filtres, statut différé et cache |
| `indicateurs_cles` | KPI pré-calculés (effectifs, taux_reussite, absentisme, turnover, masse_salariale, engagement_parents) |
| `anomalies_statistiques` | Données aberrantes détectées (notes, absences) à validation humaine |
| `recommandations_strategiques` | Actions correctives proposées par l'IA, validées par un humain |

## 4. Fonctions IA

| Fonction | Niveau | Rôle |
|---|---|---|
| `consolider_indicateurs_etablissement(etab, annee)` | Descriptif | Calcule les 6 KPI (upsert idempotent) |
| `detecter_anomalies(etab, annee)` | Prédictif | Notes à +2 écarts-types et absentéisme individuel > 30 % |
| `risque_classe(classe)` | Prédictif | Score pondéré `0.5·absentéisme + 0.3·(1−réussite) + 0.2·alertes` |
| `recommander_actions(etab, annee)` | Prescriptif | Renforcement / tutorat selon le niveau de risque |
| `generer_resume_executif(etab, annee)` | Prescriptif (NLG) | Résumé exécutif en langage naturel, traçable |

Toutes les fonctions sont `SECURITY DEFINER`, gated par `est_personnel(etab)` et
accessibles au rôle `authenticated` (grants).

## 5. RLS & permissions

- Lecture des rapports : personnel, ou `fiche_visible` pour un rapport
  individuel (élève lié / parent confirmé).
- Lecture des KPI, anomalies et recommandations : personnel uniquement.
- Génération (insert rapports, lancement d'analyses) : permission
  `rapports.generer`.
- Administration (validation des anomalies/recommandations, suppression) :
  permission `rapports.administrer`.

Trois permissions ajoutées au catalogue : `rapports.consulter`,
`rapports.generer`, `rapports.administrer`.

## 6. Garde-fous multi-tenant

Quatre triggers vérifient que l'établissement des clés étrangères (année,
classe, fiche, employé) coïncide toujours avec `etablissement_id`
(`RAPPORT_*_AUTRE_ETABLISSEMENT`, etc.).

## 7. Éthique IA

- Les indicateurs et résumés sont des **aides à la décision**, jamais des
  décisions automatisées.
- Les anomalies sont **signalées** (statut `ouverte`) sans correction
  automatique ; elles sont traitées (`confirmee` / `rejetee` / `traitee`) par
  un humain.
- Les recommandations sont proposées (`proposee`) puis validées (`validee`)
  avant mise en œuvre.
- Le résumé exécutif est une NLG structurée (contenu → agrégation →
  réalisation) : aucune assertion non traçable aux données.

## 8. Plan de tests pgTAP

| Fichier | Couverture |
|---|---|
| `22_m10_rapports_visibilite.sql` | Visibilité des rapports (personnel / parent / élève / étranger) et KPI réservés au personnel |
| `23_m10_ia_fonctions.sql` | Consolidation (6 KPI), détection d'anomalies, risque classe, recommandations, résumé NLG, contrôle d'accès |
| `24_m10_anomalies_validation.sql` | Validation humaine des anomalies et recommandations (permission d'administration) |

## 9. Recherche comparative

Voir `docs/RECHERCHE_COMPARATIVE.md`, section 12 (benchmark BI des SIS,
tableaux de bord ouest-africains, exports, IA académique).
