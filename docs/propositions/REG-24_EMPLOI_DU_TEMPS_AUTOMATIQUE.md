# REG-24 — Emploi du temps dynamique et automatisé

Directive du porteur de projet (2026-10-28) : « Implémenter un emploi du
temps dynamique et automatisé très puissant basé sur les modèles de
Pronote et Horarium IA. »

## 1. Recherche préalable

| Outil | Ce qu'il fait de mieux | Repris dans EcoShop |
|---|---|---|
| **EDT + Pronote** (Index Éducation, référence des collèges et lycées français) | Saisie des « cours » (classe ou partie de classe, matière, professeur, durée, nombre par semaine) ; placement automatique ; **cours verrouillés** ; diagnostic des cours non placés ; publication immédiate dans Pronote (élèves, parents, professeurs) | Cours = affectation enseignant × classe/groupe × matière × heures × durée ; séances verrouillées ; raison de chaque séance non placée ; publication directe dans l'application |
| **Horarium** (Italie, Espagne ; promu comme « IA ») | Plus de 40 contraintes **pondérées** choisies par l'école ; compactage des journées des enseignants ; régénération sans repartir de zéro ; analyse d'impact ; partage en PDF ou lien | Critères de qualité pondérés de 0 à 10 ; « Autre proposition » ; bilan chiffré de chaque proposition |
| **aSc Timetables** | Trous des enseignants plafonnés, répartition d'une matière sur la semaine, groupes d'une classe et cours communs à plusieurs classes, salles autorisées, vérification des déplacements manuels | Groupes en parallèle, salle imposée, répartition sur la semaine |
| **FET** (logiciel libre) / **flop!EDT** | Contraintes « dures » et « souples », solveurs d'optimisation, préférences des enseignants | Séparation impératif / qualité, indisponibilités |

Sources : [Horarium, Tecnica della Scuola](https://www.tecnicadellascuola.it/horarium-la-soluzione-intelligente-per-la-generazione-degli-orari-scolastici) ;
[Horarium, Educación 3.0](https://www.educaciontrespuntocero.com/recursos/horarios-escolares-horarium/) ;
[aSc Timetables](https://www.mockus.us/optimum/aSc/aSc.html) ;
[flop!EDT, LinuxFr](https://linuxfr.org/news/gestionnaire-libre-d-emplois-du-temps-flop-edt-avancees-et-appel-a-participation).

**Ce qu'aucun d'eux ne fait, et qu'EcoShop fait** : le calcul tourne sur
le téléphone ou le PC de l'école, **sans connexion** (EDT est un logiciel
Windows payant, Horarium un service en ligne) ; le programme officiel du
pays fournit d'office les matières, coefficients et volumes horaires ; la
grille par défaut suit l'organisation guinéenne (lundi → samedi matin,
récréation, pause de midi).

## 2. Ce qui est livré

### Données (migration `20260906001573`)

- `grilles_horaires` : jours ouvrés, journée-type (cours, récréation, pause
  de midi), demi-journées libérées, poids des critères — une par année.
- `affectations_enseignants` : + `groupe_id`, `duree_seance` (1 h, 1 h 30,
  2 h), `salle_id` (salle imposée).
- `emplois_du_temps` : + `groupe_id`, `verrouille`, `origine`,
  `affectation_id` ; unicité d'un créneau par classe **et groupe**.
- `enregistrer_emploi_genere()` : remplace en une transaction les séances
  non verrouillées de l'année.

### Moteur (`lib/features/planification/domain/moteur_emploi_du_temps.dart`)

**Impératif (jamais enfreint)** : enseignant, classe, groupe et salle à un
seul endroit à la fois ; indisponibilités (enseignant, classe, salle ;
journée ou demi-journée) ; demi-journées libérées ; séances verrouillées ;
séance de 2 h sur des créneaux consécutifs, jamais à cheval sur une pause ;
pas plus de séances d'une matière par jour que nécessaire.

**Qualité (pondérée de 0 à 10)** : pas de trous pour les élèves (10), peu
d'heures creuses pour les enseignants (5), matières réparties sur la
semaine (6), matières principales le matin — coefficient ≥ 3 (4),
journées équilibrées (3), enseignants regroupés sur moins de jours (2),
dernière heure évitée (1).

**Méthode** : « la séance la plus contrainte d'abord » (DSatur), chaînes
d'éjection quand une séance ne trouve plus de place, puis recuit simulé
(déplacements et échanges), trois départs, meilleur gardé. Dart pur, dans
un isolat : l'écran reste fluide. Budget : 8 secondes.

### Écran « Emploi du temps automatique » (Direction)

1. **Calcul** : ce qui est à placer, alertes avant calcul (classe ou
   enseignant avec plus d'heures que la grille, séance plus longue que tout
   bloc sans pause), calcul, **qualité en %**, trous élèves / enseignants,
   séances non placées et pourquoi, aperçu par classe et par enseignant,
   « Autre proposition », « Publier ». Emploi du temps publié : toucher une
   séance la verrouille.
2. **Grille** : jours, heures, pauses, demi-journées libres.
3. **Règles** : curseurs de 0 à 10.
4. **Indisponibilités** : enseignant, classe ou salle ; jour ; journée,
   matin ou après-midi.

La proposition calculée est gardée sur l'appareil ; la publication demande
le réseau.

## 3. Choix faits, modifiables

- **32 semaines de cours** pour passer du volume annuel du programme
  officiel aux heures par semaine (valeur proposée, modifiable cours par
  cours).
- **Matière principale** : coefficient 3 et plus (réglable de 2 à 6).
- **Matin** : créneau qui commence avant 12 h 30.
- Deux groupes d'une même classe sont toujours considérés comme
  **disjoints** (Anglais / Arabe, demi-groupes) : ils peuvent être en
  parallèle.

## 4. Étapes suivantes possibles

- Remplacement d'un enseignant absent (EDT : « gestion des absences et
  remplacements ») avec avis aux familles.
- Semaines A / B (alternance de séances une semaine sur deux).
- Export PDF de l'emploi du temps d'une classe, d'un enseignant.
- Préférences des enseignants (souhaits, pas seulement indisponibilités).
