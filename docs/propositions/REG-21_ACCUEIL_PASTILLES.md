# Proposition REG-21 — Accueil en pastilles, barre de navigation et profil allégé

**Date** : 2026-10-25. **Statut** : **validée** par le porteur de projet le
2026-10-25 (maquette relue et approuvée).
**Maquettes** : `docs/maquettes/accueil_pastilles/` (Parent, Direction,
Enseignant, Eleve, Profil — fichiers de maquette HTML, à lire comme
référence visuelle : couleurs, tailles, libellés, ordre).
**Registre** : `docs/REGISTRE.md` REG-21 (à créer).

---

## Problème

Tout ce qu'on peut faire est rangé en liste sous « Mon profil » (plus de 40
entrées pour une direction). Trop long, difficile à parcourir, et le profil
mélange réglages personnels et travail quotidien.

## Principe validé : trois niveaux

1. **« À faire »** en haut de l'accueil : ce qui attend une action, avec un
   compteur, chaque ligne mène directement à l'écran concerné (élève :
   « À ne pas manquer »).
2. **Pastilles** regroupées par thème : grille de 3 colonnes, icône dans un
   carré arrondi coloré, libellé de deux mots au plus, **badge** de nouveauté.
3. **« Mon profil »** ne garde que le personnel : informations, identifiant,
   invitations, sécurité, préférences, puis « Se déconnecter » tout en bas.

## Structure commune de l'accueil (tous les rôles)

- **Barre du haut** : « EcoShop » ; à droite notifications (badge),
  apparence, profil (avatar, tout à droite) — inchangé par rapport à REG-19.
- **En-tête** : nom en grand (30 px, gras) ; étiquettes rôle + établissement
  (déjà livré, à garder).
- **Bandeau hors connexion** juste sous la barre quand il n'y a pas de
  réseau : « Hors connexion — affichage des données enregistrées ».
- **Barre de navigation du bas**, 4 destinations, l'active surlignée :

| Rôle | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| Parent | Accueil | Messages (annonces + cahier) | Agenda | Paiements |
| Élève | Accueil | Annonces | Agenda | Mes notes |
| Enseignant | Accueil | Messages | Agenda | Classes |
| Direction | Accueil | Messages | Agenda | Tableau de bord |

Les rôles absents (vendeur, fondateur de réseau, admin GSG, admin contenu)
suivent le même modèle : choisir les 3 destinations les plus utilisées après
Accueil, et les justifier dans le rapport.

## Contenu par rôle

**Parent** : enfants en pastilles rondes (initiale, prénom · classe) +
« Ajouter » ; À faire (mots du cahier à signer, tranche à payer…) ;
pastilles : Annonces, Cahier de liaison, Emploi du temps, Notes et bulletins,
Scolarité, Bus, Parent IA, Inscriptions, Boutique.

**Élève** : prochain cours (heure, matière, salle, enseignant) ; À ne pas
manquer (nouvelle note, livre à rendre…) ; pastilles : Emploi du temps,
Mes notes, Annonces, Scan-Exercice, Ma carte (QR du portail), Bibliothèque,
Mon bus, Mes rapports, Boutique.

**Enseignant** : « Aujourd'hui » (cours en cours et suivant) ; À faire
(appel à faire, réponses de parents, notes à saisir) ; pastilles : Faire
l'appel, Notes, Cahier de liaison, Mes classes, Absences, Annonces,
Scan-Exercice, Progression, Mon dossier RH.

**Direction** : recherche « Que voulez-vous faire ? » (filtre les pastilles
par libellé et mots-clés : « reçu » → Encaissements) ; À faire (liaisons à
valider, numéros à confirmer, familles en retard) ; **Mes raccourcis** : 4
pastilles épinglées, bouton « Modifier », mémorisées sur l'appareil ;
groupes :
- Vie de l'école : Annonces, Cahier de liaison, Présence au portail, Alertes décrochage
- Élèves : Inscriptions en ligne, Nouvelle inscription, Réinscription, Comptes liés
- Finances : Encaissements, Relances, Comptabilité, Orange Money, Paramètres, Crédits SMS
- Personnel : Invitations, Personnel et RH, Numéros à confirmer
- Organisation : Classes et emploi du temps, Salles, Bibliothèque, Transport, Structures
- Établissement : Identité visuelle, Rapports, Ouvrir un établissement

**Profil allégé** : avatar, nom, identifiant EcoShop + copier ; Mon compte
(Mes informations, Mes invitations) ; Sécurité (Code secret, Empreinte
digitale) ; Préférences (Notifications, Langue et affichage) ; « Se
déconnecter » seul en bas.

## Règles

- Chaque pastille et chaque ligne « À faire » n'apparaissent que si le rôle
  et les droits le permettent (mêmes règles que les entrées actuelles).
- Les compteurs « À faire » et badges viennent des données locales : ils
  s'affichent hors connexion (dernière valeur connue) et se mettent à jour
  au retour du réseau. Aucune pastille ne bloque l'accueil en attendant le
  serveur.
- Aucune fonction n'est supprimée : tout ce qui était dans la liste du
  profil doit se retrouver en pastille, dans l'À faire ou dans le profil
  allégé. Fournir la table de correspondance ancienne entrée → nouvel
  emplacement dans le rapport.
- Accessibilité : vrais boutons, zones de toucher ≥ 44 px, contrastes ≥ 4,5:1,
  libellés lus par TalkBack (badge compris : « Annonces, 3 nouvelles »).
- Mode sombre : mêmes structures, couleurs adaptées.

## Méthode attendue

Recherche préalable (Material 3 : navigation bar, grilles, badges), puis un
commit par étape : barre du bas ; accueil par rôle ; profil allégé ;
raccourcis et recherche. Tests de widgets par rôle (pastilles visibles selon
les droits, À faire, hors connexion). Mise à jour du cahier et du registre.
