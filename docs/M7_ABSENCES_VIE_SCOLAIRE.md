# M7 — Absences & Vie scolaire (spécifications)

> Module backend, périmètre DeepSeek. Livrable : DDL + RLS, seed, tests RLS,
> spécifications, stratégie hors-ligne et fonctions IA. Recherche consolidée
> dans `docs/RECHERCHE_COMPARATIVE.md` §9.

## 1. Objectif

Couvrir le pilotage de l'assiduité et du comportement : pointage des
présences/absences (demi-journée ou cours), retards justifiés ou non, sanctions
**éducatives**, alertes de décrochage multi-facteurs et calendrier des
événements — avec l'IA en trois niveaux (descriptif, prédictif, prescriptif),
toujours soumise à validation humaine.

## 2. Cas d'usage & flux

1. **Pointer** — l'enseignant affecté ou principal pointe sa classe (demi-journée
   ou cours), en ligne ou hors-ligne.
2. **Enregistrer un retard** — le personnel saisit retards et justifications.
3. **Justifier** — une absence/retard peut être justifié (certificat médical,
   motif familial) ; la justification bascule le compteur non justifié.
4. **Sanctionner (éducativement)** — la scolarité propose une sanction ; si elle
   provient de l'IA (`origine = 'ia'`), elle reste « proposee » tant qu'un
   humain ne l'a pas validée (`validee_par`).
5. **Alerter** — la fonction serveur `generer_alertes_decrochage` croise
   absences, retards et moyenne (M6) ; l'alerte est transmise à la famille puis
   traitée.
6. **Piloter** — tableaux de bord direction (analyse comportementale, taux de
   présence attendu).

## 3. Modèle de données

| Table | Rôle | Contraintes clés |
|---|---|---|
| `presences` | Pointage | unique (fiche, date) en demi-journée ; (fiche, date, matière) en cours |
| `retards` | Retards | unique (fiche, date), minutes > 0 |
| `sanctions` | Sanctions éducatives | `origine` (humaine/ia), `validee_par` requis pour activer une sanction IA |
| `alertes_decrochage` | Alertes multi-facteurs | score/seuil 0-1, une alerte ouverte/transmise par fiche+année |
| `evenements_scolaires` | Calendrier | `impact_presence` 0-1 pour la prédiction |

## 4. Spécifications techniques

- **Garde-fous multi-tenant** : `*_verifie_tenant` sur chaque table ;
  `presences_verifie_tenant` vérifie en plus classe ∈ année et élève inscrit.
- **Éthique IA** : `sanctions_verifie_validation` refuse d'activer une sanction
  d'origine IA sans `validee_par` — l'IA propose, l'humain décide.
- **RLS fine** : `presence_visible`/`retard_visible`/`sanction_visible`
  (personnel ou fiche visible), `alerte_visible` (personnel, ou élève/parent
  **une fois transmise**), `concerne_etablissement` pour les événements
  (personnel, membre, élève lié, parent d'élève lié). Écriture des présences via
  `peut_pointer` (affecté, principal, ou scolarité).
- **Permissions** : `scolarite.presence.gerer`, `scolarite.sanction.gerer`,
  `scolarite.evenement.gerer`.

## 5. IA — trois niveaux, human-in-the-loop

| Niveau | Fonction | Sortie |
|---|---|---|
| Descriptive | `analyse_comportement` | jsonb : absences justifiées/non, retards, moyenne minutes, sanctions actives |
| Prédictive | `calculer_score_decrochage` | score 0-1 (absences 50 %, retards 20 %, notes 30 %) |
| Prédictive | `predire_presence` | taux attendu (historique ajusté des événements) |
| Prescriptive | `recommander_sanction_educative` | jsonb non punitif (entretien famille/tutorat, suivi ponctualité, soutien) |
| Orchestration | `generer_alertes_decrochage` | crée les alertes (service_role / Edge Function) |

**Règle éthique** : aucune alerte n'est appliquée sans traitement humain ; les
sanctions IA restent « proposee » jusqu'à validation (`validee_par`). Le score
est transparent et auditable (pondérations documentées).

## 6. Stratégie de synchronisation hors-ligne

- **Pointage LWW** : `presences` et `retards` portent `device_id` + `client_ts` ;
  rejeu idempotent via la file `sync_queue` (M0), `ON CONFLICT` dernier-écrit-gagne.
- **Cohérence** : les agrégats (score de décrochage, taux de présence) sont
  **recalculés côté serveur**, jamais synchronisés.
- **Cache initial** : annuaire des classes affectées + calendrier des événements
  téléchargés avant déconnexion.

## 7. Plan de tests

- **pgTAP (RLS)** : `13_m7_presences_visibilite`, `14_m7_pointage_droits`,
  `15_m7_ia_fonctions` — visibilité, droits de pointage, alerte transmise,
  score/recommandation/prédiction exacts.
- **Unitaires (Dart)** : miroir du calcul de score, rejeu LWW des pointages.
- **Intégration (Edge Function, à livrer)** : `sync_push` des pointages
  hors-ligne ; `generer_alertes_decrochage` en cron.
- **Prérequis** : `supabase db reset` (M0→M7 + seeds) puis `pg_prove`.

## 8. Seeds — ordre d'exécution

M0 `seed.sql` → M4 → M5 → M6 → M7 (`seed_vie_scolaire.sql`), chacun s'appuyant
sur le précédent (mêmes clés naturelles : slug d'établissement, matricules,
téléphones des comptes).

## 9. État de vérification

- **Rédigé, relu, non exécuté** : pas de Postgres local ni Docker sur ce poste.
- La session Docker de validation (`db reset` + `pg_prove 01→15` + vérification
  seeds/helpers) est **maintenue en fin de sprint M7**, comme exigé.
