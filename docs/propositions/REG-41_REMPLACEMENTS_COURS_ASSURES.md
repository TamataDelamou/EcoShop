# REG-41 — Absences des enseignants, remplacements et cours assurés : proposition

**Établi le** : 2026-10-31. **Statut** : validé par le porteur de projet
le 2026-10-31 (les trois décisions du §4 telles que proposées) ; livré. **Feuille de route** : REG-30 point 15 (suites
de l'emploi du temps : remplacement d'un enseignant absent, semaines A/B,
export PDF).

## 1. Pourquoi c'est la prochaine étape

- **Le temps d'enseignement perdu est le premier problème des écoles de la
  région.** Dans les enquêtes SDI de la Banque mondiale, l'enseignant
  est absent de l'école 20 % du temps en moyenne, et **absent de sa
  classe 42 %** du temps. En moyenne, les élèves reçoivent **2 h 53** de
  cours par jour sur **5 h 31** prévues, soit près de **la moitié du temps
  perdu** (Sénégal 2011 : environ 29 % ; Togo 2013 : environ 40 %). La
  perte vient surtout des enseignants présents à l'école mais pas en classe.
- EcoShop a déjà l'emploi du temps automatique (REG-24), l'appel (M7), les
  absences et congés du personnel (M8) et le cahier de texte (REG-40). Il
  manque ce qui les relie : **savoir, chaque jour, quel cours n'est pas
  assuré, le remplacer ou prévenir les familles, et le mesurer**.
- L'existant est insuffisant : `optimiser_remplacements` (M8) propose
  l'enseignant le moins chargé **pour toute la journée**, sans regarder
  l'heure, la matière ni la classe, et n'avertit personne.

## 2. Ce que font les meilleurs

| Outil | Ce qu'il fait de mieux |
|---|---|
| **Untis / WebUntis** (Autriche, référence européenne) | Proposition de remplaçant **en un clic** : enseignants **libres à cette heure**, qui **enseignent la matière**, qui **connaissent la classe** ; avancer un autre cours ; remplacements ouverts placés automatiquement ; **statistiques** de remplacements et d'annulations par enseignant ; permanences ; échanges |
| **aSc Timetables / EduPage** (Slovaquie, très répandu en Afrique) | Module « remplacements » relié à l'emploi du temps ; publication du plan du jour aux élèves et aux parents |
| **Pronote / EDT** (France) | Modification ponctuelle de l'emploi du temps (cours annulé, remplacé, déplacé) visible **tout de suite** dans l'emploi du temps des élèves et des parents |

## 3. Ce que je propose de construire (2 lots)

### Lot 1 — Absences et remplacements du jour

1. **Déclarer une absence** : la direction (ou l'enseignant lui-même, par
   anticipation) déclare l'absence pour une journée ou certaines heures ;
   les cours concernés apparaissent aussitôt dans « Cours à remplacer ».
2. **Pour chaque cours, quatre solutions**, la meilleure proposée d'abord :
   - **remplaçant** : liste classée des enseignants **libres à cette heure**,
     d'abord ceux de **la même matière**, puis ceux qui **connaissent la
     classe**, puis les **moins sollicités** ce mois-ci (équité, compteur
     visible) ;
   - **étude surveillée** (surveillant ou membre du personnel libre) ;
   - **cours déplacé** (échange avec un autre cours de la classe) ;
   - **cours annulé**.
3. **Prévenir automatiquement** : le remplaçant (notification), les élèves
   et les parents de la classe (« Maths de 10 h : remplacé par M. Bah » ou
   « annulé — étude en salle 3 »), aux heures de messagerie de l'école.
4. **Emploi du temps du jour à jour** pour tous : la séance montre
   « remplacé », « étude » ou « annulé ».
5. **Hors connexion** : déclarations et choix faits sans réseau partent au
   retour ; le plan du jour est gardé sur le téléphone.

### Lot 2 — Cours assurés, semaines A/B, export PDF

6. **Cours assurés** : un cours compte comme assuré quand l'appel ou le
   cahier de texte est fait pour ce créneau. Tableau de la direction :
   **taux de cours assurés** par classe, par enseignant et par semaine ;
   heures perdues par matière ; alerte quand une classe a perdu plus de 10 %
   de ses heures d'une matière sur le mois. C'est la mesure qui manque le
   plus aux écoles d'après la recherche (§1).
7. **Statistiques de remplacement** (Untis) : par enseignant, remplacements
   faits et cours manqués, pour la paie (heures supplémentaires) et l'équité.
8. **Semaines A/B** : séances une semaine sur deux (travaux pratiques,
   demi-groupes) dans l'emploi du temps automatique.
9. **Export PDF** de l'emploi du temps par classe et par enseignant, à
   l'identité visuelle de l'école (à afficher en classe ou à imprimer).

## 4. Décisions à prendre par le porteur de projet

1. **Qui déclare une absence ?** Proposition : la direction et les postes qui
   en ont le droit ; l'enseignant peut prévenir lui-même à l'avance (« Je
   serai absent jeudi matin »), la direction valide.
2. **Faut-il payer les remplacements ?** Proposition : le compteur d'heures
   de remplacement apparaît dans la fiche RH et peut alimenter la paie
   (heures supplémentaires), au choix de chaque école.
3. **Prévenir les parents à chaque remplacement ?** Proposition : oui pour
   un cours **annulé** ou en **étude** ; pour un simple remplacement, l'élève
   seulement (moins de messages).

## Sources

- Banque mondiale, enquêtes Service Delivery Indicators (présentation RISE,
  D. Filmer) : https://riseprogramme.org/sites/default/files/inline-files/25_Filmer_SDI-RISE.pdf
- Untis, planification des remplacements : https://www.untis.at/en/products/untis-basic-software/substitution-planning-1 ;
  WebUntis en ligne : https://www.untis.at/en/products/webuntis/online-substitution-planning ;
  statistiques : https://webhelp.untis.at/HTML/WebHelp/uk/untis/vp_vertretungsstatistik.htm
- aSc Timetables / EduPage : https://asctimetables.com/
- Ministère de l'Éducation nationale (France), organisation du remplacement
  des enseignants : https://www.education.gouv.fr/l-organisation-du-remplacement-des-enseignants-11321
