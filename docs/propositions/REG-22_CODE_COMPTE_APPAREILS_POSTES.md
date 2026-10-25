# Proposition REG-22 — Code du compte, appareils connectés, postes du personnel

**Date** : 2026-10-25. **Statut** : **validée** par le porteur de projet le
2026-10-25 (partie A) ; parties B et C : solution à présenter avant
construction. Complète REG-18 (partie C modifiée).
**Registre** : `docs/REGISTRE.md` REG-22 (à créer) ; REG-18 à amender.

---

## A. Faille : nouvel appareil ouvert avec le seul code e-mail (validée)

Scénario : quelqu'un a le téléphone du titulaire en main. Le verrou
EcoShop le bloque, mais il saisit l'adresse du titulaire sur un **autre**
téléphone, lit le code dans la boîte Gmail (souvent ouverte sans verrou sur
le téléphone du titulaire) et entre dans le compte. L'identifiant EcoShop
ne suffit pas à l'empêcher : il n'est pas secret.

**Décision** : le code secret de 6 chiffres devient **le code du compte**,
le même sur tous les appareils.

- **Appareil déjà connu** : inchangé — ouverture par le code ou l'empreinte,
  vérifiée localement, hors connexion comprise.
- **Nouvel appareil** : vérification de l'adresse (code e-mail ou Google)
  **et** code du compte vérifié par le serveur. Le serveur ne garde qu'une
  empreinte lente et salée, jamais le code. Essais limités par compte :
  5 échecs → nouveaux appareils bloqués 1 h, puis 24 h ; e-mail d'alerte.
- **Changement du code** : en ligne, propagé aux autres appareils à leur
  prochaine connexion.
- **Code oublié sur un nouvel appareil** :
  (a) approbation depuis un appareil déjà connu (« Autoriser ce nouvel
  appareil ? », confirmée par code ou empreinte) ;
  (b) à défaut, récupération par e-mail avec **délai de 48 h**, alertes, et
  annulation possible depuis un appareil connu ;
  (c) déblocage à l'école par la direction, en présence de la personne,
  avec journal d'audit.
- **Alerte** par e-mail à chaque connexion depuis un nouvel appareil, lien
  « Ce n'est pas moi » : ferme cette session et bloque les nouveaux
  appareils.
- **Comptes existants** : à la prochaine ouverture, le code local devient
  le code du compte, après confirmation.

Recherche préalable : NIST SP 800-63B (vérification des secrets, limitation
des essais), OWASP MASVS-AUTH, pratiques WhatsApp et Google pour l'ajout
d'un appareil.

## B. Appareils connectés (à présenter avant construction)

« Mon profil › Sécurité › Mes appareils » : liste des appareils connectés
(modèle, dernière utilisation), « Déconnecter cet appareil »,
« Déconnecter tous les autres appareils ». S'appuyer sur les sessions
Supabase (déconnexion globale / des autres sessions).

## C. Postes du personnel (à présenter avant construction)

Inventaire de l'existant (rôle principal, postes de l'établissement,
catalogue des permissions), puis liste de postes par défaut adaptée aux
écoles guinéennes, chacun avec ses droits par défaut :

| Poste | Droits par défaut (proposition à relire avec une école pilote) |
|---|---|
| Fondateur / promoteur | Tout voir, valider les finances, nommer la direction |
| Directeur général / proviseur / principal / directeur d'école | Tout gérer dans son établissement |
| Directeur des études / censeur | Classes, emplois du temps, notes, bulletins, examens |
| Surveillant général | Absences, discipline, portail, cahier de liaison |
| Comptable / économe / intendant | Comptabilité, paramètres financiers, rapports financiers |
| Caissier | Encaissements et reçus seulement ; ne modifie pas la comptabilité, n'annule pas un reçu |
| Secrétaire | Inscriptions, dossiers des élèves, numéros à confirmer |
| Enseignant / professeur principal (titulaire) | Ses classes, notes, appel, cahier de liaison ; le titulaire voit les bulletins de sa classe |
| Bibliothécaire | Bibliothèque |
| Agent du portail | Scanner les cartes au portail, rien d'autre |
| Chauffeur / convoyeur | Son circuit de bus |

Règles : séparation des tâches (qui encaisse ne valide ni ne clôture) ;
la direction ou le fondateur peut créer un poste personnalisé à partir
d'un modèle. Présenter le tableau poste → droits avant de construire.

## Ordre

A, B et C ensemble, **avant** REG-21 (accueil en pastilles).
