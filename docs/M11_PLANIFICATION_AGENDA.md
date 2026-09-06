# M11 — Planification & Agenda

> Statut : **rédigé** · Branche : `m11-planification-agenda` · Migration :
> `20260906001100_m11_planification_agenda.sql`

## 1. Objectif

Gérer les agendas (enseignants, classes, élèves, direction), les emplois du
temps, la progression pédagogique et les contraintes de planification, avec des
signaux IA soumis à validation humaine et une synchronisation **hors-ligne
last-write-wins (LWW)**.

## 2. Périmètre fonctionnel

### 2.1 Agendas

- **Emplois du temps** : créneaux hebdomadaires récurrents (classe, enseignant,
  matière M4, salle, jour, heure) avec types (`cours`, `pause`, `activite`,
  `etude`, `examen`).
- **Événements d'agenda** : examens, réunions, conseils de classe, sorties,
  fêtes, avec heure, lieu, participants et **rappel** (lien M9). Complémentaire
  de `evenements_scolaires` (M7), qui porte l'impact sur la présence.
- **Progression pédagogique** : séances liées au programme (M4) et aux
  évaluations (M6), avec objectifs, contenu et statut.

### 2.2 Hors-ligne (LWW)

- **Cache** : l'agenda est consultable hors connexion (snapshot synchronisé).
- **Synchronisation LWW** : chaque table d'agenda porte `modifie_le` +
  `device_id` ; l'écriture la plus récente gagne, les suppressions sont
  tranchées par `deleted_at` + version. Cohérent avec la file Drift/`sync_queue`
  de M0.

### 2.3 RLS

- Emplois du temps et événements : lecture par le personnel **ou** par
  `classe_visible` (élève de la classe, parent de l'enfant) ; écriture réservée
  à `planification.generer`.
- Progression pédagogique : réservée au personnel.
- Contraintes : lecture personnel, écriture `planification.administrer`.

## 3. Modèle de données

| Table | Rôle |
|---|---|
| `salles` | Ressources physiques (code, nom, capacité) |
| `emplois_du_temps` | Créneaux hebdomadaires récurrents + champs LWW |
| `evenements_agenda` | Agenda opérationnel (réunions, conseils, examens, sorties) + rappel |
| `progression_pedagogique` | Séances de cours liées au programme M4 et aux évaluations M6 |
| `contraintes_emploi` | Indisponibilités, préférences, vacances |

## 4. Fonctions IA

| Fonction | Cas | Rôle |
|---|---|---|
| `suggerer_placement_seance(etab, annee, enseignant, classe, salle)` | Optimisation (CSP glouton) | Premier créneau libre commun, respectant indisponibilités |
| `detecter_conflits_emploi(etab, annee)` | Détection de conflits | Chevauchements salle/enseignant/classe |
| `charger_travail_enseignant(etab, annee, enseignant)` | Prédiction de charge | Heures hebdo vs volume contractuel (M5) |
| `charger_travail_eleve(classe)` | Prédiction de charge | Heures hebdo de la classe, seuil 35 h |
| `recommander_seances(etab, annee)` | Recommandation | Séance de rattrapage si réussite < 0.6 (M6) ou absentéisme > 0.2 (M7) |

Toutes sont `SECURITY DEFINER` ; gating par `est_personnel` (ou `classe_visible`
pour la charge élève) ; propositions **soumises à validation humaine**.

## 5. Permissions

`planification.consulter`, `planification.generer`,
`planification.administrer` (catalogue `permissions`).

## 6. Garde-fous multi-tenant

Cinq triggers vérifient la cohérence d'établissement des clés étrangères
(année, classe, salle, enseignant membre, évaluation) et l'appartenance de la
classe à l'année (`EMPLOI_*`, `EVENEMENT_*`, `PROGRESSION_*`, `CONTRAINTE_*`).

## 7. Éthique IA

L'IA **suggère**, le personnel **valide** : le placement de séance est une
proposition, les conflits sont signalés avec un créneau de remplacement, les
séances de rattrapage sont créées en statut `proposee` (jamais `planifiee`
d'office), les seuils de charge sont des alertes et non des décisions.

## 8. Plan de tests pgTAP

| Fichier | Couverture |
|---|---|
| `25_m11_emplois_visibilite.sql` | Visibilité des créneaux/événements (personnel / élève / parent / étranger) |
| `26_m11_ia_planification.sql` | Placement, conflits, charge, recommandation, contrôle d'accès |
| `27_m11_contraintes_ecriture.sql` | Permissions d'écriture (generer / administrer) |

## 9. Recherche comparative

Voir `docs/RECHERCHE_COMPARATIVE.md`, section 13 (benchmark agenda/planification
des LMS/SIS, contraintes ouest-africaines, IA CSP, hors-ligne LWW).
