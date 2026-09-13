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
| M16 | IA à rôles — **clos le 2026-09-12 (7/7 sous-livrables)** : score de risque par élève, bannière dashboard directeur, Edge Functions IA + Tuteur IA/Directeur-Adviser (+ complément continuité de conversation), Parent IA (déclaration manuelle), Scan et résolution d'exercice, rapport d'écart global de clôture (§11-§12 arbitré), clôture formelle | `20260906001504...` → `20260906001509_m16_scan_exercice.sql` (6 migrations) | *(à consolider — pas de contrat dédié écrit pour ce module)* | livré et vérifié (pgTAP `Files=44, Tests=313, PASS` ; `flutter test` 294/294 ; `flutter analyze` propre) ; 2 dettes transversales explicitement ouvertes, voir narratif ci-dessous (QA pré-lancement conditions réelles, facturation/quota IA) |

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

**Commits** : `4882982`/`bb15226`/`89c9d49` (5/7), `44efcdd` (réconciliation
gouvernance §11-§12), `78fc8d1` (correction #5, sanctions), `5164ddb`
(correction #7, masquage Messagerie) — **tous poussés sur `origin/main`**
(voir la clôture 7/7 ci-dessous).

*Sous-livrable 7/7 — Clôture formelle du module M16* (clos le 2026-09-12,
aucun nouveau code métier — vérification, documentation et arbitrage final
uniquement).

**a) Statut définitif du complément de continuité de conversation (3/7)**
— resté sans confirmation claire malgré deux relances antérieures : **fait
et vérifié**, aucun écart. La fonctionnalité (`obtenir_conversation_libre`,
migration `20260906001507`, index unique partiel `type='libre'`,
`EcranChatIa` qui recharge conversation + historique complet dès
`initState`) est en place depuis le commit `c4b0410`, **déjà mergé sur
`origin/main` avant l'ouverture de cette session**. Reconfirmée
empiriquement aujourd'hui, à neuf, plutôt que citée depuis l'ancien message
de commit :
- pgTAP `tests/rls/42_m16_continuite_conversation_libre.sql` rejoué seul :
  8/8 assertions vertes (idempotence sur 2 appels, isolation stricte
  eleve1/eleve2, non-régression des conversations `risque_echec`, échec
  sans authentification).
- Suite pgTAP complète rejouée : `Files=44, Tests=313, PASS`, aucune
  régression.
- `flutter analyze` : propre.
- `flutter test test/features/chat_ia/` rejoué seul : 10/10, dont
  explicitement *« Continuité (complément 3/7) : réouvrir l'écran recharge
  la conversation libre existante, jamais vide »*. Suite complète :
  294/294 PASS.

**b) Poussé vers `origin/main`** : `44efcdd`, `78fc8d1`, `5164ddb`,
`91c13fc` (tout ce qui restait local à l'ouverture de ce sous-livrable).

**c) Deux dettes transversales restent explicitement ouvertes** — la
clôture de M16 ne les résout pas, elle les rend visibles et leur donne un
jalon :
- **QA pré-lancement en conditions réelles** (comportement réel du modèle
  Anthropic — garde-fou pédagogique de 3/7/5/7, jugement d'usage de 4/7 —
  jamais vérifié que par relecture de prompt, stub local pour tous les
  tests des trois sous-livrables). Jalon : vraie clé API Anthropic, avant
  toute ouverture réelle de Tuteur-IA/Directeur-Adviser, Parent IA et
  Scan-Exercice à de vrais élèves/enseignants/direction.
- **Facturation/quota IA** (accès ouvert depuis 3/7, aucune fondation
  d'abonné/quota posée pour l'ensemble du module). **Aucun jalon assigné à
  ce jour** — contrairement aux écarts §11 différés (6/7), ce point n'a pas
  de cible de module connue ; à arbitrer explicitement par le porteur de
  projet (Phase D ? un futur module de facturation dédié ? autre ?) plutôt
  que d'en inventer une ici.

**d) Arbitrage `AUDIT_ECOSHOP_FLUTTER.md` §11-§12 confirmé clos** (voir
6/7 ci-dessus) — rien de nouveau à ce sujet, rappelé ici pour que cette
entrée de clôture soit auto-suffisante.

**M16 — IA à rôles est formellement clos le 2026-09-12** : 7/7
sous-livrables livrés et vérifiés localement sans régression cumulée
(pgTAP `Files=44, Tests=313, PASS` ; `flutter test` 294/294 PASS ;
`flutter analyze` propre), le rapport d'écart rétroactif §4.2.5 intégralement
arbitré, les deux dettes transversales ci-dessus explicitement tracées avec
leur jalon (ou l'absence assumée de jalon pour la seconde) plutôt que
silencieusement oubliées. La Phase D a été ouverte séparément et
explicitement par le porteur de projet le 2026-09-12 (voir D1 ci-dessous) —
jamais déduite de la clôture de M16.

---

## 4.5 Phase D — Expérience utilisateur & configuration (D1 → D6)

Ouverte le 2026-09-12, sur demande explicite et distincte du porteur de
projet (M16 est clos, ses dettes tracées). Modules distincts D1 → D6, même
discipline que M16 : 5 livrables habituels (code, tests, doc, dette
résolue, rapport d'écart vs `ecoshop_flutter`) + point de contrôle formel,
vérification empirique avant clôture, tout écart posé en question plutôt
que tranché seul.

*D1 — Navigation & en-tête dynamique* (clos le 2026-09-12) : TopBar enrichi,
fil d'Ariane dynamique, en-tête de page (titre + descriptif), sélecteur
grille/liste/cartes.

- **État des lieux `ecoshop_flutter`** : aucun équivalent. La coquille
  source (`lib/core/navigation/app_shell.dart`) n'a aucun AppBar au niveau
  shell (chaque écran gère le sien individuellement), aucun fil d'Ariane
  nulle part dans `lib/`, et le catalogue marketplace source
  (`catalogue_screen.dart`) affiche un `GridView` fixe sans aucune bascule
  de vue. **Écart posé en question avant codage** (aucun précédent à
  trancher seul) : 4 points de cadrage validés par le porteur de projet le
  2026-09-12 — profondeur du fil d'Ariane (2-3 niveaux réels, jamais sur les
  5 onglets racine, format « Onglet > Écran(— Entité) »), périmètre du
  `PageHeader` (5 onglets racine uniquement pour cette passe, pas les
  écrans poussés), premier terrain d'application du sélecteur de vue
  (catalogue marketplace), contenu du TopBar enrichi (notifications +
  avatar, pas de recherche).
- **`FilAriane`** (`core/widgets/fil_ariane.dart`, `PreferredSizeWidget`
  pour un usage direct en `AppBar(bottom: ...)`) — câblé sur UN écran cette
  passe : `EcranSanctions` (« Scolarité > Sanctions — Aissatou »). Écart
  factuel corrigé par rapport à l'exemple de cadrage donné (qui citait
  « Profil > Sanctions ») : vérifié dans le code que `EcranSanctions` n'est
  jamais atteint depuis l'onglet Profil, seulement via Scolarité → Fiche
  élève → Suivi vie scolaire → Sanctions — l'onglet réel du fil d'Ariane
  reflète ce chemin, pas l'exemple. Les autres écrans poussés l'adopteront
  au fil de l'eau, même logique que `PageHeader` ci-dessous — pas un
  balayage exhaustif dans cette passe.
- **`PageHeader`** (`core/widgets/page_header.dart`) — appliqué aux 5
  onglets racine via `_CorpsOnglet` (`coquille_app.dart`), jamais retouché
  dans `EcranScolarite`/`EcranMarketplace`/`_VueProfil` eux-mêmes. **Décision
  d'implémentation documentée** (au-delà du cadrage explicite, pour éviter
  une redondance visuelle) : le titre dynamique de l'onglet, auparavant
  affiché dans l'AppBar, en a été retiré (l'AppBar affiche désormais
  l'identité statique « EcoShop ») puisque `PageHeader` le porte maintenant
  — sinon le nom de l'onglet apparaissait deux fois à l'écran. **Empilement
  visuel corrigé** (relevé initialement pour `EcranMarketplace` et
  `EcranStructureEtablissement`, puis élargi lors de la vérification du
  porteur de projet à un troisième cas non documenté au premier passage,
  `EcranFicheEleve`) : `_CorpsOnglet` n'affiche `PageHeader` que si l'écran
  délégué n'a pas déjà son propre `Scaffold`/`AppBar`
  (`_delegueSonAppBar`) —
  - Boutique → toujours vrai (`EcranMarketplace`, AppBar « Marketplace »),
    quel que soit le rôle ;
  - Scolarité, rôle direction → vrai (`EcranStructureEtablissement`, AppBar
    « Structures & annuaire ») ;
  - Scolarité, rôles parent et élève → vrai (`EcranFicheEleve`, AppBar =
    nom de la fiche) — trouvé en vérifiant les trois branches de rôle de
    `EcranScolarite`, pas seulement celle de la direction ;
  - Scolarité, rôle enseignant → **faux, délibérément** : `_VueEnseignant`
    n'a aucun AppBar propre et dépend de `PageHeader` pour son titre ; le
    supprimer pour tout l'onglet Scolarité l'aurait laissé sans titre.
- **`SelecteurVue`/`ModeAffichage`** (`core/widgets/selecteur_vue.dart`,
  `SegmentedButton` à 3 segments liste/grille/cartes) — widget générique
  sans connaissance du contenu, conçu explicitement pour que D2 le
  réutilise tel quel. Premier terrain d'application : `EcranCatalogue`
  (marketplace), mode par défaut « cartes » pour préserver le rendu
  existant tant que personne ne bascule le sélecteur ; mode « liste »
  ajouté (lignes denses sans `Card`) et mode « grille » ajouté (nouveau,
  2 colonnes, 4 sur grand écran ≥ 720 px).
- **TopBar enrichi** (`coquille_app.dart`) — raccourci notifications
  (`IconButton` → `EcranNotifications`, système M9 existant, aucune
  nouvelle logique de comptage non lu ajoutée — un raccourci, pas un
  badge) et raccourci avatar/menu profil compact (`_RaccourciAvatar`,
  initiales dérivées de `Profil.nomAffiche`, menu « Mon profil »/« Se
  déconnecter » réutilisant `session_logout.dart` sans dupliquer sa
  logique). Pas de recherche, comme convenu.
- **Dette résolue** : aucune dette préexistante ciblée par ce sous-livrable
  (N/A) au sens du contrat initial — mais l'empilement visuel
  `PageHeader`/AppBar interne, nouvellement identifié par cette même
  passe, a été corrigé avant clôture (voir `_delegueSonAppBar` ci-dessus)
  plutôt que différé, sur demande explicite du porteur de projet.
- **Vérifié** : `flutter analyze` propre (0 erreur/avertissement) ; suite
  `flutter test` verte, 302 tests (+8 nouveaux — `FilAriane` avec/sans
  contexte, `PageHeader`, `SelecteurVue` et ses 3 segments, `EcranCatalogue`
  dans ses 3 modes) ; aucun backend touché — suite pgTAP tout de même
  rejouée par précaution : `Files=44, Tests=313, PASS`, sans changement
  (aucune migration/RLS modifiée dans ce sous-livrable). **Re-vérifié après
  le correctif `_delegueSonAppBar`** : `flutter analyze` propre (12 infos
  pré-existantes hors zone touchée, sans rapport avec ce correctif — style
  `chat_ia`/`coquille_app.dart`, aucune ligne modifiée ici) ; tests ciblés
  coquille + marketplace + `PageHeader` rejoués : 15/15 verts.

*D2 — Galerie interactive de profils* (clos le 2026-09-13) : cartes profil,
expansion, animation Hero, filtrage multi-critères, chips — sur
`EcranAnnuairePersonnel` (M8, personnel RH) uniquement pour cette passe.

- **État des lieux** : dans `ecoshop_flutter`, aucun usage de `Hero(...)`
  nulle part dans tout le code source, et aucune galerie avec expansion. Le
  seul analogue fonctionnel proche est `personnel_liste_screen.dart` (RH) :
  deux rangées de `ChoiceChip` **à sélection simple** combinées (statut
  actif/inactif/archivé **ET** type de personnel), cartes denses poussant
  vers une fiche détaillée — pas de grille, pas d'expansion, pas de Hero.
  Côté client actuel, `EcranAnnuairePersonnel` (déjà construit, M8) n'avait
  qu'**un seul** critère de filtre (catégorie), le filtre statut de la
  source ayant été perdu. Aucune « galerie élèves » n'existe nulle part
  (ni source, ni client) — périmètre volontairement exclu par le porteur de
  projet (données de mineurs, question d'accès réelle, pas un habillage
  visuel).
- **Cadrage validé le 2026-09-13** : périmètre = `EcranAnnuairePersonnel`
  seul ; expansion = les deux comportements nommément désignés, pas une
  alternative — Hero vers `EcranFicheEmploye` en mode grille/cartes,
  accordéon en place en mode liste (avec action explicite « Voir la fiche
  complète », Hero également depuis là) ; filtrage = restauration du
  filtre statut, combiné au filtre catégorie, chips à sélection simple par
  groupe — lu à la lettre de `personnel_liste_screen.dart` cité comme
  modèle (qui n'a jamais utilisé de sélection multiple au sein d'un même
  groupe, seulement plusieurs groupes combinés) ; rendu par mode précisé
  pour liste/grille/cartes.
- **Filtre statut restauré** (`core/widgets/selecteur_vue.dart` réutilisé
  tel quel + nouvelle rangée de chips `StatutEmploye` dans
  `ecran_annuaire_personnel.dart`) — **correction d'un écart réel**, pas une
  nouveauté : documentée comme telle. Défaut « Tous statuts » retenu (pas
  « Actif » comme la source) pour ne pas masquer silencieusement, dès ce
  déploiement, des employés jusqu'ici visibles sans aucun filtre — la
  source, elle, démarrait plus stricte sur « Actifs » seuls ; écart de
  comportement assumé et documenté, pas repris à l'identique.
- **Écart de données trouvé en cours d'implémentation** (posé en clair,
  pas comblé en silence) : le modèle `Employe` (`public.employes`) n'a ni
  champ « poste » distinct de `categorie`, ni champ contact
  (téléphone/email). Le cadrage demandait un aperçu « poste, statut,
  contact » en accordéon et « poste, catégorie, statut, aperçu contact »
  en cartes riches — faute de ces deux champs, `categorie.libelle` sert de
  substitut à « poste » (pas dupliqué avec une ligne « catégorie »
  redondante) et l'aperçu contact est remplacé par matricule + date
  d'embauche, seules données réellement disponibles — avec des icônes
  volontairement neutres (`Icons.badge_outlined`, `Icons.event_outlined`),
  jamais téléphone/email, pour ne pas présenter ces deux champs comme des
  coordonnées de contact qu'ils ne sont pas (correction demandée avant
  clôture, appliquée en `_LigneIconTexte`). **Dette tracée pour plus tard**
  (pas ce sous-livrable) : ajouter de vrais champs téléphone/email à
  `Employe` pour compléter l'aperçu contact tel qu'initialement visé.
- **Hero** (`heroAvatarEmploye(id)`, tag partagé) : câblé sur l'avatar à
  initiales dans les trois modes (`_CarteEmployeAccordeon`,
  `_TuileEmployeGrille`, `_CarteEmployeRiche`) et, côté destination, sur
  `EcranFicheEmploye`, qui n'avait **aucun avatar** dans son en-tête avant
  cette passe — ajout nécessaire pour que l'animation ait un point d'arrivée
  cohérent, dérivé directement de la demande (pas un ajout hors sujet).
- **Rendu par mode** (`SelecteurVue`, mode par défaut « liste » — préserve
  le rendu actuel tant que personne ne bascule) : liste = ligne dense
  existante devenue accordéon, badge statut désormais visible dans le
  sous-titre (le filtre qu'il reflète étant revenu) ; grille = tuile
  compacte avatar + nom + catégorie, façon catalogue marketplace (D1) ;
  cartes = format riche (avatar plus grand, poste, statut, aperçu
  matricule/embauche), mode où l'animation Hero est la plus visible.
- **Dette résolue** : restauration du filtre statut (écart réel vs
  `ecoshop_flutter`, pas du N/A).
- **Vérifié** : `flutter analyze` propre sur les fichiers touchés (0
  erreur/avertissement) ; 6 nouveaux tests widgets dédiés (mode liste par
  défaut, dépliage + navigation Hero vers `EcranFicheEmploye`, filtre
  statut combiné à catégorie, recherche texte, bascule grille, bascule
  cartes) ; suite `flutter test` complète rejouée : **308/308**, verte
  (302 + 6) ; aucun backend touché, pgTAP non rejoué (aucune
  migration/RLS modifiée dans ce sous-livrable).

*D3 — Onboarding & régionalisation* (clos le 2026-09-13) : préférence de
langue (stockée localement, pas encore traduite), pays/devise en lecture
seule dérivés de l'établissement, étape légère d'onboarding non bloquante.

- **État des lieux** : `ecoshop_flutter` n'a **aucune** langue ni
  sélecteur de langue nulle part (son `onboarding_service.dart` couvre un
  tout autre sujet — demande d'établissement/invitations, item #1 déjà
  arbitré, sans rapport avec D3). En revanche `EtablissementModel`
  (`countryCode`, `currency`) y est déjà consommé en lecture seule pour le
  formatage — **précédent direct** du « pays/devise dérivés, non
  modifiables » de D3. Côté client actuel, `Etablissement` a déjà
  `paysCode`/`deviseCode`/`langueCode` (commentaire existant : « jamais
  déduits côté client ») et `EcranPreferencesApparence` applique déjà
  exactement ce patron (préférence modifiable `themeModeProvider` à côté
  d'un dérivé non modifiable `themeVariantProvider`) — réutilisé tel quel
  plutôt que réinventé. Aucune infrastructure de localisation
  (`l10n.yaml`, `.arb`, `flutter_localizations`) n'existe dans ce projet :
  point bloquant soulevé avant codage, tranché par le porteur de projet
  (option 1 : préférence stockée sans traduction réelle — fondation posée,
  traduction = chantier distinct non commencé ici).
- **`langueProvider`** (`features/regionalisation/`, persistance Drift
  partagée `preferences`/`regionalisation`/`langue`, même mécanisme que
  `ThemePreferenceStore`) — une seule option opérante (`fr`, « Français »)
  dans `languesDisponibles`, widget `SectionLangue` déjà générique pour en
  accueillir d'autres sans être reconstruit.
- **`SectionRegion`** — pays/devise lus directement sur
  `etablissementActifProvider` (codes bruts, cohérent avec
  `Etablissement.localisation` qui les affiche déjà ainsi ailleurs),
  jamais modifiables.
- **Emplacement** : `SectionLangue`/`SectionRegion` ajoutées telles
  quelles à `EcranPreferencesApparence` (pas de nouvel écran
  « Régionalisation » séparé, comme demandé) ET à une nouvelle étape
  d'onboarding `EcranOnboardingRegionalisation` — la même paire de widgets
  aux deux endroits, aucune logique dupliquée.
- **Onboarding** : nouvelle destination `DestinationSession.regionalisation`
  dans `GardeSession.resoudre` (`destination_session.dart`), insérée APRÈS
  `selectionEtablissement` et avant `accueil` (pays/devise dépendent de
  l'établissement déjà résolu, comme demandé) ; non bloquante — bouton
  « Continuer » qui marque l'étape vue **par profil**
  (`OnboardingRegionalisationStore`, clé = `profileId`, pas une clé
  globale : un second compte sur le même appareil revoit sa propre
  région) et laisse `RacineApp` réorienter vers l'accueil sans navigation
  explicite, même logique déclarative que le reste de la garde de
  session. Paramètre `regionalisationVue` par défaut `true` dans
  `GardeSession.resoudre` pour ne casser aucun appelant existant qui
  l'ignore.
- **Deux bugs trouvés et corrigés pendant la vérification empirique** (ni
  l'un ni l'autre de simple relecture de code) :
  1. Le premier lancement de la suite complète a révélé que
     `destinationProvider` touchant désormais la base Drift locale via
     `onboardingRegionalisationVuProvider` faisait *diverger*
     `pumpAndSettle` dans `garde_session_widget_test.dart` (base réelle
     tentant `path_provider`, indisponible en test). Corrigé en
     surchargeant `databaseProvider` par une base en mémoire
     (`AppDatabase.pourTests`, patron déjà établi ailleurs dans ce
     projet) et en figeant `onboardingRegionalisationVuProvider` à
     « déjà vue » dans ce fichier, qui teste la progression de session
     par rôle, pas D3 lui-même.
  2. Le nouveau test de l'écran d'onboarding a révélé un vrai piège :
     taper « Continuer » avant que `profilProvider` n'ait jamais été
     sollicité (rien dans l'arbre de cet écran ne le lit avant l'action)
     faisait diverger `pumpAndSettle` indéfiniment. En production, cet
     écran n'est jamais atteint avant que `destinationProvider` ait déjà
     confirmé `profil` chargé — le bug était donc spécifique à l'isolement
     du test, corrigé en pré-chauffant `profilProvider` dans le montage
     du test plutôt qu'en modifiant l'écran réel.
  3. (Mineur, découvert au même passage) `find.text()` par défaut ignore
     le contenu hors-champ d'un `ListView` (sliver, ne construit que ce
     qui est proche du viewport) : le test D3 ajouté à
     `ecran_preferences_apparence_test.dart` échouait à tort sur les
     sections ajoutées en bas d'un écran déjà long — corrigé avec
     `skipOffstage: false`, aucun changement de l'écran réel.
- **Dette résolue** : N/A — nouvelle fonctionnalité, mais deux écarts
  réels vs `ecoshop_flutter` absorbés au passage (pays/devise lecture
  seule déjà précédenté côté source, filtre/préférence de langue jamais
  présent côté source ni côté client).
- **Vérifié** : `flutter analyze` propre (0 erreur/avertissement, mêmes 12
  infos pré-existantes hors zone touchée) ; 2 nouveaux tests
  `GardeSession.resoudre` (régionalisation non vue/vue,
  sélection-établissement prioritaire) + 2 nouveaux tests
  `EcranOnboardingRegionalisation` (rendu, persistance par profil) + 1
  nouveau test `EcranPreferencesApparence` (sections D3) + 2 tests
  adaptés dans `garde_session_widget_test.dart` (surcharge DB/notifier,
  sans changement d'intention) ; suite `flutter test` complète rejouée :
  **314/314**, verte ; aucun backend touché, pgTAP non rejoué (aucune
  migration/RLS modifiée dans ce sous-livrable).

*D4 — Accessibilité* (clos le 2026-09-13) : contraste élevé (palette
alternative dédiée) et taille du texte (échelle discrète), seul écart
confirmé du périmètre « Expérience utilisateur & Configuration » restant
après D1-D3.

- **État des lieux, contrairement à D1-D3 : pas de cadrage initial à
  vérifier, un périmètre entier à établir.** L'étiquette provisoire
  « Centre d'aide & guides utilisateur », jamais confirmée par un cadrage
  dédié, est **abandonnée comme périmètre D4** — tracée séparément comme
  idée à cadrer plus tard si un besoin réel émerge, pas construite
  maintenant. Le chapitre 31 du cahier (Paramétrage et personnalisation)
  passé en revue point par point : logo/thèmes/templates de documents
  officiels → déjà tracés pour D5 ; système de notation → déjà couvert,
  plus finement même que demandé (`Evaluation.bareme` réglable par
  enseignant, pas un réglage global figé) ; langues → fondation posée par
  D3 ; déclaration niveaux/postes, classes/cycles/services, sélection du
  référentiel, échéances paiement/bibliothèque/transport → configuration
  structurelle déjà livrée par M4-M15, hors périmètre « expérience
  utilisateur ». Seul point du chapitre 31 sans domicile : « Animations
  d'interface, intégrées aux paramètres globaux » — **dette tracée, pas de
  cible définie, pas dans D4** (aucun écart aussi net que l'accessibilité).
  §34.9 du cahier : « Contraste et taille de police ajustables » confirmé
  absent partout — ni `ecoshop_flutter` (aucune mention
  accessibilité/contraste/taille de police dans tout `lib/`), ni le client
  actuel (palettes fixes, vérifiées WCAG AA au design mais non ajustables)
  — **seul écart réel identifié, donc le périmètre retenu pour D4.**
- **Contraste élevé** — option (a) du cadrage : une bascule vers UNE
  palette alternative dédiée (`AppPalettes.hauteVisibiliteLight/Dark`,
  `core/theme/app_palettes.dart`), indépendante des 3 variantes
  d'établissement, pas un curseur continu (qui aurait cassé la garantie
  WCAG déjà vérifiée palette par palette). **Vérifiée avant livraison**,
  comme demandé : tous les couples texte/fond dépassent largement le
  seuil AA de 4,5:1 (`encre`/`fond` = 21:1, les autres ≥ 6,25:1 — mesures
  dans le test dédié `app_palettes_test.dart`, même méthode WCAG que les 6
  palettes existantes), avec une marge volontairement large plutôt que des
  teintes en limite basse. `construireThemeData` accepte un paramètre
  `contrasteEleve` optionnel (défaut `false`, aucun appelant existant
  cassé) qui substitue cette palette à celle de la variante, quelle
  qu'elle soit.
- **Taille du texte** — échelle discrète `EchelleTexte`
  (Petit ×0,85 / Normal ×1 / Grand ×1,15 / Très grand ×1,3), stockée
  localement, même mécanisme que langue/thème (D3). Appliquée
  **globalement** via le `textScaler` ambiant posé sur le `builder` du
  `MaterialApp` racine (`main.dart`) — un seul point d'application pour
  toute l'app, comme demandé, pas un réglage écran par écran.
- **Vérification empirique du non-débordement à l'échelle maximale**
  (Très grand, ×1,3), comme explicitement demandé — pas une relecture de
  code : 3 nouveaux tests montent la coquille complète (rôles direction et
  élève, 4 et 5 onglets racine respectivement, tous les onglets visités)
  et `EcranPreferencesApparence` lui-même (l'écran le plus chargé en
  sections depuis D3/D4) sous ce facteur d'échelle, et vérifient qu'aucune
  erreur de rendu (`RenderFlex overflowed`) n'est signalée
  (`tester.takeException()`). **Portée assumée** : couvre les 5 onglets
  racine et l'écran de préférences, pas un balayage exhaustif de tous les
  écrans de l'application — signalé explicitement plutôt que présenté
  comme une garantie totale.
- **Emplacement** : `SectionAccessibilite` ajoutée à
  `EcranPreferencesApparence`, aux côtés de Thème/Langue/Région — l'écran
  accumule désormais 5 sections, choix assumé du porteur de projet, pas
  une dérive.
- **Dette résolue** : contraste et taille de police ajustables (§34.9,
  cahier v4.1) — confirmés absents partout avant cette passe, donc une
  **vraie correction d'écart**, pas seulement une nouveauté.
- **Hors périmètre D4, tracé séparément, pas construit** : « Centre
  d'aide & guides utilisateur » (jamais cadré) et « Animations
  d'interface » (chapitre 31, aucun réglage nulle part mais aucun écart
  aussi net constaté).
- **Vérifié** : `flutter analyze` propre (mêmes 12 infos pré-existantes
  hors zone touchée) ; 18 nouveaux tests (stores contraste/échelle,
  providers, `SectionAccessibilite`, palette haute visibilité + WCAG,
  `construireThemeData` avec `contrasteEleve`, non-débordement à ×1,3, et
  1 test d'intégration dans `EcranPreferencesApparence`) ; suite
  `flutter test` complète rejouée : **332/332**, verte (314 + 18) ; aucun
  backend touché, pgTAP non rejoué (aucune migration/RLS modifiée dans ce
  sous-livrable).

*D5 — Bulletins PDF classe entière* (clos le 2026-09-13) : composition
(moyenne + rang) et export PDF groupé d'une classe (cahier §12.4). Périmètre
réduit par cadrage : la personnalisation des templates de documents
officiels (chapitre 18) est différée en bloc, pas construite dans D5.

- **État des lieux, écart plus sévère que supposé** : l'arbitrage M16 6/7
  affirmait une « ampleur bornée (briques par élève déjà testées, il ne
  manque qu'un point d'entrée classe + une boucle d'assemblage) ». **Faux,
  vérifié avant d'implémenter** : aucune brique de composition de bulletin
  n'existait nulle part — ni individuelle, ni de classe. `NotesRepository`
  n'avait aucune méthode d'écriture pour les bulletins ; la seule ligne
  jamais insérée dans `public.bulletins` (schéma comme client) était un
  seed manuel de démo (`supabase/seed_notes_evaluations.sql`). Seule
  l'impression d'un bulletin **déjà existant** était couverte
  (`construireBulletinPdf`, M15ter). Écart réel plus large que ce que le
  carnet laissait supposer, signalé tel quel plutôt que traité comme
  acquis.
- **Composition et classement portés depuis `ecoshop_flutter`**
  (`NotesService.genererBulletin()` + `calculerClassementClasse()`), comme
  demandé — mais **le calcul lui-même reste côté serveur**, jamais reproduit
  côté client : la source calcule en Dart contre Firestore, alors que le
  client actuel est sous contrat M06 §5 (« aucune moyenne n'est calculée
  côté client », déjà vérifié par `moyenneEleve`/`moyenneClasse` qui
  délèguent aux RPC `calculer_moyenne_*`). Porter la logique au sens de
  l'algorithme (moyenne pondérée déjà éprouvée, classement par tri
  décroissant, rang = index+1) plutôt qu'au sens du mécanisme (calcul en
  Dart) était la seule façon de respecter les deux consignes à la fois —
  signalé explicitement plutôt que choisi en silence. Nouvelle RPC
  `classer_eleves_classe` (migration
  `20260906001510_d5_generation_bulletins_classe.sql`) : réutilise
  `calculer_moyenne_eleve` par élève inscrit, ajoute seulement le rang
  (`rank() over (order by moyenne desc)`), réservée au personnel de
  l'établissement de la classe (garde plus stricte que
  `calculer_moyenne_eleve`, qui répond pour une seule fiche à tout
  `authenticated` — celle-ci renvoie la classe entière, portée plus large
  délibérément resserrée). L'écriture est faite par une seconde RPC,
  `generer_bulletins_classe` — voir le correctif post-relecture ci-dessous
  pour la raison de ce choix (un upsert direct depuis le client, envisagé
  initialement, ne fonctionne pas sur cette table).
- **Publication immédiate, pas de brouillon** : chaque bulletin généré est
  écrit `statut = 'publie'` directement. La source n'a jamais eu de cycle
  brouillon/publication séparé pour les bulletins (visibles dès leur
  génération) ; générer en `brouillon` ici aurait rendu le bulletin
  invisible pour l'élève/parent (RLS `bulletin_visible` exige `publie`)
  sans qu'aucune action de publication n'existe pour l'en sortir — une
  régression par rapport à la source, pas un choix par défaut neutre. Le
  cycle brouillon/aperçu/publication réel appartient au chapitre 18,
  différé (voir plus bas).
- **Correctif post-relecture, avant push (question du porteur de projet sur
  la régénération §12.3)** : la version initialement livrée écrivait le
  bulletin par un upsert client direct (`bulletins.upsert(..., onConflict:
  'fiche_eleve_id,periode_id,type')`), en s'appuyant sur la policy RLS
  `bulletins_ecriture_scolarite` déjà existante — jamais exercée par un
  test réel (le pgTAP initial testait un `INSERT` brut, pas le chemin
  d'upsert du client ; le test Flutter passait par un faux port). **Vérifié
  empiriquement contre l'instance locale (appel REST réel, pas une
  relecture)** : cet upsert échoue **systématiquement** avec `42P10 — there
  is no unique or exclusion constraint matching the ON CONFLICT
  specification`, y compris à la toute première génération, pas seulement
  à la régénération — les deux index d'unicité de `bulletins` sont
  partiels (`where periode_id is [not] null`) et PostgREST construit un
  `ON CONFLICT` sans le prédicat requis pour les cibler. **Plus grave que
  la question posée ne le supposait** : la fonctionnalité telle que commitée
  ne pouvait générer aucun bulletin du tout par ce chemin. Corrigé par une
  nouvelle RPC `generer_bulletins_classe` (SECURITY DEFINER, permission
  vérifiée explicitement comme `creer_inscription_nouvel_eleve`) qui exécute
  l'`INSERT ... ON CONFLICT` en SQL brut avec le prédicat exact — seul
  endroit où Postgres peut réellement cibler ces index partiels. En
  construisant le correctif, une seconde régression latente a été trouvée
  et corrigée de la même façon empirique : `if not public.a_permission(...)`
  laissait passer un appelant sans `role_racine` choisi, parce que
  `a_permission()` peut renvoyer `NULL` (pas seulement `false`) et `IF NULL`
  ne déclenche jamais une branche en PL/pgSQL (contrairement à une clause
  RLS `USING`/`WITH CHECK`, où Postgres traite NULL comme refusé
  automatiquement) — un compte étranger recevait un tableau vide (200 OK)
  au lieu d'un refus explicite ; corrigé par `coalesce(a_permission(...),
  false)`. **Vérifié après coup, avec un scénario dédié** : première
  génération réussie, correction d'une note (10 → 17, comme le permet le
  cahier §12.3 avant proclamation), régénération de la même classe/période
  — même `id` de bulletin conservé, `contenu` mis à jour, aucun doublon —
  et le refus de permission renvoie désormais bien une erreur explicite
  (HTTP 403, `PERMISSION_REFUSEE`). Testé aussi bien pour un bulletin de
  période que pour un bulletin annuel (`periode_id` NULL), les deux index
  partiels étant concernés.
- **Conseils de classe / repêchage à seuil paramétrable / règle de
  proclamation des classes d'examen (§12.4)** : contrôle explicite effectué
  côté `ecoshop_flutter` avant de les tracer comme dette, comme demandé —
  **absents également de la source** (seule trouvaille : un placeholder
  `verifAdmisClasseSuperieure` dans `reinscription_screen.dart`,
  commenté « module Notes/bulletins non encore relié ici », donc jamais
  une fonctionnalité réelle à préserver). Confirmé hors périmètre D5, dette
  tracée sans régression possible puisque la source elle-même ne les a
  jamais implémentés.
- **Export PDF groupé** : `construireBulletinsClassePdf`
  (`export_pdf/data/bulletin_pdf_builder.dart`) — un seul PDF multi-pages
  pour toute la classe, comme `PdfService.genererBulletinsClasseA4()` côté
  source, pas un fichier par élève. Réutilise l'en-tête/pied de page déjà
  partagés avec les reçus (`entete_pdf.dart`) — satisfait l'exigence du
  cahier « même moteur que les reçus » au niveau où ce moteur existe
  réellement aujourd'hui (texte fixe, sans logo/signature — la
  personnalisation du chapitre 18 est différée, voir plus bas). Saut de
  page (`pw.NewPage()`) entre élèves plutôt qu'un `pw.Page` rigide par
  élève comme la source : si le contenu d'un élève déborde
  exceptionnellement d'une page, il continue sur la suivante au lieu
  d'être tronqué.
- **Emplacement** : `EcranGenerationBulletinsClasse`, atteint depuis
  `EcranDetailClasse` (icône « Bulletins de la classe »), réservé à la
  direction — même garde (`estDirection`) que le reste de l'administration
  scolaire (`EcranSanctions`), la véritable autorité restant la permission
  serveur `scolarite.bulletin.gerer` (RLS, défense en profondeur).
- **Hors périmètre D5, différé en bloc, pas construit** : personnalisation
  des templates de documents officiels (chapitre 18 — logo, en-tête/pied de
  page, signature/cachet, mentions, champs de fusion, cycle
  brouillon/aperçu/publication). Deux raisons vérifiées avant de différer,
  pas supposées : (a) le gate « mode payant » (§18.7) n'a **aucune**
  fondation dans le schéma ni le client (recherché explicitement —
  `mode_payant`/`plan_abonnement`/équivalent absent partout) ; construire un
  simple indicateur payant/gratuit sans facturation réelle derrière aurait
  été un gate qui ne gate rien, même type de faux choix déjà écarté pour le
  sélecteur de langue en D3. Dette de la même famille que la fondation
  facturation/quota IA laissée sans jalon à la clôture de M16. (b) §18.1
  situe cet espace côté « application Windows, Backoffice établissement » —
  jamais construite (le dossier `windows/` existe dans `client_flutter`,
  même socle Flutter mutualisé mobile+Windows du cahier, mais aucune
  interface Windows n'a jamais été développée). Pour référence future : le
  jour où ce chantier sera repris, ce sera sur le client mobile/tablette
  actuel, gardé par rôle comme le reste de l'app — pas une UI Windows
  dédiée pour un seul écran de configuration.
- **Vérifié** : migration rejouée par `supabase db reset` (podman/WSL2)
  sans erreur ; pgTAP `tests/rls/45_d5_generation_bulletins_classe.sql`
  réécrit après le correctif — **18 assertions** (classement exact et
  réservé au personnel ; génération refusée sans
  `scolarite.bulletin.gerer` — y compris le cas `a_permission()` = NULL —
  puis acceptée avec ; contenu conforme au classement pour les 2 fiches ;
  **régénération après correction d'une note : mêmes id de bulletins
  conservés, contenu recalculé, aucun doublon** ; visibilité élève lié +
  parent confirmé, opacité pour un élève étranger) — suite complète
  rejouée : `Files=45, Tests=331, PASS`, aucune régression sur les 44
  fichiers précédents. Avant le correctif, la RPC de génération avait aussi
  été appelée pour de vrai via l'API REST locale (pas seulement via pgTAP)
  pour reproduire puis confirmer la résolution du défaut `42P10`, sur les
  deux variantes (`periode_id` NULL et NOT NULL). `flutter analyze` propre
  (mêmes 12 infos pré-existantes) ; 12 nouveaux tests Flutter (passthrough
  `CachedNotesRepository` D5, smoke-tests `construireBulletinsClassePdf` à
  1 et plusieurs élèves, écran de génération — sélecteur de période,
  appel avec les bons paramètres, message dédié si aucun élève classable,
  panne réseau) ; suite `flutter test` complète rejouée : **344/344**,
  verte (332 + 12).

*D5 — complément de contenu réglementaire du bulletin* (clos le
2026-09-13, avant tout push de D5) : exigences spécifiées après coup par le
porteur de projet, absentes de f8968e1 — le document produit jusque-là était
incomplet pour un usage réel.

- **Pays + Ministère de tutelle en en-tête** — nouvelle colonne
  `pays_pedagogiques.ministere_tutelle` (nullable, jamais bloquante :
  absente → ligne simplement omise, même principe que les champs de fusion
  du chapitre 18). Vérifié avant d'ajouter : distincte de
  `organisme_examinateur` (déjà existant, mais c'est l'organisme
  certificateur d'un examen, pas l'autorité de tutelle administrative) —
  aucune valeur n'a été inventée pour la peupler, elle reste NULL tant
  qu'une source ministérielle fiable n'est pas intégrée.
- **Tableau par matière (secondaire uniquement)** — vérification demandée
  explicitement contre la classification de cycle réelle avant de coder :
  le code de cycle littéral (`cycles_educatifs.code`) varie par pays
  (« college »/« moyen »/« junior_high » désignent tous le palier
  secondaire 1er cycle) — la clé technique correcte est le **niveau ISCED
  normalisé** (`niveaux_educatifs.isced`, 1/2/3), confirmé et utilisé tel
  quel, pas une supposition tranchée seul. Nouvelle RPC `classe_isced`
  (personnel uniquement, résiliente : NULL si niveau non renseigné ou
  appelant non personnel) et `detail_bulletin_matieres` (matière,
  coefficient officiel du programme, moyenne de la matière **déléguée à
  `calculer_moyenne_eleve`** — aucun nouveau calcul —, nom + email de
  l'enseignant). Vide pour un cycle primaire (ISCED 1, un seul maître de
  classe déjà couvert par le bloc signatures).
- **Téléphone vs email — clarification du porteur en cours de route** :
  le cadrage initial demandait le téléphone du professeur sur le bulletin ;
  le porteur a ensuite précisé que le téléphone sert uniquement aux
  responsables scolaires en interne (jamais imprimé sur un document
  distribué à toute une classe) et que c'est l'**email** qui apparaît sur
  le bulletin. Ce changement résout de lui-même la question de
  confidentialité posée avant de coder cette partie (numéro personnel vs
  professionnel diffusé à une classe entière) — elle ne se pose plus
  puisque le téléphone n'est jamais imprimé. Deux colonnes ajoutées à
  `employes` (`telephone`, `email`), dette tracée depuis D2 ; écran d'édition
  ajouté sur `EcranFicheEmploye` (aucun écran d'édition employé n'existait
  auparavant — `RhRepository.creerOuModifierEmploye` existait déjà côté
  repository mais n'était appelé par aucun écran).
- **Mention « Non duplicata. »** après le bloc signatures, comme demandé.
- **Bloc signatures par cycle** — nouvelle colonne
  `pays_pedagogiques.signatures_bulletin` (jsonb, libellés par défaut
  Primaire : Directeur + Maître de classe ; Collège : Proviseur + Directeur
  des Études ; Lycée : Proviseur + Censeur — ajustables par pays, pas par
  établissement dans cette passe). Rendu comme deux lignes de signature
  vierges sous le libellé du rôle : aucun nom de titulaire n'est résolu
  pour Proviseur/Censeur/Directeur/Directeur des Études (rôles non
  modélisés individuellement dans le schéma) ; seul « Maître de classe »
  aurait pu être résolu via `Classe.enseignantPrincipalId`, délibérément pas
  fait pour garder un traitement cohérent des 6 libellés plutôt que d'en
  résoudre un seul.
- **Régénération (cahier §12.3) — avertissement UX** : `EcranGenerationBulletinsClasse`
  vérifie désormais si un bulletin existe déjà pour la classe/période avant
  de lancer la génération ; si oui, un dialogue reprend le texte exact
  demandé (« Un bulletin existe déjà pour cette période. La relance
  recalculera l'ensemble des moyennes et rangs à partir des notes
  actuelles. ») et le bouton devient « Mettre à jour / Recalculer les
  bulletins ». Purement informatif côté écran — la garantie réelle
  (mise à jour en place, jamais de doublon) reste celle déjà vérifiée
  empiriquement dans le correctif précédent (3947f02), non refaite ici.
- **Vérifié** : migration `20260906001511_d5_contenu_reglementaire_bulletin.sql`
  rejouée par `supabase db reset` sans erreur ; nouveau fichier pgTAP
  `tests/rls/46_d5_contenu_reglementaire_bulletin.sql` (16 assertions :
  ISCED exact pour les 3 cycles, résilience niveau absent/appelant non
  personnel, tableau par matière vide en primaire, contenu conforme en
  secondaire — matière/coefficient/moyenne/email —, résilience enseignant
  sans dossier RH, opacité pour un étranger, valeurs par défaut de
  `ministere_tutelle`/`signatures_bulletin`) — suite complète rejouée :
  `Files=46, Tests=347, PASS`, aucune régression sur les 45 fichiers
  précédents. `flutter analyze` propre (mêmes 12 infos pré-existantes) ;
  16 nouveaux tests Flutter (roundtrip `Employe.telephone/email`, 5
  smoke-tests `construireBulletinsClassePdf` — tableau matière, pays +
  Ministère, résilience Ministère absent, bloc signatures, isced sans
  libellé pour ce cycle —, 4 tests de l'avertissement de régénération, 4
  tests de l'écran d'édition du contact employé) ; suite `flutter test`
  complète rejouée : **360/360**, verte (344 + 16).

*D6 — Perception des frais par classe & fast-track d'inscription* (clos le
2026-09-13) : dernier module de la Phase D.

- **État des lieux avant codage** : perception (ch. 17) — tables/RPC déjà en
  place depuis M15quater (`encaissements_scolarite`, `frais_scolarite_config`,
  `paliers_paiement_config`, RPC `solde_scolarite`), mais flux strictement
  élève-par-élève (`EcranEncaissementScolarite` ouvert depuis une fiche
  précise) ; `EcranDetailClasse` n'avait aucun accès aux frais. **Silence du
  cahier sur une vue « par classe » — vérifié aussi absent côté source**
  (`paiement_screen.dart`/`cahier_journal_screen.dart` : zéro occurrence de
  « classe »), donc traité comme une fonctionnalité nouvelle, pas un
  rattrapage. Inscription (ch. 7.1) — **vrai écart cahier celui-là** :
  réinscription cible recherchait par matricule uniquement ; le cahier exige
  la recherche par téléphone du parent avec la fratrie complète. Vérifié par
  lecture directe du prototype source : `reinscription_screen.dart` cherchait
  bien par téléphone, mais ne résolvait jamais le cas de plusieurs enfants
  (`eleves.first`, TODO explicite jamais levé) — l'écart n'était donc pas
  seulement absent côté cible, il était non résolu côté source aussi.
- **Perception par classe** — nouvel écran `EcranPerceptionClasse`, accessible
  depuis `EcranDetailClasse` au même emplacement que le bouton Bulletins de
  D5 (direction uniquement). Consultation + navigation vers l'encaissement
  individuel existant **uniquement** — décision explicite du porteur de
  projet : pas de saisie groupée dans cette passe (une correction de solde
  erronée sur toute une classe serait plus difficile à défaire qu'un export
  PDF groupé, et rien ne la demandait). Aucune nouvelle RPC de liste : le
  solde par élève vient exclusivement de `solde_scolarite` (déjà existante,
  M15quater), appelée une fois par inscription active de la classe — même
  principe de délégation que `calculer_moyenne_eleve` en D5, aucun nouveau
  calcul financier écrit.
- **Correctif de sécurité trouvé en construisant ce point** (pas une dérive
  de périmètre — la fonction que ce module expose pour la première fois à
  l'échelle d'une classe entière méritait d'être creusée avant d'être
  exploitée plus largement, même réflexe qu'en D5 avec `a_permission`) :
  `solde_scolarite(p_inscription_id)` n'avait **aucune vérification
  d'autorisation** depuis M15quater — tout compte authentifié pouvait lire
  le solde de n'importe quelle inscription de n'importe quel établissement
  en connaissant seulement son UUID (fuite financière inter-établissements).
  Corrigé en appliquant exactement la frontière déjà retenue pour
  `encaissements_scolarite` (`est_personnel(etablissement) or
  fiche_visible(fiche)`, 20260906001502) — pas une règle inventée, la même
  déjà actée pour la même donnée sur la table adjacente. Fonction convertie
  de `sql` à `plpgsql` (contrôle de flux nécessaire), calcul inchangé.
- **Fast-track d'inscription (§7.1)** — nouvelle RPC
  `rechercher_enfants_par_telephone_parent` (même frontière de permission que
  `creer_reinscription` : gestion de la scolarité, ou direction), renvoyant
  la fratrie confirmée+autorisée complète (`relations_parent_eleve`, statut
  `confirmee`, `autorise = true`) — jamais un seul enfant pris
  arbitrairement. `EcranReinscription` restructuré : recherche par téléphone
  devient le point d'entrée par défaut (indicatif + numéro, normalisation
  E.164 via `Validators.normalizeE164`, déjà utilisé par l'écran de
  connexion) ; un seul résultat sélectionne automatiquement la fiche,
  plusieurs résultats affichent une vraie liste de choix. La recherche par
  matricule reste disponible en option secondaire (« Rechercher plutôt par
  matricule »), sans aucune régression sur le chemin déjà utilisé. Une fois
  la fiche identifiée par l'une ou l'autre voie, le flux de réinscription
  (alertes informatives + choix de classe + `creer_reinscription`) est
  strictement inchangé.
- **Vérifié** : migration
  `20260906001512_d6_perception_classe_et_fasttrack_inscription.sql` rejouée
  par `supabase db reset` sans erreur ; nouveau fichier pgTAP
  `tests/rls/47_d6_perception_classe_et_fasttrack_inscription.sql`
  (14 assertions : fratrie complète jamais un seul enfant, exclusion d'une
  relation non autorisée, exclusion d'une relation non confirmée, numéro
  inconnu renvoie un ensemble vide sans erreur, recherche bien scopée à
  l'établissement demandé, refus 42501 sans droit ; côté `solde_scolarite` —
  non-régression du calcul après conversion plpgsql, lecture autorisée pour
  la direction et pour le parent confirmé, **refus 42501 pour un tiers sans
  lien** — c'est la fuite corrigée —, refus 42501 pour la direction d'un
  autre établissement, erreur dédiée sur une inscription inexistante) — suite
  complète rejouée : `Files=47, Tests=361, PASS`, aucune régression sur les
  46 fichiers précédents. `flutter analyze` propre (mêmes 12 infos
  pré-existantes) ; 9 nouveaux tests Flutter (`ecran_perception_classe_test`
  — liste + solde, navigation vers l'encaissement individuel, classe vide ;
  `ecran_reinscription_test` — téléphone par défaut, sélection automatique à
  1 résultat, vraie sélection de fratrie à 2 résultats, numéro inconnu,
  numéro invalide rejeté avant tout appel réseau, matricule en secondaire) ;
  suite `flutter test` complète rejouée : **369/369**, verte (360 + 9).

Phase D close avec D6 — les six modules (D1 → D6) sont clos, vérifiés et
prêts pour le feu vert de push, selon la même discipline à chaque étape :
état des lieux avant code, écart posé en question plutôt que tranché seul,
vérification empirique avant clôture.

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
