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

## 9. M7 — Vie scolaire & décrochage (recherche complémentaire)

### 9.1 Sources ajoutées (accès 2026-09-06)

| # | Source (URL) | Type | Apport pour M7 |
|---|---|---|---|
| S8 | https://en.wikipedia.org/wiki/Dropping_out | Encyclopédique | Facteurs de risque prédictifs (Rumberger : absentéisme, problèmes de comportement, désengagement) ; antécédents d'absentéisme/redoublement ; prévention par la dynamique familiale ; données UNESCO Amérique latine (finances, désintérêt) |
| S9 | https://en.wikipedia.org/wiki/School_discipline | Encyclopédique | Formes non corporelles (retenue, conseil, suspension), discipline **restaurative** et responsabilisante, dérive des sanctions disproportionnées → virage non punitif |
| S10 | https://en.wikipedia.org/wiki/Education_in_Guinea | Encyclopédique | Contexte : primaire obligatoire 6 ans ; HRMI : 60,7 % du droit à l'éducation satisfait, secondaire à 46,6 % → enjeu de rétention |

### 9.2 Benchmark — modules de vie scolaire des LMS/SIS

| Solution | Présences/retards | Sanctions/comportement | Alerte décrochage | Hors-ligne | IA |
|---|---|---|---|---|---|
| **Schoology** (PowerSchool) | Pointage par période | Non | Non (add-on) | Non | Faible |
| **PowerSchool** | Pointage + justifications | Comportement + incidents | Early Warning System natif | Faible | Analytique |
| **InfoSIS** (SIS générique) | Pointage par cours | Disciplinaire de base | Non | Non | Non |
| **Pronote** | Absences/retards, motifs | Sanctions + commission éducative | Non | Non | Statistiques |
| **Moodle** (plugin) | Pointage simple | Non | Non | Faible | Non |
| **EcoShop (cible M7)** | Pointage demi-journée/cours + retards + justifications | Sanctions éducatives **validées humainement** | Alerte décrochage multi-facteurs (M6+M7) | **Fort** | **3 tiers, human-in-the-loop** |

**Lecture** : seuls les SIS lourds (PowerSchool) proposent un Early Warning System, mais sans
hors-ligne ni ancrage CEDEAO. Les solutions francophones (Pronote) couvrent les absences/retards
mais pas le décrochage. Le créneau d'EcoShop reste l'intersection : **pointage hors-ligne +
alerte décrochage multi-facteurs + sanction éducative validée**, adapté au contexte
ouest-africain (S10).

### 9.3 Détection de décrochage — études de cas

- **Rumberger & Larson (S8)** : absentéisme modéré à élevé, problèmes de comportement et
  absence d'activités extra-scolaires sont **fortement prédictifs** du décrochage ; les facteurs
  académiques (antécédents d'absentéisme, redoublement, difficultés) s'y ajoutent.
- **Modèle « ABC »** (Attendance, Behavior, Course performance — littérature Early Warning
  Systems, Balfanz et al.) : croiser **assiduité + comportement + résultats** est le socle des
  systèmes d'alerte précoce. C'est exactement le croisement M7 (présences/retards) × M6 (notes).
- **UNESCO Amérique latine (S8)** : difficultés financières et désintérêt dominent ; 38 % des
  15-17 ans citent l'étude comme motif — l'alerte doit donc inclure le **décrochage silencieux**
  (désengagement) et pas seulement l'absentéisme.
- **Guinée (S10)** : secondaire à 46,6 % du droit satisfait → la rétention en secondaire est la
  cible prioritaire ; l'alerte précoce et l'engagement des familles (S8) sont les leviers.

### 9.4 IA prédictive vs descriptive vs prescriptive (positionnement M7)

| Approche | Définition | Application M7 |
|---|---|---|
| **Descriptive** | Ce qui s'est passé (tableaux de bord) | `analyse_comportement` : fréquences, motifs de retard, absences injustifiées |
| **Prédictive** | Ce qui va arriver (probabilité) | `calculer_score_decrochage` (croisement absences/retards/moyennes) ; `predire_presence` (calendrier + événements) |
| **Prescriptive** | Que faire (recommandation) | `recommander_sanction_educative` (non punitive, fondée sur l'historique et les règles) |

**Règle éthique (S9, UNESCO 2024)** : les trois niveaux produisent des **signaux soumis à
validation humaine** (direction, conseil de classe, parent). Aucune sanction ni alerte n'est
appliquée automatiquement ; l'IA prescriptive propose, l'humain décide.

## 10. M8 — RH & Personnel (recherche complémentaire)

### 10.1 Sources ajoutées (accès 2026-09-06)

| # | Source (URL) | Type | Apport pour M8 |
|---|---|---|---|
| S11 | https://en.wikipedia.org/wiki/Teacher_attrition | Encyclopédique | Facteurs de rétention/départ des enseignants : conditions de travail, charge, rémunération, soutien administratif, épuisement ; « movers vs leavers » |
| S12 | https://en.wikipedia.org/wiki/Payroll | Encyclopédique | Composantes de la paie : brut, primes, retenues, net ; fréquences — socle de la « paie légère » |
| S13 | https://en.wikipedia.org/wiki/Education_in_Africa | Encyclopédique | Contexte : pénurie d'enseignants qualifiés, disparités — enjeu de gestion des personnels éducatifs |

### 10.2 Benchmark — modules RH des SIS

| Solution | Employés/contrats | Congés | Paie | Analytique RH | Hors-ligne |
|---|---|---|---|---|---|
| **PowerSchool** (ERP/SIS) | Fiches + contrats | Oui | Add-on | Oui | Non |
| **InfoSIS** (SIS générique) | Basique | Partiel | Non | Non | Non |
| **Odoo HR / OrangeHRM** (ERP générique) | **Complet** | Oui | Oui (paie) | Oui | Faible |
| **Skolera** | Basique | Non | Non | Non | Non |
| **EcoShop (cible M8)** | Employés + contrats + congés | Oui | Paie légère (brut/primes/retenues/net) | IA turn-over/formation/plannings | **Fort** |

**Lecture** : les ERP génériques (Odoo/OrangeHRM) couvrent bien le RH mais sont déconnectés
du pédagogique (affectations M5, absences M7, compétences M4) et ne ciblent pas l'établissement
scolaire ouest-africain. Le créneau d'EcoShop est le **RH intégré à la scolarité** : contrat →
affectation → absences → paie, dans un même tenant.

### 10.3 Gestion des personnels éducatifs — études de cas

- **Rétention (S11)** : les conditions de travail et la **charge de travail** sont les premières
  causes de départ, devant la rémunération ; le soutien administratif et l'autonomie sont des
  leviers de rétention. → le risque de turn-over doit croiser **absences (M7), ancienneté et
  charge (heures/affectations M5)**.
- **Contexte Afrique (S13)** : la pénurie d'enseignants qualifiés rend la **rétention et la
  formation** prioritaires sur le recrutement.
- **Paie légère (S12)** : modéliser `brut = base + primes − retenues = net`, sans fiscalité
  complexe, suffit pour les établissements privés ; l'exactitude des composantes prime sur
  l'exhaustivité réglementaire (délibérément hors périmètre).

### 10.4 IA RH — trois niveaux (cohérent M6/M7)

| Niveau | Application M8 | Données croisées |
|---|---|---|
| Descriptive | Tableau de bord effectifs, ancienneté, soldes de congés | `employes`, `contrats`, `conges` |
| Prédictive | **Risque de turn-over** (score 0-1) | absences M7 + ancienneté + charge M5/M6 |
| Prescriptive | Recommandation de formation (M4) ; optimisation des plannings (répartition des congés, remplacements) | compétences M4, affectations M5, historique |

**Règle éthique maintenue** : le score de turn-over et les recommandations sont des **signaux
d'aide à la décision** pour la direction ; aucune action RH n'est automatisée.

## 11. M9 — Communication & Notifications (recherche complémentaire)

### 11.1 Sources ajoutées (accès 2026-09-06)

| # | Source (URL) | Type | Apport pour M9 |
|---|---|---|---|
| S14 | https://en.wikipedia.org/wiki/Parental_involvement (→ consentement parental) | Encyclopédique | Droit/demande d'information du parent sur le parcours de l'enfant → les notifications d'absences/notes sont une obligation d'information, pas une option |
| S15 | https://en.wikipedia.org/wiki/WhatsApp | Encyclopédique | 3 Md d'utilisateurs mensuels (2025), moyen de communication principal dans une grande partie de l'Afrique (2016+) ; WhatsApp Business ; exige un numéro de téléphone |
| S16 | https://en.wikipedia.org/wiki/A/B_testing | Encyclopédique | Expérimentation randomisée à deux variantes, mesure d'un objectif défini, segmentation ciblée, sensibilité à la taille d'échantillon |

### 11.2 Benchmark — modules de communication des LMS/SIS

| Solution | Canaux | Préférences/horaires | IA de timing/personnalisation | Hors-ligne |
|---|---|---|---|---|
| **Canvas** | Email, push, in-app | Par cours/canal | Non (règles statiques) | Non |
| **Moodle** | In-app, email, SMS (plugins) | Riches (par événement) | Non (plugins tiers) | Faible |
| **Schoology** | Email, push | Basiques | Non | Non |
| **PowerSchool** | Email, SMS (alertes présence) | Partielles | Non | Non |
| **EcoShop (cible M9)** | **SMS + WhatsApp + Email + Push** | **Par utilisateur + horaires + fréquence** | **Timing IA + personnalisation + A/B** | **Fort (file locale)** |

**Lecture** : aucun LMS/SIS ne combine multicanal faible connectivité + préférences
horaires + IA de timing. Le créneau d'EcoShop est la **communication parentale
terrain** (SMS/WhatsApp d'abord) pilotée par des règles éthiques et du hors-ligne.

### 11.3 Engagement parent & canaux (contexte Afrique de l'Ouest)

- **WhatsApp (S15)** : premier canal de messagerie en Afrique ; WhatsApp Business
  permet les envois structurés. Canal prioritaire quand le parent est connecté.
- **SMS** : fonctionne sur tout téléphone GSM sans internet — **fallback
  obligatoire** en faible connectivité ; coût par message à provisionner.
- **Push/Email** : dépendants de l'installation de l'app et du réseau — canaux
  secondaires, privilégiés pour les utilisateurs équipés (enseignants, direction).
- **Obligation d'information (S14)** : informer le parent (absences, notes,
  sanctions, événements) est un attendu parental et réglementaire ; le module
  doit donc garantir la traçabilité (journal d'envois + accusé de lecture).

### 11.4 IA communication — trois niveaux (cohérent M6/M7/M8)

| Niveau | Application M9 | Données croisées |
|---|---|---|
| Descriptive | Journal des envois, taux de lecture par canal/type/heure | `notifications`, `logs_envois` |
| Prédictive | **Moment opportun** : éviter les heures tardives, préférer les créneaux de réception (préférences + historique) | `preferences_canaux`, `logs_envois` |
| Prescriptive | Personnalisation contenu/fréquence/canal par profil ; **A/B testing** des variantes ; **analyse sémantique** des retours | `templates_notifications`, feedbacks |

**A/B testing (S16)** : variantes randomisées mesurées sur un objectif défini
(taux de lecture), avec segmentation (la variante gagnante peut différer par
segment) et contrainte de taille d'échantillon — dans un établissement (petits
effectifs), l'A/B reste un **outil interne d'amélioration**, discret et limité.

**Règle éthique maintenue** : notifications non bloquantes, **opt-out par canal**,
pas d'envoi automatique aux heures inopportunes, minimisation des données de
lecture (on sait « lu/non lu », pas le contenu des réponses hors consentement).
