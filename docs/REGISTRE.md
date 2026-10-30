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
| REG-08 | Inscriptions et réinscriptions en ligne (parent, élève dès le collège) | P1 | **livré** (2026-10-18) — serveur, écrans familles et Direction, hors connexion ; à vérifier sur le poste |
| REG-09 | Pointage des élèves au portail (QR code), notifications push, crédits SMS (alertes et relances d'impayés) ; GPS abandonné | P1 | **livré** (2026-10-21) — réception du push : REG-11 ; reste les comptes Firebase et Orange SMS au déploiement |
| REG-10 | Encaissement de scolarité au guichet hors connexion, numéro de reçu continu | P1 | **livré** (2026-10-21) — à vérifier sur le poste |
| REG-11 | Notifications push dans l'application (Firebase, Android) : réception, bandeau, ouverture, déconnexion | P1 | **livré** (2026-10-21) — projet Firebase à créer, voir `docs/DEPLOIEMENT_PUSH.md` ; iOS au compte Apple |
| REG-12 | Kit de mise en service : script de déploiement, tâches planifiées, codes de connexion par Orange SMS, Android prêt pour le Play Store | **P0** | **livré** (2026-10-22) — à exécuter à la création du projet Supabase, voir `docs/MISE_EN_SERVICE.md` |
| REG-13 | M19 — Réseaux d'établissements (cahier ch. 28, 30.1, 30.3) | P1 | **livré** (2026-10-22) — à vérifier sur le poste |
| REG-14 | M18 — Transport scolaire (cahier ch. 24) | P1 | **livré** (2026-10-22) — à vérifier sur le poste et sur un téléphone Android (GPS) |
| REG-15 | M17 — Bibliothèque physique (cahier ch. 25) | P1 | **livré** (2026-10-22) — à vérifier sur le poste ; bibliothèque numérique (ch. 26) à venir |
| REG-16 | Connexion par e-mail et Google, téléphone au profil (SMS suspendu) | P1 | **livré** (2026-10-22) — à vérifier sur le poste ; réglages Google à faire (MISE_EN_SERVICE §5.1) |
| REG-17 | Réseaux : politique de frais (autonome, indicative, commune) et transferts d'élèves | P1 | **livré** (2026-10-22) — à vérifier sur le poste |
| REG-18 | Sécurité d'accès : inscription en étapes, code secret et verrou, identifiant EcoShop, protections à la liaison | **P0** | **livré** (2026-10-23), invitations du personnel comprises — à vérifier sur un téléphone Android |
| REG-19 | Annonces, cahier de liaison, messagerie : brancher sur le serveur (prototypes masqués en version publiée) | P1 | **lots 1 et 2 livrés** (2026-10-23) : annonces, cahier de liaison ; messagerie privée et groupes de classe **en attente** |
| REG-20 | Référentiel pédagogique et paramètres globaux livrés en production (champ « Pays » vide) ; séries du lycée guinéen | **P0** | **livré** (2026-10-24, `48574fe`) — tâche **ouverte** : séries SM, SE, SS et coefficients officiels, avant le premier lycée |
| REG-21 | Accueil en pastilles, barre de navigation du bas, profil allégé, raccourcis et recherche | P1 | **livré** (2026-10-26) — à vérifier sur un téléphone Android (migration 1569 à appliquer) |
| REG-22 | Code du compte vérifié sur tout nouvel appareil, appareils connectés, postes du personnel et lecture par permission | **P0** | **livré** (2026-10-26) — à redéployer sur Supabase (migrations 1561 à 1568, fonctions `pas_moi` et `envoyer_notifications`) et à vérifier sur un téléphone Android |
| REG-23 | Retours du test sur téléphone (2026-10-28) : accueil qui remonte, ouverture hors connexion, mise en route de l'école, écoles confirmées (GSG), programme officiel, photo de profil, slogan, calendriers en français, APK | P1 | **livré** (2026-10-28) — migrations 1570 à 1572 et 1574 à appliquer ; à vérifier sur un téléphone Android |
| REG-24 | Emploi du temps dynamique et automatisé (modèles EDT/Pronote, Horarium) | P1 | **livré** (2026-10-28) — migration 1573 à appliquer ; à vérifier sur le poste avec les classes et cours d'une école pilote |
| REG-25 | Accueil : affichage défilant ou fixe, 2 ou 3 pastilles par ligne | P2 | **livré** (2026-10-28) — à vérifier sur un téléphone Android |
| REG-26 | Autorisations des postes approfondies (délégation des actions réservées à la Direction) | P1 | **livré** (2026-10-28) — migration 1575 à appliquer |
| REG-27 | Code d'invitation à saisir ; espaces d'un même compte (parent et enseignant) | P1 | **livré** (2026-10-28) — migration 1576 à appliquer |
| REG-28 | Actions des écrans visibles, avec leur libellé, sous la barre de titre (25 écrans) | P1 | **livré** (2026-10-29) — à vérifier sur un téléphone Android |
| REG-29 | Connexion Google : un seul sélecteur de comptes | P1 | **livré** (2026-10-29) — à vérifier sur un téléphone Android |
| REG-30 | **Feuille de route** : ce qui reste à faire, par priorité (état des lieux du 2026-10-28) | P1 | **ouvert** — voir juste sous ce tableau |
| REG-31 | Pages de confidentialité, conditions d'utilisation et suppression de compte (site GSG) ; suppression du compte dans l'application | **P0** | **livré** (2026-10-29) — champs ⟦siège, RCCM⟧ à compléter, relecture de l'avocat, mise en ligne (`site_gsg/README.md`), migration 1577 |
| REG-32 | Espaces par école : un rôle dans une école (enseignant ici, parent là-bas) ; tout adulte peut relier son enfant | **P0** | **livré** (2026-10-29) — migration 1578 à appliquer ; à vérifier sur un téléphone Android |
| REG-33 | Séries du lycée (multi-pays), programme de l'école (matières et coefficients), moyenne générale pondérée | **P0** | **livré** (2026-10-29) — migration 1579 appliquée ; coefficients fixés par chaque établissement (décision du 2026-10-30) |
| REG-34 | Messagerie famille ↔ école (le parent écrit à l'enseignant ou à la direction), heures de messagerie, groupes de classe modérés | **P1** | **livré** (2026-10-30) — migration 1580 à appliquer ; à vérifier sur téléphone |
| REG-05 | README et état d'avancement à resynchroniser (M16, D1-D6, facturation, lancement) | P2 | clos (2026-10-17) |
| REG-06 | Branches locales non publiées sur le dépôt distant | P2 | clos (2026-10-17) — 2 branches distantes à supprimer au push |

---

## REG-30 — Feuille de route : ce qui reste à faire

**Établie le** : 2026-10-28 (état des lieux), rangée au registre le
2026-10-29. **Priorité** : P1. **Statut** : ouvert — tenue à jour à chaque
livraison (une ligne close renvoie vers son REG ou son commit).

Trois natures de travaux : **[code]** ce que Claude réalise dans le dépôt ;
**[GSG]** une décision, un compte ou un paiement du porteur de projet ;
**[test]** une vérification sur un téléphone ou avec une école pilote.

### P0 — avant d'ouvrir l'application à une vraie école

1. **[GSG]** Projet Supabase de production, passé en **Pro** (un projet
   gratuit est mis en pause après une semaine sans activité) —
   `docs/MISE_EN_SERVICE.md`.
2. **[GSG]** Déployer sur ce projet les migrations 1561 à 1576, les
   fonctions `pas_moi` et `envoyer_notifications`, puis les autres
   fonctions listées au README (`scripts\deployer_supabase.ps1`).
3. **[test]** `flutter test` au vert, APK `armeabi-v7a` installé, parcours
   complet sur téléphone : création de l'école, mise en route (année,
   classes, groupes, cours, emploi du temps), invitations par code,
   inscription d'un élève, encaissement, hors connexion.
4. ~~**[code]** Pages publiques **Politique de confidentialité** et
   **Conditions d'utilisation**~~ — **livré par REG-31** (avec la page et la
   fonction de suppression de compte exigées par le Play Store). Reste
   **[GSG]** : compléter siège et RCCM, faire relire (point 10), mettre en
   ligne sur Cloudflare Pages (`site_gsg/README.md`).
5. **[GSG]** Empreinte **SHA-1** de la clé GSG dans Firebase et dans la
   console Google (connexion Google, notifications) — MISE_EN_SERVICE §5.
6. **[GSG]** Réglages de la connexion Google dans Supabase
   (MISE_EN_SERVICE §5.1).

### P1 — prochains chantiers

7. ~~**[code]** **Séries du lycée guinéen** (SM, SE, SS)~~ — **livré par
   REG-33** (séries, programme de l'école, moyenne pondérée). Coefficients :
   **fixés par chaque établissement** (décision du 2026-10-30).
8. ~~**[code]** **Messagerie privée** parent ↔ enseignant et **groupes de
   classe**~~ — **livré par REG-34** (migration 1580 à appliquer).
9. **[test]** **Pilote Bambino Emmaüs** : validation de l'école et premier
   **paiement Orange Money réel** (REG-02).
10. **[GSG]** **Avocat** : conditions d'utilisation, confidentialité,
    données des mineurs, contrats écoles et vendeurs.
11. **[GSG]** **Expert-comptable** : relecture du référentiel comptable
    avant production (REG-03).
12. **[GSG]** Compte **Orange SMS** (codes de connexion de secours,
    alertes de pointage, relances d'impayés) — REG-09, REG-12.
13. **[GSG]** Confirmation du **contrat Kernel** (reporting, jetons
    inter-services) — REG-01.2 et REG-01.3.
14. **[test]** Vérifications sur téléphone Android encore dues : entrées
    marquées « à vérifier » dans le tableau ci-dessus (REG-07 à REG-29).

### P2 — ensuite

15. **[code]** Emploi du temps, suites de REG-24 : remplacement d'un
    enseignant absent, semaines A/B, export PDF par classe et par
    enseignant.
16. **[code]** **M17 — bibliothèque numérique** (cahier ch. 26), après la
    bibliothèque physique (REG-15).
17. **[code]** **M19** et **M20** : parties restantes du cahier (pages
    publiques des écoles et des réseaux, fonctions partielles listées au
    README).
18. **[code]** **iOS** : notifications, connexion Google, publication
    (compte Apple développeur à ouvrir côté GSG).
19. **[code]** **README** à resynchroniser avec REG-13 à REG-29.

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

**Livré le 2026-10-18** — migration `…1544`, module Flutter
`features/inscription_en_ligne` :
- **Direction** (« Inscriptions en ligne ») : campagne par année
  (ouvertures des réinscriptions et des nouvelles demandes, date limite,
  délai de réservation, pièces exigées par cycle, places par niveau,
  consignes, publication) ; tableau de bord (taux de réinscription, à
  traiter, acceptés à régler, liste d'attente, désistements, frais
  encaissés, places par niveau) ; examen d'un dossier (pièces, alertes
  impayé / sanction / doublon possible) et décision : accepter (ou en
  surnombre), réclamer des pièces, convoquer, liste d'attente, refuser
  (motif obligatoire, transmis à la famille), « payé au guichet →
  inscrire » (classe automatique ou choisie) ;
- **familles** (« Inscriptions et réinscriptions », parents et élèves) :
  enfants à réinscrire avec le niveau suivant proposé d'après les
  résultats (même niveau si recalé à l'examen), « revient / ne revient
  pas », choix du payeur dès le collège ; demande d'un nouvel élève en
  5 étapes (école, niveau avec places et frais, élève, demandeur et
  payeur, pièces photographiées) ; suivi du dossier, paiement des frais
  par **Orange Money** (nouvel objet `frais_inscription`) ou au guichet
  avec le numéro de dossier, retrait ;
- **mécanique** : réinscription sans alerte → place offerte aussitôt ;
  frais nuls → inscription immédiate ; offre non réglée à l'échéance →
  expirée, place au premier de la liste d'attente (aussi au retrait ou
  au refus) ; à l'inscription : fiche et matricule créés, parent lié (ou
  compte de l'élève lié), payeur enregistré, encaissement des frais ;
  notifications à chaque étape dans l'application (push par REG-09) ;
- **hors connexion** : dossier et photos gardés sur le téléphone avec un
  numéro provisoire, envoyés au retour du réseau (pièces après leur
  dossier), saisie faite avant la date limite recevable 7 jours après ;
  décisions et espèces encaissées par la Direction aussi mises en file ;
  refus du serveur expliqués dans le bandeau ; cache purgé à la
  déconnexion. En ligne seulement : paiement Orange Money, ouverture
  d'une pièce.
- À la mise en production : planifier `expirer_offres_inscription()`
  (toutes les heures) — elle est aussi appelée à chaque paiement et à
  chaque ouverture du tableau de bord.
- Vérification : pgTAP `72` 43/43, régression 01-71 inchangée (`58`, `59`
  Orange Money au vert) ; test Flutter `inscription_hors_ligne_test.dart`
  — **à lancer sur le poste**.

## REG-09 — Pointage au portail et notifications

**Priorité** : P1. **Statut** : validé le 2026-10-18 — proposition
`docs/propositions/REG-09_POINTAGE_PORTAIL.md`.

Décisions : **GPS abandonné** ; pointage par carte QR scannée au portail
(hors connexion), appel en classe = preuve officielle ; notifications
automatiques **push** (arrivée/sortie, absence à l'heure limite, sortie
anticipée), sans alerte d'absence tant que le portail n'a pas synchronisé ;
**GSG ne prend pas en charge les SMS** : l'établissement achète des crédits
SMS à GSG (revente), décomptés à l'envoi ; sans crédit, push seul.
**Ajout du 2026-10-18** : les crédits SMS servent aussi aux **relances des
parents en retard de paiement** des frais de scolarité.

**Livré le 2026-10-21** — migrations `…1545` (type « pack SMS ») et
`…1546`, Edge Functions `envoyer_push` (nouvelle), `envoyer_notifications`
(SMS), `initier_paiement_cinetpay` (packs), module Flutter
`features/pointage` :
- **cartes d'élève** à QR code, PDF 10 cartes par page (format carte
  bancaire), jeton secret par carte, remplacement d'une carte perdue
  (l'ancienne ne passe plus) ;
- **portail** (« Portail : scanner les cartes ») : caméra du téléphone
  (Android, iOS) ou douchette USB / Bluetooth (tout appareil, PC compris) ;
  sens proposé selon l'heure ; nom de l'élève affiché même sans réseau
  (liste des cartes gardée sur le téléphone) ; carte inconnue signalée ;
  double passage ignoré ; scans gardés hors connexion avec leur heure
  exacte puis envoyés (jamais en double) ; signal régulier « plus rien en
  attente » ;
- **avis aux familles** (push) : arrivée et sortie (désactivables par
  l'école et par chaque parent), retard indiqué, transmission tardive
  indiquée ; **sortie avant la fin des cours sans autorisation** : alerte
  push + SMS ; **absence** : après l'heure limite, alerte push + SMS
  aux parents (à défaut, à l'élève autonome) des élèves ni pointés ni
  absents justifiés à l'appel — seulement si le portail a transmis ses
  scans, jamais un jour sans aucun scan (fête, grève), une fois par jour ;
- **Direction** (« Présence au portail ») : arrivés, absents, retards,
  sortis, écarts avec l'appel en classe, état du portail, alertes
  envoyées, autorisation de sortie, remplacement de carte, impression des
  cartes, réglages (heure limite, fin des cours, jours, avis, SMS) ;
- **crédits SMS** : solde, historique, achat de packs (CinetPay, circuit
  GSG) ; GSG fixe le prix des packs et peut créditer une école après un
  paiement reçu (« Crédits SMS des écoles ») ; texte en alphabet GSM
  (160 caractères par SMS) ; SMS non distribué recrédité ;
- **relances d'impayés** : retard calculé sur les tranches échues
  (boursiers exclus), push au payeur (élève à sa charge ou parents), SMS au
  choix, pas deux fois la même semaine.
- **Mise en production** : tâches planifiées `detecter_absences_portail()`
  (toutes les 10 min, jours de classe) et appels de `envoyer_push` et
  `envoyer_notifications` (chaque minute) ; secrets `FCM_COMPTE_SERVICE`
  (projet Firebase à créer), `ORANGE_SMS_CLIENT_ID`,
  `ORANGE_SMS_CLIENT_SECRET`, `ORANGE_SMS_EXPEDITEUR` (Guinée : 2240000),
  `ORANGE_SMS_NOM_EXPEDITEUR` (facultatif, validé par Orange) ; prix des
  packs à fixer par GSG.
- **Reste à faire** : brancher Firebase dans l'application (réception des
  push et enregistrement du téléphone via `enregistrer_jeton_push`) une
  fois le projet Firebase créé ; d'ici là, les avis sont visibles dans
  « Notifications ».
- Vérification : pgTAP `73` 40/40, régression 01-72 inchangée ; `deno
  check` des Edge Functions ; test Flutter `pointage_test.dart` — **à
  lancer sur le poste**.

## REG-10 — Encaissement au guichet hors connexion

**Priorité** : P1 (recommandation n° 1 du point d'avancement du
2026-10-18 : geste quotidien du guichet, souvent en espèces et sans
réseau). **Statut** : livré le 2026-10-21 — migration `…1547`.

- **Numéro de reçu continu** par établissement et par année
  (`SCO-2026-000001`), attribué par le serveur dans la transaction
  d'enregistrement : aucun trou, ni sur un refus ni sur un renvoi ;
  immuable ; les encaissements existants sont numérotés dans l'ordre de
  saisie ; s'applique aussi aux paiements Orange Money et aux frais
  d'inscription.
- **Sans réseau** : l'encaissement est gardé sur l'appareil (clé de
  l'appareil, heure de saisie), reçu **provisoire** imprimable
  (`PROV-<appareil>-0001`) ; il apparaît aussitôt dans l'historique et
  le solde de l'élève ; envoyé au retour du réseau par
  `enregistrer_encaissement_scolarite` (idempotent : un renvoi ne crée
  rien) ; le reçu définitif rappelle le provisoire ; une annulation sans
  réseau part aussi en file ; refus du serveur expliqués dans le bandeau
  (« l'argent reçu doit être régularisé par la direction »).
- **Correction transversale** : une panne de réseau est maintenant
  reconnue par l'accès aux données de la scolarité (`HORS_CONNEXION`),
  si bien que tous les écrans de scolarité resservent réellement leurs
  données gardées sur l'appareil — ce n'était pas le cas jusque-là.
- Vérification : pgTAP `74` 11/11, régression 01-73 inchangée ; tests
  Flutter `encaissement_hors_ligne_test.dart`, `encaissement_pdf_e2e_test.dart`
  (mis à jour : la clé de l'appareil est désormais transmise) — **à lancer
  sur le poste**.

## REG-11 — Notifications push dans l'application

**Priorité** : P1 (suite de REG-09 : le serveur envoyait déjà, le
téléphone ne savait pas encore recevoir). **Statut** : livré le
2026-10-21 — `firebase_core` 5.0.0, `firebase_messaging` 17.0.0.

- **Identifiant d'installation Firebase (FID)** : depuis 2026, Google
  remplace les « jetons » d'appareil (`getToken`, désormais obsolète) par
  le FID (`register()` / `onRegistered`). L'application est construite
  directement sur le FID ; la fonction serveur `envoyer_push` l'envoie
  dans `message.fid` et accepte toujours les anciens jetons
  (`message.token`). Un `INVALID_ARGUMENT` ne fait plus oublier un
  téléphone que s'il le vise (avant : tout message mal formé effaçait les
  téléphones).
- **Rattachement du téléphone au compte** à l'ouverture du compte,
  retenté au retour du réseau ; gardé sur l'appareil et renouvelé chaque
  semaine (date de dernier contact côté serveur) ; le téléphone suit le
  dernier compte connecté.
- **Déconnexion** : serveur prévenu s'il est joignable, téléphone
  désinscrit du service push dans tous les cas (tablette partagée,
  téléphone prêté).
- **Réception** : application ouverte → bandeau en bas de l'écran avec
  « Voir » et boîte de notifications rafraîchie ; notification touchée
  dans la barre du téléphone (application en arrière-plan ou fermée) →
  boîte de notifications. Canal Android « Alertes de l'école »
  (importance haute) et petite icône monochrome ; autorisation Android 13
  demandée à l'ouverture du compte.
- **Sans configuration** : tant que `google-services.json` n'est pas
  déposé, l'application se construit et fonctionne sans push ; ce fichier
  n'entre jamais dans le dépôt (`.gitignore`). Sur PC, push sans objet.
- Vérification : tests Flutter `test/features/push/push_test.dart` ;
  Deno `fcm_client_test.ts` 4/4 (ajouté à la CI) — **à lancer sur le
  poste**. iOS : code prêt, demande un compte développeur Apple (clé APNs).

## REG-12 — Kit de mise en service

**Priorité** : P0 (demande du 2026-10-22 : que la publication soit courte
une fois le projet Supabase créé). **Statut** : livré le 2026-10-22 —
migration `…1548`, guide `docs/MISE_EN_SERVICE.md`.

- **`scripts/deployer_supabase.ps1`** (Windows) : liaison au projet,
  migrations, secrets (lus dans `supabase/mise_en_service/secrets.local.env`,
  ignoré par git, jamais affichés ; déclencheurs générés), déploiement de
  toutes les fonctions, coffre Vault et **8 tâches planifiées** (un seul
  modèle `taches_planifiees.modele.sql`, rejouable sans doublon),
  administrateur GSG, contrôle final. Relançable à volonté.
- **`executer_taches_quotidiennes()`** : alertes de décrochage (M7) et
  risque de réussite (M16) chaque nuit pour toutes les écoles actives —
  ces deux calculs n'avaient jusque-là aucune planification. Une école en
  erreur n'arrête pas les autres.
- **`etat_mise_en_service()`** : liste de contrôle (extensions, tâches et
  leur dernier passage, secrets rangés — présence seulement —,
  administrateur GSG, packs SMS en vente), pour l'équipe GSG et le script.
- **Codes de connexion par Orange SMS** (`envoyer_sms_auth`, crochet
  « Send SMS » de Supabase Auth, signature Standard Webhooks vérifiée sans
  bibliothèque tierce, rotation de secrets acceptée) au lieu de Twilio
  (environ 0,25 USD par code). Numéros hors Guinée : invitation à se
  connecter par e-mail. Le code n'est jamais journalisé.
- **Android** : nom « EcoShop » ; **permission Internet ajoutée à la
  version publiée** (Flutter ne la déclarait que pour les versions de
  développement : l'application publiée n'aurait joint aucun serveur) ;
  signature de publication par `key.properties` ;
  `scripts/construire_android.ps1` crée la clé de GSG et la configuration
  de production, puis construit l'`.aab` (ou un `.apk` pour le pilote).
- Vérification : pgTAP `75` 11/11 ; Deno `sms_auth_test.ts` 5/5 (CI) ;
  modèle des tâches exécuté deux fois sur une base de test (8 tâches, pas
  de doublon, chaque commande planifiée s'exécute).
- Reste manuel (documenté) : création du projet, réglages
  d'authentification du tableau de bord, contrats Orange, compte Google
  Play. **Décision à prendre** : la connexion par téléphone consomme un
  SMS payé par GSG à chaque code ; la connexion par e-mail est gratuite.

## REG-13 — M19 : réseaux d'établissements

**Priorité** : P1 (demande du 2026-10-22 ; le pilote Bambino Emmaüs
appartient au réseau de l'Église Protestante Nationale). **Statut** : livré
le 2026-10-22 — migration `…1549`, conforme au cahier ch. 28, 30.1, 30.3.

- **Recherche préalable** (logiciels de gestion multi-écoles) : tableau de
  bord consolidé avec détail par école, réglages communs adoptés librement
  par chaque école, séparation stricte — le réseau voit des chiffres, pas
  des dossiers d'élèves. Retenu tel quel, avec le cahier comme référence.
- **Création** : demande (nom, dénomination, type, pays, devise, courriel,
  téléphone, adresse, premier responsable) depuis l'application, même sans
  réseau ; validée par GSG qui constate le règlement des **frais de
  création** (17.7) ; courriels de réception, d'alerte GSG, de décision.
  Le demandeur devient Direction Générale **sans changer le rôle de son
  compte** (un directeur reste directeur, un parent fondateur garde son
  espace famille).
- **Écoles** : annuaire (nom, ville) insensible à la casse et aux accents ;
  invitation (push + boîte de notifications de la direction) ; la direction
  accepte ou refuse, même sans réseau ; retrait demandé par l'école et
  **finalisé seulement par GSG** (28.4) ; **dissolution** par la Direction
  Générale avec double confirmation, la seconde exigeant le nom exact du
  réseau (vérifié aussi par le serveur).
- **Tableau de bord consolidé** (28.5) : effectif de l'année courante,
  retraits, présence sur 30 jours, recouvrement (dû selon les tarifs de
  chaque école, encaissé), alertes de décrochage, personnel, élèves par
  enseignant — par école et au total, alertes visuelles (recouvrement
  < 50 %, présence < 85 %). **Aucun nom d'élève** ne sort de son école.
- **Pilotage** : circulaires aux directions des écoles membres (push,
  « importante », accusé de lecture « lue par n/N ») ; calendrier commun
  (rentrée, congés, examens…) que chaque école **ajoute ou non** à son
  agenda (harmonisation déclarative, 28.2) ; équipe : adjoint (pilote),
  observateur (consulte).
- **GSG** : demandes à traiter, vue d'ensemble en lecture seule, retraits
  à autoriser.
- **Hors connexion** : consultation resservie depuis l'appareil ; demande,
  circulaire, date commune, réponse à une invitation et accusé de lecture
  gardés avec leur clé et envoyés au retour du réseau, affichés « en
  attente d'envoi ».
- Vérification : pgTAP `76` 37/37, régression 01-75 inchangée ; Deno
  `courriel_test.ts` 10/10 ; Flutter `test/features/reseau/reseau_test.dart`
  — **à lancer sur le poste**.
- Non couvert, à arbitrer : transferts d'élèves entre écoles du réseau et
  grille de frais harmonisée (28.2 : « selon le paramétrage de la Direction
  Générale ») ; paiement en ligne des frais de création (aujourd'hui
  constatés par GSG).

## REG-14 — M18 : transport scolaire

**Priorité** : P1 (demande du 2026-10-22). **Statut** : livré le
2026-10-22 — migration `…1550`, conforme au cahier ch. 24.

- **Recherche préalable** (applications de bus scolaire de référence) :
  alerte d'approche avant l'arrêt de la famille, avis à la montée et à la
  descente, position masquée hors trajet. Retenu, plus une sécurité que ces
  applications réservent aux options payantes : la **vérification de fin de
  trajet** (enfants scannés à la montée et jamais à la descente).
- **Circuits et arrêts** (24.1) : véhicule, places, tarif annuel,
  chauffeur désigné par le téléphone ou le courriel de son compte ; arrêts
  ordonnés (le retour suit l'ordre inverse), repère, heures matin et soir,
  position enregistrée sur place (« Je suis à l'arrêt »).
- **Affectation** (24.2) : recherche de l'élève, arrêt, capacité du véhicule
  respectée ; visible par la famille.
- **Chauffeur** (24.3) : accès limité à ses circuits — jamais membre de
  l'établissement (il verrait sinon toutes les fiches) ; démarre un trajet
  aller ou retour, arrêts marqués automatiquement à moins de 120 m (GPS du
  téléphone, écran ouvert, jamais en arrière-plan) ou à la main, carte QR de
  l'élève (la même qu'au portail) scannée à la caméra ou à la douchette ; à
  la fin, liste des enfants encore à bord et alerte à la direction.
  **Tout fonctionne sans réseau** : circuits, élèves et cartes gardés sur le
  téléphone, trajet repris après une coupure, gestes rejoués dans l'ordre
  avec leur heure réelle, seule la dernière position attend le réseau.
- **Familles** : « le bus vient de passer X, il arrive bientôt à votre
  arrêt », montée et descente avec l'heure (même réglage que les avis du
  portail) ; écran de suivi : enfant à bord, dernier arrêt passé, arrêts
  restants avant le sien, « Voir le bus sur la carte » (ouvre la carte du
  téléphone : aucune carte embarquée à télécharger), appeler le chauffeur.
  Un avis rejoué plus de 15 minutes après les faits n'est plus envoyé.
- **Vie privée** (rétention, 34) : seule la dernière position est gardée,
  pendant le trajet ; effacée à la fin ; invisible hors trajet.
- **Facturation** (24.4) : encaissement « transport » au guichet ou par
  Orange Money ; payé et reste dû par élève dans l'écran de la direction.
- Vérification : pgTAP `77` 37/37 ; Flutter `test/features/transport/transport_test.dart`
  — **à lancer sur le poste** ; GPS à essayer sur un téléphone Android.

## REG-15 — M17 : bibliothèque physique

**Priorité** : P1 (demande du 2026-10-22). **Statut** : livré le
2026-10-22 — migration `…1551`, conforme au cahier ch. 25 (la
bibliothèque numérique et les flashcards du ch. 26 restent à faire, et ne
sont jamais confondues avec elle).

- **Recherche préalable** (logiciels de bibliothèque scolaire de
  référence) : exemplaire étiqueté et scanné, limite d'emprunts par élève,
  relances aux familles, réservation, inventaire par scan, rapports
  (retards, pertes, plus empruntés), remplissage depuis l'ISBN. Tout est
  retenu ; les amendes ne le sont pas (le cahier ne les prévoit pas).
- **Catalogue** (25.1) gratuit pour tous les membres, avec la
  disponibilité ; jamais premium.
- **Exemplaires** (25.4) numérotés par école (`LIV-000001`), étiquettes QR
  imprimables (planches 70 × 37 mm, 24 par page) ; fiche préremplie depuis
  l'ISBN (Open Library, gratuit) quand il y a du réseau.
- **Guichet** (25.2) : carte QR de l'élève (la même qu'au portail et au
  bus), puis étiquette de chaque livre ; retour en scannant le livre seul ;
  caméra ou douchette ; **fonctionne sans réseau** avec les mêmes contrôles
  qu'au serveur (exemplaire déjà prêté, limite d'emprunts), le serveur
  tranchant si deux guichets ont prêté le même livre.
- **Statuts automatiques** (25.3) « en retard » puis « perdu », calculés à
  chaque lecture ; durée du prêt, nombre d'emprunts, renouvellements et
  délai de perte réglables par l'école. Relances (veille de l'échéance,
  lendemain, une semaine après) par la tâche de nuit ; pertes répétées
  signalées, **sans sanction automatique**.
- **Réservation** d'un livre sorti par l'élève ou ses parents ; au retour,
  l'exemplaire est gardé 3 jours et la famille est prévenue.
- **Inventaire** par scan : exemplaires introuvables listés (hors prêts).
- Vérification : pgTAP `78` 30/30, test `75` inchangé (la tâche de nuit
  inclut les relances) ; Flutter `test/features/bibliotheque/bibliotheque_test.dart`
  — **à lancer sur le poste**.
- Accès : direction (et, côté serveur, tout membre ayant la permission
  `bibliotheque.gerer`) ; le menu n'apparaît pour l'instant qu'à la
  direction.

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

## REG-16 — Connexion par e-mail et Google, téléphone au profil

**Priorité** : P1 (décision GSG du 2026-10-22 : suspendre les codes de
connexion par SMS, un SMS payé par connexion). **Statut** : livré le
2026-10-22 — migration `…1552`, test `79` (22).

- **Recherche préalable** : Sign in with Google sur Android passe par le
  Gestionnaire d'identifiants du système ; la documentation Android
  recommande à la fois la feuille proposée d'office (compte déjà autorisé)
  et un bouton permanent (feuille fermée, réglages Google, aucun compte).
  Supabase accepte le jeton d'identité Google (`signInWithIdToken`).
- **Connexion** : bouton « Continuer avec Google » (`google_sign_in` 7),
  (tentative d'office à l'ouverture retirée par REG-29) ; sinon code
  à 6 chiffres par e-mail (adresse suggérée par le clavier, code collé ou
  lu automatiquement, renvoi après 60 s). Le choix SMS reste dans le code,
  masqué (`CONNEXION_TELEPHONE=true` le réaffiche ; `config.toml` :
  `enable_signup` SMS et crochet Send SMS désactivés).
- **Nouveau compte Google** : prénom et nom repris du compte Google.
- **Téléphone** : étape « Votre numéro » après la connexion (sauf élève),
  « Plus tard » possible (rappel à 30 jours), saisie sans réseau gardée et
  envoyée au retour ; modifiable depuis « Mon profil ».
- **Sécurité** : un numéro saisi n'est que **déclaré** ; il ne donne aucun
  droit et ne bloque pas son vrai titulaire. Il devient **vérifié** quand
  l'école le confirme en présence de la personne (menu « Numéros à
  confirmer » : l'agent appelle, le téléphone sonne, il confirme). Seul un
  identifiant vérifié est unique et permet d'accepter une invitation
  (`IDENTIFIANT_NON_VERIFIE` sinon) ; la recherche de fratrie par numéro
  privilégie le titulaire vérifié.
- **Mise en service** : `docs/MISE_EN_SERVICE.md` §5 réécrit (Google dans
  Firebase et Supabase, empreinte SHA-1 affichée par
  `construire_android.ps1`, SHA-1 de la clé Play à ajouter, modèle de
  courriel avec `{{ .Token }}`).

## REG-17 — Réseaux : politique de frais et transferts d'élèves

**Priorité** : P1 (demande du 2026-10-22 : certains réseaux laissent chaque
école fixer ses frais selon sa localité, d'autres non). **Statut** : livré
le 2026-10-22 — migration `…1553`, test `80` (40).

- **Recherche préalable** (logiciels multi-campus) : la tête de réseau
  définit les postes de frais, chaque campus ses montants ; un transfert
  part de l'école de départ après quitus financier, l'école d'accueil
  l'accepte et choisit la classe ; l'historique suit l'élève ; tout est
  tracé. Retenu, avec le choix laissé au réseau.
- **Politique de frais**, choisie par la Direction Générale :
  « autonome » (chaque école, aucune grille), « indicative » (grille de
  référence publiée ; une école l'adopte d'un geste puis reste libre),
  « commune » (grille appliquée aussitôt à toutes les écoles membres et à
  celles qui rejoignent le réseau ; un verrou serveur refuse toute
  modification par l'école, `FRAIS_FIXES_PAR_RESEAU`). Grille par niveau
  du pays du réseau, plus un tarif par défaut.
- **Conditions de transfert** (Direction Générale) : transferts ouverts ou
  non ; frais de l'année soldés avant le départ ; validation par la
  Direction Générale ; frais d'inscription offerts à l'arrivée ; dossier
  transmis (classe, assiduité, parents, personne à prévenir).
- **Transfert** : l'école de départ choisit l'élève (solde affiché), l'école
  d'accueil et le motif ; validation du réseau si exigée ; l'accueil choisit
  la classe (celles du même niveau d'abord, effectif et capacité affichés)
  ou refuse avec un motif. À l'acceptation, en une fois : fiche créée à
  l'arrivée (identité et famille reprises, nouveau matricule, lien vers la
  fiche d'origine), inscription, parents et compte élève rattachés, élève
  retiré au départ, familles et directions prévenues (notification
  « Transfert d'élève »).
- **Hors connexion** : demander, valider, accepter, refuser marchent sans
  réseau (clé fournie par l'appareil, jamais de doublon) et apparaissent
  aussitôt « en attente d'envoi ». Règles et grille : en ligne seulement.
- **Écrans** : pilotage du réseau (icônes « Règles » et « Transferts »),
  espace de l'école membre (« Règles du réseau », « Transferts d'élèves »).

## REG-18 — Sécurité d'accès : inscription en étapes, code secret, identifiant EcoShop

**Priorité** : P0 (premier essai de l'APK de production, nuit du
2026-10-22 au 23 : un téléphone laissé sans surveillance donnait accès au
compte sans aucune vérification). **Statut** : livré le 2026-10-23 —
proposition validée `docs/propositions/REG-18_SECURITE_ACCES.md`
(`44d6fcc`) ; cahier de conception §5.12.

- **Partie A, défauts de l'APK** : connexion Google et code par e-mail
  bloqués sur le chargement, déconnexion lente sans réseau (`4959888`),
  bouton Google conforme aux règles de Google (`48fc385`), « Valider » ne
  renvoie plus un code accepté (`dde131e`).
- **Serveur** (`84e3062`, migrations `…1554` à `…1556`, tests `81` à
  `83`, Edge Function `connexion_identifiant` et ses tests Deno) :
  identifiant EcoShop, `finaliser_inscription`, purge horaire des comptes
  jamais vérifiés, plafond de liaisons, notification de la direction,
  acceptation, refus, révocation.
- **Partie B, inscription en étapes** (`6f86507`) : accueil « Se
  connecter » / « Créer un compte » ; espace (élève ; parent, aussi client
  de la boutique ; « Je représente un établissement »), nom (ou Google),
  vérification qui seule crée le compte, téléphone, code secret,
  récapitulatif. Saisies gardées sur le téléphone, appliquées après la
  vérification, jamais à un compte existant.
- **Partie C, code secret et verrou** (`f5a5591`, corrections Android
  `a670cc7`) : code de 6 chiffres vérifié sur le téléphone,
  empreinte ou visage facultatifs, 5 échecs → session fermée et données
  locales purgées, délais par rôle (2 à 30 min), code à chaque action
  sensible, contenu caché dans les applications récentes.
- **File d'envoi chiffrée par compte** (`0fed155`) : corrige aussi un
  défaut ancien, les envois en attente d'un compte pouvaient partir au nom
  du compte suivant sur la même tablette.
- **Partie D, identifiant EcoShop** (`8cb5cb0`) : `EC-XXXX-XXX`, champ
  « E-mail ou identifiant EcoShop », adresse masquée, « Mon profil ».
- **Partie E, liaisons** (`60e39e3`) : écran « Comptes liés aux élèves »
  de la direction ; le parent est informé quand sa liaison attend l'école.
- **Défauts relevés pendant les essais** : ouverture impossible sans
  réseau, relance manuelle au retour du réseau (`0c7e935`) ; icône de
  profil qui ouvrait un menu au lieu de « Mon profil » (`3e38b72`).

**Recherche préalable et choix techniques.**

- **Modèle retenu** : appareil de confiance + code local (applications de
  mobile money), plutôt qu'un mot de passe vérifié par le serveur à chaque
  ouverture, impossible hors connexion. NIST SP 800-63B-4 (secret
  d'activation vérifié sur l'appareil : 6 chiffres au moins, codes
  évidents refusés, nombre d'échecs limité) ; OWASP MASVS-AUTH (contrôle
  local contournable sur un téléphone rooté : le serveur reste l'autorité,
  RLS inchangées).
- **`flutter_secure_storage` 11.2.0** (version figée) : Android Keystore
  et iOS Keychain ; seul paquet maintenu qui couvre aussi la **biométrie
  liée à une clé** (`BiometricPrompt` + clé du Keystore, OWASP
  MASWE-0020) : un simple « oui » du système, comme `local_auth`, se
  contourne par instrumentation ; ici le secret ne se déchiffre qu'après
  une lecture biométrique forte, et la clé est annulée quand une empreinte
  est ajoutée au téléphone.
- **`cryptography` 2.9.0 + `cryptography_flutter` 2.3.4** (figées) :
  PBKDF2-HMAC-SHA256 pour l'empreinte du code, AES-256-GCM pour la file
  d'envoi, calculs confiés à Android (`javax.crypto`), rapides sur un
  téléphone d'entrée de gamme.
- **Point de vigilance** : la dérivation du code utilise 210 000
  itérations ; l'OWASP (Password Storage Cheat Sheet) en recommande
  600 000 pour PBKDF2-HMAC-SHA256 (210 000 est sa valeur pour SHA-512).
  Pour un code de 6 chiffres, la dérivation ne fait que ralentir : la
  vraie barrière est le Keystore (empreinte et compteur illisibles hors du
  téléphone) et le compteur de 5 échecs. Le nombre d'itérations est gardé
  avec chaque code : il peut être relevé sans invalider les codes
  existants, après une mesure du temps d'ouverture sur un téléphone
  d'entrée de gamme.

**Corrections Android trouvées à la relecture** (non visibles en test) :
autorisation `USE_BIOMETRIC` absente (l'activation de l'empreinte aurait
échoué sur téléphone) ; sauvegarde automatique Android active (données
protégées par le Keystore restaurées sans leur clé sur un autre téléphone,
« Failed to unwrap key », et base locale envoyée dans Google Drive) :
sauvegarde et transfert désactivés.

**Invitations du personnel et des vendeurs** (décision du porteur le
2026-10-23 : bloquant pour le pilote ; migration `…1557`, test `84`) :
l'application n'appelait jamais `accepter_invitation`, et rien ne
permettait d'inviter ni d'envoyer le jeton. Désormais :
- la direction invite depuis « Invitations du personnel » : adresse
  e-mail (voie privilégiée, courriel `invitation_membre` envoyé aussitôt)
  ou numéro (aucun SMS) ; rôle enseignant, direction et administration,
  ou vendeur ; poste facultatif ; suivi des réponses et retrait ;
- après sa connexion, l'invité voit ses invitations (avant le choix de
  l'espace pour un compte neuf, pour ne pas choisir Élève ou Parent à la
  place du rôle prévu) et les accepte ou les refuse ; « Plus tard » les
  laisse dans « Mon profil › Mes invitations » ; la direction est prévenue
  de chaque réponse ;
- règle REG-16 : seul un identifiant prouvé vaut, pour accepter **et**
  pour refuser (sinon déclarer le numéro d'un autre suffirait à refuser à
  sa place). Une invitation à un numéro seulement déclaré est visible,
  avec la marche à suivre (confirmation à l'école).
Un compte vendeur reste sans lien avec un commerce (`commercants`) : le
vendeur invité devient membre de l'école avec le rôle vendeur.

**Code secret, mesure** : chaque dérivation (création, vérification)
écrit son temps dans les journaux de débogage (versions debug et
profile) : `Code secret : dérivation PBKDF2-HMAC-SHA256 (vérification),
210000 itérations en … ms`. 210 000 itérations gardées en attendant la
mesure sur un téléphone d'entrée de gamme.

**À vérifier sur un téléphone Android** : invitation par e-mail reçue, acceptée, refusée ; création du code, empreinte,
verrouillage après le délai, écran caché dans les applications récentes,
captures bloquées pour le personnel (Android 12 et moins), ouverture sans
réseau puis retour du réseau.

**Amendement (REG-22, 2026-10-26)** : le code secret à 6 chiffres devient
le code du **compte**, vérifié par le serveur sur tout nouvel appareil
(voir REG-22). Le rôle « direction » est réservé au fondateur et au
directeur ; secrétaire, caissier, comptable… sont invités comme
« personnel », avec un poste obligatoire.

## REG-19 — Annonces, cahier de liaison, messagerie : brancher sur le serveur

**Priorité** : P1. **Statut** : décidé le 2026-10-23 — lot 1 (annonces) puis lot 2 (cahier de
liaison) ; messagerie privée et groupes de classe **en attente**. En
attendant, les deux prototypes accessibles (annonces, cahier de liaison)
sont masqués dans la version publiée ; la messagerie prototype n'a aucun
point d'entrée.

**Constat.** Le module M9 livré ne couvre que les notifications
(`notifications`, préférences, journaux, modèles). Il n'existe **aucune
table** pour les annonces ni pour le cahier de liaison. Les groupes de
discussion de classe existent côté serveur (`groupes_discussion`,
`messages_groupe`, `signalements_message`, sept règles de protection des
mineurs, migration `…0901`) mais aucun écran ne les utilise, et ils
excluent les parents par construction : ce n'est pas la messagerie
parent ↔ école du prototype. Le prototype local ne contient rien à
reprendre (données propres à chaque téléphone, effacées à la
déconnexion).

**Travaux, par lot (estimation en jours de travail, tests compris).**

| Lot | Serveur | Application | Durée |
|---|---|---|---|
| Annonces (école → familles et personnel, par école ou par classe, lu / non lu) | table, lectures, RLS selon le ciblage, publication par fonction, notification push existante | lecture avec copie hors connexion, publication en file d'envoi (clé fournie par l'appareil), écran direction | 2 à 3 j |
| Cahier de liaison (mot de l'enseignant ou de la direction aux parents d'un élève, réponse, « vu ») | tables mots et réponses, RLS par parent **confirmé** (plafond REG-18) et enseignant affecté | fil par élève, réponse hors connexion, notification | 3 j |
| Groupes de classe (tables existantes) | à revoir seulement | écrans, modération, signalement | 2 j |
| Messagerie privée parent ↔ enseignant | à concevoir (règles de protection, modération, heures) | conversation, hors connexion | 4 à 5 j, après décision |

Annonces et cahier de liaison : **5 à 6 jours** ; avec les groupes de
classe, **7 à 8 jours**.

**Risques.**
- **Protection des mineurs** : qui écrit à qui. Le cahier de liaison ne
  doit joindre que les parents confirmés de l'élève ; une messagerie
  privée adulte ↔ élève est exclue par les règles M9.
- **Envoi en double ou perdu hors connexion** : clé fournie par
  l'appareil et file chiffrée par compte (déjà en place).
- **Pièces jointes** : stockage, poids sur réseau mobile lent, contrôle
  du contenu. Proposé : texte seul au premier lot.
- **Volume de notifications** : regroupement, horaires (préférences
  existantes).
- **Coût** : la notification push est gratuite ; un repli par SMS
  consomme des crédits, à n'activer que sur décision.
- **Modération et signalement** : responsable désigné par école,
  historique non effaçable.

**Lot 1 — annonces, livré le 2026-10-23** (migration `…1558`, test `85`).
Recherche préalable (Seesaw, Toddle, Remind, ParentSquare, ClassDojo) :
ciblage école / niveau / classe, suivi de lecture par famille, messages
courts, notification à chaque nouveau message, modération sans
suppression et tracée (qui, quand). Retenu :
- publication par la direction, texte seul, « important » ;
  destinataires figés à la publication : parents **confirmés** et
  comptes des élèves inscrits dans la portée (année courante) ;
  notification push à chacun ; SMS aux parents sur demande, dans la
  limite des crédits de l'école ;
- lecture confirmée à l'ouverture ; la direction voit « x/y familles
  ont lu » (une famille = un élève) ;
- modération : masquer avec une raison ; jamais supprimée ; journal
  d'audit (entité `annonce`) ;
- hors connexion : annonces reçues lisibles sans réseau ; publication et
  lecture gardées en file (chiffrée par compte) et renvoyées sans
  doublon (clé de l'appareil) ;
- prototype local « Annonces » retiré.

**Lot 2 — cahier de liaison, livré le 2026-10-23** (migration `…1559`,
test `86`). Retenu :
- un mot ouvre un fil au sujet d'un élève ; il est écrit par
  l'enseignant affecté à la classe de l'élève (année courante) ou par la
  direction ; chaque message reste rattaché à l'élève ;
- seuls les parents **confirmés** de l'élève le lisent (ni l'élève, ni
  un parent en attente) ; ils confirment la lecture (« J'ai lu », la
  signature du cahier papier) et répondent en texte ; le personnel
  autorisé répond aussi et voit « lu par x/y parents » ;
- notification push aux parents pour un message du personnel, à l'auteur
  du mot pour une réponse d'un parent ;
- modération : la direction masque un mot ou une réponse avec une raison ;
  jamais supprimé, encore visible pour le personnel ; journal d'audit
  (entité `mot_liaison`, avec l'élève) ;
- hors connexion : fils lisibles sans réseau ; mots, réponses et « J'ai
  lu » gardés en file et renvoyés sans doublon ;
- prototype local « Cahier de liaison » retiré ; il ne reste aucun
  prototype de communication accessible (la messagerie prototype n'a
  pas de point d'entrée).

**En attente** (décision du 2026-10-23) : messagerie privée parent ↔
enseignant et groupes de classe.

---

## REG-20 — Référentiel pédagogique en production ; séries du lycée guinéen

**Priorité** : P0. **Statut** : livré le 2026-10-24 (commit `48574fe`) ;
une tâche reste **ouverte** (séries du lycée, ci-dessous).

**Constat (production).** À la demande d'ouverture d'établissement, le
champ obligatoire « Pays » ne proposait aucune valeur : le référentiel
pédagogique et les paramètres globaux n'étaient remplis que par des seeds,
que `supabase db push` n'applique pas. Aucune école n'existait encore en
production : aucune licence n'a été calculée sans `seuil_effectif_gratuit`.

**Livré.** Migration `…1560_referentiel_production.sql` (idempotente),
test `87` :
- Guinée complète (préscolaire → Terminale, 16 niveaux ; CEE, BEPC, Bac),
  Sénégal et Ghana tels que déjà décrits ; 4 familles de systèmes ;
- niveaux d'examen (CM2, 10e, Terminale et équivalents) ;
- les 5 paramètres globaux de `seed.sql` ;
- `etat_mise_en_service()` : pays ouverts, cycles/niveaux/examens par
  pays, paramètres globaux ;
- seeds réduits aux données de démonstration ;
- application : liste des pays gardée sur le téléphone et réellement
  servie hors connexion ; messages distincts (liste vide, hors connexion,
  erreur du serveur).

**Décisions du porteur de projet (2026-10-24).**
- Préscolaire numéroté de 0 (Grande section) à -2 (Petite section) ;
  1 reste la première année du primaire dans tous les pays.
- Mention admis/recalé obligatoire pour les classes d'examen.
- Pas de préscolaire pour le Sénégal et le Ghana pour l'instant.
- Langue des pays en code (`fr`, `en`).

**Tâche ouverte — séries du lycée guinéen (SM, SE, SS) avec leurs
coefficients officiels.** À faire **avant l'arrivée du premier lycée**,
**après une recherche des textes officiels du ministère** de
l'Enseignement pré-universitaire (aucune valeur inventée). Aujourd'hui,
les séries n'existent que dans le seed de démonstration, rattachées à la
seule Terminale, sans coefficients officiels. À établir : niveaux
concernés (11e, 12e, Terminale), matières et coefficients par série, puis
livraison par migration comme le reste du référentiel.

## REG-22 — Code du compte, appareils connectés, postes du personnel

**Priorité** : P0. **Statut** : livré le 2026-10-26. Propositions
validées : `docs/propositions/REG-22_CODE_COMPTE_APPAREILS_POSTES.md` et
`docs/propositions/REG-22_SOLUTION_TECHNIQUE.md` (décisions Q1 à Q5).

**Failles corrigées.**
- La connexion (code e-mail ou Google) suffisait à ouvrir un compte sur un
  nouveau téléphone : le code secret n'était connu que du téléphone
  d'origine.
- Tout membre du personnel (agent du portail, chauffeur…) lisait notes,
  bulletins, absences, sanctions, encaissements, soldes, risques, rapports
  et journal d'audit.
- Trouvées en testant : élévation de droits par écriture directe dans les
  postes et les membres ; `est_admin_gsg()` à NULL pour un compte sans rôle
  racine, qui laissait passer plusieurs contrôles ; 5 codes vérifiés mais
  absents du catalogue (dont l'encaissement : un caissier devait être
  invité comme direction).

**Livré, dans l'ordre validé (un commit et un push par étape).**

| Étape | Commit | Contenu |
|---|---|---|
| C1 — lecture par permission | `90805d7` | migration 1561, test 88 (103) |
| A — serveur | `616af33` | migration 1562 (code du compte, contrôle avant chaque requête, Storage), fonction Edge `pas_moi`, courriels ; test 89 |
| A — application | `f251076` | étape « Code de votre compte », « Code oublié ? » (3 voies), invite « Autoriser ce nouvel appareil ? », bandeau de récupération, Sécurité, déblocage direction et GSG ; migration 1563, test 90 |
| A — mise en service | `d6d3ef9` | migration 1564 : interrupteur `code_compte_obligatoire` allumé |
| B — appareils connectés | `365ef3c` | migration 1565, test 91 ; Mon profil › Sécurité › Mes appareils |
| C — postes, serveur | `66f3169` | migrations 1566-1567 (rôle « personnel », modèles, séparation des tâches, codes branchés ou retirés), test 92 |
| C — postes, écrans | `55b6c32` | Personnel et postes, fiche d'un membre, invitation avec poste, menus du personnel selon son poste |

**Retour arrière sans migration** : `code_compte_obligatoire` et
`controle_sessions` dans `parametres_globaux`.

**Décisions du porteur de projet sur les écarts (2026-10-26).**
- Fiche élève **restreinte** (migration 1568) : fiche complète pour la
  direction, le secrétariat, le surveillant général, les enseignants de la
  classe et la famille ; les autres ne voient que l'annuaire (nom, prénom,
  classe), jamais le matricule ni la date de naissance (facteurs de la
  liaison parent ; minimisation des données des mineurs, §34.2). Aucune
  photo n'est stockée aujourd'hui.
- Comptable sans `rapports.generer` : validé.
- Chauffeur sans code de transport (affectation au circuit) : validé.
- Cahier de liaison ouvert au surveillant général
  (`scolarite.liaison.ecrire`), mêmes règles que l'enseignant ; chaque mot
  écrit est journalisé.
- Realtime : jeton valable jusqu'à 1 h après une déconnexion à distance
  (Q5, accepté).

**À vérifier sur un téléphone Android** : nouvel appareil (code du compte,
5 codes faux, « Code oublié ? » et ses trois voies) ; « Autoriser ce nouvel
appareil ? » reçu sur l'ancien téléphone ; lien « Ce n'est pas moi » du
courriel ; « Mes appareils » et déconnexion à distance (le téléphone
déconnecté efface ses données à son retour sur le réseau) ; menus d'un
membre « personnel » selon son poste.

## REG-21 — Accueil en pastilles, barre du bas, profil allégé

**Priorité** : P1. **Statut** : livré le 2026-10-26. Proposition validée :
`docs/propositions/REG-21_ACCUEIL_PASTILLES.md` ; maquettes
`docs/maquettes/accueil_pastilles/`.

**Recherche préalable.** Material 3 : une barre de navigation porte 3 à 5
destinations, toutes avec leur libellé ; au-delà, tiroir ou onglets.
Zones de toucher de 48 dp au moins (Android, Flutter) — plus large que les
44 px de la proposition. Un badge n'est lu par TalkBack que si le libellé
du bouton l'inclut : chaque pastille fusionne sa sémantique
(« Annonces, 3 nouvelles »).

**Livré (un commit et un push par étape).**

| Étape | Commit | Contenu |
|---|---|---|
| Barre du bas | `73d2193` | destinations par rôle, profil par l'avatar, pages « Messages » et « Agenda » |
| Accueil par rôle | `3dfb275` | catalogue des fonctions, « À faire », pastilles, groupes de la direction, « Mon travail » du personnel selon son poste ; migration 1569 (`accueil_resume`, `mon_aujourdhui`), test 94 |
| Profil allégé | `0cd278b` | Mon compte, Sécurité (Code secret, Empreinte, Mes appareils), Préférences, déconnexion |
| Raccourcis et recherche | `d51d8a2` | 4 raccourcis gardés sur l'appareil, « Que voulez-vous faire ? » |

**Rôles hors proposition, destinations retenues.** Personnel : Accueil,
Messages, Agenda (ses outils dépendent de son poste : ils sont sur
l'accueil). Vendeur : Accueil, Boutique, Messages. Fondateur de réseau :
Accueil, Réseau, Messages, Agenda. Administrateur GSG : Accueil, Écoles,
Réseaux, Vendeurs (les trois files de validation). Administrateur du
contenu : Accueil, Référentiel, Notifications.

**Écarts aux maquettes.**
- Élève « Ma carte (QR du portail) » et enseignant « Absences » : aucun
  écran n'existe ; pastilles non créées (l'appel et l'absence passent par
  « Faire l'appel »). Enseignant « Scan-Exercice » : l'écran exige une fiche
  d'élève ; réservé à l'élève.
- Parent : les enfants en pastilles rondes sont l'en-tête déjà livré
  (sélecteur d'enfant) ; « Ajouter » y reste.
- « Paiements » (parent) ouvre la fiche de l'enfant (solde, encaissements,
  Orange Money, notes, vie scolaire), écran existant.

**Table de correspondance — ancienne entrée de « Mon profil » → nouvel
emplacement.** Aucune fonction supprimée.

| Ancienne entrée | Nouvel emplacement |
|---|---|
| Mon numéro de téléphone | Mon profil › Mes informations |
| Mes invitations | Mon profil › Mes invitations |
| Rôle | Mon profil › Mes informations |
| Référentiel pédagogique CEDEAO | Accueil › pastille « Programmes officiels » |
| Langue et affichage | Mon profil › Préférences › Langue et affichage |
| Conditions générales d'utilisation | Mon profil › Préférences › Conditions d'utilisation |
| Assistant IA du rôle | Accueil › pastille « Assistant IA » |
| Scan-Exercice (élève) | Accueil › pastille « Scan-Exercice » |
| PARENT IA (élève, parent) | Accueil › pastille « Parent IA » |
| Inscriptions et réinscriptions (famille) | Accueil › pastille « Inscriptions » |
| Avis du portail (famille) | Mon profil › Préférences |
| Présence au portail | Accueil › Vie de l'école › « Présence au portail » |
| Portail : scanner les cartes | Accueil › « Scanner au portail » |
| Relancer les impayés | Accueil › Finances › « Relances » (+ À faire « familles en retard ») |
| Bibliothèque (gestion) | Accueil › Organisation › « Bibliothèque » |
| Bibliothèque (famille) | Accueil › pastille « Bibliothèque » (+ À faire « livres à rendre ») |
| Personnel et postes | Accueil › Personnel › « Postes » |
| Débloquer le code d'une personne | Accueil › Personnel › « Débloquer un code » |
| Numéros à confirmer | Accueil › Personnel › « Numéros à confirmer » (+ À faire) |
| Invitations du personnel | Accueil › Personnel › « Invitations » |
| Comptes liés aux élèves | Accueil › Élèves › « Comptes liés » (+ À faire « demandes de liaison ») |
| Transport scolaire | Accueil › Organisation › « Transport » |
| Bus de (enfant) | Accueil › pastille « Bus » |
| Conduire mon circuit | Accueil › « Conduire mon circuit » |
| Réseau d'établissements | Accueil › Établissement › « Réseau » (fondateur de réseau : barre du bas) |
| Notifications (liste) | Barre du haut › cloche (admin contenu : barre du bas) |
| Préférences de notification | Mon profil › Préférences › Notifications |
| Annonces de l'école | Barre du bas › Messages (élève : Annonces) ; Accueil › « Annonces » |
| Cahier de liaison | Barre du bas › Messages ; Accueil › « Cahier de liaison » (+ À faire) |
| Tableau de bord communication | Accueil › Vie de l'école › « Lecture des messages » |
| Rapports & statistiques | Barre du bas › Tableau de bord (direction) ; Accueil › « Rapports » |
| Mon emploi du temps (enseignant) | Barre du bas › Agenda ; Accueil › « Emploi du temps » |
| Classes — emploi du temps & progression | Accueil › Organisation › « Classes et emploi du temps » ; enseignant : « Progression » |
| Salles | Accueil › Organisation › « Salles » |
| Agenda de l'établissement | Barre du bas › Agenda ; Accueil › « Agenda de l'école » |
| Conflits d'occupation | Accueil › Organisation › « Conflits d'occupation » |
| Emploi du temps de mon enfant / Mon emploi du temps (élève) | Barre du bas › Agenda ; Accueil › « Emploi du temps » |
| Rapports de mon enfant / Mes rapports | Accueil › « Mes rapports » |
| Structures & annuaire | Accueil › Organisation › « Structures » |
| Alertes de décrochage | Accueil › Vie de l'école › « Alertes décrochage » (+ À faire) |
| Personnel & RH | Accueil › Personnel › « Personnel et RH » |
| Tableau de bord RH | Accueil › Personnel › « Tableau RH » |
| Mon dossier RH | Accueil › « Mon dossier RH » |
| Comptabilité | Accueil › Finances › « Comptabilité » |
| Inscriptions en ligne | Accueil › Élèves › « Inscriptions en ligne » (+ À faire « dossiers ») |
| Nouvelle inscription | Accueil › Élèves › « Nouvelle inscription » |
| Réinscription | Accueil › Élèves › « Réinscription » |
| Paramètres financiers | Accueil › Finances › « Paramètres » |
| Cahier des encaissements | Accueil › Finances › « Encaissements » (raccourci par défaut) |
| Ouvrir un nouvel établissement | Accueil › Établissement › « Ouvrir un établissement » |
| Identité visuelle | Accueil › Établissement › « Identité visuelle » |
| Paiement Orange Money | Accueil › Finances › « Orange Money » |
| Vendeurs marketplace | Accueil › Finances › « Vendeurs » |
| Demandes d'établissement (GSG) | Barre du bas › Écoles ; Accueil › Plateforme GSG |
| Réseaux d'établissements (GSG) | Barre du bas › Réseaux ; Accueil › Plateforme GSG |
| Crédits SMS des écoles (GSG) | Accueil › Plateforme GSG › « Crédits SMS des écoles » |
| Validation des vendeurs (GSG) | Barre du bas › Vendeurs ; Accueil › Plateforme GSG |
| Débloquer un code (GSG) | Accueil › Plateforme GSG › « Débloquer un code » |
| Sécurité (code du compte, appareils) | Mon profil › Sécurité (Code secret, Empreinte, Mes appareils) |
| Se déconnecter | Mon profil, seul en bas |
| onglet Scolarité | Barre du bas › Paiements (parent), Mes notes (élève), Classes (enseignant) ; direction : « Structures » |
| onglet Boutique | Accueil › pastille « Boutique » (vendeur : barre du bas) |
| onglet Révision | supprimé : ce n'était qu'un texte d'attente, aucune fonction |

**À vérifier sur un téléphone Android** : barre du bas de chaque rôle ;
« À faire » et badges hors connexion (dernière valeur), puis au retour du
réseau ; recherche (« reçu ») ; raccourcis modifiés gardés après
fermeture ; profil allégé ; TalkBack sur une pastille avec badge ; mode
sombre ; texte agrandi (×1,3).

---

## REG-23 — Retours du test sur téléphone (2026-10-28)

**Reçue le** : 2026-10-28. **Priorité** : P1. **Statut** : livré le
2026-10-28.

| Retour | Cause | Correction |
|---|---|---|
| APK `x86_64` : « Application non installée » ; `armeabi-v7a` s'installe | L'APK x86_64 est fait pour les émulateurs (processeurs Intel) ; les téléphones sont ARM. Celui du test est en 32 bits (ou son système l'est) | `scripts/construire_android.ps1 -ParAbi` ne produit plus que `arm64-v8a` (téléphones récents) et `armeabi-v7a` (téléphones 32 bits) |
| L'accueil « s'actualise » et renvoie en haut de la page | Toute relecture du profil (relance toutes les 30 s quand le serveur est lent, retour du réseau, nouvelle copie) faisait passer la session par « Ouverture de votre espace… » : l'accueil était démonté puis remonté | Une relecture garde la valeur connue ; l'accueil déjà atteint n'est plus retiré pendant une relecture ou un échec réseau ; position de défilement gardée |
| Hors connexion, après 2 ou 3 ouvertures : « Pas de connexion », accueil inaccessible | Une copie illisible (format d'une version précédente) ou une panne réseau non reconnue (poignée de main TLS coupée, connexion fermée en cours de réponse) bloquait au lieu de servir la copie | Copie illisible traitée comme absente ; pannes réseau reconnues élargies ; hors connexion, toute erreur sert la copie ; l'accueil atteint reste affiché |
| Calendriers en anglais | Aucune traduction des composants Flutter | `flutter_localizations`, application en français (`intl` 0.20) |
| Dates sans barres obliques | Saisie libre du sélecteur Flutter | Sélecteur EcoShop (`choisirDate`) : calendrier français et champ JJ/MM/AAAA où les barres s'écrivent seules, dans les 19 écrans qui demandent une date |
| Pas de photo de profil | — | Photo prise ou choisie depuis « Mon profil » (bucket privé `photos-profils`, 512 Ko), visible des membres de la même école ; gardée sur l'appareil ; avatar de la barre du haut |
| Pas de slogan dans l'identité visuelle | — | `etablissements.slogan` (120 caractères) : écran Identité visuelle, en-tête de l'application, en-tête des reçus et bulletins |
| Direction : où créer l'année, les classes, inscrire ? | Aucun écran ; et la base refusait ces écritures à la Direction (`a_permission` ne regardait que le poste, et le poste « Directeur » n'a aucun code) | Migration 1570 : la Direction détient toutes les permissions de son école. **« Configurer mon établissement »** : 13 étapes dans l'ordre, chacune avec son état (année et périodes, programme officiel, classes, frais, personnel, groupes, salles, cours et enseignants, emploi du temps, inscriptions, inscriptions en ligne, logo-couleur-slogan, Orange Money) ; carte sur l'accueil tant que ce n'est pas fini ; pastilles dans « Organisation » |
| Groupes pédagogiques | N'existaient pas | `groupes_pedagogiques`, `groupes_membres` : demi-classe, langue, option, soutien ; composition par cases à cocher ou première moitié de la classe |
| Administration : pas de liste des écoles confirmées ni de tableau de bord | — | Onglet « Écoles » : toutes les écoles en service (élèves, classes, personnel, parents, dernière activité, recherche, tri), tableau de bord par école (effectifs, comptes actifs 7 j / 30 j, actions par jour sur 30 jours, finances, crédits SMS, mise en route, renseignements de la demande) ; demandes à un toucher |
| Programme officiel peu visible (administration, établissements) | Pastille rangée en dernier, dans « Tout EcoShop » | Direction, enseignants, personnel : « Programme officiel » de leur pays (Organisation), dans la mise en route et sur chaque classe ; Administrateur GSG : pastille de la plateforme |

**Migrations** : `20260906001570_direction_tous_droits`,
`20260906001571_slogan_photo_profil`,
`20260906001572_configuration_etablissement`,
`20260906001574_ecoles_gsg`.

**À vérifier sur un téléphone Android** : accueil qui ne remonte plus
(réseau lent, mode avion puis retour) ; trois ouvertures de suite en mode
avion ; calendrier et saisie JJ/MM/AAAA ; photo de profil (appareil photo,
galerie, retrait) ; slogan ; création d'une année avec reprise des classes ;
création de 3 classes d'un niveau ; « Écoles » de l'Administrateur GSG.

## REG-24 — Emploi du temps dynamique et automatisé

**Reçue le** : 2026-10-28. **Priorité** : P1. **Statut** : livré le
2026-10-28. Recherche et conception :
`docs/propositions/REG-24_EMPLOI_DU_TEMPS_AUTOMATIQUE.md`.

Calcul sur l'appareil, hors connexion (Dart pur, isolat) ; contraintes
impératives (personne à deux endroits, indisponibilités, demi-journées
libres, séances verrouillées, séances de 2 h sans pause au milieu, groupes
en parallèle) et sept critères de qualité pondérés ; diagnostic avant
calcul ; qualité en %, séances non placées et pourquoi ; aperçu par classe
et par enseignant ; autre proposition ; publication en une transaction
(`enregistrer_emploi_genere`, migration `20260906001573`). Tests :
`test/features/planification/moteur_emploi_du_temps_test.dart`.

**Choix validés par le porteur de projet (2026-10-28)** : 32 semaines de
cours par an pour proposer les heures par semaine ; matière principale à
partir du coefficient 3 ; matin = avant 12 h 30 ; groupes d'une même classe
disjoints ; grille par défaut du lundi au samedi matin.

## REG-25 — Affichage de l'accueil

**Reçue le** : 2026-10-28. **Priorité** : P2. **Statut** : livré le
2026-10-28.

Réglage « Affichage de l'accueil » (bouton « Personnaliser l'accueil »
en bas de l'accueil depuis REG-28, et Mon profil › Préférences), gardé sur le téléphone pour
chaque compte :
- **Défilante** (par défaut) : toutes les pastilles, de haut en bas ;
- **Fixe** : une ligne par thème, qu'on fait glisser de côté (la pastille
  suivante dépasse pour le montrer) ; la page reste courte ;
- **2 par ligne** (grandes pastilles : icône 56, libellé 15) ou **3 par
  ligne** (par défaut). Tablette et ordinateur : une ou deux colonnes de
  plus.
La recherche et « Mes raccourcis » restent en grille.

## REG-26 — Autorisations des postes approfondies

**Reçue le** : 2026-10-28. **Priorité** : P1. **Statut** : livré le
2026-10-28 (migration `20260906001575_autorisations_postes`).

Modèle : les profils d'autorisations de Pronote — chaque action sensible a
son droit, coché poste par poste. Huit droits nouveaux, chacun vérifié par
le serveur (les fonctions réservées à la Direction acceptent désormais la
Direction **ou** le droit) :

| Droit | Fonctions du serveur |
|---|---|
| Publier des annonces | `publier_annonce`, `annonces_etablissement`, `portees_annonce` |
| Masquer une annonce | `masquer_annonce` |
| Modérer le cahier de liaison | `masquer_message_liaison` |
| Proclamer les résultats | `proclamer_classe`, `definir_mention_finale` |
| Régler Orange Money | `enregistrer_identifiants_orange_money` |
| Acheter des crédits SMS | `initier_achat_credits_sms` |
| Agréer les vendeurs | `decider_agrement_vendeur_etablissement` |
| Débloquer le code d'une personne | `personnes_debloquables`, `debloquer_code_membre` (jamais celui de la Direction) |

Repère « sensible » (argent, comptes, résultats) affiché dans l'écran des
postes ; compteur des droits et des droits sensibles ; « Tout cocher » par
domaine. Les droits techniques de la plateforme (observabilité, comptes
marchands) ne sont plus proposés aux postes d'une école.

Modèles enrichis (censeur : proclamation, annonces ; surveillant général :
cahier de liaison ; comptable : Orange Money, crédits SMS, export ;
secrétaire : annonces, notifications) et trois nouveaux : **Responsable de
la communication**, **Coordinateur pédagogique**, **Gestionnaire des
comptes**. Les postes créés depuis un modèle reçoivent ses nouveaux droits
(ajout seulement ; séparation encaissement / comptabilité respectée).

**Invitations (question du porteur, 2026-10-28)** : l'identifiant de
l'invitation est l'adresse e-mail (ou le numéro) saisi par la Direction ;
l'invité se connecte avec cette adresse et accepte l'invitation qui
s'affiche. Code à saisir : voir REG-27.

## REG-27 — Code d'invitation ; parent et enseignant sur un même compte

**Reçue le** : 2026-10-28 (décision du porteur : code validé). **Priorité** :
P1. **Statut** : livré le 2026-10-28 (migration
`20260906001576_code_invitation`).

**Code d'invitation.** Chaque invitation (sauf Direction) porte un code de
8 caractères (« K7Q2-M9XD », alphabet sans lettres ambiguës ; O, I et L
saisis par erreur sont corrigés). La Direction le voit dans « Invitations
du personnel », le copie ou l'envoie par WhatsApp avec la marche à suivre.
L'invité, connecté avec n'importe quel compte, touche « J'ai un code
d'invitation » (fin de création du compte, « Mes invitations ») :
- usage unique, valable jusqu'à l'expiration de l'invitation (14 jours) ;
- 5 codes faux par heure et par compte au plus ;
- jamais le rôle Direction ;
- la Direction voit qui a accepté et que c'était « avec le code ».
Écart assumé à la règle REG-16 (identifiant prouvé seul) : le code est
remis en main propre par l'école, qui en répond.

**Parent et enseignant (question du porteur, 2026-10-28)** : un compte
déjà inscrit (parent, élève) qui accepte une invitation garde son rôle
principal et gagne un espace dans l'école. Avant ce correctif, l'accueil
et la barre du bas ne suivaient que le rôle principal : un parent devenu
enseignant ne voyait pas ses outils d'enseignant. Désormais l'étiquette du
rôle, sous le nom, permet de changer d'espace (« Espace enseignant »,
« Espace parent ») ; l'espace de l'école est proposé d'abord, le choix est
gardé sur le téléphone. Les droits restent jugés par le serveur sur
l'appartenance à l'école.

## REG-28 — Actions des écrans visibles

**Reçue le** : 2026-10-29. **Priorité** : P1. **Statut** : livré le
2026-10-29.

Retour du test : « certaines actions sont difficiles à voir, cachées à côté
de la barre de titre ». Une icône seule dans la barre de titre ne dit ni
qu'elle existe ni ce qu'elle fait sans appui long.

Règle désormais : la barre de titre ne garde que le retour, le titre et les
icônes universelles (notifications, apparence, profil, panier). Les actions
d'un écran sont posées juste sous le titre (`BarreActions`,
`lib/core/widgets/barre_actions.dart`), chacune avec son icône **et son
libellé** ; l'action la plus utilisée est en bouton plein ; la rangée
défile de côté sur un petit téléphone ; les onglets de l'écran restent
dessous. Les sélecteurs de date affichent la valeur choisie
(« Période : 01/10/2026 → 30/06/2027 »).

Écrans repris (25) : détail d'une classe (Appel, Évaluations, Bulletins,
Frais, Proclamation — l'appel et les évaluations réservés au personnel),
fiche élève, marketplace (Mes commandes, Sous-comptes, Orange Money,
Anomalies — les trois derniers étaient dans un menu « ⋮ »), présence du
jour (Portail, Cartes, Relances, Crédits SMS, Réglages — menu « ⋮ »
supprimé), portail, pilotage du réseau, communication, balance, grand
livre, journal, pièces comptables, carnet de notes, conflits et
progression de l'emploi du temps, écoles GSG, campagne d'inscription,
personnel, assistant IA, transport (chauffeur, circuit), rattachement de
la scolarité, programme officiel, anomalies, recommandations, appel,
vie scolaire, groupes pédagogiques.

Accueil : le bouton d'affichage quitte la barre du haut (3 icônes au plus)
pour un bouton « Personnaliser l'accueil » en bas des pastilles. Les icônes
restantes de la barre du haut prennent la couleur de l'école (taille 26).

## REG-29 — Connexion Google : un seul sélecteur de comptes

**Reçue le** : 2026-10-29. **Priorité** : P1. **Statut** : livré le
2026-10-29.

Retour du test : à la connexion, le sélecteur des comptes du téléphone
s'ouvrait, puis une seconde feuille « comptes déjà connectés » apparaissait
derrière et ne se fermait pas après le choix.

Cause : à l'ouverture de l'écran de connexion, l'application tentait d'office
une connexion Google discrète (REG-16) ; sur Android, elle affiche sa propre
feuille. Rien n'empêchait le bouton « Continuer avec Google » d'ouvrir le
sélecteur en même temps, et un écran reconstruit relançait la tentative —
avec le compte qu'on venait d'autoriser. L'application ne peut pas fermer
une feuille du système une fois ouverte.

Correction : plus de tentative d'office ; un seul sélecteur, à l'appui du
bouton. Une seule demande Google à la fois dans le contrôleur de connexion
(double appui, écran reconstruit). La session déjà ouverte sur le téléphone
reste reprise sans écran de connexion.

## REG-31 — Confidentialité, conditions, suppression de compte

**Reçue le** : 2026-10-29. **Priorité** : P0 (bloque la publication sur le
Play Store et le logo de l'écran de consentement Google). **Statut** :
livré le 2026-10-29.

Demande : pages de confidentialité et de conditions d'utilisation « beaucoup
plus humaines que possible », pour le futur site de Global Service Groupe
qui hébergera toutes ses applications.

**Recherche préalable.**
- Google Play, *Données utilisateur* et *Suppression de compte* : une
  application où l'on crée un compte doit offrir la suppression **dans
  l'application** et par **une page web** (lien déclaré dans *Sécurité des
  données*), qui nomme l'application et l'éditeur, permet la demande sans
  réinstaller, et dit ce qui est gardé et pourquoi. EcoShop n'avait pas
  cette fonction : elle est ajoutée ici.
- Guinée, loi L/2016/037/AN du 26 juillet 2016 (cybersécurité et données
  personnelles) : déclaration préalable des traitements à l'autorité de
  protection ; **autorisation préalable** pour les transferts hors de
  Guinée (serveurs à Paris, prestataires étrangers) et pour certains
  identifiants (numéros de téléphone). Décret d'avril 2025 : mise en
  conformité sous 12 mois. Points remis à l'avocat.

**Site** (`site_gsg/`, HTML et CSS seuls, sans script ni traceur, thème
sombre automatique, lisible sur un petit téléphone) :
- `/confidentialite/` : une politique pour tout GSG — nos promesses, puis une
  section par application (`#ecoshop`) : l'école décide, GSG protège
  (responsable / sous-traitant), ce que nous savons selon le rôle, ce que le
  téléphone utilise (caméra, position du seul chauffeur, notifications,
  empreinte), élèves et enfants, IA (Anthropic, minimisation, « l'IA
  propose, une personne décide »), paiements (GSG ne détient jamais
  l'argent), prestataires, lieu d'hébergement, durées, sécurité, droits
  (réponse sous 30 jours), suppression ;
- `/conditions/` : compte, respect, rôle de l'école, parents et élèves,
  personnel, paiements et remboursements, boutique, IA, tarifs, limites,
  propriété, suspension, changements (préavis de 15 jours), litiges (droit
  guinéen, Conakry) ;
- `/suppression-compte/` : depuis l'application, ou par e-mail prérempli ;
  ce qui est effacé, ce qui est gardé ; cas de la direction, de l'élève
  mineur, du vendeur ;
- `README.md` : champs à compléter, relecture, mise en ligne sur
  Cloudflare Pages, déclarations Google.

**Application.**
- Mon profil : rubrique « Vos données » (conditions, confidentialité) et
  « Supprimer mon compte » tout en bas ; écran qui dit ce qui est effacé et
  gardé, case « J'ai compris », motif facultatif, code secret demandé
  (action sensible) ; refus expliqué si l'on est la seule direction d'une
  école ; bandeau « Votre compte sera supprimé le … — Garder mon compte »
  pendant les 7 jours.
- Écran de connexion : « En continuant, vous acceptez… » avec les deux
  liens. Écran des conditions : boutons vers les textes complets.

**Serveur** (migration `…1577`, test pgTAP `95`, 29 assertions) :
`demandes_suppression_compte`, `demander_` / `annuler_` /
`etat_suppression_compte`, `enregistrer_demande_suppression_web` (équipe
GSG, demandes reçues par e-mail), `anonymiser_compte`, tâche nocturne
`effectuer-suppressions-comptes` (comptes échus ; traces de sécurité de
plus d'un an). **Anonymisation, pas effacement de la ligne** : plus de
cinquante tables renvoient au profil sans cascade (notes, reçus, écritures
comptables) — ces pièces appartiennent à l'école ou doivent être gardées.
Conditions **v1.0** publiées pour les deux parcours (adulte, élève).

**Vérifié** : toutes les migrations passent sur un PostgreSQL 16 local
(imitation des schémas Supabase) ; test `95` 29/29, tests `54`, `75` et
`92` verts (75 et 92 mis à jour : 10 tâches planifiées, 15 modèles de poste
et droits du comptable de REG-26) ; pages rendues sur téléphone (clair et
sombre) et ordinateur, sans débordement, ancres vérifiées.

**Reste** : compléter ⟦siège⟧ et ⟦RCCM⟧ ; relecture de l'avocat ;
déclarations à l'autorité guinéenne ; mise en ligne ; liens dans la Play
Console. Photo de profil : si Supabase refuse l'effacement direct du
fichier, la demande le note (`reste_a_faire`) pour reprise.

## REG-32 — Les espaces partent de l'établissement

**Reçue le** : 2026-10-29. **Priorité** : P0 (contrôle d'accès). **Statut** :
livré le 2026-10-29.

Retour du test : le changement d'espace dans la barre de titre est apprécié,
mais « un enseignant peut être parent dans un établissement et pas dans
l'autre » ; les rôles doivent partir de l'établissement.

**Constat (contrôle).**
1. L'espace « parent » était proposé dans **toute** école dès que le rôle
   principal du compte était « parent », même sans enfant dans cette école.
2. Le sélecteur d'enfant mélangeait les enfants de **toutes** les écoles.
3. Un enseignant (rôle principal enseignant) **ne pouvait pas relier son
   enfant** : `lier_parent_a_fiche` exigeait le rôle principal « parent ».
   L'accès aux données des enfants, lui, était déjà correct côté serveur :
   il passe par les liens confirmés, école par école (`est_parent_confirme`,
   `fiche_visible`).

**Recherche.** Pronote et VSware : un espace par établissement, mais un
compte de connexion par espace. ClassDojo : deux comptes et deux adresses
e-mail obligatoires. Bloomz : bascule de rôle sans école. McGraw-Hill :
bascule de rôle et bascule d'organisation séparées. Retenu : **une seule
connexion, et chaque espace = (rôle, école)**.

**Livré.**
- Serveur (migration `…1578`, test pgTAP `96`, 9/9 ; test `08` mis à jour) :
  `mes_espaces()` — rattachements actifs (personnel, élève) et écoles où le
  compte a un enfant lié **confirmé et autorisé** ; liaison d'un enfant
  ouverte à tout compte adulte, refusée aux comptes élèves.
- Application : espaces « Enseignant · École A », « Parent · École B
  (2 enfants) » dans la barre de titre ; choisir un espace de personnel
  d'une autre école en fait l'école active (vérifié par le serveur) ;
  l'espace parent ne montre que les enfants de son école ; l'en-tête
  affiche l'école de l'espace ; « Relier mon enfant » dans Mon profil pour
  tout adulte ; copie hors connexion des espaces, purgée à la déconnexion.

**Effet pour un parent seul** dont les enfants sont dans deux écoles : deux
espaces parent, un par école (comme deux espaces Pronote), au lieu d'une
liste mélangée.

## REG-33 — Séries du lycée, programme de l'école, moyenne pondérée

**Reçue le** : 2026-10-29. **Priorité** : P0 (bloquait toute école
guinéenne). **Statut** : livré le 2026-10-29.

Demande : séries du lycée, pour une plateforme multi-systèmes et
multi-pays, après recherche approfondie et comparaison des meilleures
applications.

**Recherche.**
- **Guinée** : Baccalauréat unique en séries SM, SE, SS ; lycée en 11e,
  12e, Terminale ; session de rattrapage de 8,50 à 9,99 de moyenne (2026).
  **Aucune grille officielle des coefficients n'est publiée en ligne**
  (site du ministère, presse, annales consultés) : rien n'est inventé.
- **Sénégal** : L1, L1a, L2, L'1, L'2, S1 à S5, T1, T2, G. **Côte
  d'Ivoire** : A, C, D… avec programmes par série. **Ghana** (nouveau
  programme 2024) : tronc commun, matières remplacées selon le programme
  (Science : Additional Mathematics au lieu de Core Mathematics).
- **Pronote** : l'établissement tient ses matières (services) et leurs
  coefficients ; moyenne générale = moyennes de matières pondérées.

**Constats en cours de route (plus urgents que les séries).**
1. **Aucun programme officiel n'est publié pour la Guinée en production** :
   une école ne pouvait créer **aucun cours**, donc ni notes ni bulletins.
2. **La moyenne générale ignorait les coefficients des matières** : elle
   mêlait toutes les évaluations (un devoir de dessin pesait autant qu'un
   devoir de mathématiques).

**Livré** (migration `…1579`, test pgTAP `97` 17/17 ; test `46` adapté) :
- une série couvre plusieurs niveaux (`filieres_niveaux`) ; SM, SE, SS
  publiées pour la Guinée en 11e, 12e et Terminale, **sans coefficients** ;
  chaque lycée choisit la série de chacune de ses classes ;
- **programme de l'école** (`programmes_officiels.etablissement_id`) :
  reprise du programme national (copie ajustable) ou matières créées par
  l'école ; lecture réservée à l'école, aux parents de ses élèves et à GSG ;
  ajusté par la direction ou le poste « paramètres de la scolarité » ;
- coefficients **décimaux** (0,5 ; 2,5) et nature de la matière (tronc
  commun, spécialité, option) ;
- **moyenne générale** = moyennes de matières pondérées par leurs
  coefficients (1 s'il manque) ; moyenne d'une matière inchangée ;
- application : étape de mise en route « Matières et coefficients » (par
  niveau et série des classes), écran des matières avec suggestions de
  noms, « Cours et enseignants » sur le programme de l'école, état de la
  mise en route (niveaux sans matières), copie hors connexion purgée à la
  déconnexion ; le référentiel gardé sur le téléphone ne contient que le
  national.

**Décision du porteur de projet (2026-10-30).** Chaque établissement
fixe ses coefficients (programme de l'école) : GSG ne publie pas de grille
nationale ; un programme national, s'il est publié un jour, ne sert que de
modèle à reprendre.

**Vérifié chez le porteur de projet (2026-10-30)** : 766 tests Flutter au
vert (test du profil adapté, commit `006dd4c`) ; migrations 1578 et 1579
appliquées sur Supabase, 17 fonctions redéployées, contrôle de préparation
au vert sauf le prix des packs SMS.

**Reste.** [code] Notation anglophone (pourcentages, lettres A1–F9 de la
WAEC) le jour d'une école ghanéenne.

---

## REG-34 — Messagerie famille ↔ école, heures de messagerie, groupes de classe

**Reçue le** : 2026-10-30 (feuille de route, point 8). **Priorité** : P1.
**Statut** : livré le 2026-10-30 — migration `…1580` à appliquer, à
vérifier sur téléphone.

**Recherche.**
- **ClassDojo** : « heures calmes » de l'enseignant (les messages arrivent,
  la notification attend) ; numéros personnels jamais montrés ; la
  direction peut voir les échanges.
- **Remind** : historique ineffaçable, signalement ; l'enseignant peut
  couper les réponses (« annonce ») ; heures de bureau.
- **Seesaw** : l'administration peut lire tous les messages ; pas de
  message privé entre élèves.
- **Pronote / ParentSquare** : la famille écrit à un enseignant de
  l'enfant ou à la vie scolaire, choisis dans une liste.
- **Directive du Manitoba (23 oct. 2026)** : pas d'échange personnel
  adulte ↔ élève sur une plateforme non supervisée. **Projet sud-africain
  (sept. 2026)** : déconseille les discussions privées enseignant ↔
  élève, privilégie les heures de classe.

**Règles retenues.** Jamais d'échange privé adulte ↔ élève : les élèves
n'échangent que dans le groupe de leur classe, sous les yeux de leurs
enseignants (règles M9, inchangées : groupe créé par un adulte, aucun
parent, texte seul, rien n'est effacé). Le parent écrit au sujet de **son
enfant**, à un **enseignant de la classe** ou à la **direction** ; la
direction voit tout ; aucun numéro personnel n'est exposé.

**Livré** (migration `…1580`, test pgTAP `98` 55/55 ; tests `86` 41/41 et
`94` 22/22 adaptés, aucun autre écart sur la suite locale) :
- **heures de messagerie de l'école** (par défaut du lundi au samedi, de
  7 h à 19 h, fuseau de l'école), réglées par la direction. En dehors : la
  notification au personnel est **reportée à l'ouverture**
  (`notifications.envoyer_apres`, respecté par le service d'envoi) et les
  élèves n'écrivent pas dans les groupes ;
- **le parent écrit à l'école** (cahier de liaison étendu,
  `ecrire_mot_parent`) : choix du destinataire, heures affichées avant
  d'écrire, « Lu par l'école » ; le fil n'est lu que par ce destinataire,
  la direction et les parents confirmés — pas par les autres
  enseignants ; le personnel qui ouvre le fil le marque lu ;
- **groupes de classe** : ouverts à la demande par un enseignant de la
  classe ou la direction ; messages avec la clé de l'appareil (renvoi sans
  doublon) ; groupe « annonces seulement » ou suspendu ; signalement par
  tout membre ; retrait motivé (l'élève voit « message retiré », les
  adultes gardent le texte), journal d'audit ; non lus par compte ; un
  message d'adulte prévient la classe (à l'ouverture), un message d'élève
  ne réveille personne ;
- accueil : `groupes_non_lus` dans le résumé ; le cahier du personnel ne
  compte que les fils qu'il voit ;
- application : « Écrire à l'école » dans le cahier (parent, seulement les
  enfants de l'école de l'espace choisi) ; pastille et entrée « Groupes de
  classe » (« Ma classe » pour l'élève) ; fil avec appui long (signaler,
  retirer), réglages, signalements ; écran des heures pour la direction ;
  lecture et envoi hors connexion (rejeu enregistré, copies purgées à la
  déconnexion).

**Reste.** [GSG] appliquer la migration 1580. [test] parcours sur
téléphone : parent → enseignant, réponse, « Lu par l'école » ; groupe de
classe, élève hors des heures ; notification reportée le soir.
[code] pièces jointes (photos de devoirs) si les écoles le demandent —
volontairement absentes (texte seul, règle M9).
