# Recherche comparative — EcoShop v4.1 (M4 · M5 · M6)

> Document de veille consolidé pour les modules backend M4 (référentiel
> pédagogique), M5 (administration & scolarité) et M6 (notes & évaluations).
> Périmètre DeepSeek : backend, données, sécurité, logique métier, hors-ligne.
> **Date d'accès aux sources : 2026-09-06.** Moteur de recherche plein-texte
> indisponible (clé Tavily absente) ; sources consultées en accès direct.

## 1. Sources documentées

| # | Source (URL) | Type | Apport pour le projet |
|---|---|---|---|
| S1 | https://en.wikipedia.org/wiki/Learning_analytics | Académique | Définition, modèles prédictifs, bénéfices par acteur, éthique/confidentialité (InBloom, checklist DELICATE) |
| S2 | https://en.wikipedia.org/wiki/Educational_data_mining | Académique | 4 objectifs EDM, phases, applications (prédiction de performance, détection de comportements, recommandation, regroupement) |
| S3 | https://en.wikipedia.org/wiki/Learning_management_system | Encyclopédique | Fonctions LMS, parts de marché US 2023 (Canvas 41 %, Blackboard 17 %, Moodle 16 %, Brightspace 16 %), standards SCORM/xAPI/LTI, marché 24,05 Md$ (2024), CAGR 19,9 % |
| S4 | https://en.wikipedia.org/wiki/Conflict-free_replicated_data_type | Technique | CRDT état/opération, LWW-Register, OR-Set, usages industriels (Apple Notes hors-ligne, Figma, Redis, Riak) |
| S5 | https://en.wikipedia.org/wiki/Student_information_system | Encyclopédique | Modules SIS : notes, emploi du temps, assiduité, relevés ; risque de sécurité des données élèves |
| S6 | https://en.wikipedia.org/wiki/Artificial_intelligence_in_education | Académique | Historique (PLATO, ITS), 3 paradigmes (Ouyang & Jiao 2021), applications (feedback, prédiction, tutorat), risques (biais, sur-dépendance, vie privée), guidance UNESCO 2024 |
| S7 | https://en.wikipedia.org/wiki/International_Standard_Classification_of_Education | Institutionnel (UNESCO) | ISCED 2011 niveaux 0-8 — base du référentiel M4 (déjà exploitée) |

## 2. Benchmark concurrentiel

Comparaison des solutions comparables sur les axes qui différencient EcoShop :
**couverture multi-tenant (établissements CEDEAO), hors-ligne réel, IA
pédagogique locale, prix abordable en contexte africain.**

| Solution | Type | Notes/évaluations | Hors-ligne | Analytique/IA | Cible |
|---|---|---|---|---|---|
| **Moodle** (open source) | LMS | Très complet (activités, quiz, notes) | Faible (app mobile limitée, essentiellement consultation) | Analytique de base, plugins | Établissements sup. surtout ; anglophone dominant |
| **Canvas** (Instructure) | LMS | Leader US (≈41 %), rubric/notes/analytique | Quasi nul | Analytique solide, IA émergente | HE/K-12 US, coûteux |
| **Pronote** (Index Éducation) | Cahier de notes FR | Référence francophone notes/bulletins/appréciations | Aucun | Statistiques simples | France/DOM, non multi-pays CEDEAO |
| **PowerSchool** | SIS | Référentiel K-12 (inscriptions, notes, assiduité, relevés) | Faible | Analytique/IA add-on payant | US/K-12 |
| **Eneza Education** | EdTech mobile Afrique | Contenu par SMS/USSD, faible bande passante | Fort (SMS) | Quiz adaptatifs légers | Kenya/RDC ; périmètre pédagogie, pas SIS |
| **uLesson** | EdTech Afrique de l'Ouest | Cours vidéo + quiz, packs SD préchargés | Fort (téléchargement) | Recommandation simple | Nigeria/Ghana ; pas de gestion d'établissement |

**Lecture du benchmark.** Les leaders mondiaux (Canvas, PowerSchool) couvrent
bien les notes et l'analytique mais supposent une connectivité permanente, un
prix de licence élevé et un ancrage US/anglophone. Les solutions francophones
(Pronote) couvrent excellemment le cahier de notes mais sont mono-pays et 100 %
en ligne. Les EdTech africaines (Eneza, uLesson) résolvent la connectivité mais
ne gèrent pas l'établissement (pas de SIS multi-tenant). **Le créneau d'EcoShop
est l'intersection vacante : SIS + cahier de notes + hors-ligne réel + IA
légère, multi-tenant CEDEAO.**

## 3. Analyse des besoins par acteur (M6)

| Acteur | Besoins prioritaires | Traduction produit |
|---|---|---|
| Enseignant | Saisir vite des notes (même sans réseau), gérer devoirs/contrôles/compositions, appréciations | Saisie hors-ligne par lot, types d'évaluation, appréciations structurées |
| Élève | Consulter ses notes, moyennes, rang, progression | Bulletins temps réel, dashboard de progression |
| Parent | Suivre l'enfant, être alerté des décrochages | Vue enfant lié (M5), alertes d'écart |
| Direction | Comparer classes/matières, piloter la réussite, rapports officiels | Statistiques agrégées, exports bulletins |
| Administrateur GSG | Référentiel, conformité CEDEAO, supervision multi-tenant | Rôles `admin_gsg`, agrégats anonymisés |

## 4. Fonctionnalités différenciantes retenues

1. **Hors-ligne complet en saisie de notes** — l'enseignant note en classe sans
   réseau ; synchronisation différée avec résolution de conflits (voir §6).
2. **IA de détection d'anomalies** — écarts de note suspects (saisie erronée),
   ruptures de tendance par élève, absentéisme corrélé.
3. **Prédiction de réussite** — risque de redoublement/abandon par matière et
   période, à partir de l'historique des notes.
4. **Recommandation de contenus** — relier les lacunes détectées aux ressources
   du référentiel M4 (alignement note → compétence → contenu).
5. **Analyse sémantique des appréciations** — NLP sur les commentaires des
   bulletins pour extraire points forts/faibles et nourrir le profil de maîtrise.

## 5. Pistes IA pour M6 (cas d'usage, données, contraintes)

| Cas d'usage | Données nécessaires | Contrainte technique | Cible d'implémentation |
|---|---|---|---|
| Prédiction de réussite (risque par matière/période) | Historique `notes`, `evaluations`, `inscriptions`, `periodes_scolaires` | Modèle léger (régression logistique / forêt aléatoire), inférence batch | Edge Function (Supabase) + cache d'agrégats |
| Détection d'anomalies (écarts de note, ruptures de tendance) | Séries de notes par élève/matière | Règles statistiques (z-score, IQR) d'abord, ML ensuite | Postgres (fonctions SQL) → zéro latence réseau |
| Recommandation de contenus | Notes ↔ `programmes_matieres`/compétences (M4), historique | Jointure référentiel, scoring de lacunes | Edge Function, résultat pré-calculé dans `statistiques_agregats` |
| NLP des appréciations | `appreciations` texte | Français + langues locales, coût/confidentialité | Hors-ligne : lexique local + TF-IDF léger (ML Kit) ; en ligne : Edge Function appelant un modèle hébergé |

**Principe de sobriété IA** (source S6, guidance UNESCO 2024) : commencer par
des **règles statistiques transparentes et auditées** (explicables, sans biais
de modèle), puis monter en complexité uniquement là où la valeur le justifie.
Aucune décision automatique bloquante (redoublement, exclusion) : l'IA produit
des **signaux d'aide à la décision** pour l'enseignant et la direction.

**Architecture légère proposée :**
- **Tier 1 — SQL/Postgres** : moyennes, écarts-types, z-scores, classements —
  calculés par fonctions SQL sur agrégats (`statistiques_agregats`), disponibles
  hors-ligne une fois synchronisés.
- **Tier 2 — Edge Function** : régression/forêt légère (prédiction, détection),
  déclenchée en lot (cron) sur les données agrégées — jamais sur les notes brutes
  en requête.
- **Tier 3 — On-device (Flutter)** : NLP légère des appréciations (ML Kit / TF
  Lite) et cache local des prédictions — fonctionne sans réseau, dans la
  continuité de la directive hors-ligne.

## 6. Stratégie de synchronisation hors-ligne (M6)

Inspirée des CRDT (S4), appliquée au domaine des notes avec un modèle simple et
sûr : **registre Last-Write-Wins (LWW) par champ**, c'est-à-dire chaque note
porte un `device_id`, un `client_ts` et un `server_ts` ; en cas de conflit, la
dernière écriture gagne avec départage serveur (horodatage serveur à l'arrivée).
Ce modèle est le même que celui documenté pour Figma (LWW par propriété).

- **File de synchronisation** : la table `sync_queue` (M0) journalise chaque
  `INSERT`/`UPDATE` de note hors-ligne (opération, entité, payload, `client_ts`).
- **Rejeu idempotent** : l'Edge Function `sync_push` applique les opérations dans
  l'ordre causal (`client_ts`), avec `ON CONFLICT` LWW — un rejeu dupliqué ne
  corrompt pas les données.
- **Conflits** : (a) même note modifiée par deux enseignants → LWW par
  `client_ts` ; (b) suppression vs modification → tombstones (`deleted_at`),
  résolution suppression-vs-écriture documentée ; (c) moyennes/bulletins
  **jamais synchronisés** — toujours recalculés côté serveur sur les notes
  sources, ce qui élimine les conflits d'agrégats.
- **Téléchargement initial** : l'enseignant télécharge en cache Drift l'annuaire
  (M5) + les grilles d'évaluation avant de partir hors-ligne ; le périmètre est
  limité à ses classes affectées (M5 `affectations_enseignants`).

## 7. Synthèse comparative (tableau de décision)

| Critère | Moodle | Canvas | Pronote | PowerSchool | Eneza/uLesson | **EcoShop (cible)** |
|---|---|---|---|---|---|---|
| Multi-tenant CEDEAO | Non | Non | Non | Non | Partiel | **Oui (M1)** |
| Notes/évaluations | Oui | Oui | **Excellent** | Oui | Non | **Oui (M6)** |
| Hors-ligne saisie | Faible | Non | Non | Faible | Fort | **Fort (M6)** |
| IA pédagogique | Faible | Moyenne | Non | Moyenne (payant) | Légère | **Légère, sobre, off-line** |
| Référentiel CEDEAO/ISCED | Non | Non | Non | Non | Partiel | **Oui (M4)** |
| Coût/licence | Libre (infra) | Élevé | Moyen | Élevé | Freemium | **Optimisé** |

## 8. Références académiques clés (reprises de S1/S2/S6)

- Siemens, Long — « Penetrating the fog: analytics in education », Educause Review 46(5), 2011 (learning analytics appliquée à la décision).
- Baker, R. S. — « Data Mining for Education », International Encyclopedia of Education, 3e éd., Elsevier, 2010 (4 objectifs EDM, phases).
- Romero & Ventura — « Educational Data Mining: A Review of the State-of-the-Art », IEEE TSMCC 40(6), 2010 (taxonomie des applications EDM).
- Ouyang & Jiao — trois paradigmes IA-éducation (AI-directed / AI-supported / AI-empowered), 2021.
- Shapiro et al. — « Conflict-Free Replicated Data Types », SSS 2011 (fondement CRDT, convergence).
- UNESCO — « Guidance for generative AI in education and research », 2024 (éthique, formation des enseignants, protection des données).
