# Proposition REG-09 — Pointage des élèves au portail et notifications

**Date** : 2026-10-18. **Statut** : **validée** par le porteur de projet le
2026-10-18 — construction après REG-08.
**Registre** : `docs/REGISTRE.md` REG-09.

---

## 1. Demande initiale et décision

Demande : contrôle de présence par GPS (téléphones du parent et de l'élève)
entre 7 h et 15 h. **Abandonnée le 2026-10-18** au profit du pointage au
portail, pour ces raisons :

- le téléphone du parent ne renseigne pas sur l'enfant (le parent n'est pas
  à l'école) ; beaucoup d'élèves n'ont pas de téléphone ;
- GPS imprécis à l'intérieur, facile à falsifier, coûteux en batterie et
  en données ;
- suivi continu de mineurs jugé disproportionné (CNIL) ; loi guinéenne
  L/2016/037 : déclaration préalable des traitements ; cahier §34.2 :
  minimisation des données des mineurs.

## 2. Pointage au portail

- Carte d'élève à **QR code** ; un téléphone de l'école au portail scanne
  l'arrivée et la sortie.
- **Hors connexion d'abord** : les scans sont gardés sur le téléphone du
  portail et envoyés au retour du réseau.
- L'appel en classe (M7, déjà hors connexion) reste la **preuve
  officielle** ; le tableau de la Direction montre les écarts (entré au
  portail mais absent du cours).

## 3. Notifications (automatiques)

| Événement | Destinataires | Canal |
|---|---|---|
| Arrivée, sortie (« arrivée à 7 h 42 ») | parents liés ; l'élève s'il est autonome sans parent lié | push (désactivable) |
| Absence : non scanné et non justifié à l'heure limite fixée par l'école | idem | push (+ SMS si crédit, §4) |
| Sortie anticipée sans autorisation | idem | push (+ SMS si crédit, §4) |

**Garde-fou** : aucune alerte d'absence tant que le portail n'a pas
transmis ses scans postérieurs à l'heure limite (sinon fausses alertes
massives) ; la Direction voit « portail non synchronisé ». Une arrivée
transmise en retard l'indique (« transmis à 9 h 10 »).

## 4. Canaux — décision du porteur de projet (2026-10-18)

- **Push uniquement** par défaut ; GSG ne prend pas en charge le coût des
  SMS.
- **SMS en option payante** : l'établissement **achète des crédits SMS
  auprès de GSG**, qui les achète lui-même auprès des fournisseurs. Le
  crédit de l'établissement est décompté à chaque SMS ; sans crédit, seul
  le push part. La Direction choisit les alertes envoyées aussi par SMS
  (par défaut : absence et sortie anticipée).
- **Relances d'impayés (décision du 2026-10-18)** : les mêmes crédits SMS
  servent aux messages de relance des familles en retard de paiement des
  frais de scolarité (échéances des paliers), en plus du push.
- À construire : envoi push (Firebase Cloud Messaging), portefeuille de
  crédits SMS par établissement, vente des packs (backoffice GSG, paiement
  CinetPay — circuit GSG), adaptateur fournisseur SMS (à choisir).
