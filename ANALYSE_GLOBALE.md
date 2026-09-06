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
figurent dans [`docs/ETAT_PHASE_A.md`](./docs/ETAT_PHASE_A.md). **Réserve
principale** : aucune migration SQL ni Edge Function n'a pu être exécutée
(outils backend absents du poste) ; la clôture formelle de M1 et M2 suppose un
`supabase db reset` et les tests d'intégration RLS (pgTAP).

Le module suivant est **M4 — Référentiel pédagogique CEDEAO**.
