# REG-22 — Solution technique proposée (A, B, C)

**Date** : 2026-10-25. **Statut** : validée le 2026-10-25 (ordre et réponses ci-dessous).
Réponse à `REG-22_CODE_COMPTE_APPAREILS_POSTES.md` (partie A validée le
2026-10-25 ; B et C à présenter).

---

## 0. Recherche préalable — ce qui en ressort

| Source | Retenu pour EcoShop |
|---|---|
| NIST SP 800-63B-4 (vérifieurs) | Limitation obligatoire des échecs par compte, au plus 100 échecs consécutifs ; délais croissants permis. Nous : 5 échecs → 1 h, puis 24 h. |
| OWASP Password Storage | Empreinte lente salée (bcrypt ≥ 10, ou Argon2id) ; « poivre » (clé secrète hors base, HMAC) en défense en profondeur ; changer le poivre oblige à refaire tous les codes. |
| Signal (verrou d'inscription, Secure Value Recovery) | Un code court ne tient **que** par la limitation des essais côté serveur : une empreinte volée se casse hors ligne (1 million de combinaisons). D'où le poivre hors base. Code oublié : jusqu'à 7 jours d'attente. |
| WhatsApp (vérification en deux étapes) | Code à 6 chiffres demandé sur tout nouvel appareil ; réinitialisation par e-mail, ou attente de 7 jours sans e-mail. Notre délai de 48 h avec alertes et annulation va dans le même sens. |
| Google (ajout d'un appareil) | Invite « Est-ce vous ? » sur un appareil déjà connecté : c'est notre voie (a). |
| Supabase | `pgrst.db_pre_request` : une fonction exécutée **avant chaque requête** de l'API de données (tables et RPC), qui peut la refuser. Sans effet sur Storage et Realtime : on y ajoute la même vérification dans les politiques. Déconnexion : portées `local` / `others` / `global` ; **un jeton déjà délivré reste valable jusqu'à son expiration (1 h ici)**, d'où le contrôle à chaque requête. |

Sources : [NIST 800-63B-4](https://pages.nist.gov/800-63-4/sp800-63b/authenticators) ·
[OWASP Password Storage](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html) ·
[Signal, Registration Lock + SVR](https://signal.org/blog/improving-registration-lock/) ·
[Signal, assistance PIN](https://support.signal.org/hc/en-us/articles/360007059792) ·
[WhatsApp PIN oublié](https://blog.lastpass.com/posts/how-to-reset-whatsapp-password) ·
[Supabase, pre-request](https://supabase.com/docs/guides/api/securing-your-api) ·
[Supabase, déconnexion](https://supabase.com/docs/guides/auth/signout.md).

---

## A. Code du compte

### Principe technique

1. **« Nouvel appareil » = toute nouvelle connexion** (code e-mail ou
   Google). Une session déjà ouverte sur un téléphone reste un « appareil
   connu » : ouverture locale par code ou empreinte, inchangée, hors
   connexion comprise. Après « Ce n'est pas moi », une déconnexion ou 5
   codes faux, le téléphone redevient « nouveau ». C'est voulu : c'est
   précisément le scénario de la faille (déconnecter puis se reconnecter
   avec le seul code Gmail).
2. **Contrôle central, avant chaque requête** (`controle_requete()`,
   enregistrée comme `pgrst.db_pre_request`) :
   - session absente de `auth.sessions` (déconnectée) → refus
     `SESSION_REVOQUEE` : la coupure est immédiate, sans attendre l'heure
     d'expiration du jeton ;
   - compte doté d'un code et session pas encore vérifiée → seules les
     fonctions de vérification sont permises (liste fermée), tout le reste
     est refusé avec `APPAREIL_A_VERIFIER`.
   Un seul point de contrôle, qui couvre d'un coup les ~300 politiques et
   RPC existantes. Storage : la même fonction est ajoutée aux politiques
   des fichiers. Realtime : jeton encore valable au plus 1 h (risque
   résiduel accepté, ou durée du jeton réduite : voir Q5).
   **Interrupteur** `parametres_globaux.code_compte_obligatoire` : la mise
   en service peut être annulée sans migration si un défaut apparaît.
3. **Empreinte** : `crypt(hmac_sha256(code, poivre), gen_salt('bf', 10))`
   (pgcrypto, bcrypt coût 10). Le **poivre** vit dans le coffre Supabase
   (Vault), posé par le script de déploiement, et contrôlé par
   `etat_mise_en_service()`. Une copie de la base seule ne permet pas de
   retrouver les codes. Sa perte invaliderait tous les codes : il est
   sauvegardé avec les autres secrets (procédure de mise en service).

### Migration `…1561_code_compte.sql`

| Table | Contenu | Accès |
|---|---|---|
| `codes_compte` | compte, empreinte, `version` (+1 à chaque changement), dates | aucune lecture ni écriture directe (RLS fermée), fonctions seulement |
| `essais_code_compte` | compte, échecs consécutifs, palier (1 h, puis 24 h), bloqué jusqu'à | idem |
| `sessions_appareils` | session (→ `auth.sessions`, effacée avec elle), compte, modèle, système, version de l'application, statut `a_verifier` / `approuvee`, méthode (`creation`, `existant`, `code`, `appareil_connu`, `recuperation`, `ecole`), date | lecture de ses propres appareils |
| `demandes_appareil` | approbation (expire en 10 min), récupération (effective après 48 h, annulable), déblocage à l'école (valable 30 min) ; statut, auteur, motif | lecture des siennes ; direction pour les déblocages qu'elle a faits |

Fonctions :

| Fonction | Rôle |
|---|---|
| `etat_appareil()` | statut de la session, version du code, blocage, demandes en cours, prénom (« Bonjour Awa ») — permise avant vérification |
| `definir_code_compte(code)` | premier code (création du compte, ou comptes existants : voir plus bas) ; refuse les codes évidents (mêmes règles que l'application) |
| `verifier_code_compte(code)` | nouvel appareil : session approuvée si juste ; 5 échecs → nouveaux appareils bloqués 1 h, puis 24 h ; e-mail à chaque blocage |
| `changer_code_compte(ancien, nouveau)` | depuis un appareil vérifié, en ligne ; version +1 ; e-mail |
| `demander_approbation_appareil()` / `approuver_appareil(demande)` / `refuser_appareil(demande)` | voie (a) : notification push et invite sur les appareils connus, confirmée sur place par code ou empreinte |
| `lancer_recuperation_code()` / `annuler_recuperation(demande)` / `finaliser_recuperation_code(nouveau)` | voie (b) : effective 48 h après, e-mails au début et à la fin, bandeau « Récupération en cours — Annuler » sur les appareils connus |
| `debloquer_code_membre(compte, motif)` | voie (c) : direction de l'école, personne présente ; ouvre 30 min pendant lesquelles le nouvel appareil de la personne choisit un nouveau code ; journal d'audit (entité `code_compte`) |
| `enregistrer_appareil(modele, systeme, version)` | après la connexion (aussi pour B) |

Courriels (file `notifications_sortantes` existante) : nouvel appareil
connecté, avec un lien « Ce n'est pas moi » ; nouveaux appareils bloqués ;
récupération lancée et terminée ; code changé. Le lien « Ce n'est pas
moi » ouvre une fonction Edge publique `pas_moi`, munie d'un jeton signé à
usage unique et valable 7 jours. Elle ferme la session concernée et bloque
les nouveaux appareils (durée : voir Q2).

**Comptes existants.** Tant que le compte n'a pas de code serveur, le
contrôle le laisse passer : la mise en service ne coupe personne. À la
prochaine ouverture en ligne, l'écran dit « Votre code devient le code de
votre compte, le même sur tous vos appareils ». La personne confirme son
code actuel, puis `definir_code_compte`. Ses sessions déjà ouvertes à ce
moment-là sont marquées `existant` (appareils connus) et ne sont pas
coupées.

**Code changé ailleurs.** Un appareil connu voit, à sa prochaine
connexion, que `version` a changé. Il demande alors une fois le nouveau
code (vérifié par le serveur), puis remplace son empreinte locale. Hors
connexion, l'ancien code local ouvre encore l'appareil jusqu'au retour du
réseau. C'est ce que prévoit la proposition (« propagé à leur prochaine
connexion »).

### Écrans (application)

- **« Code de votre compte »** (nouvelle étape après la connexion, avant
  l'accueil) : « Bonjour Awa », pavé numérique existant, essais restants,
  blocage affiché avec l'heure de fin ; lien **« Code oublié ? »** →
  feuille à trois choix : « Autoriser depuis un autre appareil »,
  « Récupérer par e-mail (48 h) », « Me présenter à l'école ».
- **« Autoriser ce nouvel appareil ? »** (appareils connus, par push et
  à l'ouverture) : modèle, heure ; « Autoriser » (code ou empreinte) /
  « Ce n'est pas moi ».
- **Bandeau** sur les appareils connus pendant une récupération : « Une
  récupération du code est en cours (fin le … à …). Annuler ».
- **Direction › Personnel › « Débloquer le code d'une personne »** :
  recherche de la personne, motif obligatoire, confirmation par le code de
  la direction.
- **Mon profil › Sécurité › Changer le code du compte**.
- Le modèle de l'appareil vient de `device_info_plus` (nouvelle
  dépendance, version figée).

### Tests prévus

pgTAP : contrôle avant chaque requête (session déconnectée, appareil à
vérifier, liste fermée, interrupteur) ; 5 et 10 échecs ; codes évidents ;
approbation (expirée, refusée, par un appareil non vérifié : refusée) ;
48 h (trop tôt refusée, annulée) ; déblocage (autre école, soi-même,
direction par direction : refusés) ; comptes existants ; aucune lecture
directe des empreintes. Flutter : nouvelle étape, trois voies, version du
code changée, erreur `APPAREIL_A_VERIFIER` qui renvoie à l'étape.

---

## B. Appareils connectés

- **Liste** : `mes_appareils()` joint `sessions_appareils` et
  `auth.sessions`. Elle donne le modèle, le système, la date de connexion,
  la **dernière utilisation** (dernier renouvellement du jeton, sans
  écriture de plus) et « cet appareil ».
- **Déconnecter un appareil** : `deconnecter_appareil(session)` supprime
  la session dans `auth.sessions` (ses jetons de renouvellement partent
  avec elle). Grâce au contrôle de A, elle est refusée dès la requête
  suivante. **Déconnecter tous les autres** :
  `deconnecter_autres_appareils()`. Les deux sont des actions sensibles
  (code ou empreinte), journalisées, avec un e-mail.
- **Appareil déconnecté** : à sa prochaine requête, il reçoit
  `SESSION_REVOQUEE`, déconnecte et efface les données du téléphone. Un
  appareil resté sans réseau garde ses données jusqu'à son retour en
  ligne. C'est le risque résiduel d'un téléphone volé et éteint (le
  verrou local le protège).
- **À vérifier avant de construire** : que la suppression dans
  `auth.sessions` par une fonction serveur est permise sur le projet
  hébergé. Sinon, une fonction Edge (`service_role`) fera la même chose.
- **Écran** « Mon profil › Sécurité › Mes appareils » : une carte par
  appareil (icône, « Samsung Galaxy A14 », « Cet appareil », « Dernière
  utilisation : aujourd'hui à 14 h 05 », « Connecté depuis le 12/10 »,
  « Déconnecter ») ; en bas, « Déconnecter tous les autres appareils » ;
  au-dessus, les demandes en cours (approbation, récupération).

---

## C. Postes du personnel

### Inventaire de l'existant (constats)

1. **Deux mécanismes coexistent.**
   - Rôle dans l'établissement (texte libre) : `direction`,
     `fondateur_reseau`, `enseignant`, `vendeur`, `eleve`, `parent`.
   - Postes de l'école (`postes`, `poste_permissions`), qui donnent des
     permissions du catalogue (`a_permission`, 118 vérifications).
2. **La direction a tout** : `est_direction` (68 vérifications) passe
   partout.
3. **Faille de lecture.** `est_personnel` vaut pour tout membre qui n'est
   ni élève ni parent. **32 fonctions de lecture et 6 d'écriture ne
   demandent rien d'autre.** Elles couvrent les notes, les bulletins, les
   moyennes, les sanctions, les absences, les encaissements, les soldes,
   le journal d'audit, les risques de décrochage… Un agent du portail ou
   un chauffeur verrait tout cela.
4. **À l'invitation**, on ne peut choisir que `enseignant`, `direction`
   (affiché « direction et administration ») ou `vendeur`. **Une secrétaire
   ou un caissier doit donc être invité comme direction, avec tous les
   droits.**
5. **Aucun poste par défaut en production** : seul le seed de
   démonstration en crée (Proviseur, Secrétaire, Enseignant). **Aucun
   écran** de gestion des postes : un poste ne s'attribue qu'à
   l'invitation, et c'est facultatif.
6. **Catalogue** : 31 codes vérifiés. 17 codes du catalogue ne sont
   vérifiés nulle part (`rh.paie.gerer`, `comptabilite.plan.gerer`,
   `rh.conge.valider`, `etablissement.invitation.gerer`…) : ce sont des
   cases sans effet.
7. **Reçus** : aucune fonction d'annulation n'existe (numéro continu,
   reçu immuable). La règle « le caissier n'annule pas un reçu » est donc
   déjà tenue par construction.

### Solution

- **Nouveau rôle `personnel`** (administratif et technique), invitable à
  côté de `enseignant`. Ses droits viennent **uniquement** de son poste.
  Le rôle `direction` est réservé à la direction effective.
- **Lecture par permission.** Les 38 fonctions fondées sur
  `est_personnel` seul passent à des contrôles précis : enseignant affecté
  à la classe, titulaire, ou permission de lecture du domaine. Nouveaux
  codes de lecture : `scolarite.note.lire`, `scolarite.bulletin.lire`,
  `scolarite.sanction.lire`, `scolarite.presence.lire`,
  `scolarite.encaissement.lire`, `audit.journal.lire`, `rh.employe.voir`
  (existant, enfin vérifié). Codes de métier : `portail.scanner`,
  `transport.circuit.suivre`, `comptabilite.valider` (validation et
  clôture).
- **Les 17 codes sans effet** : soit ils sont branchés, s'ils protègent
  une action réelle, soit ils sont retirés du catalogue. La liste détaillée
  sera dans le lot.
- **Modèles de postes** (`modeles_postes`) : données de référence livrées
  par migration, comme le référentiel. Les postes de chaque école sont
  créés à partir des modèles à la validation de l'école
  (`traiter_demande_etablissement`), et rattrapés pour les écoles
  existantes. Chaque poste garde `modele_code`. La direction ou le
  fondateur peut créer un **poste personnalisé** à partir d'un modèle :
  renommer, cocher ou décocher des droits.
- **Séparation des tâches, côté serveur** : un poste ne peut pas cumuler
  `scolarite.encaissement.gerer` et `comptabilite.valider` ou
  `comptabilite.ecrire`. Le serveur refuse le cumul, l'écran l'explique.
- **Écrans** : Direction › Personnel › **Postes** (liste, nombre de
  personnes, « Créer à partir d'un modèle », droits groupés par domaine
  en français simple) ; **fiche d'un membre** (changer son poste) ;
  invitation : choix du poste, obligatoire pour `personnel`.

### Tableau poste → droits (proposition à relire avec une école pilote)

« Lire » et « gérer » s'entendent dans son établissement. Direction =
rôle `direction` (tous les droits) ; les autres = rôle `enseignant` ou
`personnel` + poste.

| Poste (modèle) | Rôle | Permissions par défaut |
|---|---|---|
| Fondateur / promoteur | direction | tout ; en plus, `comptabilite.valider`, `etablissement.membre.gerer` (nomme la direction) |
| Directeur général / proviseur / principal / directeur d'école | direction | tout |
| Directeur des études / censeur | personnel | `scolarite.classe.gerer`, `scolarite.periode.gerer`, `planification.administrer`, `planification.generer`, `scolarite.evaluation.gerer`, `scolarite.note.lire`, `scolarite.note.gerer`, `scolarite.bulletin.gerer`, `scolarite.appreciation.gerer`, `scolarite.parametres.gerer`, `rh.enseignant.affecter`, `rapports.generer` |
| Surveillant général | personnel | `scolarite.presence.gerer`, `scolarite.presence.lire`, `scolarite.sanction.gerer`, `scolarite.sanction.lire`, `scolarite.evenement.gerer`, `portail.scanner`, `communication.groupe.moderer`, cahier de liaison (écrire aux parents) |
| Comptable / économe / intendant | personnel | `comptabilite.lire`, `comptabilite.ecrire`, `comptabilite.valider`, `scolarite.encaissement.lire`, `rapports.generer` (financiers) — **pas** d'encaissement |
| Caissier | personnel | `scolarite.encaissement.gerer`, `scolarite.encaissement.lire` (reçus) — **pas** de comptabilité, pas de clôture |
| Secrétaire | personnel | `scolarite.inscription.gerer`, `scolarite.eleve.gerer`, `scolarite.relation.gerer` (parents, numéros à confirmer), `etablissement.membre.lire` |
| Enseignant | enseignant | ses classes : notes, appel, cahier de liaison (par affectation, sans permission) |
| Professeur principal (titulaire) | enseignant | idem, plus les bulletins et les appréciations de sa classe (déjà prévus via `enseignant_principal_id`) |
| Bibliothécaire | personnel | `bibliotheque.gerer` |
| Agent du portail | personnel | `portail.scanner` — rien d'autre |
| Chauffeur / convoyeur | personnel | `transport.circuit.suivre` (son circuit seulement) |

### Migrations et tests prévus

- `…1562_postes_personnel.sql` : rôle `personnel`, nouveaux codes,
  `modeles_postes`, création des postes par défaut et rattrapage,
  séparation des tâches, invitation (rôle `personnel`, poste
  obligatoire).
- `…1563_lecture_par_permission.sql` : les 38 fonctions réécrites.
- pgTAP : pour **chaque** fonction réécrite, un agent du portail et un
  chauffeur sont refusés ; le bon poste est accepté ; la direction a
  toujours tout. Cumul encaissement + validation refusé. Postes par défaut
  créés à la validation d'une école.
- Flutter : écrans Postes, fiche d'un membre, invitation.

---

## Ordre de construction proposé

1. **C, lecture par permission** (corrige la faille de lecture, sans
   changer d'écran).
2. **A, serveur** (contrôle avant chaque requête, interrupteur coupé),
   puis **A, application**, puis interrupteur allumé.
3. **B** (s'appuie sur A).
4. **C, postes, modèles et écrans.**

Un commit et un push par lot validé ; REG-22 créé au registre, REG-18
amendé (partie C).

## Questions au porteur de projet

- **Q1** — Déblocage à l'école : la direction peut débloquer le
  personnel, les parents et les élèves de son école. **Pas elle-même, ni
  un autre membre de la direction** : ce cas passe par l'administrateur
  GSG (sinon un membre de la direction pourrait prendre le compte d'un
  autre). D'accord ?
- **Q2** — « Ce n'est pas moi » : nouveaux appareils bloqués **jusqu'à ce
  que le titulaire change son code depuis un appareil connu** (ou passe à
  l'école), plutôt qu'une durée fixe. D'accord ?
- **Q3** — Rôle `personnel` pour le non-enseignant (secrétaire, caissier,
  comptable, surveillant, portail, chauffeur, bibliothécaire, censeur),
  et `direction` réservé au fondateur et au directeur : d'accord ? Les
  membres déjà invités comme « direction » qui sont en réalité secrétaire
  ou caissier : la direction devra changer leur rôle (écran de fiche de
  membre), on ne devine pas.
- **Q4** — Fondateur / promoteur : rôle `direction` dans son école
  (tous les droits) ou poste distinct avec moins de droits au quotidien ?
- **Q5** — Realtime : jeton valable 1 h après une déconnexion à distance.
  Accepter, ou ramener la durée du jeton à 15 min (renouvellement plus
  fréquent, un peu plus de trafic) ?

## Décisions du porteur de projet (2026-10-25)

- **Ordre** : C (lecture par permission) d'abord, puis A, B, enfin les
  écrans de postes. Un commit et un push par étape, tests serveur pour
  chaque poste, refus compris.
- **Q1** — Oui. La direction débloque le personnel, les parents et les
  élèves. La direction et le fondateur sont débloqués par l'administrateur
  GSG, après vérification d'identité. Personne ne se débloque soi-même.
- **Q2** — Oui. « Ce n'est pas moi » bloque les nouveaux appareils jusqu'au
  changement de code depuis un appareil connu. S'il n'en reste aucun, la
  récupération par e-mail (48 h) et le déblocage à l'école restent
  possibles.
- **Q3** — Oui. Rôle `personnel` pour tous les non-enseignants ;
  `direction` réservé au fondateur et au directeur. Aucune école réelle en
  production : personne à reclasser.
- **Q4** — Le fondateur ou promoteur a le rôle `direction` (tous les
  droits) ; ses actions sont journalisées.
- **Q5** — Jeton valable jusqu'à 1 h accepté pour Realtime : durée
  actuelle conservée (l'application reste verrouillée par le code secret
  sur un téléphone volé).
