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
| REG-02 | Proposition d'implémentation d'un opérateur Mobile Money | P1 | ouvert |
| REG-03 | Référentiel comptable : SYSCOHADA ou comptabilité simplifiée | P1 | à arbitrer |
| REG-04 | Création et validation d'un nouvel établissement (fondateur) | P1 | ouvert (dette du 2026-09-17) |
| REG-05 | README et état d'avancement à resynchroniser (M16, D1-D6, facturation, lancement) | P2 | ouvert |
| REG-06 | Branches locales non publiées sur le dépôt distant | P2 | ouvert |

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

**Priorité** : P1 (après REG-01). **Statut** : ouvert.

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

**Priorité** : P1. **Statut** : à arbitrer par le porteur de projet.

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

---

## REG-04 — Création et validation d'un nouvel établissement (fondateur)

**Priorité** : P1. **Statut** : ouvert. Dette tracée le 2026-09-17
(`docs/AUDIT_ECOSHOP_FLUTTER.md`, commit `7c96c35`) : aucun parcours ne
permet aujourd'hui de créer un établissement autrement que par insertion SQL
directe — aucun client réel ne peut être accueilli sans lui.

## REG-05 — README à resynchroniser

Le README annonce encore M16 « bloqué / à venir » alors que M16, D1-D6, la
facturation (a-d), la journalisation et les quatre points bloquants avant
lancement sont clos.

## REG-06 — Branches non publiées

Une vingtaine de branches de travail n'existent qu'en local (seules `main`,
`m14-comptabilite-sans-ohada` et `m15-marketplace-sans-auth` sont sur le
dépôt distant). À publier ou à supprimer après vérification de leur fusion
dans `main`.
