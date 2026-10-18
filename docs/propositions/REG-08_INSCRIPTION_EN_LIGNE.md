# Proposition REG-08 — Inscriptions et réinscriptions en ligne

**Date** : 2026-10-18. **Statut** : **validée** par le porteur de projet le
2026-10-18 (principes ci-dessous) — construction à lancer.
**Registre** : `docs/REGISTRE.md` REG-08.

---

## 1. Ce qui existe déjà (M15quater, D6)

- Inscription d'un nouvel élève et réinscription **au guichet**
  (`creer_inscription_nouvel_eleve`, `creer_reinscription` — réservées au
  personnel habilité ou à la Direction).
- Détection de doublon d'élève (`verifier_doublon_eleve`).
- Contrôles **informatifs** avant réinscription (`verifications_reinscription` :
  impayé, sanction active, boursier précédent).
- Paiement Orange Money de la scolarité (`initier_paiement_orange_money`,
  objet `scolarite`) et lien parent ↔ enfant par téléphone.
- Proclamation des résultats (passage / redoublement).

**Manque** : campagne datée, accès parent / élève, demande d'inscription
d'un nouvel élève avec pièces, places par classe, liste d'attente.

## 2. Recherche (2026-10-18)

- Réinscription : intention de retour demandée tôt, dossier pré-rempli à
  vérifier, relances multiples, suivi conjoint administration / finance
  (OpenApply, PowerSchool Enrollment Express).
- Afrique de l'Ouest (Dakar, Bamako) : paiement mobile money, relances,
  **guichet assisté** pour les familles sans smartphone, paiement en espèces
  conservé avec reçu généré par le système.

## 3. Décisions du porteur de projet (2026-10-18)

1. **Qui agit** : en primaire, le parent seul. **À partir du collège**,
   l'élève **comme** le parent peuvent faire l'inscription, la réinscription
   et payer — certains élèves sont « à leur propre charge » et paient
   eux-mêmes leur scolarité. On enregistre **qui paie** (parent ou élève) ;
   s'ils sont tous deux liés, ils voient le même dossier et le même solde.
2. **Impayés et autres alertes** : **jamais de blocage automatique** ; la
   Direction voit les alertes et décide au cas par cas.

## 4. Conception retenue

1. **Campagne d'inscription** (Direction, par année scolaire) : ouverture
   des réinscriptions (anciens élèves, prioritaires), ouverture des
   nouvelles demandes, date limite, places par classe, frais à régler pour
   valider, pièces exigées par niveau, délai de réservation d'une place.
2. **Réinscription en ligne** : chaque enfant (ou l'élève lui-même dès le
   collège) avec la classe suivante proposée d'après la proclamation ;
   vérification des données pré-remplies ; « revient / ne revient pas » ;
   paiement Orange Money (frais + arriérés) **ou** « je paie au guichet »
   (place réservée N jours) ; paiement reçu → réinscription créée et reçu
   émis ; alertes (impayé, sanction) → décision de la Direction.
3. **Demande d'inscription d'un nouvel élève** : dossier + photos des
   pièces ; circuit soumise → incomplète (pièces réclamées) → test /
   entretien (facultatif) → acceptée (délai pour payer) → inscrite ; ou
   refusée (motif) ou **liste d'attente classée** (offre expirée → famille
   suivante).
4. **Hors connexion d'abord** : dossier rempli et pièces photographiées
   sans réseau, envoi au retour du réseau avec un numéro de dossier
   provisoire ; saisie par le secrétariat pour les familles sans téléphone ;
   paiement en espèces au guichet conservé.
5. **Direction** : tableau de bord (taux de réinscription, places
   restantes, liste d'attente, encaissé) ; notifications **push** (ouverture,
   pièce manquante, acceptation, échéance) — SMS selon REG-09 §4.
