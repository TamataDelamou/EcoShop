# Registre des décisions et chantiers — EcoShop

Registre unique des directives reçues, décisions à arbitrer et chantiers
ouverts, avec leur priorité. Toute nouvelle directive du porteur de projet y
est inscrite **avant** d'être traitée ; chaque entrée renvoie vers le
document ou le commit qui la clôt.

Légende des priorités : **P0 — impérative** (bloque tout le reste),
**P1 — haute** (prochain chantier), **P2 — normale**.
Statuts : `ouvert`, `en cours`, `à arbitrer` (décision du porteur de projet
attendue), `clos`.

---

## Vue d'ensemble

| Réf. | Intitulé | Priorité | Statut |
|---|---|---|---|
| REG-01 | Directive Kernel — mutation en Control Plane (KER-MUT) | **P0** | en cours |
| REG-01.1 | K1 — Délestage des dépendances au Kernel (identité, référentiels) | **P0** | clos (2026-10-17) |
| REG-01.2 | K2 — Export du reporting (métriques + journaux d'audit) vers le Kernel | **P0** | livré côté EcoShop, contrat Kernel à confirmer |
| REG-01.3 | K3 — Jetons d'accès inter-services (Kernel → EcoShop) | **P0** | livré côté EcoShop, contrat Kernel à confirmer |
| REG-02 | Orange Money Guinée en direct (circuit établissement) | P1 | **validé** — L1 à L7 livrés ; reste le test réel (pilote Bambino Emmaüs) |
| REG-03 | Référentiel comptable : SYSCOHADA ou comptabilité simplifiée | P1 | C1 à C7 livrés (2026-10-18) — relecture expert-comptable avant production |
| REG-04 | Création et validation d'un nouvel établissement (fondateur) | P1 | livré (2026-10-17), courriels compris — mise en service à la création de la base Supabase |
| REG-07 | Thèmes : charte arabophone, identité visuelle par établissement, ambiances personnelles | P1 | livré (2026-10-17) — à vérifier sur le poste |
| REG-08 | Inscriptions et réinscriptions en ligne (parent, élève dès le collège) | P1 | **validé** (2026-10-18) — construction à lancer |
| REG-09 | Pointage des élèves au portail (QR code) et notifications push ; GPS abandonné | P1 | **validé** (2026-10-18) — après REG-08 |
| REG-05 | README et état d'avancement à resynchroniser (M16, D1-D6, facturation, lancement) | P2 | clos (2026-10-17) |
| REG-06 | Branches locales non publiées sur le dépôt distant | P2 | clos (2026-10-17) — 2 branches distantes à supprimer au push |

---

## REG-01 — Directive d'architecture : mutation du rôle du Kernel GSG

**Reçue le** : 2026-10-17. **Priorité** : P0 — impérative, traitée avant
REG-02 à REG-06.

**Principe directeur (texte de la directive)** : le Kernel GSG abandonne son
rôle de fournisseur de services transverses (authentification, référentiels
pays/devises) pour devenir exclusivement un **Control Plane centralisé
(Super-Admin / Hub de tableaux de bord)**.

**Conséquences sur le cadrage antérieur** — `ANALYSE_GLOBALE.md` §5 est
**amendé** sur deux points :

- §5.1 : `src/` n'est plus le contrat de référence d'un fournisseur
  d'identité ou de référentiels ; il est supprimé du dépôt (K1).
- §5.3 : la « fédération GSG ID, couche additive » est **abandonnée**.
  L'identité est exclusivement Supabase Auth natif + `public.profiles`.

### REG-01.1 — K1 : délestage des dépendances

État constaté avant intervention (2026-10-17) :

| Dépendance au Kernel | Constat | Action |
|---|---|---|
| Fédération GSG ID (`supabase/functions/gsg-id-federate`) | Seul appel sortant au Kernel (`/v1/identity/external-identities/link`). Jamais invoqué par le client Flutter. | **Retirée** (fonction + entrée `config.toml` + secrets `GSG_KERNEL_BASE_URL/API_KEY/TIMEOUT_MS`). |
| `gsg_id` recopié dans le JWT par `custom_access_token_hook` | Claim de confort issu de la fédération. | **Retiré du jeton** (migration `…1525`), puis **colonne supprimée** (migration `…1527`, après redéfinition du trigger `profiles_protege_colonnes()` qui la référençait). |
| Affichage « Identité GSG ID » (menu Profil Flutter) | Affichait « non fédérée » pour tous. | **Retiré** de l'écran et du modèle `Profil`. |
| Sessions / gestion des utilisateurs | Déjà 100 % Supabase Auth + `profiles`. | Aucune — conforme. |
| Référentiels pays / devise / langue / fuseau | Déjà portés localement (`etablissements.pays_code/devise_code/langue_code/fuseau_horaire`, `pays_pedagogiques`). Aucun appel au Referential Engine du Kernel. | Aucune — conforme. |

**Point tranché le 2026-10-17** (porteur de projet : « il faudra s'en
débarrasser ») : le dossier `src/` (miroir des contrôleurs du Kernel :
identity, referential, referential-engine, org, product, product-registry)
est supprimé, ainsi que la colonne `profiles.gsg_id`. Test `03_hook_jwt`
étendu (6/6) : colonne absente, trigger de protection toujours opérant.

### REG-01.2 — K2 : intégration du reporting (webhooks / API)

Livré côté EcoShop :

- **Edge Function `kernel-export`** : pousse par lots incrémentaux les
  journaux d'audit (`journal_audit`), les métriques techniques
  (`journal_metriques`) et un instantané des métriques clés vers les
  endpoints d'agrégation du Kernel. Chaque lot est signé par un jeton
  inter-services (voir K3). Non bloquante : un échec ne fait pas avancer le
  curseur, le lot est renvoyé au passage suivant.
- **Curseurs d'export** (`kernel_export_curseurs`) : reprise exacte après
  coupure réseau, aucune ligne envoyée deux fois en fonctionnement normal
  (le Kernel doit néanmoins dédoublonner sur `id`, livraison « au moins
  une fois »).
- **Minimisation des données** : les journaux d'audit sont exportés **sans
  `ancienne_valeur` / `nouvelle_valeur`** (qui peuvent contenir des copies
  de messages de groupes d'élèves mineurs ou des montants nominatifs). Seuls
  partent : identifiant, établissement, type d'entité, identifiant d'entité,
  champ modifié, auteur (uuid), horodatage. **À confirmer par le porteur de
  projet** si le Kernel doit recevoir davantage.
- **Métriques clés** (`kernel_metriques_cles()`) : établissements actifs,
  comptes actifs, inscriptions actives de l'année courante, encaissements
  de scolarité validés (jour / 30 jours), transactions de paiement par
  statut (30 jours), commandes marketplace (30 jours), santé de la base.

Contrat proposé au Kernel (à valider et implémenter côté Kernel) :
`docs/contrats/KERNEL_CONTROL_PLANE.md`.

### REG-01.3 — K3 : sécurisation des accès globaux

- **Choix : JWT inter-systèmes asymétriques (ES256)**, pas mTLS : les Edge
  Functions Supabase ne terminent pas elles-mêmes le TLS et n'exposent pas le
  certificat client, le mTLS n'y est donc pas applicable sans proxy dédié.
- **Sortant (EcoShop → Kernel)** : EcoShop signe chaque envoi avec sa clé
  privée (`KERNEL_INTERSERVICES_CLE_PRIVEE_JWK`) ; le Kernel vérifie avec la
  clé publique publiée par EcoShop (`/kernel-control-plane/jwks.json`).
- **Entrant (Kernel → EcoShop)** : Edge Function `kernel-control-plane`, en
  lecture seule (`/sante`, `/metriques`, `/audit`). Elle n'accepte qu'un JWT
  signé par le Kernel (vérifié via `GSG_KERNEL_JWKS_URL`), avec émetteur,
  audience `ecoshop`, scope `ecoshop:lecture` et durée de vie ≤ 5 min.
  Aucun accès en écriture n'est ouvert au Kernel.

### Vérification (2026-10-17)

- pgTAP, sur Postgres 16 avec bouchons des rôles/schémas Supabase, toutes
  migrations appliquées de bout en bout : `03_hook_jwt` 3/3,
  `57_kernel_control_plane` 18/18, non-régression `53_journalisation_audit`
  49/49.
- Deno : `interservices_test.ts` 12/12 (jeton valide, mauvaise clé, mauvaise
  audience, mauvais émetteur, expiré, durée trop longue, scope absent,
  `alg: none`, aller-retour signé/JWKS publié, clé invalide, idempotence,
  comparaison à temps constant) ; `deno check` des deux fonctions propre.
  Ajoutés à la CI (job `edge_functions`).
- Flutter : retrait d'un champ et d'une ligne d'affichage seulement ;
  `flutter analyze` / `flutter test` non exécutés ici (outil absent de
  l'environnement) — à confirmer par la CI ou sur le poste.
- Non vérifié : appel réel au Kernel (endpoints d'agrégation pas encore
  disponibles) et exécution des Edge Functions dans le runtime Supabase.

---

## REG-02 — Proposition d'implémentation d'un opérateur Mobile Money

**Priorité** : P1 (après REG-01). **Statut** : proposition remise le
2026-10-17 — `docs/propositions/REG-02_MOBILE_MONEY.md` — **validée sans
réserve par le porteur de projet le 2026-10-17** (Orange Money est présent
dans presque toutes les communes rurales).

**Établissement pilote** : **Bambino Emmaüs** — choix à confirmer
explicitement par le porteur de projet à réception du RCCM et des pièces
du fondateur (annoncée pour le 2026-10-18).

**Position du porteur de projet sur le point juridique** : GSG ne détient
jamais l'argent des utilisateurs ; il reste chez l'opérateur, sur le compte
marchand de l'établissement. C'est pourquoi tout établissement qui veut
encaisser par CinetPay ou mobile money fournit lui-même ses pièces
justificatives à l'opérateur (au besoin via le lien d'affiliation de la
plateforme). Un juriste sera consulté pour confirmation.

**Livré le 2026-10-17 (serveur, testé contre un faux serveur Orange)** :

| Lot | Contenu | Vérification |
|---|---|---|
| L1 | Migrations `…1528` (valeurs d'énumération) et `…1529` : identifiants marchands par établissement (deny-all), `transactions_mobile_money`, RPC d'activation, d'initiation, de crédit idempotent | pgTAP `58_orange_money_gn` 32/32 |
| L2 | `_shared/orange_money_client.ts` (jeton OAuth, création de paiement, statut) | Deno 7/7 |
| L3 | Edge Functions `initier_paiement_orange_money` et `recevoir_notification_orange_money` (notification authentifiée par empreinte puis **reconfirmée auprès d'Orange**) | `deno check` |
| L4 | Effets d'un paiement réussi : scolarité → encaissement `mobile_money` + reçu ; marketplace → `paiements` + commande payée | pgTAP 58 |

Non-régression : 03 (6/6), 38 (28/28), 50 (32/32), 53 (49/49), 56 (18/18),
57 (18/18). Non vérifié : appel réel à Orange (bac à sable non encore
obtenu) et exécution des Edge Functions dans le runtime Supabase.

**L5 — écrans Flutter, livrés le 2026-10-17** (`lib/features/paiement_mobile/`) :

- *Payer avec Orange Money* : bouton sur la fiche élève (parent confirmé ou
  élève, quand un reste à payer existe) et option « Orange Money » au
  paiement d'une commande marketplace. Écran de paiement : récapitulatif,
  montant animé, choix Totalité / Moitié / Autre montant (scolarité,
  plafonné au reste à payer), étapes expliquées, garantie « l'argent va
  directement sur le compte de l'établissement », erreurs serveur traduites.
- *Suivi du paiement* : ouverture de la page Orange Money, statut relu
  toutes les 3 s et à chaque retour dans l'application, animation
  d'attente, chronomètre, aide après 5 min, écran de confirmation (montant,
  référence Orange, date) ou d'échec ; solde/commandes rafraîchis au succès.
- *Espace Orange Money de la Direction* (menu Direction et Marketplace) :
  état d'activation, indicateurs du jour animés (montant confirmé,
  paiements, en cours, non aboutis), formulaire d'activation (mode test /
  production avec confirmation), identifiants jamais réaffichés, derniers
  paiements en direct.
- Android : lien de retour `io.gsg.ecoshop://paiement/retour` qui ramène
  l'application au premier plan ; dépendance `url_launcher` ajoutée.
- Tests : `test/features/paiement_mobile/paiement_mobile_test.dart`
  (domaine, plafonnement du montant, parcours complet jusqu'à la
  confirmation, montant imposé pour une commande, erreurs, suivi arrêté
  après un statut final, activation Direction).
- **À vérifier sur le poste** (aucune chaîne Flutter disponible dans
  l'environnement de développement assisté) : `flutter pub get`,
  `flutter analyze`, `flutter test`.

**L7 — relance et rapprochement, livrés le 2026-10-17** :

- Migration `…1530` + Edge Function planifiée
  `relancer_paiements_orange_money` (en-tête `x-declencheur-secret`,
  secret `PAIEMENTS_DECLENCHEUR_SECRET`, toutes les 5 min recommandé) :
  abandon des initiations jamais présentées au payeur (> 30 min), nouvelle
  interrogation d'Orange pour chaque transaction en cours (jamais deux
  fois en moins de 2 min), clôture « EXPIREE_SANS_CONFIRMATION » après
  24 h — toujours après une dernière vérification.
- Rapprochement du jour (`rapprochement_mobile_money`, personnel de
  l'établissement) : totaux confirmés par Orange (scolarité / marketplace),
  non aboutis, en cours, et écarts — paiement confirmé sans écriture
  valide, encaissement « OM: » sans paiement en ligne, encaissement
  automatique annulé après coup. Carte « Rapprochement » navigable jour par
  jour dans l'espace Orange Money de la Direction.
- Tests : pgTAP `59` 15/15 (et `58` 32/32, `38` 28/28 inchangés) ;
  `deno check` de la fonction ; test widget du rapprochement.

**Reste à faire** : le test réel avec l'établissement pilote dès l'accès au
bac à sable d'Orange Guinée (confirmer `CONFIG_ORANGE`), et la
planification effective des deux appels périodiques (`kernel-export`,
`relancer_paiements_orange_money`) au déploiement. Points à confirmer sur
la documentation Orange Guinée : chemins, code pays, devise de test, format
de la notification — regroupés dans `CONFIG_ORANGE`
(`_shared/orange_money_client.ts`). Recommandation : **Orange Money Guinée en direct** pour le
circuit établissement (scolarité, marketplace), CinetPay conservé pour le
circuit GSG et en repli (couvre aussi l'ex-MTN, devenu Areeba Guinée,
nationalisé en décembre 2025).

Contexte déjà acté : `ANALYSE_GLOBALE.md` §1.3 (A3) et §5.5 prévoient un
**Port Paiement agnostique** avec CinetPay en première implémentation (livrée,
étape facturation (b)) et un adaptateur **Mobile Money local**
(Orange Money / MTN MoMo / Wave) en seconde implémentation, activable par pays
ou par établissement.

À produire : une proposition comparant l'intégration directe d'un opérateur
(API Orange Money, MTN MoMo…) et le passage par un agrégateur, pour le marché
guinéen d'abord (frais, délais de règlement, contrat marchand requis,
disponibilité d'un bac à sable, webhooks), puis l'adaptateur correspondant
derrière le port existant (`_shared/cinetpay_client.ts` sert de modèle).

---

## REG-03 — Référentiel comptable : SYSCOHADA ou comptabilité simplifiée

**Priorité** : P1. **Statut** : **décidé le 2026-10-17 — option 2** (voir
la décision en fin de section). À construire.

Contexte : M14 a été livré en **comptabilité sans OHADA** (partie double
simplifiée, `docs/COMPTABILITE.md`). Lors des échanges avec de futurs
utilisateurs, **une partie demande une comptabilité conforme au système
OHADA (SYSCOHADA révisé)**, une autre partie ne l'estime pas nécessaire.

Options à arbitrer :

1. **Statu quo** — comptabilité simplifiée seule ; les établissements qui
   tiennent une comptabilité OHADA exportent vers leur logiciel comptable.
2. **Référentiel comptable paramétrable par établissement** — l'établissement
   choisit « simplifiée » ou « SYSCOHADA » ; le moteur d'écritures reste
   unique, seul le plan de comptes et les états de sortie changent
   (journal, grand livre, balance, et pour SYSCOHADA bilan / compte de
   résultat au format réglementaire).
3. **SYSCOHADA pour tous** — plus lourd pour les petits établissements, qui
   sont précisément ceux qui ne le demandent pas.

Recommandation technique (non décisionnelle) : l'option 2 répond aux deux
groupes sans casser M14. Décision attendue avant tout développement.

**Décision du porteur de projet (2026-10-17)** : option 2 — « faire les
deux et laisser à l'établissement de choisir lequel appliquer dans sa
comptabilité ». Les deux référentiels (simplifié actuel et SYSCOHADA révisé)
coexistent ; chaque établissement choisit le sien. Développement à engager
après recherche comparative (règle : rechercher l'état de l'art avant
chaque implémentation).

**Proposition validée sans réserve (2026-10-17)** —
`docs/propositions/REG-03_COMPTABILITE.md` : quatre référentiels
(simplifié, SYSCOHADA SMT, SYSCOHADA normal, **SYCEBNL** ajouté), plans de
référence pré-remplis, comptabilisation automatique, pièces multi-lignes,
validation/clôture, états financiers ; lots C1 → C5 ; relecture par un
expert-comptable inscrit en Guinée avant mise en production.

**Pilote** : Bambino Emmaüs appartient à un **réseau national
d'établissements de l'Église Protestante Nationale** ; chaque établissement
est représenté par le pasteur de la localité au moment de sa création (nom
porté au RCCM). Référentiel présumé : **SYCEBNL** (entité confessionnelle) —
à confirmer à la lecture du RCCM. Le lot SYCEBNL est donc à soigner en
priorité. Le caractère « réseau » rejoint M19 (Réseau d'établissements).

**Lot C1 livré (2026-10-17)** — migration `…1534` :
- plans de référence en lecture seule (`plans_comptables_reference`) :
  SYSCOHADA révisé (commun SMT / normal, numéros et intitulés relevés sur le
  plan officiel) et SYCEBNL (relevé sur une copie non officielle, toutes les
  lignes `a_relire`), réduits aux comptes utiles à une école, plus des
  sous-comptes EcoShop signalés (`extension_ecoshop`) : scolarité,
  inscription, cantine, transport, familles débitrices, Orange Money (5521) ;
- seuil SMT « services » (`seuils_smt_services`) : 30 M FCFA (XOF/XAF) ;
  équivalent GNF indicatif 450 M (cours du 2026-10-04), **à confirmer** ;
- `recommander_referentiel_comptable` (forme juridique, chiffre d'affaires,
  souhait) : recommande, ne décide pas ; `choisir_referentiel_comptable`
  (Direction) : charge le plan, retire les comptes libres sans écriture,
  historise le choix ; SMT ↔ normal toujours possible (même plan) ;
  changement de plan refusé dès qu'une écriture existe
  (`ECRITURES_EXISTANTES`, à lever au lot C2 par l'ouverture d'exercice) ;
- comptes réglementaires verrouillés (`COMPTE_REGLEMENTAIRE_PROTEGE`) ;
  sous-comptes obligatoirement rattachés à un compte réglementaire, nature
  et parent hérités (`SOUS_COMPTE_INVALIDE` sinon) ; plan simplifié inchangé.
- Flutter : écran « Référentiel comptable » (menu Comptabilité >
  Configuration) — référentiel actuel, trois questions, recommandation
  motivée, alternatives, confirmation ; plan comptable affiché en arbre avec
  cadenas sur les comptes réglementaires ; natures actif/passif/capitaux
  reconnues.
- Vérification : pgTAP `63` 30/30 (non-régression M14 31-33 : 12/12) ;
  tests Flutter `test/features/comptabilite/referentiel_comptable_test.dart`
  — **à lancer sur le poste**.

**Lot C2 livré (2026-10-17)** — migration `…1535`, exigences de l'Acte
uniforme relatif au droit comptable traduites une à une :
- pièces à N lignes (`pieces_comptables`, `lignes_pieces_comptables`) :
  brouillard modifiable, validation seulement si débit = crédit ;
  **numérotation continue** par journal et exercice attribuée à la
  validation (art. 66 ; un brouillard supprimé ne laisse pas de trou) ;
  référence `JOURNAL-AAAA-NNNNNN` ;
- **irréversibilité** (art. 22) : pièce validée et lignes figées, y compris
  hors des fonctions (déclencheurs) ; aucune écriture directe ;
- **contre-passation en négatif** (art. 20), motivée, unique, liée à la
  pièce d'origine ; impossible sur un exercice clôturé (report à nouveau) ;
- OHADA : imputation sur comptes de détail seulement ; saisie M14 à deux
  comptes fermée (`SAISIE_PAR_PIECES_OBLIGATOIRE`) ; elle reste ouverte en
  simplifié ;
- **exercices** contigus ; OHADA : année civile (art. 7), premier exercice
  libre ; **clôture de période** (art. 22 3°) qui fige toutes les dates
  antérieures, pièces comme écritures M14 ; **clôture d'exercice**
  (Direction) : résultat, à-nouveaux validés dans l'exercice suivant (créé
  au besoin), résultat porté en 131/139 (OHADA) ou 13 (simplifié) ;
- journal, grand livre et balance lisent pièces + écritures M14 ; la
  balance porte sur l'exercice de la date (à-nouveaux compris).
- Flutter : écrans « Pièces comptables » (filtres, détail, validation,
  modification, suppression du brouillard, contre-passation), saisie
  multi-lignes avec totaux et équilibre en direct, « Exercices et
  clôtures » ; l'ancienne saisie à deux comptes n'est proposée qu'en
  simplifié.
- Vérification : pgTAP `64` 49/49 (non-régression 31-33, 61-63 vertes) ;
  tests Flutter `pieces_comptables_test.dart` — **à lancer sur le poste**.

Reste après C2 : changement de plan de comptes pour une comptabilité qui a
déjà un historique (table de correspondance, lot dédié) ; signaux IA M14
(trésorerie, tendances, anomalies) encore limités aux écritures M14 — à
étendre aux pièces avec le lot C4.

**Lot C3 livré (2026-10-17)** — migration `…1536` :
- chaque encaissement de frais scolaires (espèces, **Orange Money**,
  virement, chèque) produit sa pièce **validée** sans ressaisie : débit du
  compte du moyen de paiement (571 / 5521 / 521), crédit du compte du type
  de frais (SYSCOHADA 70611-70618, SYCEBNL 70521-70528) ; journaux CAI, OM,
  BQ créés au besoin ; une seule pièce par encaissement (index unique) ;
- l'annulation d'un encaissement produit sa **contre-passation** ; une pièce
  automatique ne s'annule pas à la main (`PIECE_AUTOMATIQUE`) ;
- **la comptabilité ne bloque jamais l'encaissement** : sans exercice, en
  période clôturée ou sans compte, un incident est consigné ;
  `comptabiliser_en_attente` rattrape tout de façon idempotente ;
- comptes remplaçables par l'école (`definir_regle_comptabilisation`,
  comptes de détail seulement) ; en simplifié, rien d'automatique sans
  règles ;
- Flutter : écran « Écritures automatiques » (état, incidents expliqués,
  « Rattraper maintenant », comptes utilisés modifiables).
- Vérification : pgTAP `65` 29/29 (non-régression Orange Money 58-59,
  comptabilité 31-33 et 63-64 vertes) ; tests Flutter
  `comptabilisation_automatique_test.dart` — **à lancer sur le poste**.

Choix comptables à faire valider par l'expert-comptable : produit reconnu à
l'encaissement ; or l'année scolaire (sept.-juin) chevauche l'exercice
civil — en Système normal, la part des frais couvrant l'exercice suivant
relève des **produits constatés d'avance** (régularisation au lot C4).
Hors périmètre : ventes marketplace (revenu du vendeur), facturation GSG.

**Lot C4 livré (2026-10-17)** — migration `…1537` :
- `etat_financier` : bilan actif (brut, amortissements, net), bilan passif,
  compte de résultat, colonnes N et N-1, contrôle actif = passif, comptes
  non repris signalés, tableau de trésorerie (état de base du SMT) ;
  SYSCOHADA aux références officielles (AD…BZ, CA…DZ, TA…XI, relevées sur
  des liasses publiées) ; SYCEBNL en présentation **provisoire** ;
  simplifié par nature de compte ; rubriques stockées comme données
  (`rubriques_etats_financiers`) : un ajustement de l'expert-comptable ne
  demande pas de code ;
- **produits constatés d'avance** (477) : prorata de l'année scolaire de
  l'inscription au-delà du 31/12 (scolarité, cantine, transport ; les frais
  d'inscription restent acquis), pièce au 31/12 et extourne au 1er janvier,
  une seule fois par exercice ; aperçu avant passage ;
- prévision de trésorerie, tendances et anomalies (doublons de pièces)
  lisent désormais les pièces ;
- Flutter : écran « États financiers » (choix de l'exercice, résultat,
  équilibre, onglets Actif / Passif / Résultat / Trésorerie, carte des
  produits constatés d'avance) et **export PDF** (A4, en-tête et logo de
  l'établissement, mention « provisoire »).
- Vérification : pgTAP `66` 29/29 (non-régression 33, 48, 63-65 vertes) ;
  tests Flutter `etats_financiers_test.dart` — **à lancer sur le poste**.

**Lot C5, partie 1 livrée (2026-10-17) — la paie passe en comptabilité** —
migration `…1538` :
- bulletin M8 **validé** → constatation datée de la fin de période, journal
  PAIE : débit charges de personnel (brut = base + primes), crédit salaires
  dus (net), crédit retenues ; **payé** → règlement : débit salaires dus,
  crédit trésorerie ;
- comptes par défaut : SYSCOHADA 661 / 422 / 447 / 571, SYCEBNL
  66 / 422 / 44 / 571 ; remplaçables par l'école (règles `paie:*`) ;
- la comptabilité suit toujours le bulletin : modifié, ramené en
  brouillon, archivé ou supprimé après coup → les pièces devenues fausses
  sont contre-passées, puis les bonnes sont créées (jamais de
  modification d'une pièce validée) ;
- la paie n'est jamais bloquée : sans exercice ouvert ou en période
  clôturée, un incident est consigné et le rattrapage le résout ;
  simplifié sans règles « paie » : rien d'automatique ;
- Flutter : l'écran « Écritures automatiques » affiche les bulletins à
  reporter, les incidents de paie expliqués et une section « Comptes
  utilisés — paie ».
- Limites : les retenues M8 sont un total unique (un seul compte) ; les
  charges patronales ne sont pas calculées par M8 — à traiter avec
  l'expert-comptable.
- Vérification : pgTAP `67` 31/31, régression 01-66 inchangée ; tests
  Flutter `comptabilisation_automatique_test.dart` — **à lancer sur le
  poste**.

**Lot C5, partie 2 livrée (2026-10-17) — registre des donateurs et des
dons** — migrations `…1539` (audit) et `…1540`, recherche préalable sur le
SYCEBNL (comptes 704x « revenus liés à la générosité », 165 « fonds
affectés », 7925 « reprises de fonds affectés ») et sur les logiciels de
gestion des dons :
- donateurs (personne, organisation, église), accord de contact, archivage
  (jamais supprimé après un don) ; accès direction et comptables seulement ;
- dons : don, legs, denier du culte, quête, mécénat, parrainage, autre ;
  **reçu numéroté sans trou par année** (REC-2026-000001) ; un don ne se
  modifie jamais : annulation motivée (contre-passation, journal d'audit)
  puis ressaisie ; option « anonyme » (nom sur le reçu, jamais dans les
  listes) ;
- campagnes : libres, **projets à fonds affectés**, parrainage d'élèves ;
  objectif, collecté, employé, disponible ; type figé dès le premier don ;
- comptabilité automatique : SYCEBNL D trésorerie / C 7041 à 7048 selon la
  nature ; projet → C 165 ; emploi des fonds → D 165 / C 7925 (journal
  OD), refusé au-delà des fonds reçus ; SYSCOHADA → C 758 ; simplifié →
  selon les règles de l'école ; comptes SYCEBNL ajoutés (7045-7048, 79,
  792, 7925, 475, 636), y compris pour les écoles déjà en SYCEBNL ;
- engagements réguliers (parrainage mensuel, promesse) : attendu à ce jour,
  reçu, retard ;
- synthèse annuelle : total et évolution, nouveaux donateurs, fidèles,
  donateurs à remercier et relancer (ont donné l'an dernier, pas encore
  cette année, et acceptent d'être contactés), principaux donateurs ;
- Flutter : écran « Dons et donateurs » (Synthèse, Dons, Donateurs,
  Campagnes), saisie avec montant en lettres, **reçu PDF** (mention
  « ANNULÉ » le cas échéant) et **relevé annuel PDF** par donateur.
- Limites : la page de don en ligne (Orange Money) et les dons en nature
  (7542, stocks) sont à venir ; la valeur fiscale des reçus en Guinée
  n'est pas affirmée — à confirmer avec l'expert-comptable.
- Vérification : pgTAP `68` 46/46, régression 01-67 inchangée ; tests
  Flutter `dons_test.dart` — **à lancer sur le poste**.

**Lot C5, partie 3 livrée (2026-10-17) — tableau des flux de trésorerie
complet et notes annexes** — migration `…1541`, modèles relevés sur une
liasse SYSCOHADA révisé publiée (BRVM) et sur le modèle SYCEBNL :
- TFT au modèle du référentiel : **SYSCOHADA** ZA → ZH (méthode indirecte :
  CAFG, variations du besoin de financement, investissement, capitaux
  propres, capitaux étrangers) ; **SYCEBNL** ZA → ZG (méthode directe :
  cotisations, subventions, générosité, manifestations, autres revenus,
  fournisseurs, personnel ; fonds affectés en fonds propres) ; simplifié ;
  colonne N-1 ;
- chaque mouvement de trésorerie est rattaché à la contrepartie de **sa
  pièce** (classement exact, sans estimation) ; les à-nouveaux font la
  trésorerie d'ouverture, jamais un flux ;
- contrôles publiés : trésorerie de clôture = trésorerie du bilan ; en
  SYSCOHADA, rapprochement méthode indirecte / flux constatés pièce par
  pièce (tout écart est affiché, jamais masqué) ;
- rubriques stockées comme données (`rubriques_flux_tresorerie`) ;
- notes annexes calculées : méthodes comptables (texte généré),
  immobilisations, créances et dettes, trésorerie, variation des fonds
  propres, produits et charges N / N-1, personnel, produits constatés
  d'avance ; SYCEBNL : générosité par nature, fonds affectés par projet
  (report, reçus, employés, solde), engagements reçus ;
- notes rédigées par l'école (faits marquants, continuité, événements
  postérieurs, engagements hors bilan, autres informations, précisions
  sur les méthodes), figées à la clôture de l'exercice ;
- Flutter : onglets « Flux de trésorerie » et « Notes annexes » dans les
  états financiers ; le PDF comprend désormais le TFT et les notes.
- Limites : présentation SYCEBNL toujours provisoire (copie non
  officielle) ; CAFG par la méthode additive (dotations, reprises, cessions)
  et dépréciation des stocks hors CAFG — à valider par l'expert-comptable.
- Vérification : pgTAP `69` 38/38, régression 01-68 inchangée ; tests
  Flutter `etats_financiers_test.dart` — **à lancer sur le poste**.

**REG-03 : lots C1 à C5 livrés.** Reste avant mise en production : relecture
par un expert-comptable inscrit en Guinée (plans, rubriques, notes),
confirmation du référentiel de Bambino Emmaüs (RCCM) et du seuil SMT en GNF,
puis le changement de plan avec historique (lot dédié).

**Lot C6 livré (2026-10-18) — changement de plan de comptes avec
historique** — migration `…1542` :
- le changement (simplifié ↔ SYSCOHADA ↔ SYCEBNL) prend effet au **premier
  jour d'un exercice** sans écriture (hors à-nouveaux), jamais en cours
  d'exercice ; le choix direct reste refusé dès qu'il y a des écritures ;
- **table de correspondance proposée** pour chaque compte utilisé : même
  compte, correspondance connue (70611 → 70521, 661 → 66, 447 → 44…), même
  numéro à vérifier, compte de rattachement, nature (caisse, banque) ;
  corrigeable ligne par ligne, y compris pour garder un sous-compte de
  l'école (5711 sous 571) ;
- à l'application : les états, tableaux des flux et notes des exercices
  antérieurs sont **archivés tels que publiés** ; les anciens comptes sont
  retirés et renumérotés (« 70611* », « ancien plan ») ; aucune pièce
  n'est modifiée ; les règles d'écritures automatiques suivent ; la note 1
  de l'exercice explique le changement de méthode ;
- l'historique est **lu à travers la correspondance** (balance, grand
  livre, états, tableau des flux, notes) : l'exercice précédent se présente
  dans le nouveau plan et la colonne N-1 reste comparable (bonne pratique
  de retraitement), la version d'origine restant consultable ;
- Flutter : quand le choix direct est refusé, l'écran « Référentiel
  comptable » propose « Préparer le passage en … » → table de correspondance
  (lignes à vérifier, recherche du compte cible, sous-compte), puis
  application confirmée.
- Vérification : pgTAP `70` 36/36, régression 01-69 inchangée ; tests
  Flutter `changement_plan_test.dart` — **à lancer sur le poste**.

**Lot C7 livré (2026-10-18) — la comptabilité d'abord hors connexion**
(règle permanente du porteur de projet : « hors connexion d'abord dans tout
ce qu'on donnera ») — migration `…1543`, pratiques des caisses hors ligne
(clé unique générée par l'appareil, dédoublonnage au serveur, file de
régularisation des refus) :
- **consultation sans réseau** : états financiers, tableau des flux, notes
  annexes, écritures automatiques, synthèse et registre des dons, reçus,
  relevés, exercices et pièces sont gardés sur l'appareil à chaque
  consultation et resservis sans réseau ; les PDF restent imprimables ;
  un bandeau dit de quand datent les données ;
- **saisie sans réseau** : dons (reçu **provisoire** PROV-<appareil>-0001,
  numéro définitif sans trou attribué à l'envoi, le reçu définitif rappelle
  le provisoire), donateurs, campagnes, engagements, annulations de dons,
  notes annexes rédigées, **brouillards** de pièces ; tout part en file et
  s'affiche aussitôt dans les listes ;
- **en ligne seulement, expliqué à l'écran** : validation d'une pièce (elle
  attribue le numéro continu, art. 66), clôtures, contre-passations, emploi
  des fonds affectés (solde vérifié au serveur), produits constatés
  d'avance, rattrapage des écritures automatiques, changement de plan ;
- serveur : `enregistrer_don` accepte la clé de l'appareil (un second envoi
  renvoie le reçu déjà attribué), `enregistrer_piece_hors_ligne` (brouillard
  sous la clé de l'appareil, pièce validée jamais touchée) ;
- **refus au retour du réseau** (période clôturée entre-temps, droits) :
  l'opération n'est plus réessayée, elle s'affiche dans le bandeau avec la
  raison (« Voir » → « Compris ») ; les pannes de réseau, elles, sont
  réessayées ;
- sécurité : le cache comptable (dont les données des donateurs) est purgé
  à la déconnexion.
- Vérification : pgTAP `71` 16/16, régression 01-70 inchangée ; tests
  Flutter `lecture_hors_ligne_test.dart`, `sync_engine_rejet_test.dart`,
  `comptabilite_hors_ligne_test.dart` — **à lancer sur le poste**.

**Dossier de relecture pour l'expert-comptable** : document partagé
« EcoShop — Dossier de relecture comptable » (décisions attendues, plans,
écritures automatiques, pièces et clôtures, états, tableau des flux, notes
annexes, questions à trancher).

---

## REG-07 — Thèmes : trois niveaux de personnalisation

**Demandé le** : 2026-10-17 (« chacun est à des niveaux d'utilisation
différents »). **Statut** : livré le 2026-10-17.

État de départ : 3 chartes par pays (francophone, anglophone, lusophone),
clair/sombre, contraste élevé (M15bis, D4).

| Niveau | Qui décide | Livré |
|---|---|---|
| **A — Charte arabophone** | automatique (pays de l'établissement) | 4ᵉ charte `arabophone_mixte` clair/sombre (sarcelle et cuivre sur fond sable) ; les pays arabophones n'utilisent plus la charte francophone par repli. |
| **B — Identité de l'établissement** | la Direction | Couleur principale (nuancier de 16 teintes ou code `#RRGGBB`) et logo. La couleur est **ajustée automatiquement** (même teinte, luminosité corrigée) pour rester lisible (WCAG AA) en clair et en sombre — jamais refusée ; l'aperçu clair/sombre le montre en direct. Le logo s'affiche à côté du nom de l'école et dans l'en-tête des reçus et bulletins. Migration `…1531` : colonnes `couleur_identite` / `logo_chemin`, bucket public `logos-etablissements` (images, 1 Mo), dépôt réservé à la Direction dans le dossier de SON établissement, RPC `definir_identite_visuelle`. Écran : menu Direction > « Identité visuelle ». |
| **C — Ambiance personnelle** | chaque utilisateur, sur son appareil | Océan, Savane, Graphite (clair/sombre), ou « Charte de l'établissement » (par défaut). Écran Apparence. Ne s'applique jamais aux documents imprimés. |

Ordre de priorité : contraste élevé > ambiance personnelle > charte de
l'établissement (avec sa couleur ajustée). Toutes les nouvelles palettes
passent le seuil WCAG AA (4,5:1) — vérifié par calcul et par
`test/core/theme/app_palettes_test.dart`.

Vérification : pgTAP `60_identite_visuelle_etablissement` 14/14 (non-régression
58 : 32/32) ; tests Flutter ajoutés (`couleur_identite_test`,
`ecran_identite_visuelle_test`, ambiance dans `ecran_preferences_apparence_test`
et `theme_preference_store_test`) — **`flutter analyze` / `flutter test` à
lancer sur le poste**.

## REG-04 — Création et validation d'un nouvel établissement (fondateur)

**Priorité** : P1. **Statut** : livré le 2026-10-17 (cahier §5.3 et §30.1).

Parcours livré :

1. **Fondateur** — sur l'écran « Qui êtes-vous ? » (compte neuf), carte
   « Vous dirigez une école ? » → formulaire : nom, pays (référentiel),
   ville, nombre d'élèves, adresse, n° d'autorisation d'ouverture,
   téléphone, courriel, message. Puis suivi de la demande (envoyée → examen
   GSG → ouverture), motif affiché en cas de refus avec possibilité de
   soumettre une demande corrigée. Une Direction existante peut aussi
   demander un nouvel établissement (menu Direction).
2. **Administrateur GSG** — menu « Demandes d'établissement » : fiche
   complète de chaque demande, Valider (confirmation) ou Refuser (motif
   obligatoire, transmis au demandeur).
3. **Validation** — l'établissement est créé avec la devise, la langue et
   le fuseau du pays ; le demandeur devient Direction (jamais
   auto-attribué), est rattaché et l'établissement devient son
   établissement actif : il entre directement dans son espace.

Migration `…1532` (table `demandes_etablissement`, une demande en cours par
compte, aucune écriture directe ; RPC `soumettre_demande_etablissement`,
`traiter_demande_etablissement`, `demandes_etablissement_a_traiter`).
Vérification : pgTAP `61` 20/20 ; tests Flutter
`test/features/creation_etablissement/` (à lancer sur le poste).

**Courriels (livrés le 2026-10-17)** — fournisseur : **Brevo** (compte GSG
existant), domaine d'envoi `globalservicegroupe.com`. Le fondateur reçoit un
accusé de réception, puis la décision (acceptation, ou refus avec motif) ;
l'équipe GSG est alertée de chaque nouvelle demande. Conception « boîte
d'envoi transactionnelle » : migration `…1533` (`notifications_sortantes`,
mise en file dans la même transaction que l'événement, réservation
`FOR UPDATE SKIP LOCKED` avec bail, nouvel essai à attente croissante,
6 tentatives, clé d'idempotence, purge à 90 jours, indicateurs de
supervision) ; Edge Function `envoyer_notifications` ; modèles HTML + texte
versionnés dans le dépôt, sans image distante ni pistage. Vérification :
pgTAP `62` 26/26, Deno `courriel_test.ts` 9/9. Mise en service :
`docs/DEPLOIEMENT_COURRIEL.md` (DNS Brevo, clé API, secrets, planification,
SMTP de Supabase Auth).

**Reste** : la base Supabase EcoShop n'existe pas encore (limite de deux
projets gratuits atteinte avec AssoShop et PharmaConnect) — création prévue
au moment du pilote Bambino Emmaüs, directement en formule Pro. Canal SMS
pour les fondateurs inscrits par téléphone seulement : à arbitrer entre
l'API SMS Orange Guinée et Brevo (nom d'expéditeur à pré-enregistrer
auprès des opérateurs, environ 3 semaines).

Dette d'origine tracée le 2026-09-17
(`docs/AUDIT_ECOSHOP_FLUTTER.md`, commit `7c96c35`) : aucun parcours ne
permet aujourd'hui de créer un établissement autrement que par insertion SQL
directe — aucun client réel ne peut être accueilli sans lui.

## REG-08 — Inscriptions et réinscriptions en ligne

**Priorité** : P1. **Statut** : validé le 2026-10-18 — proposition
`docs/propositions/REG-08_INSCRIPTION_EN_LIGNE.md`.

Décisions : campagne datée par la Direction (réinscriptions puis nouvelles
demandes, places par classe, liste d'attente) ; en primaire le parent seul,
**dès le collège l'élève comme le parent** peuvent inscrire, réinscrire et
payer (élèves à leur propre charge — on enregistre qui paie) ; **aucun
blocage automatique** pour impayé ou sanction, décision de la Direction au
cas par cas ; hors connexion d'abord (dossier et pièces sans réseau,
guichet assisté, espèces conservées).

## REG-09 — Pointage au portail et notifications

**Priorité** : P1. **Statut** : validé le 2026-10-18 — proposition
`docs/propositions/REG-09_POINTAGE_PORTAIL.md`.

Décisions : **GPS abandonné** ; pointage par carte QR scannée au portail
(hors connexion), appel en classe = preuve officielle ; notifications
automatiques **push** (arrivée/sortie, absence à l'heure limite, sortie
anticipée), sans alerte d'absence tant que le portail n'a pas synchronisé ;
**GSG ne prend pas en charge les SMS** : l'établissement achète des crédits
SMS à GSG (revente), décomptés à l'envoi ; sans crédit, push seul.

## REG-05 — README à resynchroniser

Le README annonce encore M16 « bloqué / à venir » alors que M16, D1-D6, la
facturation (a-d), la journalisation et les quatre points bloquants avant
lancement sont clos.

**Clos le 2026-10-17** : README réécrit — état réel des modules (M16 livré,
M17-M18 à venir, M19 et M20 partiels), tableau des chantiers transverses
(D1-D6, facturation, journalisation, bloquant lancement, REG-01/02/04/07),
liste complète des Edge Functions à déployer, secrets Brevo, commandes de
test (Flutter 440, Deno, 62 scripts pgTAP), prochaines étapes, index de la
documentation. Libellés de la CI mis à jour (ils citaient encore M0→M15 et
« RLS 01→36 » alors que tous les scripts sont exécutés).

## REG-06 — Branches non publiées

Une vingtaine de branches de travail n'existent qu'en local (seules `main`,
`m14-comptabilite-sans-ohada` et `m15-marketplace-sans-auth` sont sur le
dépôt distant). À publier ou à supprimer après vérification de leur fusion
dans `main`.

**Clos le 2026-10-17** : vérification faite branche par branche — les 25
branches locales étaient **toutes déjà fusionnées** dans `main`, sans aucun
commit propre. Chacune a été conservée sous forme d'étiquette annotée
`archive/<nom>` (trace permanente du découpage par module, restaurable par
`git switch -c <nom> archive/<nom>`), puis supprimée. Il ne reste que
`main`. Côté GitHub : étiquettes publiées par `git push origin --tags`, et
les deux branches distantes en double supprimées par
`git push origin --delete m14-comptabilite-sans-ohada m15-marketplace-sans-auth`.
