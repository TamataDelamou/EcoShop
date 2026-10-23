# Proposition REG-18 — Sécurité d'accès : inscription en étapes, code secret, identifiant EcoShop

**Date** : 2026-10-23. **Statut** : **validée** par le porteur de projet le
2026-10-23. Construction immédiate, après la correction des défauts de la
partie A.
**Registre** : `docs/REGISTRE.md` REG-18 (à créer).

---

## Origine

Premier essai réel de l'APK de production (2026-10-23, nuit) : la mise en
service fonctionne (Google, code par e-mail, administrateur GSG), mais le
porteur de projet relève deux inquiétudes :

1. un utilisateur curieux peut créer plusieurs comptes avec plusieurs
   adresses e-mail ;
2. **un téléphone laissé sans surveillance donne accès au compte sans
   aucune vérification** (aucun verrou dans l'application aujourd'hui).

Analyse validée :

- (1) est un risque limité : l'auto-inscription ne donne que les espaces
  élève ou parent, vides tant qu'ils ne sont pas liés à une fiche par
  matricule + date de naissance (RPC `lier_compte_a_fiche`, essais
  limités). Une inscription en étapes n'empêche pas les comptes multiples
  (une adresse Gmail se crée en deux minutes) : la protection se place à la
  **liaison** (§5).
- (2) est un vrai trou. Réponse retenue : le modèle des applications de
  mobile money, **appareil de confiance + code secret local**, et non un
  mot de passe vérifié par le serveur à chaque ouverture (qui ne
  fonctionnerait pas sans réseau, contraire au principe « hors connexion
  d'abord »).

---

## Partie A — Défauts constatés sur l'APK (à corriger en premier, commits séparés)

> **État 2026-10-23 : corrigée et poussée.** Défauts 1 et 3 : `4959888`
> (session relue à chaque événement Auth ; déconnexion hors connexion
> d'abord) et `dde131e` (« Valider » ne renvoie plus un code accepté).
> Défaut 2 : `48fc385` (bouton Google conforme). Vérifié : `flutter analyze`
> sans problème, `flutter test` 548/548.

1. **Blocage après connexion réussie**, avec Google **et** avec le code par
   e-mail : après la feuille Google, ou après la vérification automatique
   du code, l'écran reste sur le chargement. La session est bien ouverte :
   à la réouverture on arrive sur le choix du profil (nouveau compte) ou
   sur le tableau de bord. Reproduit 3 fois sur 3. Un second appui sur
   « Valider » affiche « code expiré » (le code a déjà servi). Trouver ce
   qui bloque après l'ouverture de session (attente sans fin : profil,
   rattachement push… ; ou navigation qui n'écoute pas le changement de
   session). Test qui reproduit le cas. Après une vérification réussie,
   « Valider » ne renvoie plus le code.
2. **Bouton Google** : logo « G » officiel et règles de présentation de
   Google (Sign in with Google branding guidelines). Les utilisateurs ne le
   reconnaissent pas aujourd'hui.
3. **Déconnexion lente sans réseau** (`session_logout.dart`) : détachement
   push, `signOut` Supabase et oubli Google s'enchaînent sans délai
   maximum. La déconnexion doit être **immédiate sur le téléphone**
   (session et données locales effacées tout de suite), les appels réseau
   faits ensuite en arrière-plan avec un délai court.

---

## Partie B — Inscription en étapes (nouveaux comptes auto-inscrits)

Ordre des écrans :

1. **Espace** : élève ou parent (détermine la suite).
2. **Nom et prénoms.**
3. **Vérification de l'e-mail** : code à 6 chiffres ou Google (Google
   pré-remplit nom et prénoms ; l'étape 2 est alors seulement confirmée).
   **Le compte n'est créé qu'ici** : une inscription abandonnée avant ne
   laisse rien dans la base (saisies gardées sur le téléphone).
4. **Numéro de téléphone** : déclaré, sans SMS, comme REG-16 (« Plus tard »
   possible).
5. **Création du code secret** (partie C), puis proposition d'activer
   l'empreinte ou le visage.
6. **Récapitulatif** : bienvenue, **identifiant EcoShop** (partie D),
   prochaine étape (lier une fiche d'élève).

Comptes du personnel (invitation) : pas de choix d'espace (l'invitation le
fixe) ; mêmes étapes 2 à 6.

**Comptes existants** (déjà créés avant REG-18) : à la prochaine
ouverture, attribution de l'identifiant et création obligatoire du code
secret, sans repasser par l'inscription.

---

## Partie C — Code secret EcoShop et verrouillage

**Principe** : on prouve son identité **une fois par téléphone** (code
e-mail ou Google). Ensuite, sur ce téléphone, l'application s'ouvre avec un
**code secret de 6 chiffres** ou l'empreinte / le visage.

| Règle | Valeur |
|---|---|
| Longueur du code | **6 chiffres** (l'OWASP déconseille 4) ; refuser les suites évidentes (123456, 000000, date de naissance si connue) |
| Empreinte / visage | Facultatif, proposé après la création du code ; le code reste toujours le recours |
| Verrouillage après passage en arrière-plan | Délai **différent selon le rôle**, du plus sensible au moins sensible : voir le tableau « Délais de verrouillage par rôle » ci-dessous |
| Actions sensibles | Code (ou empreinte) **à chaque fois** : paiement, validation et verrouillage de notes, écritures et clôtures comptables, encaissements, décisions de l'administration GSG, changement d'e-mail ou de téléphone |
| Échecs | **5 codes faux de suite** → session fermée sur ce téléphone et données locales purgées ; reconnexion par e-mail ou Google, puis nouveau code |
| Code oublié | « Code oublié » → vérification par e-mail ou Google → nouveau code |
| Hors connexion | Tout fonctionne sans réseau (vérification locale) |
| Écran verrouillé | Le contenu de l'application n'est jamais visible derrière le verrou ni dans la liste des applications récentes |

**Délais de verrouillage par rôle** (décision 2026-10-23). Le délai court
dès que l'application passe en arrière-plan ou que l'écran s'éteint. Un
compte qui cumule plusieurs rôles prend le délai **le plus court**.

| Rôle | Délai | Raison |
|---|---|---|
| Administrateur GSG, administrateur contenu | **2 min** | Accès à toutes les écoles et aux décisions de la plateforme |
| Direction, fondateur de réseau | **5 min** | Encaissements, comptabilité, personnel, données de toute l'école ou du réseau |
| Vendeur (marketplace) | **5 min** | Ventes et argent |
| Enseignant | **15 min** | Notes et absences d'une classe ; utilisé en cours, verrou trop fréquent gênant |
| Parent | **30 min** | Données de ses enfants, paiements protégés à part (action sensible) |
| Élève | **30 min** | Données personnelles d'un mineur ; téléphone souvent partagé en famille |

Le code reste demandé **à chaque action sensible**, quel que soit le délai.
Les délais sont des constantes faciles à ajuster (un seul endroit dans le
code, et côté serveur si un contrôle y est fait).

**Écran d'ouverture** (téléphone déjà connu) : « Bonjour Achille », puis
un pavé numérique qui monte du bas de l'écran (feuille), comme les
applications de paiement guinéennes ; bouton empreinte si activée ; lien
« Ce n'est pas moi » (déconnexion et choix d'un autre compte).

**Exigences techniques** (à confirmer par la recherche préalable) :

- secret dérivé du code rangé dans le stockage sécurisé du système
  (Android Keystore / iOS Keychain), jamais le code en clair ; dérivation
  lente avec sel ; compteur d'échecs protégé de la même façon ;
- empreinte par l'API biométrique du système (classe forte), invalidée si
  l'empreinte du téléphone change ;
- le verrou est une protection **de l'appareil** : le serveur reste la
  seule autorité (RLS inchangées). Un téléphone rooté peut contourner un
  verrou local (OWASP : tout contrôle client est contournable) ; c'est
  accepté, les droits restent vérifiés côté serveur ;
- plusieurs comptes sur un même téléphone (famille, tablette d'école) :
  chacun son code ; l'écran d'ouverture propose les comptes mémorisés
  (peut venir dans un second temps si le reste est prêt avant).

---

## Partie D — Identifiant EcoShop

- **Propre à EcoShop uniquement** (décision 2026-10-23) : ce n'est pas un
  identifiant GSG commun aux produits ; ne pas réintroduire l'ancien
  « GSG ID » retiré par `…1527_kernel_suppression_gsg_id`.
- Format court et lisible, sans caractères ambigus (alphabet de type
  Crockford, sans I, L, O, U), par exemple `EC-7K4M-29` ; unique ; attribué
  par le serveur à la création du compte ; jamais réattribué.
- Affiché dans « Mon profil », copiable ; utile au guichet de l'école.
- **Connexion** : champ unique « E-mail ou identifiant EcoShop ». Avec un
  identifiant, le serveur retrouve l'adresse et y envoie le code ; l'écran
  affiche l'adresse masquée (« a•••@gmail.com »). **Réponse identique** que
  l'identifiant existe ou non (pas d'énumération), essais limités.
- **L'identifiant n'est pas un secret** : sur un nouveau téléphone, la
  vérification par e-mail ou Google reste obligatoire.
- Distinct du **matricule** de l'élève (qui appartient à l'école).

---

## Partie E — Comptes multiples : protections à la liaison

- **Prévenir la direction** (notification + liste dans son tableau de
  bord) à chaque nouveau compte lié à un élève de son école, avec la
  possibilité de **révoquer** une liaison.
- **Plafond de comptes par fiche**, réglable par l'école ; par défaut 2
  comptes parents + le compte de l'élève. Au-delà : demande soumise à la
  direction.
- Rien ne change pour les espaces du personnel (invitation).

---

## Méthode attendue

1. **Recherche préalable** : meilleures pratiques actuelles (verrou local
   PIN + biométrie sur Flutter, OWASP MASVS-AUTH, NIST SP 800-63B), et les
   paquets Flutter les plus sûrs et maintenus ; justifier les choix dans le
   registre.
2. Partie A d'abord (commits séparés, poussés), puis B à E.
3. Migrations Supabase pour l'identifiant, le plafond et les notifications
   de liaison ; RLS ; tests serveur.
4. Tests Flutter pour chaque règle du tableau de la partie C (délais par
   rôle, 5 échecs, actions sensibles, hors connexion).
5. Mise à jour du **cahier de conception** (chapitre authentification),
   de `docs/REGISTRE.md` (REG-18) et de `docs/MISE_EN_SERVICE.md` si un
   réglage change.
6. Au passage : mettre à jour `docs/DEPLOIEMENT_PUSH.md` (le JSON du compte
   de service passe maintenant par `FCM_COMPTE_SERVICE_FICHIER` et le
   script `deployer_supabase.ps1`, ou est collé sous `FCM_COMPTE_SERVICE`).
7. `flutter analyze` et `flutter test` propres, commit, push.
