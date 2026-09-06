# M5 — Administration & Scolarité (spécifications)

> Module backend, périmètre DeepSeek. Livrable : DDL + RLS, documentation,
> seed et tests RLS associés.

## 1. Objectif

Poser la **colonne vertébrale administrative** des établissements : structures
(campus, périodes, classes), inscriptions et fiches élèves, liaison
parent ↔ élève (sélecteur d'enfant) et affectation des enseignants — le tout
sous **RLS multi-tenant stricte**, prêt pour la consultation hors-ligne.

## 2. Recherche & benchmark

La recherche web live reste **indisponible** sur ce poste (clé Tavily non
configurée) ; le benchmark concurrentiel est reporté. L'analyse s'appuie sur le
cahier v4.1 et les pratiques CEDEAO :

- **Découpage de l'année variable** : 3 trimestres (systèmes francophones), 3
  termes (Ghana/WASSCE), 2 semestres (certains établissements). Le schéma rend
  ce découpage **libre par établissement et par année** (`type_periode` :
  `trimestre`, `semestre`, `terme`), jamais codé en dur.
- **Classe = structure d'accueil annuelle** (« 6e A 2026-2027 »), alignée sur le
  référentiel M4 (`niveau_id`) pour préparer la pédagogie.
- **Sélecteur d'enfant** : le parent n'est **pas membre** de l'établissement ;
  sa visibilité passe exclusivement par la relation parentale confirmée.

## 3. Modèle de données

| Table | Rôle | Clés |
|---|---|---|
| `periodes_scolaires` | trimestres/semestres/termes d'une année | `(annee_scolaire_id, code)`, `(annee_scolaire_id, ordre)` |
| `classes` | structures d'accueil (par année scolaire) | `(annee_scolaire_id, code)` |
| `inscriptions` | fiche élève → classe → année | `(fiche_eleve_id, annee_scolaire_id)` unique |
| `relations_parent_eleve` | lien parent ↔ élève (sélecteur d'enfant) | `(parent_profile_id, fiche_eleve_id)` unique |
| `affectations_enseignants` | enseignant → classe (+ matière M4) | `(annee_scolaire_id, enseignant, classe, matière)` |
| `fiches_eleves` (enrichie) | + sexe, lieu de naissance, nationalité, statut, est_supervise | `(etablissement_id, matricule)` |

Réutilisé (M1/M2) : `unites_operationnelles` (campus), `annees_scolaires`,
`postes`/`poste_permissions`, `etablissements_membres`, `fiches_eleves`.

## 4. Spécifications fonctionnelles

1. **Structures** : la direction/scolarité crée périodes et classes d'une année
   scolaire ; une classe peut être rattachée à un campus (`unite_id`) et à un
   niveau M4.
2. **Inscriptions** : inscription/retrait d'un élève à une classe ; une fiche ne
   peut être inscrite qu'une fois par année.
3. **Liaison parent** : un compte `parent` lie une fiche par **matricule + date
   de naissance** (double facteur, 5 échecs/heure) ; il consulte ensuite la
   fiche et la classe de l'enfant (sélecteur d'enfant). Un non-parent est refusé.
4. **Affectations** : affecter un enseignant (membre actif) à une classe, avec
   une matière optionnelle issue du référentiel M4 et un rôle
   (titulaire/enseignant/suppléant).

## 5. Spécifications techniques

- **RLS** : chaque table porte `etablissement_id` (dénormalisation de tenant) ;
  les policies combinent `est_personnel()` (personnel ≠ élève/parent),
  `a_permission()` et des helpers `security definer` de visibilité
  (`fiche_visible`, `classe_visible`, `est_parent_confirme`) — sans récursion.
- **Garde-fous multi-tenant** : triggers `*_verifie_tenant` sur chaque table
  (cohérence année/campus/fiche/classe/enseignant ↔ établissement), sur le
  modèle `membres_verifie_tenant` (M1).
- **Écritures sensibles** : liaison parent via RPC `lier_parent_a_fiche`
  (`security definer`), jamais en écriture client directe.
- **Hors-ligne (Drift/SQLite)** : l'annuaire de l'établissement (fiches,
  classes, périodes, affectations) est un candidat direct au cache local ; la
  file de synchro (`sync_queue`, M0) journalisera les inscriptions hors-ligne.

## 6. Maquette de données (seed)

`supabase/seed_administration_scolarite.sql` — sur le « Lycée Innovation
Conakry » : année 2026-2027, 3 trimestres, 3 classes (7e A, 10e A, Terminale A),
3 fiches élèves inscrites, 1 relation parent↔élève (tuteur légal), 1 affectation
d'enseignant (titulaire 7e A).

## 7. État de vérification

- **Rédigé, relu, non exécuté** : pas de Postgres local ni Docker sur ce poste.
- À exécuter dès outillage disponible : `supabase db reset` (migrations M0→M5 +
  seeds), puis `pg_prove tests/rls/*.sql` (01 à 09).
