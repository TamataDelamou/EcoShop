# M6 — Notes & Évaluations (spécifications)

> Module backend, périmètre DeepSeek. Livrable : DDL + RLS, seed, tests RLS,
> spécifications fonctionnelles/techniques, stratégie hors-ligne et pistes IA.
> Recherche consolidée dans `docs/RECHERCHE_COMPARATIVE.md`.

## 1. Objectif

Couvrir le cycle complet de la note : évaluations (devoirs, contrôles,
compositions), saisie des notes (avec ou sans connexion), calcul des moyennes,
bulletins et tableaux de bord, adossés au référentiel M4 et aux structures M5.

## 2. Cas d'usage & flux

1. **Préparer une évaluation** — un enseignant affecté (M5) crée une évaluation
   pour sa classe, avec coefficient, barème et matière (M4) optionnelle.
2. **Saisir les notes** — l'enseignant saisit en ligne ou **hors-ligne** (cache
   Drift) ; la synchronisation différée rejoue les écritures avec résolution
   LWW (voir §6).
3. **Publier/clôturer** — la publication rend les notes visibles aux élèves et
   parents ; la clôture verrouille toute modification.
4. **Consulter** — l'élève voit ses notes, le parent celles de son enfant lié
   (M5), la direction l'ensemble de l'établissement.
5. **Bulletins** — la scolarité génère un bulletin (snapshot signé) par élève et
   période ; publication contrôlée.
6. **Tableaux de bord & signaux IA** — agrégats pré-calculés (moyennes, rangs,
   risque, anomalies, recommandations) ; aides à la décision, jamais bloquants.

## 3. Modèle de données

| Table | Rôle | Contraintes clés |
|---|---|---|
| `evaluations` | Unité de notation | coefficient > 0, barème > 0, statut (brouillon/publiee/cloturee) |
| `notes` | Score d'un élève | unique (évaluation, fiche), absent ⟺ valeur nulle |
| `appreciations` | Commentaires (générale/matière/conseil) | champs NLP `ton`, `points_forts`, `points_faibles` |
| `bulletins` | Snapshot signé (période/annuel) | unique partiel par fiche+période+type |
| `statistiques_agregats` | Agrégats + signaux IA | `type_agregat` (moyenne, rang, risque, anomalie, recommandation) |

## 4. Spécifications techniques

- **Garde-fous multi-tenant** : trigger `*_verifie_tenant` sur chaque table
  (cohérence année/période/classe/fiche/matière ↔ établissement), sur le modèle
  M1/M5. `notes_verifie_tenant` vérifie en plus que l'élève est bien inscrit à
  la classe de l'évaluation et que la note ne dépasse pas le barème.
- **RLS fine** : `evaluation_visible`, `note_visible`, `appreciation_visible`,
  `bulletin_visible` (helpers SECURITY DEFINER, sans récursion) ; écriture des
  évaluations par l'enseignant **affecté** (`est_enseignant_affecte`) ou la
  scolarité ; saisie des notes par l'auteur ou la permission `scolarite.note.gerer`.
- **Calculs serveur** : `calculer_moyenne_eleve` (moyenne pondérée ramenée sur
  20) et `calculer_moyenne_classe` — les moyennes ne sont **jamais** calculées
  ni synchronisées côté client, ce qui élimine les conflits d'agrégats.
- **Permissions** : `scolarite.evaluation.gerer`, `scolarite.note.gerer`,
  `scolarite.appreciation.gerer`, `scolarite.bulletin.gerer`.

## 5. Stratégie de synchronisation hors-ligne

- **Registre Last-Write-Wins par champ** (inspiré CRDT, cf. recherche §6) :
  chaque note porte `device_id` + `client_ts` ; le rejeu est idempotent via
  `ON CONFLICT (evaluation_id, fiche_eleve_id) DO UPDATE ... WHERE
  excluded.client_ts > notes.client_ts`.
- **File de synchro** : `sync_queue` (M0) journalise chaque opération hors-ligne
  (INSERT/UPDATE de note) ; l'Edge Function `sync_push` (à livrer) rejoue dans
  l'ordre causal.
- **Conflits** : modification concurrente → dernier `client_ts` gagne ;
  suppression → tombstone `deleted_at` ; moyennes/bulletins → recalcul serveur
  exclusif.
- **Téléchargement initial** : grilles d'évaluation + annuaire des classes
  affectées (M5) mis en cache Drift avant déconnexion.

## 6. Pistes IA (documentées, sobres, off-line d'abord)

| Cas d'usage | Données | Implémentation cible |
|---|---|---|
| Prédiction de réussite | historique `notes`/`evaluations` | Edge Function (régression/forêt légère), résultat dans `statistiques_agregats` (`risque_reussite`) |
| Détection d'anomalies | séries de notes | règles SQL (z-score/IQR) sur agrégats (`anomalie_note`) |
| Recommandation de contenus | lacunes ↔ compétences M4 | Edge Function, résultat `recommandation_contenu` (jsonb) |
| NLP des appréciations | `appreciations.texte` | on-device (ML Kit/TF Lite) pour `ton`/`points_forts`/`points_faibles` |

**Principe** : trois tiers — (1) SQL/Postgres pour les statistiques
transparentes, (2) Edge Function pour les modèles légers en lot, (3) on-device
pour le NLP hors-ligne. Aucune décision automatique bloquante (redoublement,
exclusion) : les signaux IA sont des aides à la décision.

## 7. Plan de tests

- **pgTAP (RLS)** : `10_m6_notes_visibilite`, `11_m6_saisie_notes`,
  `12_m6_evaluations_ecriture` — visibilité, droits de saisie, création
  d'évaluation, moyenne pondérée.
- **Unitaires (Flutter/Dart)** : validateur de barème/coefficient, calcul de
  moyenne (miroir de `calculer_moyenne_eleve`), file de synchro LWW (rejeu
  idempotent, conflit dernier-écrit-gagne).
- **Intégration (Edge Function, à livrer)** : `sync_push` rejoue un lot
  hors-ligne puis un lot concurrent → état convergent, aucun doublon.
- **Prérequis** : `supabase db reset` (M0→M6 + seeds) puis `pg_prove`.

## 8. Seeds — ordre d'exécution

Les seeds sont des fichiers séparés ; ils doivent être exécutés dans l'ordre
(M0 `seed.sql` → M4 → M5 → M6) car chacun s'appuie sur le précédent. À défaut
de chaînage automatique dans Supabase, les enchaîner manuellement ou via le
script de validation technique planifiée avant la fin du sprint M6.

## 9. État de vérification

- **Rédigé, relu, non exécuté** : pas de Postgres local ni Docker sur ce poste.
- À exécuter : `supabase db reset` puis `pg_prove tests/rls/*.sql` (01 à 12).
