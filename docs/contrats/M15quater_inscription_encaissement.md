# M15quater — Inscription, réinscription & encaissement de scolarité — Contrat de module

> Inséré dans la séquence de construction entre M15ter (livré) et M16 (IA à
> rôles, qui conserve son numéro et son contenu inchangés), **avant** les ~8
> autres écarts de l'audit rétroactif restant à arbitrer.
> Migration : `supabase/migrations/20260906001501_m15quater_inscription_encaissement.sql`.
> Tests pgTAP : `tests/rls/38_m15quater_inscription_encaissement.sql`.
> Code Flutter : `apps/client_flutter/lib/features/scolarite/` (extension —
> pas un nouveau dossier de feature, ce module étend M5 et introduit un
> nouveau sous-domaine financier au sein de la scolarité).

## 1. Origine et périmètre

Ce module regroupe des écarts déjà identifiés par l'audit rétroactif
(`docs/AUDIT_ECOSHOP_FLUTTER.md`, §4 « M4 → M5 ») et le point qui a motivé
son ouverture immédiate : le retrait du sous-périmètre « reçu PDF » de
M15ter (`docs/contrats/M15ter_export_pdf.md` §7), qui s'appuyait faute de
mieux sur une écriture comptable générale sans lien avec un élève.

Périmètre livré :

1. **Création d'inscription** (nouvel élève) — matricule généré serveur,
   détection de doublon informative.
2. **Réinscription annuelle** — recherche par matricule, vérifications
   informatives (impayé, sanction active, statut boursier précédent).
3. **Statut boursier** — annuel, par inscription, traçabilité qui/quand.
4. **Champs administratifs complémentaires** de la fiche élève (filiation,
   quartier, contact d'urgence, redoublement, n° dans la classe).
5. **Paramètres établissement** — tarif par défaut, paliers de paiement.
6. **Encaissement de scolarité** — entité dédiée (`encaissements_scolarite`),
   liée explicitement à `fiche_eleve_id`/`inscription_id`, jamais une
   écriture comptable générale. Solde calculé côté serveur.
7. **Suivi financier sur la fiche élève** — solde, historique des
   encaissements, action d'encaissement, une fois les paiements enregistrés
   via cette nouvelle entité.

## 2. Architecture serveur

### 2.1 Enrichissements de schéma

- `fiches_eleves` : `numero_classe`, `nom_pere`, `nom_mere`, `quartier`,
  `personne_urgence_nom`, `personne_urgence_telephone`, `redoublant`.
- `inscriptions` : `boursier`, `boursier_modifie_par`, `boursier_modifie_le`
  (trigger `inscriptions_verifie_boursier` — jamais transmis par le client).

### 2.2 Nouvelles tables

- `frais_scolarite_config` (etablissement, année, niveau nullable = tarif
  par défaut, montant annuel, frais d'inscription).
- `paliers_paiement_config` (etablissement, année, nom, pourcentage, ordre,
  date limite) — trigger `paliers_verifie_somme` : la somme des pourcentages
  actifs d'un (établissement, année) ne peut jamais dépasser 100.
- `encaissements_scolarite` (etablissement, fiche élève, inscription, type
  de frais, montant, moyen de paiement, référence, date, auteur, statut
  valide/annulé, motif d'annulation). Triggers :
  - `encaissements_verifie_tenant` — cohérence multi-tenant fiche/inscription
    + **`saisi_par` toujours imposé par `auth.uid()`**, jamais par le client.
  - `encaissements_verifie_immuable` — montant/moyen/date/fiche/inscription
    immuables après création ; seule l'annulation (statut + motif + qui +
    quand) peut changer, et exige un motif non vide.

### 2.3 RPC

- `creer_inscription_nouvel_eleve` — génère le matricule serveur (préfixe
  slug établissement + compteur séquentiel), crée la fiche et sa première
  inscription. Gate : `scolarite.inscription.gerer` ou direction.
- `verifier_doublon_eleve` — booléen seul (jamais les données d'un
  établissement concurrent) : un élève de mêmes nom/prénom/date de naissance
  est-il déjà inscrit actif ailleurs ?
- `verifications_reinscription` — impayé/sanction active/boursier précédent
  (informatif, jamais un blocage serveur absolu).
- `creer_reinscription` — nouvelle inscription pour une fiche existante.
- `solde_scolarite` — tarif applicable (par niveau, sinon tarif par défaut)
  moins encaissements validés, calculé à chaque appel, jamais stocké.

### 2.4 RLS

Résumé (détail complet dans la migration) : paramètres financiers lisibles
par toute personne concernée par l'établissement (transparence tarifaire),
écriture réservée à la permission dédiée ou à la direction. Encaissements
lisibles par le personnel, l'élève concerné ou son parent confirmé ; création
et annulation réservées à la permission dédiée ou à la direction ; **aucune
policy DELETE** sur `encaissements_scolarite` — un encaissement ne se
supprime jamais, il s'annule (piste d'audit).

## 3. Architecture client (Flutter)

- Domaine : `encaissement_scolarite.dart`, `frais_scolarite_config.dart`,
  `palier_paiement_config.dart`, `solde_scolarite.dart`,
  `verifications_reinscription.dart`, `enums_financier_scolaire.dart` ;
  enrichissement de `fiche_eleve.dart` et `inscription.dart`.
- `ScolariteRepository` étendu (10 nouvelles méthodes) — écritures sans
  repli hors ligne (même principe que `lierEnfant`, M5 : un matricule
  généré serveur, un solde ou une détection de doublon ne s'approximent pas
  localement) ; lectures avec repli cache Drift (même politique que le
  reste du module).
- Écrans : `ecran_creation_inscription.dart`, `ecran_reinscription.dart`,
  `ecran_parametres_financiers.dart`, `ecran_encaissement_scolarite.dart`,
  `ecran_cahier_encaissements.dart` ; `ecran_fiche_eleve.dart` enrichi
  (champs administratifs affichés + dialogue d'édition direction, carte
  solde + bouton encaissements + bascule boursier).
- Entrées de navigation (direction) : « Nouvelle inscription »,
  « Réinscription », « Paramètres financiers », « Cahier des encaissements »
  dans l'onglet Profil (`coquille_app.dart`).

## 4. Résolution des problèmes hérités

1. **Aucun moyen d'inscrire un élève** n'existait dans la cible —
   `ScolariteRepository` n'avait aucune méthode de création (confirmé par
   l'audit). Résolu.
2. **Le reçu PDF de M15ter reposait sur une entité sans rapport avec la
   scolarité** (`EcritureComptable`) — corrigé en fournissant enfin l'entité
   dédiée que ce sous-périmètre attendait ; le reçu a été reconstruit dessus
   (`docs/contrats/M15ter_export_pdf.md` §7).
3. **`TypeBulletin` sans libellé lisible** avait déjà été corrigé par
   M15ter ; ce module suit la même discipline (`.libelle` sur les nouveaux
   enums plutôt que des `switch` dupliqués dans chaque écran).

## 5. Rapport d'écart fonctionnel vs `ecoshop_flutter`

Conformément à la règle transversale ANALYSE_GLOBALE.md §4.2.5.

| Fonctionnalité | ecoshop_flutter (source) | EcoShop (cible, ce module) | Écart |
|---|---|---|---|
| Création d'inscription | `inscription_screen.dart` — génération serveur de matricule, détection de doublon, **frais d'inscription distinct de l'annuité** | `creer_inscription_nouvel_eleve` — matricule serveur, doublon détecté. Frais d'inscription et d'annuité restent deux champs de `frais_scolarite_config` mais aucun écran ne les distingue à la saisie du premier encaissement (l'utilisateur choisit le type manuellement) | Dégradé — pas de flux guidé « payez d'abord l'inscription » ; à confirmer si nécessaire |
| Réinscription | `reinscription_screen.dart` — recherche par **téléphone parent** | `creer_reinscription` — recherche par **matricule** | Écart assumé et documenté (§6) — le matricule est l'identifiant canonique côté cible |
| Vérifications de réinscription | 4 vérifications (impayés, admission classe supérieure, sanction active, boursier) | 3 vérifications (impayé, sanction active, boursier précédent) — **« admission en classe supérieure »** non vérifiée | Dégradé — cette vérification dépendrait d'une règle de progression de niveau non modélisée ; à débattre si jugée nécessaire |
| Statut boursier | `InscriptionModel.statutBoursier`, traçabilité `boursierModifiePar`/`Le` | `inscriptions.boursier` + trigger équivalent | Couvert |
| Champs administratifs | `EleveModel` (numeroClasse, nomPere, nomMere, quartier, personneUrgenceNom/Telephone, redoublant) | Colonnes équivalentes sur `fiches_eleves`, dialogue d'édition direction | Couvert |
| Détection de doublon | Inter-établissement, avec dialogue de confirmation et revalidation serveur | `verifier_doublon_eleve` — inter-établissement, booléen seul (pas de détail sur l'établissement concurrent, volontairement, pour la confidentialité) ; dialogue de confirmation côté client | Couvert, plus prudent que la source sur la confidentialité |
| Paramètres établissement | `parametres_etablissement_screen.dart` — tarifs **par niveau**, paliers de paiement, activation paiement en ligne | Tarif **par défaut de l'établissement** géré à l'écran ; tarif par niveau supporté par le schéma mais pas encore par l'écran (§6). Paliers de paiement couverts. Activation paiement en ligne hors périmètre (dépend du Port Paiement, M16-M20) | Dégradé (tarif par niveau) et différé (paiement en ligne) |
| Encaissement de scolarité | `paiement_screen.dart`, `recu_screen.dart`, `cahier_journal_screen.dart` — écran dédié, reçu, cahier journal | `ecran_encaissement_scolarite.dart`, reçu PDF (M15ter §7), `ecran_cahier_encaissements.dart` | Couvert |
| Suivi financier fiche élève | Solde, historique, PDF de fiche complète | Solde + historique à l'écran (`ecran_fiche_eleve.dart`) ; **pas de PDF de fiche complète** (seul le reçu par encaissement est exportable) | Dégradé — voir `docs/contrats/M15ter_export_pdf.md` §4 |
| Historique des réinscriptions | Affiché sur la fiche élève, distinct de l'historique de classes | Les réinscriptions apparaissent dans le même historique de classes que les inscriptions initiales (pas de distinction visuelle « inscription » vs « réinscription ») | Dégradé mineur |

## 6. Limites connues et éléments différés

- **Recherche par matricule plutôt que téléphone parent** pour la
  réinscription — simplification assumée. Le matricule est déjà
  l'identifiant canonique côté cible ; à revoir si un usage réel montre que
  le personnel ne l'a pas toujours sous la main au moment de la réinscription.
- **Tarif par niveau non géré à l'écran** — le schéma serveur
  (`frais_scolarite_config.niveau_id`) le permet déjà, mais
  `ecran_parametres_financiers.dart` ne gère que le tarif par défaut de
  l'établissement (`niveau_id` null). Le sélecteur de niveau (référentiel
  M4) n'est pas encore branché sur cet écran.
- **Vérification « admission en classe supérieure »** non implémentée
  (dépendrait d'une règle de progression de niveau non modélisée à ce jour).
- **Pas de distinction visuelle inscription/réinscription** dans
  l'historique de classes de la fiche élève.
- **Génération de matricule non verrouillée contre une concurrence stricte**
  — collision extrêmement improbable, rattrapée par la contrainte unique
  `fiches_matricule_unique` (documenté dans la migration).
- **Activation du paiement en ligne** hors périmètre — dépend du Port
  Paiement hexagonal (CinetPay + Mobile Money), replanifié en M16-M20.

## 7. Tests

- pgTAP (`tests/rls/38_m15quater_inscription_encaissement.sql`, 25
  assertions) : création d'inscription (permission, matricule généré),
  doublon, réinscription (contrainte unique sur la même année), statut
  boursier tracé, paliers ≤ 100 %, solde calculé serveur, encaissement
  (auteur forcé, visibilité personnel/parent/tiers, immutabilité,
  annulation motivée). Renforcé après relecture : isolation inter-
  établissement prouvée avec un **second établissement réel** doté de sa
  propre direction (pas seulement un tiers non affilié — §8, section 9) ;
  annulation **valide** (motif fourni) — succès, `annule_par`/`annule_le`
  tracés automatiquement, `solde_scolarite` recalculé (section 10).
- Flutter : round-trip JSON pour tous les nouveaux domaines
  (`test/features/scolarite/domain_json_test.dart`), repli cache hors ligne
  pour les nouvelles lectures et absence de repli pour les écritures
  (`test/features/scolarite/cached_scolarite_repository_test.dart`), reçu
  PDF reconstruit (`test/features/export_pdf/recu_pdf_builder_test.dart`,
  y compris un test de chaîne complète JSON-serveur → `depuisJson` →
  `construireRecuPdf`, sans objet Dart construit à la main dans le chemin
  testé).

261 tests Flutter passent au total, `flutter analyze` propre. Statut
d'exécution des 25 assertions pgTAP : voir `docs/AUDIT_ECOSHOP_FLUTTER.md`
§0.4 (tentative d'installation Docker/Podman documentée).

---

**Point de contrôle** : le module M15quater est-il totalement clos et validé
pour passer au suivant ? — Code livré, testé, documenté, écart vs
`ecoshop_flutter` posé (§5), limites explicitement signalées (§6), reçu PDF
de M15ter rebranché sur la bonne entité. **M16** reste bloqué
indépendamment de M15quater, par l'arbitrage en attente des ~8 autres
écarts du rapport d'audit rétroactif (`docs/AUDIT_ECOSHOP_FLUTTER.md` §11).
