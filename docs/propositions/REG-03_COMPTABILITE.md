# REG-03 — Comptabilité au choix de l'établissement : proposition

> Décision du porteur de projet (2026-10-17) : « faire les deux et laisser à
> l'établissement de choisir lequel appliquer ». Ce document précise **comment**,
> après recherche. Statut : proposition, à valider avant développement.

## 1. Ce que dit le droit OHADA (vérifié)

| Texte | En vigueur | Qui est concerné | Ce qu'il impose |
|---|---|---|---|
| **SYSCOHADA révisé** (Acte uniforme relatif au droit comptable et à l'information financière, 26 janvier 2017) | 1ᵉʳ janvier 2018 | Toute entreprise : SARL, SA, entreprise individuelle… — donc les **écoles privées commerciales** | Plan de comptes normalisé (classes), tenue dans la monnaie légale de l'État (GNF en Guinée), états financiers annuels |
| **SYSCOHADA — Système minimal de trésorerie (SMT)** (art. 13) | idem | Petites entités, **sauf option** : chiffre d'affaires HT ≤ 30 M FCFA pour les **services** (catégorie d'une école), « ou l'équivalent dans l'unité monétaire ayant cours légal » | Comptabilité de trésorerie (recettes / dépenses) et états financiers simplifiés |
| **SYSCOHADA — Système normal** (art. 11) | idem | Toutes les autres entités | Bilan, compte de résultat, tableau des flux de trésorerie, notes annexes |
| **SYCEBNL** (Acte uniforme relatif au système comptable des entités à but non lucratif, adopté fin décembre 2022) | **1ᵉʳ janvier 2024**, 17 États dont la Guinée | Associations, fondations, organisations confessionnelles, ONG, projets de développement — donc les **écoles associatives ou confessionnelles** | Bilan, compte de résultat, tableau des flux, notes ; registre des donateurs ; traitement propre des subventions et fonds affectés à un projet |

**Conséquence importante, absente de l'arbitrage initial** : « OHADA » ne
désigne pas un seul système. Une école privée **commerciale** relève du
SYSCOHADA ; une école **associative ou confessionnelle** relève, depuis 2024,
du **SYCEBNL**. Proposer « SYSCOHADA » à une école associative serait
proposer le mauvais référentiel. La forme juridique de chaque établissement
(dont Bambino Emmaüs) décide du bon choix.

## 2. Ce qui manque aujourd'hui dans EcoShop (constat sur le code)

1. **Plan de comptes libre** (M14) : chaque école invente ses comptes —
   impossible de produire un bilan OHADA.
2. **Une écriture = un seul débit et un seul crédit** : une pièce comptable
   réelle (ex. un reçu ventilé scolarité + cantine, une paie avec retenues)
   a plusieurs lignes.
3. **Aucune écriture automatique** : les encaissements de scolarité (M15quater),
   les paiements Orange Money et CinetPay, la paie (M8) ne passent pas en
   comptabilité — tout serait ressaisi à la main. C'est le principal gisement
   de valeur : la plupart des logiciels de gestion scolaire s'arrêtent à
   l'export vers un logiciel comptable généraliste (Sage et équivalents).
4. **Aucune clôture** : une écriture validée reste modifiable ; le droit
   comptable exige l'irréversibilité des écritures validées et la clôture
   des exercices.
5. **Pas d'états financiers** : seulement journal, grand livre et balance.

## 3. Proposition

### 3.1 Quatre référentiels, un seul moteur

| Référentiel | Pour qui | États produits |
|---|---|---|
| **Simplifié** (M14 actuel, conservé) | Écoles qui ne veulent pas de comptabilité réglementaire : suivi de gestion | Journal, grand livre, balance, recettes/dépenses |
| **SYSCOHADA — SMT** | Petite école commerciale (sous le seuil, ou sur option) | Recettes/dépenses de trésorerie, états SMT |
| **SYSCOHADA — Système normal** | École commerciale au-dessus du seuil | Bilan, compte de résultat, puis tableau des flux et notes |
| **SYCEBNL** | École associative ou confessionnelle | Bilan, compte de résultat, puis tableau des flux, notes, registre des donateurs |

Le choix se fait à l'ouverture de la comptabilité (assistant de 3 questions :
forme juridique, chiffre d'affaires annuel estimé, souhait de comptabilité
réglementaire → référentiel **recommandé**, jamais imposé). Il ne change
qu'au début d'un nouvel exercice, avec une table de correspondance des
comptes pour reprendre les soldes.

### 3.2 Plans de comptes de référence pré-remplis

Pour chaque référentiel réglementaire, un plan de référence **en lecture
seule** chargé par EcoShop, réduit aux comptes utiles à une école (avec
sous-comptes dédiés : scolarité, inscription, cantine, transport ;
élèves/parents débiteurs ; caisse ; banque ; **monnaie électronique**
— Orange Money — que le SYSCOHADA révisé range dans la trésorerie ;
personnel ; subventions et dons pour le SYCEBNL). L'école peut ajouter des
sous-comptes, jamais modifier les comptes réglementaires.

> Les numéros de comptes exacts seront relevés dans les textes officiels
> (plans de comptes SYSCOHADA révisé et SYCEBNL) et **doivent être relus par
> un expert-comptable inscrit à l'ordre en Guinée** avant mise en production.

### 3.3 Comptabilisation automatique (le vrai différenciateur)

Chaque opération déjà gérée par EcoShop génère sa pièce comptable,
**dans la même transaction** (même principe que la file des courriels :
rien de perdu, rien en double) :

| Événement | Écriture (principe) |
|---|---|
| Encaissement de scolarité en espèces | Caisse ⟶ créance élève / produit scolarité |
| Paiement Orange Money confirmé | Monnaie électronique ⟶ créance élève |
| Versement Orange Money vers la banque | Banque ⟶ monnaie électronique |
| Annulation d'encaissement | Contre-passation (jamais suppression) |
| Paie validée (M8) | Charges de personnel ⟶ personnel, retenues |
| Vente marketplace | selon le rôle de l'école (point de retrait) — à préciser |

Les comptes utilisés sont paramétrés une fois par référentiel ; la Direction
voit chaque écriture générée et peut la compléter, jamais la falsifier.

### 3.4 Pièces à plusieurs lignes, validation et clôture

- **Pièce** numérotée par journal et par exercice, avec N lignes
  débit/crédit dont la somme s'équilibre (contrôle en base).
- **Brouillard → validée** : une pièce validée devient immuable ; toute
  correction passe par une contre-passation (même modèle que le verrou des
  notes déjà livré).
- **Clôture d'exercice** : verrouillage définitif, report à nouveau,
  ouverture de l'exercice suivant.
- Les écritures M14 existantes deviennent des pièces à deux lignes : rien
  n'est perdu.

### 3.5 États financiers

PDF (comme les bulletins et reçus) et export tableur : journal, grand livre,
balance, puis bilan et compte de résultat au format de chaque référentiel ;
tableau des flux et notes annexes dans un second temps.

## 4. Découpage proposé

| Lot | Contenu | Valeur |
|---|---|---|
| **C1** | Référentiel par établissement + plans de référence + assistant de choix | Base de tout le reste |
| **C2** | Pièces multi-lignes, validation, contre-passation, clôture | Conformité (irréversibilité) |
| **C3** | Comptabilisation automatique : scolarité, Orange Money, CinetPay | Fin de la double saisie |
| **C4** | Bilan et compte de résultat (SMT, normal, SYCEBNL) en PDF | Dossier annuel |
| **C5** | Paie → comptabilité, tableau des flux, notes annexes, registre des donateurs | Complétude |

Chaque lot : migration + tests pgTAP + écrans Flutter + tests, comme les
chantiers précédents.

## 5. Points à trancher

1. **Inclure le SYCEBNL** comme référentiel à part entière (recommandé :
   écoles associatives et confessionnelles, sans doute nombreuses parmi les
   clients visés).
2. **Forme juridique de Bambino Emmaüs** (société ou association ?) : elle
   fixe le référentiel du pilote et donc le lot à soigner en priorité.
3. **Relecture par un expert-comptable** des plans de comptes et des schémas
   d'écritures avant la mise en production (indispensable ; peut se faire
   en parallèle de C1-C2).

## Sources

- [Acte uniforme relatif au droit comptable et à l'information financière (texte, art. 11, 13, 17, 18)](https://naturaljustice.org/wp-content/uploads/2022/04/Acte-uniforme-relatif-au-droit-comptable-et-a-linformation-financiere.pdf)
- [OHADA — présentation du SYSCOHADA révisé (entrée en vigueur, états du système normal et du SMT)](https://www.ohada.com/uploads/actualite/3999/presentation.pdf)
- [Droit Médias Finance — nouvel acte uniforme SYCEBNL (adoption décembre 2022, vigueur 1ᵉʳ janvier 2024)](https://droitmediasfinance.com/index.php/actualites/droit-ohada-affaires/432-ohada-un-nouvel-acte-uniforme-pour-la-comptabilite-des-associations-des-ordres-professionnels-des-fondations-et-assimiles)
- [DGB Cameroun — module de formation SYCEBNL (états par type d'entité, fonds propres avec ou sans droit de reprise)](https://www.dgb.cm/wp-content/uploads/wpfd/preview_files/MODULE_1_-SYSTEME_COMPTABLE_DES_ENTITES_A_BUT_NON_L(816d385f9dfa8b6e2f3637f77b97ac9c).pdf)
- [OHADA — Acte uniforme SYCEBNL](https://www.ohada.com/actualite/6569/acte-uniforme-relatif-au-systeme-comptable-des-entites-a-but-non-lucratif-sycebnl.html)
- [Programme de formation SYSCOHADA révisé (états du système normal, trésorerie incluant la monnaie électronique)](https://formarecrut.com/wp-content/uploads/2022/03/SYSCOHADA-REVISE.pdf)
