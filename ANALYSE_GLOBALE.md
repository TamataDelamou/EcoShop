# EcoShop — Analyse Globale & Vision d'Architecture (rév. 2 — alignée Cahier v4.1)

> **Livrable Phase 3 — Analyse globale, révisée après cadrage officiel.**
> Ce document intègre les réponses définitives du porteur de projet (architecture
> Supabase, monorepo, identité, marketplace AssoShop, ordre de démarrage).
>
> **Projet source original (traçabilité obligatoire) :**
> `C:\Users\delam\ProjetsFlutter\ecoshop_flutter`
> **Dépôt cible :** `C:\Users\delam\PlatformGSG\EcoShop`
> **Cahier de conception de référence :** `Cahier_de_Conception_EcoShop_v4.1.md`

---

## 0. Synthèse exécutive

EcoShop v4.1 est la **fusion du cahier EcoShop v2.0** (gestion scolaire +
marketplace) **et du cahier EduRéussite** (moteur de révision et de réussite aux
examens). L'application — Flutter (Android/iOS/Windows) — est adossée à
**Supabase** (Postgres + RLS, Auth natif, Storage, Realtime, Edge Functions),
remplaçant l'architecture Firebase du code source historique. L'identité est
fédérée de façon **additive** par **GSG ID** via le **GSG Platform Kernel**
(externe, dont `src/` est ici le contrat de référence).

Le dépôt est organisé en **monorepo** : `apps/client_flutter` (application),
`supabase` (migrations/RLS/Edge Functions), `docs` (documentation maître).

La construction est strictement séquentielle, module par module, selon trois
phases : **A — Socle & Data (M0-M3)**, **B — Verticaux pédagogiques & scolaires
(M4-M12)**, **C — Marketplace AssoShop, services & monétisation (M13-M20)**.

---

## 1. Audit du Code Existant & Correctifs

### 1.1 Chiffres clés du projet source (référence métier)

| Élément | Valeur constatée |
|---|---|
| Modules fonctionnels (`lib/features/`) | 21 |
| Écrans livrés | 99 / ~242 estimés |
| Modèles (`lib/models/`) | 41 fichiers |
| Services (`lib/services/`) | 28 fichiers |
| Cloud Functions Firebase | ~15 |
| Règles de gestion documentées | 18 (source v2.0) + règles v4.1 |

### 1.2 Positionnement du code source

`ecoshop_flutter` est conservé comme **référence fonctionnelle et réglementaire**
uniquement. Son architecture (Firebase Auth/Firestore/Functions, logique métier
dispersée client/functions/règles) **n'est pas la cible** : la cible est le socle
Supabase décrit au chapitre 3. Les migrations Firebase → Supabase suivent le
« Modèle d'authentification Supabase » commun au portefeuille GSG.

### 1.3 Dettes techniques héritées à corriger dans la cible

| # | Problème source | Correctif dans la cible v4.1 |
|---|---|---|
| A1 | Logique métier dispersée client/Functions/règles | Règles métier portées par **Postgres (RLS, contraintes, triggers) + Edge Functions** ; client = présentation + état |
| A2 | Couplage fort à Firebase | **Supabase** natif (Auth, Postgres, Storage, Realtime) |
| A3 | Conformité paiement non tranchée | **Port Paiement agnostique** (hexagonal) : adaptateur CinetPay + adaptateur Mobile Money local (Orange/MTN/Wave) activable par pays/établissement |
| A4 | App Check absent | Sécurité portée par **RLS + serveur systématique** (ch. 34) |
| A5 | Rôle-par-établissement partiel | **Modèle de rôles à deux niveaux** (rôle racine + poste déclaré), `profiles` + RLS |
| A6 | Dérive documentaire | Mise à jour du suivi dans le **même changement** que chaque module |
| A7 | Pas de projet de dev | **Supabase local / projet dev** provisionné dès M0-M1 |

---

## 2. Étude des Règles Métiers (v4.1)

### 2.1 Modèle de rôles (ch. 4) — deux niveaux

- **Rôles racine** (6) : Élève, Parent, Enseignant, Direction, Vendeur,
  Fondateur de réseau.
- **Postes déclarés** (dynamiques, par établissement) : attribution fine des
  permissions au-delà du rôle racine.
- **Rôles plateforme** : Administrateur GSG (supra-établissement, unique),
  Administrateur de contenu pédagogique.
- **Élève supervisé** (primaire/maternelle) : compte créé par le parent, lié à
  un compte parent superviseur.
- Un enseignant peut être rattaché à **plusieurs établissements** (sélecteur
  d'établissement actif).

### 2.2 Authentification & identité (ch. 5)

- **Auth native Supabase** : 2 entrées (téléphone/e-mail) × 4 canaux (SMS,
  WhatsApp, Magic Link, OTP e-mail), normalisation **E.164** avant tout appel.
- Élève et Parent sont les **seuls rôles auto-inscriptibles** ; les rôles à
  privilège passent par invitation ou demande validée.
- **Identifiant canonique unique** : le premier identifiant authentifié devient
  canonique ; les seconds canaux ne sont ajoutés que depuis une session active.
- **Fédération GSG ID** : couche additive non bloquante — trigger/Edge Function
  présente le JWT à GSG ID (vérification JWKS, liste blanche), colonne
  `gsg_id` sur `profiles`, **Custom Access Token Hook** recopie rôle/poste/
  établissement dans le jeton (source de vérité = table `profiles`, jamais le jeton).
- Liaison compte↔fiche : **matricule + date de naissance** (double facteur),
  anti-brute-force.

### 2.3 Référentiel pédagogique multi-pays (ch. 6)

- 16 pays CEDEAO, 4 systèmes : `francophone_cfa`, `anglophone_waec`,
  `lusophone`, `arabophone_mixte`.
- Entités : `pays`, `pays_cycle`, `pays_niveau` (+ `grade_level_normalise`),
  `pays_examen`, `pays_filiere`, `programme_officiel`, `programme_matiere`.
- Domaine « éducation », **distinct** du Referential Engine générique du Kernel
  (qui qualifie l'utilisateur : pays/devise/langue/fuseau). Pas de migration de
  l'un vers l'autre.

### 2.4 Marketplace — cadre AssoShop mono-vendeur (ch. 27)

- **Panier mono-vendeur** pour les commerçants externes : une commande validée
  auprès d'**un seul commerçant à la fois** (logistique et ventilation des
  paiements simplifiées).
- **Sous-compte marchand par établissement** : chaque établissement configure
  son propre compte CinetPay ; les frais de scolarité, cotisations, inscriptions
  et repas sont encaissés **directement sur le compte de l'établissement**.
- **Absence de portefeuille vendeur** ; règlement différé hors plateforme ;
  convention vendeur-établissement.
- Le **panier multi-vendeur** de la v2.0 est **supprimé**.

### 2.5 Modèle économique (ch. 36) — 9 flux

1. Licence applicative Pro établissement (seuil gratuit paramétrable, jamais en dur).
2. Frais IA admin (annuel, indépendant du palier Pro).
3. Abonnement Premium élève (moteur de révision).
4. Abonnement IA professeur.
5. Frais de création de réseau.
6. Commission marketplace.
7. Packs de préparation aux examens.
8. Concours sponsorisés / partenariats.
9. Publicité limitée (protégée pour les mineurs).

### 2.6 Règles transversales conservées (héritées v2.0)

Soft-delete systématique, jamais de privilège sur la seule foi du client,
jamais de commission GSG sur la scolarité, soldes élève/établissement distincts,
statut Pro par année scolaire, protection des mineurs (groupes surveillés, pas
de MP élève↔élève), cycle de verrouillage progressif des notes officielles.

---

## 3. Instanciation & Vision Plurielle (Architecture)

### 3.1 Principes directeurs

1. **Supabase est le backend applicatif** : Postgres + RLS, Auth natif,
   Storage, Realtime, Edge Functions. Pas de monolithe NestJS applicatif.
2. **GSG Platform Kernel est externe** : `src/` sert de contrat de référence
   (DTOs/API) pour la fédération GSG ID, couche additive non bloquante.
3. **Monorepo** : `apps/client_flutter`, `supabase`, `docs`.
4. **Client hors-ligne prioritaire** : SQLite/Drift + file de synchronisation
   (outbox) + résolution de conflits par entité.
5. **Port Paiement hexagonal** : CinetPay = adaptateur n°1 ; Mobile Money local
   (Orange/MTN/Wave) = adaptateur n°2, activable par pays/préférence.
6. **Serveur fait foi** : toute vérification de permission s'exécute côté
   serveur à chaque requête (RLS + Edge Functions), jamais seulement à l'écran.

### 3.2 Vue d'ensemble cible

```
apps/client_flutter (Flutter — Riverpod, Drift/SQLite hors-ligne)
        │  supabase_flutter (REST/Realtime)
        ▼
Supabase : Auth (OTP E.164) · Postgres + RLS · Storage · Realtime · Edge Functions
        │
        ├─ Edge Function « gsg-id-federate » ──► GSG Platform Kernel (src/ : contrat)
        ├─ Edge Functions paiement ──► Port Paiement ─┬─ adaptateur CinetPay
        │                                              └─ adaptateur Mobile Money local
        └─ Edge Functions IA / notifications (Twilio, Resend)
```

### 3.3 Charte graphique « Innovation & Énergie »

| Usage | Couleur | Rôle |
|---|---|---|
| Base 70 % | `#F8FAFC` | fonds, surfaces |
| Base 70 % | `#2563EB` | actions principales, navigation |
| Accent 20 % | `#FF6B00` | CTA secondaires, badges |
| Premium 10 % | `#10B981` | succès / validation |
| Premium 10 % | `#E1A100` | marqueurs haut de gamme (Pro, Premium) |

### 3.4 Stratégie hors-ligne (ch. 34-35)

- **SQLite/Drift** pour le stockage local ; file de synchronisation outbox ;
  `connectivity_plus` pour la détection réseau.
- **Conflits par entité** : dernière écriture horodatée pour les progressions,
  écritures additives pour les données cumulatives, « garder les deux + alerte »
  pour les entités partagées.
- Badge « non synchronisé » sur les écrans critiques ; reçus marqués
  « en ligne / en attente de synchronisation ».

---

## 4. Plan de Découpage Modulaire Strict

### 4.1 Règles de séquençage

- Exécution **strictement module par module** ; un module n'est ouvert qu'une
  fois le précédent **100 % clos, testé, corrigé et validé**.
- Point de contrôle formel après chaque module :
  **« Le module [Nom] est-il totalement clos et validé pour passer au suivant ? »**

### 4.2 Livrables obligatoires par module

1. Résolution complète des problèmes du code existant associés au module.
2. Code source complet, propre, optimisé et commenté.
3. Documentation d'API et mise en conformité aux règles métiers (v4.1).
4. Scénarios de tests unitaires et d'intégration couvrant le module.
5. **Rapport d'écart fonctionnel vs `ecoshop_flutter`** — avant de déclarer un
   module clos, comparer le périmètre réellement couvert avec le code source
   original (`C:\Users\delam\ProjetsFlutter\ecoshop_flutter`, dossier
   `lib/features/` correspondant). Toute fonctionnalité présente dans
   `ecoshop_flutter` mais absente ou dégradée ici est **listée et posée en
   question — jamais implémentée ni écartée silencieusement**. La décision
   (implémenter maintenant / différer / abandonner explicitement et pourquoi)
   se prend en conversation avec le porteur de projet, module par module.
   Rappel de cadrage : ce projet est un environnement d'**amélioration** de
   `ecoshop_flutter`, pas une réécriture qui peut perdre des fonctionnalités
   en route. Règle transversale permanente, applicable à tous les modules,
   passés et à venir (cf. audit rétroactif M0→M15 dans
   [`docs/AUDIT_ECOSHOP_FLUTTER.md`](./docs/AUDIT_ECOSHOP_FLUTTER.md)).

### 4.3 Séquence (Phase A / B / C)

**Phase A — Socle & Data (M0-M3)**

| # | Module | Contenu |
|---|---|---|
| M0 | **Initialisation & Socle Supabase/Flutter** | Monorepo, README (traçabilité), conventions, CI, config Supabase, migrations cœur (profiles/rôles/multi-tenant + RLS), hook GSG ID, socle Flutter (Riverpod, Drift/SQLite, thème, sync queue) |
| M1 | **Schéma Supabase avancé** | Établissements, unités, postes, membres, contraintes multi-tenant, seeds, RLS fine |
| M2 | **Auth & fédération GSG ID** | Parcours OTP (E.164), sélection de rôle, liaison compte↔fiche, Edge Function fédération bout en bout |
| M3 | **Socle applicatif Flutter** | Navigation/coquille, sélecteurs établissement/enfant, écrans auth, garde de session |

**Phase B — Verticaux pédagogiques & scolaires (M4-M12)**

| # | Module | Contenu |
|---|---|---|
| M4 | **Référentiel pédagogique CEDEAO** | pays/cycle/niveau/filière/examen/programme, 16 pays, 4 systèmes |
| M5 | **Administration & Scolarité** | Élèves, inscriptions/réinscriptions, classes, liaison compte↔fiche |
| M6 | **Notes & Bulletins** | Saisie, verrouillage progressif, moyennes, bulletins, risque d'échec |
| M7 | **Emploi du temps** | Grilles, séances, conflits, annulations |
| M8 | **RH** | Personnel, contrats, congés, paie |
| M9 | **Vie scolaire** | Absences, sanctions, bourses |
| M10 | **Moteur de questions & quiz** | Banque de questions, quiz, mode entraînement/examen, CMS pédagogique |
| M11 | **Profil de maîtrise & progression** | Compétences, répétition espacée, planificateur, gamification |
| M12 | **Préparation aux examens** | Examens nationaux, packs, résultats, récompenses/certificats |

**Phase C — Marketplace AssoShop, services & monétisation (M13-M20)**

| # | Module | Contenu |
|---|---|---|
| M13 | **Marketplace AssoShop mono-vendeur** | Catalogue, panier mono-vendeur, commandes, sous-comptes établissement |
| M14 | **Paiement (Port hexagonal)** | Adaptateur CinetPay + adaptateur Mobile Money local, reçus, encaissements scolarité |
| M15 | **Communication & Notifications** | Twilio/Resend, annonces, groupes surveillés, signalements |
| M16 | **IA à rôles** | Tuteur IA, Directeur-Adviser, Parent IA, Scan d'exercice, Edge Functions IA |
| M17 | **Bibliothèque & Ressources** | Bibliothèque physique, bibliothèque numérique, flashcards |
| M18 | **Transport scolaire** | Circuits, affectation, suivi en direct |
| M19 | **Réseau d'établissements & Backoffice GSG** | Réseaux, validation, paramètres globaux, CMS |
| M20 | **Reporting, Tableaux de bord & Premium** | Tableau de bord directeur, alertes, monétisation Premium élève |

### 4.4 État réel du découpage — réconciliation (livré M4 → M15)

Le plan §4.3 (retenu pour traçabilité) a été **réordonné à la construction** :
les verticaux pédagogiques les plus structurants ont été livrés en priorité, et
la vie scolaire / communication ont été avancées. Le périmètre **réellement
délivré** par migrations SQL est le suivant.

| # | Module réellement livré | Migration | Contrat d'interface | Écart vs plan §4.3 |
|---|---|---|---|---|
| M4 | Référentiel pédagogique CEDEAO | `20260906000400_m4_referentiel_pedagogique.sql` | [M04](./docs/contrats/M04_referentiel_pedagogique.md) | conforme |
| M5 | Administration & Scolarité | `20260906000500_m5_administration_scolarite.sql` | [M05](./docs/contrats/M05_administration_scolarite.md) | conforme |
| M6 | Notes & Évaluations | `20260906000600_m6_notes_evaluations.sql` | [M06](./docs/contrats/M06_notes_evaluations.md) | conforme (« Bulletins » inclus) |
| M7 | Absences & Vie scolaire | `20260906000700_m7_absences_vie_scolaire.sql` | [M07](./docs/contrats/M07_absences_vie_scolaire.md) | vie scolaire avancée (ex-M9) |
| M8 | RH & Personnel | `20260906000800_m8_rh_personnel.sql` | [M08](./docs/contrats/M08_rh_personnel.md) | conforme |
| M9 | Communication & Notifications | `20260906000900_m9_communication_notifications.sql` | [M09](./docs/contrats/M09_communication_notifications.md) | communication avancée (ex-M15) |
| M10 | Rapports & Statistiques | `20260906001000_m10_rapports_statistiques.sql` | [M10](./docs/contrats/M10_rapports_statistiques.md) | nouveau (ex-Reporting M20, avancé) |
| M11 | Planification & Agenda | `20260906001100_m11_planification_agenda.sql` | [M11](./docs/contrats/M11_planification_agenda.md) | emploi du temps (ex-M7) |
| M12 | Intégration & Déploiement (observabilité) | `20260906001200_m12_observabilite.sql` | [M12](./docs/contrats/M12_observabilite.md) | nouveau |
| M13 | Marketplace AssoShop (mono-vendeur) | `20260906001300_m13_marketplace_assoshop.sql` | [M13](./docs/contrats/M13_marketplace_assoshop.md) | conforme |
| M14 | Comptabilité sans OHADA | `20260906001400_m14_comptabilite_sans_ohada.sql` | [M14](./docs/contrats/M14_comptabilite.md) | livré et vérifié (client Flutter + RLS 31-33 ; le Port Paiement, ex-M14 dans le plan §4.3, reste un chantier distinct à replanifier M16-M20 — non couplé à ce module) |
| M15 | Marketplace sans authentification | `20260906001500_m15_marketplace_sans_auth.sql` | [M15](./docs/contrats/M15_marketplace_public.md) | nouveau |
| M15bis | Thèmes internationaux & Dark Mode | *(aucune — module client pur)* | [M15bis](./docs/contrats/M15bis_themes_dark_mode.md) | inséré hors plan §4.3, entre M15 et M16 (cf. règle transversale §4.2.5) |
| M15ter | Export PDF (bulletins & reçus) | *(aucune — module client pur)* | [M15ter](./docs/contrats/M15ter_export_pdf.md) | inséré hors plan §4.3, entre M15bis et M16, en réponse au point d'écart §0.2 de l'audit — volet « reçu PDF » livré, retiré, puis reconstruit après M15quater, voir M15ter §7 |
| M15quater | Inscription, réinscription & encaissement de scolarité | `20260906001501_m15quater_inscription_encaissement.sql` | [M15quater](./docs/contrats/M15quater_inscription_encaissement.md) | inséré hors plan §4.3, entre M15ter et M16, devant les ~8 autres écarts de l'audit |
| M16 | IA à rôles (en cours) — sous-livrables 1-4/7 : score de risque par élève, bannière dashboard directeur, Edge Functions IA + Tuteur IA/Directeur-Adviser, Parent IA (déclaration manuelle) | `20260906001504...`, `20260906001505...`, `20260906001506...`, `20260906001507_m16_continuite_conversation_libre.sql`, `20260906001508_m16_parent_ia.sql` | *(à consolider en fin de module)* | conforme au plan §4.3, ordre de construction réordonné selon l'état des lieux `ecoshop_flutter` (voir narratif ci-dessous) |

**Non encore livrés** (replanifier dans M16 → M20) : le Port Paiement hexagonal
(CinetPay + Mobile Money, ex-M14), et les verticaux EduRéussite décalés — moteur
de questions & quiz (ex-M10), profil de maîtrise & gamification (ex-M11),
préparation aux examens (ex-M12) — ainsi que M16 IA à rôles, M17 Bibliothèque,
M18 Transport, M19 Réseau & Backoffice GSG, M20 Reporting/Premium.

**M15bis — Thèmes internationaux & Dark Mode** (livré, cf.
[`docs/contrats/M15bis_themes_dark_mode.md`](./docs/contrats/M15bis_themes_dark_mode.md)) :
inséré dans la séquence de construction entre M15 (livré) et M16 (IA à rôles,
qui conserve son numéro et son contenu inchangés). Périmètre : deux nouvelles
chartes graphiques d'établissement alignées sur le référentiel CEDEAO de M4
(`anglophone_waec`, `lusophone` — `arabophone_mixte` différé, pas encore de
charte dédiée ; `francophone_cfa` reste la charte « Innovation & Énergie »
existante) et un mode sombre réellement fonctionnel sur l'ensemble de
l'application (contrairement à `ecoshop_flutter`, qui définissait un thème
sombre jamais branché — `themeMode: ThemeMode.light` figé en dur, cf. rapport
d'écart du module). A entraîné, en problème hérité résolu au passage, la
migration des ~76 fichiers d'écrans qui lisaient des couleurs figées à la
compilation (`AppColors.xxx`) vers un système de palette réactif au thème
(`AppPalette`, `ThemeExtension`).

**M15ter — Export PDF (bulletins & reçus)** (livré, cf.
[`docs/contrats/M15ter_export_pdf.md`](./docs/contrats/M15ter_export_pdf.md)) :
inséré juste après M15bis, avant M16. Réponse au point d'écart §0.2 de
`docs/AUDIT_ECOSHOP_FLUTTER.md` : `ecoshop_flutter` générait un bulletin et
un reçu PDF (mise en page codée en dur) que la cible ne savait pas du tout
produire. Le bulletin (M6) est désormais exportable, prévisualisable,
imprimable et partageable, aligné sur les 3 chartes graphiques de M15bis
(toujours en variante claire pour le document imprimé). Les attestations
restent hors périmètre (confirmées absentes des deux côtés par l'audit, pas
une régression). **Le volet « reçu » a été retiré puis reconstruit** : la
première version s'appuyait sur `EcritureComptable` (écriture comptable
générale M14), sans aucun lien structurel avec un élève, une inscription ou
un solde dû — un document ayant l'apparence d'un reçu de scolarité sans
garantie qu'il en soit un. Retiré avant tout push (voir
`docs/contrats/M15ter_export_pdf.md` §7), puis reconstruit après M15quater
sur l'entité d'encaissement dédiée.

**M15quater — Inscription, réinscription & encaissement de scolarité**
(livré, cf.
[`docs/contrats/M15quater_inscription_encaissement.md`](./docs/contrats/M15quater_inscription_encaissement.md)) :
regroupe les écarts liés à l'administration scolaire et aux finances élève
déjà signalés par l'audit (§4-5 ci-dessus et
`docs/AUDIT_ECOSHOP_FLUTTER.md` §3-4) — création d'inscription, réinscription
annuelle, statut boursier, champs administratifs de la fiche élève,
paramètres établissement (tarifs/paliers), détection de double inscription,
et une **entité d'encaissement de scolarité dédiée** (liant explicitement
`fiche_eleve_id`/`inscription_id`, montant dû, montant payé, solde calculé
serveur) — préalable qui a permis la reconstruction du reçu PDF retiré de
M15ter. A été traité devant les ~8 autres écarts de l'audit, encore en
attente d'arbitrage.

**Patch de sécurité M9 — messagerie de groupe scolaire** (résolu, cf.
`docs/AUDIT_ECOSHOP_FLUTTER.md` §0.1 et
`docs/contrats/M09_communication_notifications.md` §6) : traité en urgence,
hors séquencement normal. Schéma RLS complet créé pour les groupes de classe
supervisés (7 règles absolues de protection des mineurs reprises
d'`ecoshop_flutter`, absentes côté serveur cible) ; fuite de données locales
entre comptes successifs sur un même appareil corrigée côté client
(purge à la déconnexion). Réserve assumée : les écrans du prototype local ne
sont pas encore raccordés à ce nouveau backend.

**Patch transversal — `INSERT ... RETURNING` sur policies auto-référentielles
et replis `est_direction()` manquants** (résolu le 2026-09-11, cf.
`docs/AUDIT_ECOSHOP_FLUTTER.md` addendum et
`docs/ETAT_PHASE_C.md` §4bis/§4ter) : traité en urgence, même priorité que le
patch de sécurité M9 ci-dessus — bloquait M16. Origine : le déblocage de
l'outillage Docker/Podman local (§4bis de `docs/ETAT_PHASE_C.md`) a permis de
trouver, sur M15quater, deux défauts jamais détectés (ni en local ni en CI, ce
module n'avait jusque-là jamais tourné nulle part) — une policy UPDATE
(`inscriptions`) sans repli `est_direction()`, et une policy SELECT
(`encaissements_scolarite`) auto-référentielle qui cassait `INSERT ...
RETURNING` pour tout le monde, y compris le vrai chemin de code de l'app.
Recherche systémique du même symptôme sur les autres tables suivant la même
forme (`policy SELECT` basée sur une fonction `xxx_visible(id)`
auto-référentielle) : **chaque table vérifiée empiriquement avant correction,
pas supposée identique par ressemblance de code** — la ressemblance s'est
révélée trompeuse (`sanctions` et `contrats` ont une forme quasi identique à
`encaissements_scolarite`/`notifications` mais ne présentaient PAS le défaut
RETURNING). Résultat, cinq tables corrigées :

- `notifications` (M9), `evaluations` (M6), `groupes_discussion` (M9-patch,
  pas encore exposé côté Flutter mais corrigé pour ne pas laisser la dette
  s'accumuler) : policy SELECT auto-référentielle cassant `INSERT ...
  RETURNING` — remplacée par une forme inline.
- `sanctions` (M7), `relations_parent_eleve` (M5) : policy d'écriture sans
  repli `est_direction()` (même défaut que sur `inscriptions`) — repli
  ajouté.
- `contrats` (M8) : vérifié, aucun défaut des deux types — laissé tel quel.

Chaque correction accompagnée d'un test pgTAP de non-régression explicite
(`INSERT ... RETURNING` réel, ou compte direction sans poste RH). Suite
complète (38 fichiers, 211 assertions) reconfirmée verte après coup.

**M16 — IA à rôles** (ouvert le 2026-09-11, cf.
`docs/AUDIT_ECOSHOP_FLUTTER.md` §0.5) : ordre de construction établi à partir
d'un état des lieux `ecoshop_flutter` des 5 rôles IA (pas l'ordre du cahier) —
score de risque par élève → bannière dashboard directeur → Edge Functions
IA/Tuteur IA/Directeur-Adviser → Parent IA → Scan d'exercice.

*Sous-livrable 1/7 — score de risque par élève* (clos le 2026-09-11, cf.
`supabase/migrations/20260906001504_m16_materialisation_risque_reussite.sql`,
`tests/rls/39_m16_risque_reussite.sql`) : **ce n'est pas l'ajout d'un score
qui n'existait pas** — `calculer_score_decrochage` (M7, 50 % absences non
justifiées + 20 % retards non justifiés + 30 % moyenne) et le type d'agrégat
`statistiques_agregats.risque_reussite` (M6) existaient déjà, antérieurs à
M16, mais n'étaient jamais matérialisés ni consommés par aucun écran ni
aucune fonction IA. Ce sous-livrable **persiste et expose un score par
élève qui existait déjà côté backend** : `materialiser_risque_reussite`
(service_role, même pattern que `generer_alertes_decrochage`) écrit le
résultat de `calculer_score_decrochage` dans `statistiques_agregats` (une
ligne par fiche/année, upsert versionné) ; `risque_reussite_actuel` l'expose
en relecture (SECURITY DEFINER — visibilité personnel/`fiche_visible`
revérifiée explicitement dans la fonction, la RLS de la table ne s'appliquant
pas à l'intérieur d'une fonction SECURITY DEFINER). Écart source documenté
et **assumé, pas importé** : `ecoshop_flutter` calcule un score différent
(70 % tendance des moyennes sur ~3 mois + 30 % présence, `NotesService.
recalculerRisqueEchec`) — décision : ne pas remplacer la formule
`calculer_score_decrochage` déjà testée en production M7, pour ne pas
introduire un second score divergent sur le même élève ni changer le
comportement déjà éprouvé de `alertes_decrochage`. Poids/seuil de M7
inchangés. Suite complète reconfirmée verte (39 fichiers, 222 assertions).

*Sous-livrable 2/7 — bannière dashboard directeur* (clos le 2026-09-11, cf.
`supabase/migrations/20260906001505_m16_banniere_eleves_a_risque.sql`,
`tests/rls/40_m16_banniere_eleves_a_risque.sql`) : ajoute un 7e indicateur
(`eleves_a_risque`) au mécanisme de consolidation déjà existant
(`consolider_indicateurs_etablissement`, M10) plutôt qu'un second
mécanisme parallèle — rafraîchit `statistiques_agregats.risque_reussite`
(sous-livrable 1/7) puis compte au seuil 0.6 (identique à
`generer_alertes_decrochage`, même population « à risque »). Côté client,
extrait de la grille générique de KPI et affiché en bannière IA dédiée
(`_BanniereRisque`, `ecran_tableau_bord_rapports.dart`) — pas un chiffre
parmi d'autres, conforme au cahier. Écart source documenté et non porté :
le sous-compte « dontDonneeFiable » d'`ecoshop_flutter` (fiabilité liée à
Parent IA/mesure device) n'a pas d'équivalent, `calculer_score_decrochage`
ne portant aucun indicateur de fiabilité — absence assumée, pas oubliée.
Suite pgTAP reconfirmée verte (40 fichiers, 227 assertions) ; côté Flutter,
`flutter analyze` propre et test de domaine ajouté
(`test/features/rapports/domain_json_test.dart`) — **le rendu visuel de la
bannière n'a pas été vérifié dans un run applicatif réel** (nécessiterait
une session direction connectée avec données seedées), à garder en tête si
un écart d'affichage apparaît en usage réel.

*Sous-livrable 3/7 — Edge Functions IA + Tuteur IA/Directeur-Adviser*
(clos le 2026-09-11, cf. `supabase/migrations/20260906001506_m16_edge_
functions_ia_infra.sql`, `supabase/functions/envoyer_message_ia/`,
`supabase/functions/demarrer_analyse_risque_echec/`, `tests/rls/
41_m16_edge_functions_ia.sql`) : porte l'architecture à 3 couches de
`CHAT_IA_GROUNDING.md` (déclenchement structuré → réponse groundée,
chiffres réels injectés sans outil → détail nominatif optionnel via
tool_use, pseudonymisation stricte). Décisions de cadrage actées et
tenues :

- **Correctif de sécurité construit dès la conception, pas après coup**
  (contrairement à la source, qui l'a trouvé et corrigé APRÈS le premier
  ship — voir §6 de `CHAT_IA_GROUNDING.md`) : la policy RLS d'écriture
  cliente sur `ai_conversations` force `grounding = false` et cibles
  nulles — seule la fonction `preparer_analyse_risque_echec` (SECURITY
  DEFINER, jamais appelable directement par le client) peut poser ces
  champs. Isolation stricte par auteur, même entre deux comptes direction
  du même établissement (aucun partage de conversation).
- **Aucune nouvelle formule de risque** : `preparer_analyse_risque_echec`
  rafraîchit et consomme `materialiser_risque_reussite`/
  `statistiques_agregats.risque_reussite` (sous-livrable 1/7), seuil 0.6
  inchangé.
- **Rôle IA réel recalculé côté serveur** (`determiner_role_ia`), jamais
  celui envoyé par le client — un compte sans rôle IA dans l'établissement
  (ex. parent) reste sans accès au chat, même comportement que
  `PROMPTS[role]` absent côté source.
- **Hors périmètre, assumé** : le second rapport groundé « échéances de
  paiement » de la source (généralisation ultérieure du même mécanisme,
  pas présente dans le périmètre M16 d'origine) — extension future de la
  même infrastructure si besoin, pas un écart oublié. Le ciblage
  `cible_type = 'eleve'` n'est pas non plus exposé (même limite déjà
  documentée côté source).
- **Prof-Assistant (enseignant) ajouté** comme 3ᵉ persona sur la même
  infrastructure, au-delà des 5 rôles listés au cahier M16 — coût marginal
  nul (un prompt système de plus), pour ne pas perdre une fonctionnalité
  source sans raison.
- **Testé jusqu'à la frontière de l'appel Anthropic avec une réponse HTTP
  simulée**, sans clé API réelle (câblage du secret en production différé,
  étape de déploiement séparée) — le CLI Deno autonome restant indisponible
  sur ce poste (même blocage réseau que Docker Desktop, §0.4/§0.6 de
  `docs/AUDIT_ECOSHOP_FLUTTER.md`), la vérification a été faite via
  `supabase functions serve` (fonctionne sans binaire Deno séparé) + un
  serveur Node jetable simulant l'API Anthropic + un JWT signé à la main —
  un aller-retour RÉEL (vrai HTTP, vraie auth, vraie RLS, vrai Postgres) a
  confirmé le flux complet (déclenchement, réponse groundée avec les
  vrais chiffres du fixture, tool-use, pseudonymisation) et l'absence de
  toute fuite nominative (nom/matricule réels) dans ce qui est effectivement
  envoyé côté simulation Anthropic — vérifié par recherche explicite dans
  les logs de la simulation, pas seulement par lecture de code.
- **Non construit dans cette passe initiale** : les écrans Flutter du chat
  (équivalent `AiChatScreen`/`ai_service.dart`) — le cadrage validé portait
  sur l'architecture serveur, pas explicitement sur l'IHM cliente. Complété
  juste après, voir ci-dessous.

Suite pgTAP reconfirmée verte (41 fichiers, 257 assertions).

*Complément sous-livrable 3/7 — écrans Flutter du chat* (même jour) :
`lib/features/chat_ia/` (domaine `MessageChatIa`/`DetailElevePseudonymise`/
`PersonaIa`, port `ChatIaRepository` + implémentation Supabase,
`EcranChatIa`), branché dans `_VueProfil` de `coquille_app.dart` pour les 3
rôles couverts (élève/enseignant/direction).

- **Un seul écran pour les 3 personas** — le flux et les garanties de
  sécurité sont identiques, seul `PersonaIa.libelle` change l'affichage ;
  le rôle réel reste re-dérivé côté serveur à chaque appel, jamais choisi ni
  transmis par cet écran.
- **Couleurs/texte exclusivement via `context.palette`/`Theme.of(context)`**
  (thème M15bis) — aucune constante `AppColors` codée en dur, cohérent avec
  la migration déjà actée dans ce thème (`app_palette.dart`) qui a
  entièrement supprimé cette ancienne classe.
- **Flux à 3 couches côté UI** : le bouton structuré (icône « analyser »,
  direction uniquement) ouvre un dialogue de ciblage
  (établissement/classe) puis appelle `demarrer_analyse_risque_echec` —
  jamais un texte libre ; la réponse groundée s'affiche normalement ; une
  puce d'action « Qui sont-ils ? », visible seulement une fois la
  conversation groundée, envoie ensuite un message ordinaire à
  `envoyer_message_ia` — c'est le serveur (rôle + `grounding` relus en base)
  qui décide d'exposer l'outil, jamais l'écran.
- **Mapping pseudonyme → identité affiché uniquement côté client**, replié
  par défaut, jamais réinjecté dans une requête à l'IA — reçu une fois en
  retour de `envoyer_message_ia`, gardé en mémoire locale de l'écran
  seulement (pas persisté dans `ai_messages`, dont le contenu ne contient
  que le texte, lui-même toujours en pseudonymes).
- **Volontairement sans décorateur de cache/file hors-ligne** (contrairement
  à `RapportsRepository`) : un chat IA suppose une connexion active, il n'y
  a rien de sensé à mettre en file d'attente hors-ligne pour ce port.
- **Portée limitée assumée, tenue** : pas de liste de conversations PASSÉES
  à choisir parmi plusieurs — la source elle-même n'en a pas non plus (son
  propre commentaire de code le dit explicitement : *« aucune "liste de mes
  conversations" n'existe sur ce projet »*), donc rien à corriger sur ce
  point précis.
- **Vérifié** : `flutter analyze` propre (0 erreur/avertissement, seulement
  des notes de style déjà présentes ailleurs dans le code base) ; suite
  `flutter test` complète verte (272 tests, dont 9 nouveaux — 7 tests de
  domaine + 2 tests de widget qui rejouent réellement le tap utilisateur :
  envoi libre côté élève, puis côté direction le déclenchement structuré →
  réponse groundée → tap sur « Qui sont-ils ? » → révélation du détail
  pseudonymisé — avec un faux port `ChatIaRepository`, la couche SQL/Edge
  Functions elle-même ayant déjà été vérifiée bout-en-bout en local dans la
  passe précédente).

*Complément 3/7 — continuité de conversation, TROUVÉ ET CORRIGÉ* (même jour,
suite à une vérification demandée explicitement sur ce point précis) :
en confirmant si la source avait un cache hors-ligne et/ou une liste
multi-conversations pour `AiChatScreen`, la lecture directe du code
(`ai_service.dart`) a révélé un écart RÉEL et plus significatif que « pas de
liste » : la source rouvre **toujours la même conversation**
(`conversationId = 'default'`, fixe par rôle) — l'historique complet
réapparaît donc à chaque ouverture d'écran, même après redémarrage de l'app
(et brièvement hors ligne, via la persistance automatique du SDK Firestore,
un comportement par défaut de ce SDK plutôt qu'une décision d'architecture
dédiée — Postgres/Supabase n'a pas d'équivalent). L'implémentation initiale
de `EcranChatIa`, elle, créait une **nouvelle conversation vide à chaque
ouverture** et ne rechargeait jamais l'historique — pas juste « pas de
liste », mais « pas de continuité » du tout. Corrigé plutôt que laissé en
l'état :

- `obtenir_conversation_libre(etablissement_id)` (migration `20260906
  001507`, `SECURITY DEFINER`) : renvoie la conversation `'libre'` stable de
  l'appelant pour cet établissement, la crée si elle n'existe pas encore.
  Index unique partiel (`... where type = 'libre'`) empêchant structurellement
  toute duplication — y compris sous course concurrente (`unique_violation`
  rattrapée par une relecture). Les conversations `'risque_echec'` restent
  volontairement hors de cet index : chaque déclenchement structuré reste
  une nouvelle ligne, comportement déjà voulu et documenté par la source
  elle-même pour celles-ci.
- `envoyer_message_ia` appelle désormais cette fonction au lieu d'un INSERT
  direct quand `conversationId` est absent.
- `EcranChatIa` recharge la conversation + son historique COMPLET (jamais
  résumé) dès `initState`, avant tout envoi — un spinner s'affiche pendant
  ce chargement.
- **Vérifié** : `Files=42, Tests=265, PASS` côté pgTAP (nouveau fichier `tests/
  rls/42_m16_continuite_conversation_libre.sql`, 8 assertions — idempotence
  sur 2 appels successifs, isolation stricte entre deux élèves, non-régression
  des conversations `risque_echec`, échec sans authentification) ; `flutter
  analyze` propre ; suite `flutter test` verte, 273 tests (+1, un test de
  widget qui pré-remplit un historique existant et vérifie qu'il s'affiche
  sans qu'aucun envoi n'ait eu lieu dans le test).

*Sous-livrable 4/7 — Parent IA (déclaration manuelle)* (clos le 2026-09-12,
cf. `supabase/migrations/20260906001508_m16_parent_ia.sql`, `supabase/
functions/analyser_usage_parent_ia/`, `tests/rls/43_m16_parent_ia.sql`) —
état des lieux `ecoshop_flutter` (`PARENT_IA.md`, cahier §15.3) fait
d'abord, comme pour chaque sous-livrable :

- **Principe repris à l'identique** : autolimitation numérique activée par
  l'ÉLÈVE lui-même (jamais un parent, jamais l'établissement), verrou
  d'engagement de 30 jours non contournable, parent en lecture seule.
- **Score de risque RÉUTILISÉ** (`risque_reussite_actuel`, sous-livrable
  1/7, matérialisation rafraîchie avant lecture comme en 3/7) — la source
  lit sa propre formule (`NotesService.recalculerRisqueEchec`, 70% évolution
  des moyennes + 30% présence), distincte de `calculer_score_decrochage` :
  pas importée, la formule EcoShop déjà matérialisée est exposée telle
  quelle, repli neutre 50/100 identique en l'absence de données.
- **Correctif de sécurité construit dès la conception** (comme en 3/7,
  au lieu de le découvrir après coup comme la source l'a fait) : AUCUNE
  policy d'écriture cliente sur `parent_ia_config`/`parent_ia_historique` —
  seules 3 fonctions `SECURITY DEFINER` (`activer_parent_ia`,
  `desactiver_parent_ia`, `enregistrer_restriction_parent_ia`) peuvent
  écrire, verrou de 30 jours calculé et posé UNIQUEMENT côté serveur.
- **Notifications réutilisées** : écrit dans la table `notifications`
  existante (M9, `type = 'parent_ia_restriction'`), aucun mécanisme
  parallèle inventé pour ce module.
- **Visibilité élève + parent confirmé UNIQUEMENT, jamais le personnel** —
  divergence délibérée de `fiche_visible()` (qui inclut le personnel),
  reprise à l'identique de la source : le bien-être numérique d'un mineur
  reste une donnée plus sensible que ses notes/absences, exclue du
  personnel de l'établissement même pour la direction.
- **Client n'appelle jamais Anthropic directement** : nouvelle Edge
  Function `analyser_usage_parent_ia`, prompt technique interne porté mot
  pour mot (`PARENT_IA_ANALYSIS_PROMPT` → `PROMPT_ANALYSE_USAGE_PARENT_IA`),
  distinct des 3 personas officiels, jamais exposé en conversation.
- **Périmètre confirmé pour cette passe** : déclaration manuelle
  uniquement (formulaire app + minutes estimées). **Écart documenté,
  reporté après discussion explicite** : mesure automatique Android
  (`usage_stats`/`UsageStatsManager`, permission système
  `PACKAGE_USAGE_STATS`) — non triviale (nécessite un plugin natif Android
  + un appareil/émulateur réel avec la permission accordée pour être
  vérifiée empiriquement, ce que l'outillage local actuel ne permet pas) ;
  la déclaration manuelle construite ici couvre déjà exactement le chemin
  de repli qu'utilisait la source pour iOS et pour Android sans permission
  — jamais un mur « indisponible ».
- **Vérifications de sécurité supplémentaires demandées explicitement,
  faites AVANT clôture** (même discipline qu'en 1/7 et 3/7) :
  - *Abus inter-comptes des 3 fonctions SECURITY DEFINER* — testé par
    pgTAP (`tests/rls/43_m16_parent_ia.sql`, 22 assertions) : un autre
    élève, la direction de l'établissement, et même le PARENT CONFIRMÉ (et
    autorisé) de l'élève concerné se voient tous refuser
    `activer_parent_ia`/`desactiver_parent_ia`/
    `enregistrer_restriction_parent_ia` sur une fiche qui n'est pas la
    leur — seul le `profile_id` de la fiche compte, jamais une relation
    parentale même confirmée. Un tiers non lié (`parent_b`) ne lit NI la
    configuration NI l'historique, avant et après l'écriture d'une vraie
    restriction. Un bug réel a été trouvé et corrigé pendant cette
    vérification : les triggers `_verifie_tenant` de ce module
    n'étaient pas `SECURITY DEFINER`, donc leur lecture de
    `fiches_eleves` (table étroitement protégée par RLS) s'exécutait sous
    les droits de l'appelant — invisible pour un tiers ciblant la fiche
    d'un autre élève, ce qui masquait le vrai rejet RLS (42501) derrière un
    faux `FICHE_AUTRE_ETABLISSEMENT` (23514). Corrigé en rendant ces deux
    triggers `SECURITY DEFINER` (leur rôle n'est qu'une vérification de
    cohérence de données déjà garantie par la contrainte de clé étrangère,
    jamais une décision d'autorisation — aucun risque à le faire).
  - *Absence de fuite d'identité vers Anthropic* — vérifiée par un vrai
    appel HTTP bout-en-bout (`supabase functions serve` + conteneur stub
    Anthropic + JWT signé à la main, même méthodologie que 3/7) puis par
    **recherche explicite dans les logs du stub** (`grep`, pas seulement
    lecture de code) du nom, prénom, matricule et des deux UUID de
    l'élève fixture : zéro occurrence des cinq ; confirmation positive que
    les chiffres agrégés attendus (« 180 minutes », « 50/100 ») sont bien
    ce qui a été transmis. La ligne `parent_ia_historique` et la
    notification créées par cet appel réel ont aussi été vérifiées en
    base.
- **Vérifié** : `Files=43, Tests=287, PASS` côté pgTAP ; `flutter analyze`
  propre (0 erreur/avertissement) ; suite `flutter test` verte, 285 tests
  (+12 nouveaux — domaine + widgets couvrant consentement obligatoire,
  verrou affiché et non contournable même par le propriétaire légitime,
  déclaration, historique partagé élève/parent). Un vrai bug d'overflow
  d'affichage (`RenderFlex`) et un `ListTile` peignant sur un fond opaque
  sans `Material` propre ont aussi été trouvés et corrigés par ces tests de
  widget, pas seulement par relecture visuelle.

*Sous-livrable 5/7 — Scan et résolution d'exercice* (clos le 2026-09-12, cf.
`supabase/migrations/20260906001509_m16_scan_exercice.sql`, `supabase/
functions/demarrer_scan_exercice/`, `tests/rls/44_m16_scan_exercice.sql`) —
fonctionnalité ENTIÈREMENT NOUVELLE (absorbée du module M14 d'EduRéussite,
cahier §21.5), sans équivalent côté source `ecoshop_flutter` : aucun état des
lieux à faire, à la différence des sous-livrables précédents.

- **Flux respecté à la lettre** : photo → reconnaissance de texte →
  identification matière/chapitre → analyse du problème → proposition de
  méthode → guidage progressif → correction finale détaillée.
- **Protection mineur strictement supérieure à ce qu'imposait le cahier
  littéral, actée avec l'utilisateur avant codage** : reconnaissance de texte
  100% EMBARQUÉE sur l'appareil (Google ML Kit, hors ligne par construction).
  Conséquence structurante : LA PHOTO NE QUITTE JAMAIS L'APPAREIL — seul le
  texte déjà reconnu (jamais une image) est envoyé au serveur puis à
  Anthropic ; aucun stockage Supabase Storage, donc aucune fuite possible de
  la photo elle-même (même philosophie de minimisation des données que
  Parent IA, 4/7, chiffres agrégés uniquement).
- **Chapitre/matière en texte libre, jamais persistés dans un référentiel** :
  aucune table `chapitres_matieres` n'existe dans le M4 (référentiel
  pédagogique) ; en créer une sans contenu curaté derrière serait une fausse
  promesse de structure (décision explicite de l'utilisateur). Dette
  explicite, à reprendre quand le futur module référentiel pédagogique/CMS
  posera une vraie notion de chapitre.
- **Garde-fou réponse finale : aucun mécanisme structurel nouveau** — même
  discipline que le Tuteur-IA conversationnel (3/7) : l'interdiction de
  donner la solution brute avant d'être passé par méthode+guidage est portée
  par le prompt système (`PROMPT_SCAN_EXERCICE`), appliquée par le modèle à
  partir de l'historique déjà reçu à chaque tour — aucun compteur serveur
  ajouté.
- **Consentement capturé À CHAQUE scan** (donnée scolaire d'un mineur) —
  volontairement différent du verrou persistant de Parent IA : pas de notion
  d'engagement ici, un consentement par exercice photographié, avec
  contrainte SQL (`scan_exercices_consentement_requis`) en plus de la
  vérification côté fonction.
- **Réutilise intégralement l'infrastructure IA du sous-livrable 3/7**
  (`ai_conversations`/`ai_messages`, `determiner_role_ia`, RLS, `envoyer_
  message_ia`) — un nouveau type de conversation (`scan_exercice`) est
  ajouté, jamais une table de conversation parallèle ; les tours de guidage
  suivant le premier passent par `envoyer_message_ia` (persona dédié
  `PROMPT_SCAN_EXERCICE`), jamais un second appel à `demarrer_scan_exercice`.
- **Garde-fou tenant SECURITY DEFINER dès la conception** (leçon du test 43,
  4/7) : le trigger `scan_exercices_verifie_tenant` est `SECURITY DEFINER`
  dès sa première version, jamais après coup.
- **Écran Flutter construit** (`features/scan_exercice/`) : capture photo
  (`image_picker`, caméra ou galerie) → OCR embarqué (`google_mlkit_text_
  recognition`) → texte reconnu affiché et modifiable avant envoi (l'OCR
  n'est jamais parfait) → case de consentement obligatoire → écran de
  guidage réutilisant les mêmes widgets que le chat IA (`BulleMessageIa`),
  la suite des tours passant par `ChatIaRepository` (aucun port dupliqué).
  Point d'entrée ajouté au profil élève (`coquille_app.dart`), à côté de
  Tuteur-IA et Parent IA. Permissions caméra ajoutées (`AndroidManifest.xml`,
  `Info.plist`).
- **Hors ligne** : la reconnaissance de texte elle-même fonctionne déjà hors
  ligne (ML Kit) ; un appel hors ligne à `demarrer_scan_exercice` est mis en
  file par le même mécanisme de synchronisation différée que le reste de la
  plateforme (`sync_queue`/`SyncEngine`) — rien à modéliser côté SQL, le
  rejeu appelle exactement la même Edge Function qu'un appel en ligne normal.
- **Facturation** : accès ouvert pour cette passe, comme 3/7 — aucune
  fondation d'abonné/quota posée ici (chantier transversal distinct).
- **Vérifications de sécurité supplémentaires demandées explicitement,
  faites AVANT clôture** (même discipline qu'en 1/7 et 4/7 — la même
  catégorie de test avait trouvé un vrai bug dans ces deux sous-livrables) :
  - *Consentement* : confirmé porté côté serveur, pas seulement une case à
    cocher côté client — `preparer_scan_exercice` rejette
    `CONSENTEMENT_REQUIS` (22023) si `p_consentement is not true`, la table
    porte en plus la contrainte `scan_exercices_consentement_requis check
    (consentement)`, et l'Edge Function coerce strictement
    (`corps.consentement === true`) avant transmission. Aucun changement
    nécessaire.
  - *Isolation inter-établissement* : un deuxième établissement totalement
    distinct (`eleve3`, aucun lien avec le premier) a été ajouté au test 44
    (même méthode que le test 38, M15quater) — usurpation de l'établissement
    de la victime avec sa propre fiche, rôle élève valide chez lui mais
    ciblant la fiche de la victime, et `renseigner_identification_scan_
    exercice` sur le scan d'un élève d'un autre établissement : les 3 sont
    rejetées (42501) sans modification de code, `determiner_role_ia` et la
    vérification de propriété tenaient déjà la charge.
- **Point ouvert, assumé, transféré à un jalon distinct — PAS résolu, PAS
  non applicable** : le garde-fou pédagogique (jamais la solution finale
  sans guidage progressif, sauf demande explicite ET répétée) n'a été
  vérifié QUE par relecture du prompt système (`PROMPT_SCAN_EXERCICE`),
  jamais en conditions réelles. Tous les appels IA de ce sous-livrable, comme
  en 3/7 et 4/7, passent par le stub Anthropic local
  (`ANTHROPIC_URL_OVERRIDE`, `supabase/functions/.env`) — un stub ne simule
  que la plomberie (payload transmis, absence de fuite), jamais le
  raisonnement réel du modèle sur plusieurs tours. Vérifier ce comportement
  précis exige un vrai appel à l'API Anthropic (vraie clé, coût réel) :
  décision explicite de ne pas exposer/chercher de clé réelle pour cette
  passe. **Reporté à un jalon de QA pré-lancement distinct, avec une vraie
  clé API, avant toute ouverture réelle du Scan-Exercice aux élèves** — à
  reprendre explicitement dans le rapport d'écart global de clôture de M16.
- **Vérifié** : migration rejouée par `supabase db reset` (podman/WSL2) sans
  erreur ; pgTAP `Files=44, Tests=313, PASS` (suite complète rejouée, aucune
  régression sur les 43 fichiers précédents) ; Edge Function testée en vrai
  via `curl` contre le runtime local (`parametres_requis` sur corps vide,
  `authentification_requise` sur JWT anonyme — confirme le chargement et la
  validation, pas seulement une relecture de code) ; `flutter analyze`
  propre (0 erreur/avertissement) ; suite `flutter test` verte, 287 tests
  (+2 nouveaux — consentement bloquant tant que texte ou case manquent,
  démarrage du scan puis continuité du guidage via `ChatIaRepository`).

*Sous-livrable 6/7 — Rapport d'écart global de clôture M16* (clos le
2026-09-12) : n'ajoute aucune fonctionnalité IA nouvelle — clôt l'arbitrage
transversal §4.2.5 resté ouvert pendant la construction des 5 sous-livrables
précédents, consolide le jalon de QA pré-lancement, et récapitule le module.

**1. Arbitrage des écarts `AUDIT_ECOSHOP_FLUTTER.md` §11-§12 — désormais
clos.** Sur les ~9 écarts non pleinement résolus identifiés à l'ouverture de
M16 (2026-09-11), vérification croisée avec le carnet de gouvernance du
porteur de projet le 2026-09-12 :

- **5 étaient déjà arbitrés ailleurs**, simplement jamais répercutés dans le
  dépôt — corrigé dans `AUDIT_ECOSHOP_FLUTTER.md` §11-§12 : parcours
  d'entrée rôles à privilège → différé, cible M2/M3 ; plafond de comptes
  parents → différé avec l'anti-brute-force existant, cible un futur module
  d'accueil ; paie RH → différé, cible M8bis ; séances ponctuelles/
  annulation de cours → différé, cible M11 ; gestion des stocks/
  anti-survente → différé, cible M15.
- **2 ont été corrigés dans le cadre de ce sous-livrable**, après un
  paragraphe de contexte par écart (nature du manque, ampleur, risque) pour
  éviter un arbitrage à l'aveugle :
  - **Déclaration/changement de statut d'une sanction disciplinaire (M7)**
    — manque purement UI (`proposerSanction()`/`changerStatutSanction()` et
    la policy RLS existaient déjà, testés) : formulaire de déclaration +
    menu de changement de statut ajoutés à `EcranSanctions`, même règle de
    visibilité que le reste de l'écran (`estDirection`). 313 assertions
    pgTAP inchangées (aucun backend touché) ; 7 tests Flutter ajoutés.
  - **Écran prototype de messagerie de groupe non raccordé (M9)** — vérifié
    directement reachable par tout rôle y compris élève (aucune garde),
    contrairement à la propre recommandation de l'audit (§0.1). Le
    prototype étant 100 % local et non synchronisé (aucune fuite réseau
    réelle possible, la fuite inter-comptes sur appareil partagé étant déjà
    corrigée par `session_logout.dart`), l'entrée « Messagerie » a été
    retirée du menu Profil pour tous les rôles — le raccordement réel au
    backend sécurisé (`groupes_discussion`/`messages_groupe`) reste un
    chantier séparé, différé, cible à définir.
- **2 différés, avec une cible distincte chacun** :
  - **Génération de bulletins pour une classe entière (M6)** — différé vers
    D5 (Phase D, moteur d'impression multi-formats). Ampleur bornée : les
    briques par élève existent déjà et sont testées (`construireBulletinPdf`,
    `EcranBulletins`), il ne manque qu'un point d'entrée classe + une boucle
    d'assemblage, aucun nouveau backend. Aucune échéance de fin de trimestre
    imminente signalée par le porteur de projet à ce jour — priorité
    inchangée, à réévaluer si une échéance réelle apparaît.
  - **Tableau de bord directeur consolidé Finances+Scolarité (M10)** —
    différé, **nouveau backlog distinct** (ni D5, ni le futur audit réseau
    →M19 : celui-ci consolide deux domaines pour UN établissement, M19
    agrège plusieurs établissements pour un rôle réseau — aucun
    recouvrement). Le plus gros des 4 : nécessite d'exposer les KPI
    financiers (M14) à côté des KPI scolarité existants ET un concept
    réellement nouveau (seuils d'alerte configurables par établissement,
    inexistant aujourd'hui) — hors périmètre d'un « petit complément ».

**2. Jalon de QA pré-lancement consolidé — point ouvert, transversal aux
trois sous-livrables conversationnels.** Constat fait à la clôture de 5/7,
qui s'applique en réalité identiquement à 3/7 et 4/7 : tout comportement qui
dépend du raisonnement réel du modèle Anthropic (garde-fou pédagogique du
Tuteur-IA/Scan-Exercice — jamais la solution/réponse finale sans guidage
progressif sauf demande explicite et répétée ; jugement de l'IA sur le
grounding/l'usage excessif en Parent IA) n'a été vérifié QUE par relecture
des prompts système, jamais en conditions réelles — les trois sous-livrables
utilisent exclusivement le stub Anthropic local
(`ANTHROPIC_URL_OVERRIDE`/`supabase/functions/.env`) pour tous leurs tests,
y compris les vérifications bout-en-bout par appel HTTP réel. Décision
explicite (2026-09-12) : ne pas exposer/chercher de clé API réelle pendant
la construction. **Reporté formellement à un jalon de QA pré-lancement
unique, avec une vraie clé Anthropic, avant toute ouverture réelle de
Tuteur-IA/Directeur-Adviser (3/7), Parent IA (4/7) et Scan-Exercice (5/7)
à de vrais élèves/enseignants/directions** — ni résolu, ni non applicable,
condition de passage explicite avant mise en production de ces trois
sous-livrables.

**3. Récapitulatif des 5 sous-livrables clos (1/7 → 5/7)**, tous vérifiés
localement (podman/WSL2, `supabase db reset` + pgTAP) sans régression
cumulée : score de risque par élève (1/7, réutilise `calculer_score_
decrochage` de M7 sans nouvelle formule) → bannière dashboard directeur
(2/7, 7ᵉ indicateur sur `consolider_indicateurs_etablissement`) → Edge
Functions IA à 3 couches + Tuteur-IA/Directeur-Adviser (3/7, garde-fou
RLS conçu dès le départ, jamais découvert après coup) + son **complément**
écrans Flutter (`EcranChatIa`, un seul écran pour les 3 personas) et
correctif de continuité de conversation (`obtenir_conversation_libre`,
trouvé et corrigé le jour même) → Parent IA (4/7, déclaration manuelle,
verrou 30 jours non contournable, bug réel de trigger non `SECURITY
DEFINER` trouvé et corrigé par les vérifications demandées) → Scan et
résolution d'exercice (5/7, fonctionnalité entièrement nouvelle, photo
jamais transmise, isolation inter-établissement renforcée par un test
dédié). pgTAP : `Files=44, Tests=313, PASS` à la clôture de ce 6/7 (313
inclut les 26 assertions de 5/7 renforcé, inchangé par les corrections
Flutter #5/#7 de ce sous-livrable, aucun backend touché). `flutter test` :
294 tests PASS (+7 pour la correction #5).

**Commits** (locaux, non poussés sauf mention contraire) : `4882982`/
`bb15226`/`89c9d49` (5/7, **poussés sur `origin/main`**), `44efcdd`
(réconciliation gouvernance §11-§12), `78fc8d1` (correction #5, sanctions),
`5164ddb` (correction #7, masquage Messagerie).

La liste colonne par colonne des DTOs et RPCs de M4 → M15 est spécifiée dans
[`docs/contrats/`](./docs/contrats/README.md).

---

## 5. Cadrage officiel acté (réponses définitives)

1. **Backend** : intégralement **Supabase** (Postgres + RLS, Auth natif, Edge
   Functions, Realtime). `src/` (NestJS) = **GSG Platform Kernel externe**,
   contrat de référence pour la fédération GSG ID, non le backend applicatif.
2. **Monorepo** : `apps/client_flutter`, `supabase`, `docs` + `README.md` avec
   traçabilité vers `C:\Users\delam\ProjetsFlutter\ecoshop_flutter`.
3. **Identité** : source de vérité = **Supabase Auth natif** (E.164, OTP
   SMS/WhatsApp/E-mail) lié à `profiles` ; GSG ID = couche additive (Custom
   Access Token Hook + JWKS), sans migration de l'auth hors Supabase.
4. **Marketplace** : bascule **AssoShop mono-vendeur** (sous-compte par
   établissement, suppression du panier multi-vendeur) ; intégration des
   verticaux **EduRéussite** (référentiel 16 pays, moteur quiz/examens, profil
   de maîtrise, gamification).
5. **Paiement** : **Port Paiement agnostique** — adaptateur **CinetPay** +
   adaptateur **Mobile Money local** (Orange Money/MTN/Wave) en seconde
   implémentation, activable par pays ou préférence d'établissement/commerçant.
6. **Ordre de démarrage** : Phase A (M0-M3) → Phase B (M4-M12) → Phase C (M13-M20).

---

**Point de contrôle** : l'analyse globale révisée est validée par le porteur de
projet.

La **Phase A (M0 → M3)** est construite : socle Supabase/Flutter, schéma avancé
multi-tenant, authentification OTP et fédération GSG ID, socle applicatif
Flutter. Les défauts de sécurité du schéma cœur de M0 (escalade de privilège
sur `role_racine`, récursion RLS, hook JWT inopérant) ont été corrigés par la
migration `20260906000100_fix_core_security.sql`.

Le détail des livrables, l'état de vérification et les réserves ouvertes
figurent dans [`docs/ETAT_PHASE_A.md`](./docs/ETAT_PHASE_A.md).

**État de livraison au-delà de la Phase A** : les modules M4 → M15 sont
également livrés par migrations SQL (cf. §4.4), leurs contrats d'interface
(DTOs & RPCs) sont spécifiés dans [`docs/contrats/`](./docs/contrats/README.md),
et le socle M0 → M15 est validé de bout en bout en CI : migrations + seeds +
36 tests RLS passent sur la branche `main` (hook JWT, modèle de rôles,
multi-tenant, audit des RPC).

**Réserve** : les migrations n'ont pas été exécutées sur une instance Supabase
locale (outils backend absents du poste) ; la validation repose sur le
rejeu `supabase db reset` + tests pgTAP du workflow CI GitHub Actions.

**M15bis — Thèmes internationaux & Dark Mode** est livré (cf. §4.4 ci-dessus et
[`docs/contrats/M15bis_themes_dark_mode.md`](./docs/contrats/M15bis_themes_dark_mode.md)) :
233 tests passent, `flutter analyze` ne remonte aucun problème.

**M15ter — Export PDF (bulletins & reçus)** est livré (cf. §4.4 ci-dessus et
[`docs/contrats/M15ter_export_pdf.md`](./docs/contrats/M15ter_export_pdf.md)) :
261 tests passent, `flutter analyze` ne remonte aucun problème. Le volet
« reçu », retiré avant tout push (aucune garantie de lien avec un vrai
encaissement de scolarité, voir M15ter §7), a été **reconstruit** après
M15quater sur l'entité d'encaissement dédiée.

**M15quater — Inscription, réinscription & encaissement de scolarité** est
livré (cf. §4.4 ci-dessus et
[`docs/contrats/M15quater_inscription_encaissement.md`](./docs/contrats/M15quater_inscription_encaissement.md)) :
261 tests Flutter passent, `flutter analyze` propre ; 25 assertions pgTAP
écrites — voir `docs/AUDIT_ECOSHOP_FLUTTER.md` §0.4 pour la vérification
détaillée de l'isolation RLS, de l'annulation tracée, et le statut réel de
la tentative d'exécution locale (Docker/Podman).

**Patch de sécurité M9 — messagerie de groupe scolaire** est résolu (cf.
`docs/AUDIT_ECOSHOP_FLUTTER.md` §0.1) : schéma RLS complet + purge de la
fuite locale entre comptes à la déconnexion, 15 assertions pgTAP dédiées.

**M16 — IA à rôles** a été **ouvert le 2026-09-11** (cf. §4.4 ci-dessus,
`docs/AUDIT_ECOSHOP_FLUTTER.md` §0.5) sur un critère plus étroit que la règle
transversale §4.2.5 ne le prévoyait à la lettre : le déblocage Docker/Podman
et les deux patches RLS (M15quater, patch transversal) empiriquement vérifiés
— pas l'arbitrage complet du rapport d'écart rétroactif
[`docs/AUDIT_ECOSHOP_FLUTTER.md`](./docs/AUDIT_ECOSHOP_FLUTTER.md) (M0 → M15).
Les points les plus sensibles (protection des mineurs en M9, génération PDF
des bulletins/reçus, inscription/encaissement de scolarité) étaient déjà
traités à cette date ; ~9 autres écarts (§11 de l'audit) restaient non
arbitrés au moment de l'ouverture, et les 5 sous-livrables M16 1/7 → 5/7 ont
été construits pendant que cet arbitrage restait en suspens — écart de
processus par rapport à §4.2.5, constaté et documenté ici le 2026-09-12
(clôture du sous-livrable 5/7), pas retrouvé plus tôt car ce paragraphe
lui-même n'avait pas été mis à jour depuis l'audit initial.

**Mise à jour du 2026-09-12** (vérification croisée avec le carnet de
gouvernance du porteur de projet) : sur ces ~9 écarts, **5 avaient déjà été
arbitrés ailleurs** (carnet de gouvernance), simplement jamais répercutés
dans ce document ni dans `AUDIT_ECOSHOP_FLUTTER.md` §11-§12 — désormais fait,
tous différés avec une cible (parcours d'entrée → M2/M3 ; plafond de comptes
parents → futur module d'accueil ; paie RH → M8bis ; séances ponctuelles →
M11 ; stocks/anti-survente → M15). **Les 4 écarts restants ont été tranchés
dans le cadre de M16 sous-livrable 6/7** (rapport d'écart global de clôture,
détaillé ci-dessous) : 2 corrigés immédiatement (sanctions M7, écran
Messagerie masqué M9), 2 différés avec une cible propre (bulletins classe
entière M6 → D5, tableau de bord directeur consolidé M10 → nouveau backlog
distinct). **Plus aucun écart de `AUDIT_ECOSHOP_FLUTTER.md` §11 n'est sans
arbitrage** — la règle transversale §4.2.5 est désormais satisfaite. La
replanification des verticaux décalés déjà identifiée ailleurs dans ce
document : Port Paiement, moteur de questions/quiz, profil de maîtrise,
préparation aux examens — reste hors périmètre de M16, inchangée.
