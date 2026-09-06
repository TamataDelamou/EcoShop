# M4 — Référentiel pédagogique CEDEAO (spécifications)

> Module backend, périmètre DeepSeek. Livrable : schéma SQL commenté,
> spécifications fonctionnelles et techniques, maquette de données pour 3 pays.

## 1. Objectif

Décrire **16 systèmes éducatifs CEDEAO** sous un modèle unique, **inter-comparable**
et **téléchargeable hors-ligne**, afin de porter le moteur de révision, la
préparation aux examens et le comparateur inter-pays (axe différenciant).

## 2. Recherche comparative — état et méthode

La recherche web live est **partiellement indisponible** sur ce poste (clé Tavily
non configurée). Un accès direct a permis de confirmer la référence **ISCED 2011**
(niveaux 0 à 8). Le benchmark concurrentiel complet sera enrichi en session
dédiée dès que le moteur de recherche est débloqué (Tavily ou Bing).

Cadre retenu pour le benchmark (à documenter ensuite) :

- **Acteurs génériques** : Khan Academy, Quizlet, Duolingo — forces : gamification
  et répétition espacée ; faiblesse : non alignés sur les programmes CEDEAO.
- **Acteurs Afrique de l'Ouest** (à confirmer par recherche) : Etudesk (CI),
  Schoolap (RDC), Eneza Education (SMS, Afrique de l'Est), Quizac (NG) — force :
  ancrage local ; faiblesse : couverture multi-pays rare et hors-ligne souvent
  partiel.
- **Constats structurants** : la couverture multi-pays alignée sur les examens
  officiels (BEPC/BAC/BFEM/BECE/WASSCE) ET un vrai mode hors-ligne sont les deux
  trous du marché à exploiter.

Normes mobilisées pour le modèle :

- **ISCED 2011** (UNESCO) : niveaux 0-8 pour coder chaque niveau d'enseignement.
- **LOM (IEEE 1484.12.1)** : inspiration pour les métadonnées des contenus
  (sera appliquée au moteur de questions, M10).
- **grade_level_normalise** (cahier ch. 6) : clé continue par pays, jamais
  affichée, support du comparateur inter-pays.

## 3. Modèle de données

| Table | Rôle | Clé naturelle |
|---|---|---|
| `systemes_educatifs` | 4 familles (francophone_cfa, anglophone_waec, lusophone, arabophone_mixte) | `code` |
| `pays_pedagogiques` | 16 pays CEDEAO | `code_iso` |
| `cycles_educatifs` | primaire / collège / lycée… par pays | `(pays_code, code)` |
| `niveaux_educatifs` | niveau d'enseignement (CP1, 6e, JHS1…) | `(pays_code, code)` + `(pays_code, grade_level_normalise)` |
| `examens_nationaux` | BEPC, BAC, BFEM, BECE, WASSCE… | `(pays_code, code)` |
| `filieres_educatives` | séries (L, S, technique…) | `(pays_code, code)` |
| `programmes_officiels` | curriculum versionné | `(pays_code, code, version)` |
| `programmes_matieres` | matières d'un programme (coef, volume) | `(programme_id, code)` |
| `paquets_referentiel` | paquets hors-ligne par pays/niveau (SHA-256, version) | `(pays_code, niveau_id, version)` |

**Note** : `grade_level_normalise` est une **colonne** de `niveaux_educatifs`
(pas une table) : c'est la clé de normalisation inter-pays, contiguë et unique
par pays, jamais montrée à l'utilisateur.

## 4. Spécifications fonctionnelles

1. **Consultation** : tout client lit les données publiées (`statut = 'publie'`
   / `statut_deploiement = 'deploye'`) sans authentification renforcée.
2. **Publication** (back-office) : le CMS/back-office GSG crée et publie pays,
   cycles, niveaux, examens, filières, programmes et matières via `service_role`.
3. **Comparateur inter-pays** : `grade_level_normalise` permet de répondre
   « à quel niveau sénégalais correspond la Terminale guinéenne ? » par simple
   jointure sur la clé normalisée.
4. **Téléchargement hors-ligne** : le client télécharge un `paquet_referentiel`
   (pays entier ou un niveau), vérifie son empreinte SHA-256, et consulte le
   référentiel sans réseau.
5. **Curation par organisme examinateur** : `examens_nationaux.organisme` et
   `pays_pedagogiques.organisme_examinateur` filtrent les contenus par instance
   de certification (WAEC, Office du Bac, ministère).

## 5. Spécifications techniques

- **RLS** : lecture publique des données publiées ; **aucune** policy d'écriture
  client (écriture `service_role` uniquement, via Edge Function/back-office).
- **Intégrité** : unicité par clé naturelle ; `grade_level_normalise > 0` ;
  `isced` borné 0-8 ; cascade `on delete` pour les hiérarchies pays→cycle→niveau.
- **Continuité du grade** : garantie d'unicité et de positivité en base ; la
  contiguïté (absence de trou) est une règle de back-office (ch. 6), contrôlée
  par le CMS à la publication.
- **Versioning** : `programmes_officiels.version` + `paquets_referentiel.version`
  préparent les mises à jour incrémentales de contenus hors-ligne.

## 6. Maquette de données (seed)

`supabase/seed_referentiel_pedagogique.sql` — 3 pays, 2 systèmes :

| Pays | Système | Cycles / niveaux | Examens |
|---|---|---|---|
| Guinée (GN) | francophone_cfa | primaire (CP1→CM2), collège (7e→10e), lycée (11e→Terminale) | CEE, BEPC, BAC |
| Sénégal (SN) | francophone_cfa | primaire (CI→CM2), moyen (6e→3e), secondaire (2nde→Terminale) | CFEE, BFEM, BAC |
| Ghana (GH) | anglophone_waec | primary (P1→P6), JHS (JHS1→3), SHS (SHS1→3) | BECE, WASSCE |

+ filières (séries), un programme officiel par pays et ses matières
(coefficients et volumes horaires).

## 7. État de vérification

- **Rédigé, relu, non exécuté** : pas de Postgres local ni Docker sur ce poste
  (Supabase CLI 2.116.0 installé, mais `supabase start` exige Docker).
- À exécuter dès outillage disponible : `supabase db reset` puis
  `supabase db push` (ou psql) pour appliquer
  `20260906000400_m4_referentiel_pedagogique.sql` et le seed.
