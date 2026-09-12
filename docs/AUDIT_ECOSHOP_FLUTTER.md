# Audit d'écart fonctionnel — EcoShop (cible) vs ecoshop_flutter (source)

> Livrable de l'**étape immédiate 1** (règle transversale ANALYSE_GLOBALE.md §4.2.5).
> Périmètre : audit rétroactif de tous les modules livrés à ce jour, **M0 → M15**.
> Méthode : lecture directe et comparée du code source
> (`C:\Users\delam\ProjetsFlutter\ecoshop_flutter`, dossier `lib/features/` + docs racine)
> et du code cible (`C:\Users\delam\PlatformGSG\EcoShop`, `apps/client_flutter`,
> migrations `supabase/migrations/`, contrats `docs/contrats/`).
>
> **Ce rapport ne tranche rien.** Chaque écart est posé en question avec une
> recommandation *proposée* (implémenter / différer / abandonner) — la décision
> revient au porteur de projet, module par module. Tant que ce rapport n'a pas
> été examiné et arbitré, **M16 ne doit pas être ouvert** (cf. ANALYSE_GLOBALE.md,
> état de livraison).

---

## 0. Synthèse exécutive — ce qui demande une décision urgente

Sur les deux points explicitement signalés comme sensibles par le porteur de
projet, l'audit confirme un écart réel des deux côtés :

### 0.1 Protection des mineurs dans les conversations de classe — **RÉSOLU** (patch de sécurité d'urgence)

> **Statut : corrigé.** Traité hors séquencement normal, avant tout autre
> point de cet audit, sur décision explicite du porteur de projet.
>
> - **Volet serveur** — schéma RLS complet créé par
>   `supabase/migrations/20260906000901_m9_patch_securite_messagerie_groupe.sql`
>   (tables `groupes_discussion`/`messages_groupe`/`signalements_message`,
>   appartenance dérivée des inscriptions/affectations réelles, jamais des
>   relations parentales, RLS dès la création couvrant les 7 règles absolues
>   listées ci-dessous). Vérifié par 15 assertions pgTAP dans
>   `tests/rls/37_m9_patch_messagerie_groupe.sql` (membre/parent/non-membre,
>   création réservée adulte, modération, signalements).
> - **Volet client (fuite entre comptes)** — cause identifiée : le prototype
>   local (`CommunicationLocaleRepository`) stockait ses entrées sous une clé
>   de cache unique (`'global'`) non isolée par profil, et `rafraichirSession()`
>   n'invalidait jamais `entreesLocalesProvider`. Corrigé par
>   `apps/client_flutter/lib/features/coquille/application/session_logout.dart` :
>   la déconnexion purge désormais systématiquement ce cache local et invalide
>   le provider avant qu'un autre compte puisse se connecter sur le même
>   appareil. Reproduit et vérifié par
>   `apps/client_flutter/test/features/coquille/session_logout_test.dart`
>   (scénario explicite : déconnexion A → connexion B → B ne voit rien de A).
> - **Réserve assumée** : le schéma serveur existe et est protégé, mais les
>   écrans du prototype local (`ecran_messagerie_prototype.dart` et consorts)
>   ne sont **pas encore raccordés** à ce nouveau backend — voir
>   `docs/contrats/M09_communication_notifications.md` §6. Ce patch ferme le
>   trou de sécurité serveur ; le raccordement de l'écran reste un travail
>   distinct, à cadrer avec les ~10 autres écarts de cet audit.

Contrairement à ce que l'on pourrait supposer d'un simple report de fonctionnalité,
ce n'était pas seulement une fonctionnalité manquante : c'était une **régression de
sécurité active**, décrite ci-dessous telle que constatée avant correction.

- Côté source, `ecoshop_flutter` applique 7 règles absolues au niveau des règles
  Firestore elles-mêmes (pas seulement l'UI) : création de groupe réservée à une
  Cloud Function serveur, adulte permanent non retirable, zéro message privé
  élève↔élève, zéro accès parent, texte seul, modération réservée au personnel,
  soft-delete uniquement, signalements traités en collection dédiée protégée.
- Côté cible, **aucune table serveur n'existe** pour les conversations de classe
  (`conversations`/`messages`/`groupes_discussion`/`signalements`) : le module de
  communication de groupe est un **prototype 100 % local**, sans aucune des 7
  règles, ni côté serveur (puisqu'il n'y a pas de serveur) ni côté UI (n'importe
  quel rôle, y compris élève, peut ouvrir une conversation à label libre).
- Pire : la clé de cache local utilisée (`'global'`, non isolée par profil) fait
  qu'**un appareil partagé** (tablette d'établissement, scénario courant en
  contexte scolaire) **expose les messages d'un élève au prochain utilisateur qui
  se connecte sur le même appareil** — une fuite de données réelle et immédiate
  entre comptes successifs, concernant des mineurs.

**Recommandation** : ne pas exposer davantage cet écran à un rôle élève tant
qu'aucune des 7 règles absolues n'a de contrepartie serveur (table + RLS +
trigger) équivalente à la source. Détail complet en [§9 — M9](#9-m9--communication--notifications).

### 0.2 Génération de documents depuis des modèles (bulletins, reçus, attestations) — **RÉSOLU**

> **Statut : corrigé**, en deux temps. Le bulletin (M6) est exportable en
> PDF depuis **M15ter — Export PDF**
> ([`docs/contrats/M15ter_export_pdf.md`](./contrats/M15ter_export_pdf.md)).
> Le reçu (M13/M14) a été livré une première fois avec M15ter, **retiré**
> avant tout push (il s'appuyait sur une écriture comptable générale,
> `EcritureComptable`, sans aucun lien structurel avec un élève, une
> inscription ou un solde dû — un document ayant l'apparence d'un reçu sans
> le garantir), puis **reconstruit** sur l'entité dédiée
> `EncaissementScolarite` livrée par
> **M15quater — Inscription, réinscription & encaissement de scolarité**
> ([`docs/contrats/M15quater_inscription_encaissement.md`](./contrats/M15quater_inscription_encaissement.md)).
> Voir `docs/contrats/M15ter_export_pdf.md` §7 pour l'historique complet du
> retrait puis de la reconstruction. **Attestations toujours hors
> périmètre** (pas une régression, confirmé absent des deux côtés).

- **Bulletins** (M6) : absents des deux côtés en tant que « système de modèles »
  paramétrable — mais la source avait au moins un **export PDF codé en dur**
  (mise en page A4, impression). La cible n'avait **aucune capacité d'export**
  avant M15ter (le bulletin était un simple affichage écran d'un champ JSON) —
  **corrigé**, voir `apps/client_flutter/lib/features/export_pdf/data/bulletin_pdf_builder.dart`.
  Réserve assumée : un bulletin s'exporte à la fois, pas de génération groupée
  pour toute une classe (dépend d'un autre écart déjà signalé, non résolu —
  §6 point 8).
- **Reçus de paiement** (M13/M14) : la source génère un reçu thermique 58 mm à
  chaque encaissement et un reçu A4 annuel ; **corrigé pour le format A4** —
  `apps/client_flutter/lib/features/export_pdf/data/recu_pdf_builder.dart`
  (M15quater), adossé à `EncaissementScolarite` (`fiche_eleve_id`/
  `inscription_id` explicites, `saisi_par` imposé serveur). Réserve assumée :
  pas de format thermique 58 mm ni de récapitulatif annuel consolidé.
- **Attestations** (scolarité/inscription/paiement) : recherche exhaustive côté
  source — **cette fonctionnalité n'existe pas dans ecoshop_flutter non plus**.
  Ce n'est donc pas une régression, mais une fonctionnalité à instruire comme
  nouvelle si le besoin est confirmé. **Non traitée**, hors périmètre assumé.

Détail complet en [§6](#6-m6--notes--évaluations) et [§13-15](#13-15-m13-marketplace-assoshop--m14-comptabilité--m15-marketplace-public).

### 0.3 Autres écarts à impact élevé relevés par l'audit (hors les deux points ci-dessus)

| # | Écart | Module | Impact |
|---|---|---|---|
| 1 | Aucun parcours d'entrée pour Enseignant/Direction/Vendeur/Fondateur réseau (RPC serveur prêtes, rien côté client) | M0-M3 | Élevé |
| 2 | Aucune création d'inscription / réinscription élève (M5 = consultation seule) | M5 | Élevé |
| 3 | Aucun suivi financier élève (solde, paiements) sur la fiche élève | M5 | Élevé |
| 4 | Déclaration manuelle de sanction disciplinaire impossible depuis l'app (repository prêt, écran manquant) | M7 | Élevé |
| 5 | Génération de bulletins pour une classe entière : aucun chemin utilisateur | M6 | Élevé |
| 6 | Paie RH : cycle complet (génération, primes, avances, PDF) très dégradé, le report annoncé vers M14 n'a pas eu lieu | M8 | Élevé |
| 7 | Tableau de bord directeur consolidé (Finances+Scolarité) avec alertes à seuil, absent | M10 | Élevé |
| 8 | Séances ponctuelles / annulation d'un cours un seul jour, impossible sans casser la récurrence | M11 | Élevé |
| 9 | Aucun écran d'encaissement de frais de scolarité (solde élève, reçu) — le périmètre annoncé pour M14 n'a pas été livré tel quel | M14 | Élevé |
| 10 | Gestion des stocks absente y compris en base — survente non prévenue par construction | M13 | Élevé |

### 0.4 Vérifications post-M15quater — preuves RLS/annulation et tentative d'exécution locale des tests pgTAP

Trois points de vérification exigés avant tout push, avec preuve.

**a) Isolation par établissement sur `encaissements_scolarite` — pas seulement par élève.**
Confirmé par lecture directe du code, pas par supposition :
- `encaissements_insert_gestion`/`encaissements_update_annulation`
  (migration `20260906001501...sql`, lignes 474-483) exigent
  `a_permission(etablissement_id, 'scolarite.encaissement.gerer')` ou
  `est_direction(etablissement_id)` — évalués sur la colonne
  `etablissement_id` de la ligne, jamais sur l'élève.
- `est_direction(p_etablissement)` (migration M1, ligne 298) et
  `a_permission` filtrent `etablissements_membres` sur
  `m.etablissement_id = p_etablissement` **exact** — un compte direction de
  l'établissement B n'a simplement aucune ligne d'appartenance pour
  l'établissement A, donc `est_direction(A)` est faux pour lui.
- `encaissements_select_visible` appelle `encaissement_visible(id)` (lignes
  250-259), qui teste `est_personnel(e.etablissement_id)` (même logique de
  filtre exact) **ou** `fiche_visible(e.fiche_eleve_id)` — cette dernière
  (migration M5, ligne 328) exige elle-même
  `est_personnel(f.etablissement_id)` (établissement du fiche, pas
  générique) **ou** être l'élève lui-même **ou** son parent confirmé.
- **Preuve par test, renforcée à cette occasion** : le test 38 ne couvrait
  jusqu'ici qu'un tiers non affilié à aucun établissement (§8c) — insuffisant
  pour prouver une isolation *inter-établissement* au sens strict.
  `tests/rls/38_m15quater_inscription_encaissement.sql` a été complété
  (section 9) avec un **second établissement réel**, doté de sa propre
  direction (`dir_b_id`) : la direction B ne voit pas l'encaissement de
  l'établissement A (assertion 9a) et ne peut pas y insérer un encaissement
  (42501, assertion 9b). 25 assertions au total désormais (était 18).

**b) Recalcul du solde à l'annulation + traçabilité qui/quand.**
- `solde_scolarite` (lignes 264-292) est une fonction **calculée à chaque
  appel** (CTE sur `sum(montant) where statut = 'valide'`) — jamais une
  colonne stockée. Un encaissement annulé (`statut = 'annule'`) sort
  mécaniquement de cette somme dès l'appel suivant : la « mise à jour » est
  automatique par construction, il n'y a pas de recalcul explicite à
  déclencher ni à oublier.
- `encaissements_verifie_immuable` (lignes 216-239) impose
  `new.annule_par := auth.uid()` et `new.annule_le := now()` **côté
  serveur**, uniquement à la transition `valide → annule`, en plus du motif
  saisi par le client (`motif_annulation`, obligatoire, sinon 23514).
- **Le test 38 ne couvrait jusqu'ici que le rejet d'une annulation sans
  motif (§8d)**, jamais le succès d'une annulation valide — c'est un vrai
  trou comblé à cette occasion : section 10 du test insère une annulation
  motivée, puis vérifie `statut = 'annule'`, `annule_par = dir_id`,
  `annule_le` non nul, et surtout que `solde_scolarite` redevient égal au
  tarif plein (`montant_paye = 0`, `solde = 1000000`) une fois le seul
  encaissement annulé.

**c) Test de bout en bout encaissement → PDF reçu, sur la même donnée.**
Le test existant (`test/features/export_pdf/recu_pdf_builder_test.dart`)
construisait un objet `EncaissementScolarite` **à la main** en Dart, puis le
passait au générateur de PDF — un test unitaire du rendu, pas une preuve que
la donnée *telle qu'elle reviendrait du serveur* survit intacte jusqu'au PDF.
Un test d'intégration au sens strict (insertion réelle en base, export
depuis cette même ligne) n'est pas réalisable sans instance Postgres
disponible (voir ci-dessous). En attendant, un test de chaîne a été ajouté
au même fichier : une ligne JSON snake_case **identique à ce que renverrait
Postgres** (colonnes de la migration `encaissements_scolarite`/
`fiches_eleves`) est désérialisée via `EncaissementScolarite.depuisJson`/
`FicheEleve.depuisJson` — le même chemin que `_exporterRecu()` dans
`ecran_encaissement_scolarite.dart` — puis passée telle quelle à
`construireRecuPdf`. Limite assumée : le test vérifie que la donnée
traverse la désérialisation sans altération et produit un PDF structurel
valide ; il ne relit pas le texte à l'intérieur du PDF généré (aucune
dépendance d'extraction de texte PDF n'est présente dans le projet —
ajouter une telle dépendance pour ce seul test a été jugé disproportionné,
à confirmer avec le porteur de projet si une preuve plus forte est exigée).

**Tentative d'installation Docker/Podman en local, avec preuve.**
Constat avant toute tentative : `docker`/`podman` absents du PATH ; le CLI
Supabase, lui, est déjà installé (`supabase 2.116.0`).

1. `winget --version` → `v1.29.280` (disponible).
2. `wsl --status` → *« Le Sous-système Windows pour Linux n'est pas
   installé. Vous pouvez effectuer l'installation en exécutant
   "wsl.exe --install". »* — **WSL2 absent**, prérequis du backend par
   défaut de Docker Desktop sur Windows.
3. Vérification des droits : la session d'exécution n'est **pas**
   administrateur (`IsInRole(Administrator)` → `False`).
4. Tentative réelle : `winget install --id Docker.DockerDesktop -e
   --accept-source-agreements --accept-package-agreements`. Sortie
   obtenue avant blocage :
   ```
   Trouvé Docker Desktop [Docker.DockerDesktop] Version 4.90.0
   Téléchargement en cours https://desktop.docker.com/win/main/amd64/238679/Docker%20Desktop%20Installer.exe
   ```
   Après 25 minutes d'exécution, le processus `winget.exe` n'affichait
   qu'un temps CPU cumulé de 3,7 s (quasi inactif) et aucun fichier
   partiel n'était visible sur le disque — un blocage silencieux, sans
   message d'erreur.
5. Diagnostic du blocage — mesure directe de la bande passante disponible
   vers l'hôte de téléchargement :
   `curl` vers cette même URL a reçu **212 992 octets sur 604 875 184**
   (la taille totale de l'installeur, ~577 Mo) en 15 secondes, soit
   environ **14 Ko/s**. À ce débit, le seul téléchargement prendrait de
   l'ordre de **12 heures**. Le réseau de ce poste (sandbox d'exécution)
   n'est donc pas coupé vers ce domaine, mais sévèrement bridé — un blocage
   de fait, pas un simple manque de tentative. Le processus a été arrêté
   (`Stop-Process`) plutôt que laissé tourner indéfiniment.
6. Podman a été écarté sans nouvelle tentative séparée : Podman Desktop sur
   Windows exige la même machine de virtualisation (WSL2 ou Hyper-V,
   ci-dessus absente) et la même élévation administrateur (ci-dessus
   indisponible dans cette session) — les deux blocages constatés aux
   points 2 et 3 s'appliquent identiquement, indépendamment du débit
   réseau.

**Conclusion honnête** : l'installation de Docker/Podman sur ce poste, dans
cette session, est **bloquée par trois facteurs indépendants et vérifiés**
(pas de droits administrateur, WSL2 non installé, débit réseau prohibitif
vers le CDN de Docker) — pas par un manque de tentative. Les 25 assertions
pgTAP des tests 38 (M15quater) et 31-33 (M14) restent donc **écrites mais
non exécutées localement**. Elles n'ont pas non plus pu être vérifiées via
la CI dans le cadre de cette demande (portée : exécution *locale*,
explicitement hors CI). Lever ce blocage demanderait soit des droits
administrateur + WSL2 pré-installé sur ce poste, soit un environnement
d'exécution avec accès réseau non bridé vers `desktop.docker.com`, soit une
alternative sans Docker (ex. Postgres natif Windows + extension pgTAP
installée manuellement) — à arbitrer avec le porteur de projet si la preuve
d'exécution locale reste requise avant le prochain push.

### 0.5 Déblocage Docker/Podman, première exécution locale réelle, deux patches RLS — **RÉSOLU** (2026-09-11)

> **Statut : corrigé et poussé sur `origin/main`.** Suite directe de §0.4,
> même soirée. Détail complet dans `docs/ETAT_PHASE_C.md` §4/§4bis/§4ter —
> résumé ici pour la traçabilité de l'audit.

**Déblocage** : les trois facteurs bloquants de §0.4 restent vrais pour
**Docker Desktop** (toujours bloqué — son installeur exige une élévation UAC
interactive, impossible en session automatisée, échec confirmé exit code
`4294967291`), mais **Podman CLI 5.8.3 s'installe et fonctionne sans
élévation**, et `podman machine start` (backend WSL2) a été rendu
fonctionnel sur ce poste — le réseau, lui, n'est plus bridé (mesuré à
~1,1 Mo/s contre ~14 Ko/s en §0.4).

**Conséquence directe** : `main` local avait alors 13 commits d'avance sur
`origin/main`, jamais poussés — la CI n'avait donc **jamais exécuté**
M15quater ni son test pgTAP. Première exécution réelle, nulle part avant
cette date : **échec** (13/25 assertions exécutées, 2 échecs explicites,
puis erreur RLS bloquante). Deux défauts trouvés et corrigés (policy UPDATE
`inscriptions` sans repli `est_direction()` ; policy SELECT
`encaissements_scolarite` auto-référentielle cassant `INSERT ...
RETURNING` pour tout le monde, y compris le vrai chemin de code de l'app) —
migration `20260906001502...sql`, test porté à 27 assertions, confirmé
27/27 puis **poussé vers `origin/main`** (commit `97ea026`).

**Recherche systémique immédiate** (même symptôme, autres tables) : demandée
et traitée en second patch, même urgence — voir `ANALYSE_GLOBALE.md` §4.4
« Patch transversal » et `docs/ETAT_PHASE_C.md` §4ter pour le détail
complet (méthode empirique table par table, tableau des 6 tables vérifiées,
5 corrigées dont 3 pour le défaut RETURNING et 2 pour le repli
`est_direction()` manquant, 1 saine). Migration
`20260906001503_patch_transversal_returning_et_repli_direction.sql`, 5 tests
de non-régression ajoutés, suite complète reconfirmée à 211/211 assertions.

**Point important pour la suite de cet audit** : la ressemblance de code
(une policy SELECT basée sur une fonction `xxx_visible(id)`
auto-référentielle) **ne prédit pas de façon fiable** si `INSERT ...
RETURNING` échoue — `sanctions` et `contrats` ont une forme quasi identique
à `encaissements_scolarite`/`notifications` mais n'avaient PAS ce défaut.
Toute correction future de ce type doit être vérifiée empiriquement,
table par table, pas généralisée par supposition.

### 0.6 M16 sous-livrable 3/7 — Edge Functions IA, `supabase functions serve` sans Deno CLI (2026-09-11)

Construction de l'architecture à 3 couches de `CHAT_IA_GROUNDING.md`
(déclenchement structuré → réponse groundée → détail nominatif pseudonymisé
via tool-use) côté EcoShop — voir `ANALYSE_GLOBALE.md` §4.4 pour le détail
complet. Point de méthode à retenir pour tout futur test d'Edge Function
sur ce poste : le CLI Deno autonome (`deno`) reste indisponible ici — deux
tentatives d'installation (npm, script officiel `install.ps1`) ont échoué,
la seconde pour la même raison que Docker Desktop en §0.4 (téléchargement
d'un binaire de ~40 Mo throttlé à ~15 Ko/s, jamais abouti). **Contournement
trouvé et validé, pas un contournement théorique** : `supabase functions
serve` fonctionne sans binaire Deno séparé — il réutilise le conteneur
`edge-runtime` déjà présent localement. Combiné à un serveur Node
jetable simulant l'API Anthropic (conteneur sur le même réseau podman,
`host.containers.internal`/l'IP de la gateway ne fonctionnant pas de
manière fiable depuis ce conteneur vers l'hôte Windows) et un JWT HS256
signé à la main (même secret que `supabase start`), ceci a permis une
vérification **de bout en bout réelle** (vrai réseau HTTP, vraie
authentification, vraie RLS, vrai Postgres) des deux Edge Functions et de
l'absence de fuite nominative vers l'appel Anthropic simulé — plus probant
qu'un test unitaire Deno mocké, obtenu malgré l'indisponibilité du CLI.

---

## 1. Méthode et limites

- Chaque module a été audité par lecture réelle du code des deux côtés (pas
  seulement des noms de fichiers) : écrans, services, modèles, règles
  Firestore côté source ; migrations SQL, RLS, contrats d'interface, écrans
  Flutter côté cible.
- Les choix déjà actés au cadrage v4.1 (suppression du panier multi-vendeur,
  bascule Firebase→Supabase, GSG ID en couche additive non bloquante) **ne sont
  pas listés comme des écarts** — ils sont déjà arbitrés.
- Le chantier « Port Paiement CinetPay complet » (webhooks, crédit réel) est
  explicitement replanifié en M16-M20 par `ANALYSE_GLOBALE.md` §4.4 : les écarts
  qui en dépendent strictement sont signalés mais pas comptés comme un manquement
  de M13/M14 pris isolément.
- Le module réseau/multi-établissement (`tableau_bord_reseau_screen.dart` côté
  source) est hors périmètre de M10 tel que défini par le contrat cible — signalé
  pour mémoire, non compté comme écart de M10.

---

## 2. M0 → M3 — Socle Supabase/Flutter, auth, fédération GSG ID

**Constat général** : le socle serveur (rôles à deux niveaux, RLS, anti-brute-force,
OTP multi-canal) est au moins équivalent, souvent supérieur à la source. Le trou
principal est **côté client** : des parcours entiers n'ont pas d'écran alors que
la RPC serveur existe déjà.

| Écart | Source | État cible | Impact | Recommandation proposée |
|---|---|---|---|---|
| Parcours d'entrée Enseignant/Direction/Vendeur/Fondateur réseau (code d'invitation, demande d'établissement, attente de validation) | `role_selection_screen.dart`, `invitation_code_screen.dart`, `demande_etablissement_screen.dart` | Absent — seuls Élève/Parent ont un parcours ; RPC `accepter_invitation`/`demandes_adhesion` livrées en SQL mais jamais appelées par le client | Élevé | **Implémenter maintenant** — travail serveur déjà prêt, seul le client manque |
| Décompte exact du verrouillage anti-brute-force (compte à rebours précis) | `liaison_eleve_helpers.js` (5 tentatives/30 min, verrouillage 15 min) | Dégradé — fenêtre glissante 1h sans verrouillage dédié, message client non chiffré | Faible | Différer — sécurité égale/supérieure, UX seulement |
| Plafond de comptes parents liés à une fiche élève | `MAX_PARENTS_LIES = 4` | Absent — aucune limite | Moyen | **Implémenter maintenant** — ajout simple, garde-fou anti-abus |
| Connexion alternative via GSG ID (bouton dédié) | `gsg_id_login_screen.dart` (documenté comme pilote expérimental, MFA jamais testée) | Absent — GSG ID = couche additive JWT uniquement, choix documenté à ANALYSE_GLOBALE.md §5.3 | Faible | **Abandonner** — choix d'architecture déjà assumé et documenté |
| Auto-gestion vendeur (statut parallèle non exclusif, self-service catalogue) | `DemandeVendeurScreen`, `validation_vendeurs_screen.dart` | Dégradé — `RoleRacine.vendeur` exclusif, RLS réservent l'écriture au back-office | Moyen | Différer — bascule de modèle déjà actée, parcours à construire (plutôt M13/M19) |

**Couvert sans écart notable** : modèle de rôles à deux niveaux (plus fin que la
source), sélection d'établissement actif multi-établissements, anti-brute-force
sur la liaison compte↔fiche (double facteur + anti-énumération + journal),
OTP E.164 multi-canal, sélecteur d'enfant parent, garde de session « compte
bloqué » (absente côté source). « Élève supervisé » n'a pas d'équivalent source
(nouveauté du cahier v4.1, pas une régression).

Rapport détaillé : voir archive de session (audit M0-M3).

---

## 3-4. M4 — Référentiel pédagogique CEDEAO / M5 — Administration & Scolarité

**Constat général** : M4 est une extension neuve sans équivalent construit côté
source (la source n'avait qu'une liste plate de niveaux, jamais enrichie en
référentiel multi-pays — 0/6 sur la feuille de route source elle-même). M5 en
revanche est aujourd'hui une **couche de consultation** côté cible, alors que la
source couvrait un cycle complet de gestion administrative et financière liée à
l'élève.

| Écart | Source | État cible | Impact | Recommandation proposée |
|---|---|---|---|---|
| Création d'une inscription (nouvel élève) | `inscription_screen.dart`, génération serveur de matricule, détection de double inscription, frais distinct de l'annuité | **Résolu** — RPC `creer_inscription_nouvel_eleve` (M15quater), matricule généré serveur, `ecran_creation_inscription.dart` | Élevé | **Corrigé** — voir `docs/contrats/M15quater_inscription_encaissement.md` |
| Réinscription annuelle avec vérifications automatiques (impayés, admission, sanction, boursier) | `reinscription_screen.dart` | **Résolu (3/4 vérifications)** — RPC `creer_reinscription`/`verifications_reinscription`, `ecran_reinscription.dart`. Vérification « admission classe supérieure » non couverte (§6 du contrat M15quater) | Élevé | **Corrigé pour l'essentiel** |
| Statut boursier annuel avec traçabilité (qui/quand) | `InscriptionModel.statutBoursier` | **Résolu** — `inscriptions.boursier` + trigger `inscriptions_verifie_boursier` (auteur/date automatiques), bascule dans `ecran_fiche_eleve.dart` | Moyen à élevé | **Corrigé** |
| Champs administratifs du dossier élève (filiation, quartier, contact d'urgence, redoublant, n° classe) | `EleveModel` | **Résolu** — colonnes ajoutées à `fiches_eleves`, dialogue d'édition dans `ecran_fiche_eleve.dart` | Moyen | **Corrigé** |
| Suivi financier consolidé sur la fiche élève (solde, historique paiements, PDF) | `fiche_eleve_screen.dart`, `FinancierService`, `PdfService.genererFicheEleve` | **Résolu à l'écran** — solde + historique d'encaissements dans `ecran_fiche_eleve.dart` (RPC `solde_scolarite`). **PDF de fiche complète non couvert** (seul le reçu par encaissement est exportable, voir §10) | Élevé | **Corrigé pour l'essentiel** |
| Historique des réinscriptions sur la fiche élève | `streamReinscriptionsEleve` | **Dégradé** — les réinscriptions apparaissent dans le même historique de classes que les inscriptions initiales, sans distinction visuelle | Faible isolément | Corrigé indirectement (visible dans l'historique), distinction fine différée |
| Paramètres établissement : tarification, paliers de paiement, activation paiement en ligne | `parametres_etablissement_screen.dart` | **Résolu (tarif par défaut + paliers)** — `ecran_parametres_financiers.dart`. Tarif **par niveau** supporté par le schéma mais pas encore par l'écran ; activation paiement en ligne différée (Port Paiement, M16-M20) | Élevé | **Corrigé pour l'essentiel** |
| Détection de double inscription inter-établissements (identifiant déterministe) | `genererIdentifiantGenere`, `verifierDoubleInscription` | **Résolu** — RPC `verifier_doublon_eleve` (booléen seul, confidentialité inter-établissement préservée), dialogue de confirmation dans `ecran_creation_inscription.dart` | Moyen | **Corrigé** |

**Couvert sans écart notable** : liaison parent↔fiche (RPC `lier_parent_a_fiche`,
anti-brute-force au moins aussi robuste), sélecteur multi-enfants, structure
classes/années/périodes (amélioration nette vs source), historique de classes,
référentiel pédagogique CEDEAO complet (M4, nouveauté sans risque de régression).

---

## 5. M6 — Notes & Évaluations

Voir aussi §0.2 pour le point prioritaire bulletins PDF.

| Écart | Source | État cible | Impact | Recommandation proposée |
|---|---|---|---|---|
| **Génération de bulletins PDF** | `pdf_service.dart` (mise en page A4 codée en dur, pas un système de gabarits paramétrable ; export individuel et par classe, impression) | **Résolu (individuel)** par M15ter — export/impression/partage PDF fonctionnel (`bulletin_pdf_builder.dart`). Reste absent : export groupé pour une classe entière (dépend du point 8 ci-dessous, non résolu) | Élevé | **Corrigé** pour l'export individuel — voir `docs/contrats/M15ter_export_pdf.md` |
| Génération administrative de bulletins pour toute une classe | `generation_bulletins_screen.dart`, `NotesService.genererBulletin()` | Absent côté UI — aucune RPC de calcul/composition automatique, aucun écran | Élevé | Implémenter maintenant — prérequis pour que l'export PDF ait un contenu |
| Rédaction d'appréciations (bulletin/matière) | Champ libre `appreciationGenerale` | Dégradé — modèle cible plus riche (table `appreciations` typée) mais **aucun écran ne l'utilise**, ni saisie ni affichage | Moyen | Implémenter un écran de saisie — la donnée existe déjà |
| Score de risque d'échec continu par élève (0-100, alimente un chatbot IA direction) | `NotesService.recalculerRisqueEchec()` | **Résolu — décision de convergence tranchée (M16, 2026-09-11)** : la source calcule 70 % tendance des moyennes + 30 % présence ; EcoShop a sa propre formule antérieure et déjà testée (`calculer_score_decrochage`, M7 : 50 % absences injustifiées + 20 % retards injustifiés + 30 % moyenne). **Choix assumé : ne pas importer la formule source.** `statistiques_agregats.risque_reussite` est désormais matérialisé (`materialiser_risque_reussite`, service_role) et exposé (`risque_reussite_actuel`, RLS revérifiée en interne) — voir migration `20260906001504_m16_materialisation_risque_reussite.sql` et `tests/rls/39_m16_risque_reussite.sql` | Moyen | **Corrigé** — la donnée existait déjà côté backend sans être matérialisée ni consommée ; ce n'est plus le cas |

**Couvert sans écart notable** : saisie de notes avec verrouillage progressif
(brouillon→publiée→clôturée, plus riche que le binaire source, hors-ligne natif
en prime), calcul des moyennes par RPC serveur, déverrouillage administratif
(absent des deux côtés — parité).

---

## 6. M7 — Absences & Vie scolaire

| Écart | Source | État cible | Impact | Recommandation proposée |
|---|---|---|---|---|
| Déclaration manuelle d'une sanction disciplinaire | `sanction_declaration_screen.dart` | Absent côté UI — le repository expose `proposerSanction()` mais aucun écran ne l'appelle ; seule la voie IA (validation d'une proposition) est exploitable | Élevé | **Implémenter maintenant** — écart suggérant un oubli, pas un choix délibéré |
| Changement de statut / levée d'une sanction | `VieScolaireService.leverSanction()` | Dégradé — `changerStatutSanction` existe côté data, aucun écran ne l'appelle | Moyen-élevé | Implémenter avec le point précédent (mêmes écrans) |
| Type de sanction « exclusion définitive » | `SanctionType.exclusionDefinitive` | Absent de l'enum cible (plus riche sur le volet éducatif, mais perd la sanction la plus sévère) | Moyen | À trancher — si le retrait est un choix « toute sanction est éducative », le documenter ; sinon ajouter la valeur (migration mineure) |
| Statut boursier / bourses | Vit côté source dans Administration/Financier, pas Vie scolaire | Absent au global — `ANALYSE_GLOBALE.md` mappe pourtant « bourses » du plan original vers M7 | Moyen | Différer et reclasser vers un futur module Scolarité/Financier |

**Couvert sans écart notable** : appel de classe et absences/retards (enrichi :
présent/absent/retard/exclu/dispense + hors-ligne, vs présent/absent seul côté
source), historique disciplinaire consultable élève/parent, alertes de
décrochage combinant notes et vie scolaire (nouveauté cible avec garde-fous
éthiques), événements scolaires (nouveauté, pas un écart).

---

## 7. M8 — RH & Personnel

| Écart | Source | État cible | Impact | Recommandation proposée |
|---|---|---|---|---|
| Paie — cycle complet (génération, primes, avances, validation/annulation avec restauration, PDF) | `RH_PAIE.md` intégral | **Fortement dégradé** — table unique `paie_bulletins` (montants bruts, pas d'entités primes/avances), pas d'état « annulé » avec restauration ; le port Flutter documente lui-même un report vers M14 qui **n'a pas eu lieu** (M14 livré ne contient aucune mention de paie) | Élevé | Implémenter maintenant si M14 ne comble pas ce trou (à vérifier) ; sinon documenter formellement ce report |
| Dossier personnel — documents, qualifications génériques, historique d'audit | Sous-collections `documents`/`qualifications`/`historique`, `typePersonnel` configurable | Absent — `categorie` figée en dur par CHECK, aucune table équivalente | Moyen | Différer si pas de module Transport à court terme ; l'historique d'audit reste recommandable indépendamment |
| Congés — états manquants, chevauchement non vérifié, admin-on-behalf autorisé côté RLS | Machine à états incluant annulé/révoqué, vérification de chevauchement, interdiction stricte admin-on-behalf | Dégradé sur 3 points : pas d'état annulé/révoqué distinct, pas de vérification de chevauchement, RLS `conges_insert_demande` autorise le RH à déposer une demande *pour* un employé (interdit côté source) | Moyen | Resserrer la policy RLS et ajouter la vérification de chevauchement — sauf si l'admin-on-behalf est un choix produit assumé, à confirmer |
| Liaison compte personnel par matricule (auto-service, dossier créé avant le compte) | `RH_PERSONNEL.md` §2/§6.5 | Absent — `employes.profile_id` est NOT NULL dès la création | Faible à moyen | À confirmer avec le porteur de projet, dépend du parcours d'onboarding global |

**Couvert sans écart notable** : dossier employé de base, contrats (enrichi de
types stage/prestataire), gate serveur de validation des congés, isolation
multi-tenant, IA RH (analyse effectifs, turn-over, remplacement — capacité
nouvelle et plus riche que la source).

---

## 8. M9 — Communication & Notifications

Voir [§0.1](#01-protection-des-mineurs-dans-les-conversations-de-classe--résolu-patch-de-sécurité-durgence)
pour le détail complet du patch de sécurité — **résolu**, plus une alerte
ouverte.

| Écart | Source | État cible | Impact | Statut |
|---|---|---|---|---|
| **Groupes de classe supervisés (7 règles absolues de protection des mineurs)** | Règles Firestore explicites : création serveur uniquement, adulte permanent, zéro MP élève↔élève, texte seul, modération réservée personnel, soft-delete, signalements dédiés | **Résolu** — schéma RLS complet (`20260906000901_m9_patch_securite_messagerie_groupe.sql`, 15 assertions pgTAP) + purge de la fuite locale à la déconnexion (`session_logout.dart`). Réserve : les écrans du prototype local ne sont pas encore raccordés à ce backend (§0.1) | **Élevé — sécurité** | **Corrigé** (voir §0.1) |
| Annonces d'établissement | `annonces_screen.dart`, RLS réservant la création au personnel admin | Absent en tant que fonctionnalité réelle — aucune table `annonces`, remplacé par un prototype local avec garde cosmétique non protégé par RLS | Moyen | Implémenter une vraie table + RLS (patron réutilisable de `templates_notifications`) avant de considérer M9 complet |
| Cahier de liaison parent-enseignant | — | Prototype local, mais correctement restreint parent/enseignant côté UI (contrairement à la Messagerie) | Faible à moyen | Différer sauf priorité égale aux annonces |

**Couvert sans écart notable** : notifications multicanal (SMS/WhatsApp/Email/Push),
préférences utilisateur, journal d'envois, verrouillage par trigger — couverts et
enrichis (IA descriptive/prédictive/prescriptive), RLS au moins aussi rigoureuse
que la source.

---

## 9. M10 — Rapports & Statistiques / M11 — Planification & Agenda / M12 — Observabilité

| Écart | Source | État cible | Impact | Recommandation proposée |
|---|---|---|---|---|
| Tableau de bord directeur consolidé (Finances+Scolarité) avec alertes proactives à seuil | `tableau_bord_directeur_screen.dart` | Absent — aucun indicateur financier, aucune alerte à seuil configurable, rien ne consolide les deux domaines | Élevé | Implémenter maintenant si le rôle direction est déjà actif — à confirmer la priorité |
| Bannière IA « élèves à risque » consolidée pour la direction | `dashboard_screen.dart _AiBanner` | **Résolu (M16, sous-livrable 2/7, 2026-09-11)** — indicateur `eleves_a_risque` ajouté à `consolider_indicateurs_etablissement` (seuil 0.6, identique à `generer_alertes_decrochage`), affiché en bannière IA dédiée `_BanniereRisque` sur `ecran_tableau_bord_rapports.dart` (extraite de la grille générique de KPI, pas un chiffre parmi d'autres — conforme au cahier). Écart non porté, documenté : le sous-compte « dontDonneeFiable » de la source n'a pas d'équivalent (`calculer_score_decrochage` ne porte aucun indicateur de fiabilité) | Moyen | **Corrigé** |
| Score de risque par élève (pas seulement par classe) | `risqueEchecActuel` par élève | **Résolu (M16, 2026-09-11)** — `statistiques_agregats.risque_reussite` est désormais matérialisé et exposé PAR ÉLÈVE (`risque_reussite_actuel(p_fiche)`), pas seulement agrégé par classe. `risque_classe()` (M10/M11) reste disponible séparément pour les besoins agrégés | Moyen | **Corrigé** |
| Tableau de bord réseau multi-établissements | `tableau_bord_reseau_screen.dart` | Absent, hors périmètre strict de M10 | Faible à moyen | Hors périmètre de cet audit — à traiter dans un futur audit réseau dédié |
| **Séances ponctuelles / annulation d'un cours un seul jour sans casser la récurrence** | Champs `type`/`statut`/`dateException` sur `emplois_du_temps` | **Absent** — seule `deleted_at` (suppression totale et définitive) existe côté cible | **Élevé** | **Implémenter maintenant** — cas d'usage quotidien réel (enseignant absent, salle indisponible, sortie scolaire) |
| Notification automatique en cas d'annulation de séance | `onSeancePonctuelleCreated` | Absent — conséquence directe du point précédent | Moyen | Implémenter avec le point précédent |
| Congé enseignant annulant automatiquement les cours concernés | Documenté dans `FONCTIONNALITES.md` | Absent — M8 (congés) et M11 (emploi du temps) totalement cloisonnés | Moyen | Différer — dépend des séances ponctuelles |
| Exclusion des séances qui se remplacent volontairement dans la détection de conflit (bug déjà corrigé côté source) | Correctif documenté | Sans objet actuellement, mais **risque de réintroduire ce bug** dès l'ajout des séances ponctuelles | — | Anticiper explicitement dans la spec du futur chantier séances ponctuelles |
| M12 — Observabilité | Aucun équivalent (recherche exhaustive : zéro résultat) | Module entièrement nouveau côté cible | Sans objet | Sans objet — nouveauté pure |

**Couvert sans équivalent notable ou correctement porté** : détection de
conflits d'occupation, résumé exécutif NLG, détection d'anomalies notes/absences,
recommandations stratégiques à validation humaine, rapports différés multi-formats
tolérants au hors-ligne, prédiction de charge horaire, vues de consultation par
rôle de l'emploi du temps.

---

## 10. M13 — Marketplace AssoShop / M14 — Comptabilité sans OHADA / M15 — Marketplace sans authentification

Voir §0.2 pour le point prioritaire reçus PDF — **retiré après une première
livraison, en attente de M15quater** (entité d'encaissement dédiée).

| Écart | Source | État cible | Impact | Recommandation proposée |
|---|---|---|---|---|
| **Génération de reçus PDF** (thermique 58mm + A4 annuel) | `pdf_service.dart` (`genererRecuThermique`, `genererRecuA4`) | **Résolu (format A4, par encaissement)** — reconstruit sur `EncaissementScolarite` (M15quater) après le retrait de la version M15ter adossée à `EcritureComptable`. Format thermique 58mm et récapitulatif annuel toujours absents | Élevé | **Corrigé pour l'essentiel** — voir `docs/contrats/M15quater_inscription_encaissement.md` |
| Attestations (scolarité/inscription/paiement) | **Absent aussi côté source** (recherche exhaustive négative) | Absent | Nul pour cet audit | Différer — hors périmètre des deux bases, à instruire comme nouveauté si besoin confirmé |
| **Encaissement de frais de scolarité** (écran dédié, solde élève, reçu automatique) | `paiement_screen.dart`, `cahier_journal_screen.dart` | **Résolu** — entité `encaissements_scolarite` dédiée, `ecran_encaissement_scolarite.dart`, `ecran_cahier_encaissements.dart`, solde calculé serveur (M15quater) | **Élevé** | **Corrigé** |
| Achat sans authentification (parcours invité) | Sans équivalent source (l'original exige toujours l'auth) | Absent côté client bien que le schéma SQL existe (`profils_publics`, `visiteur_id`) ; le code cible reconnaît lui-même que tout achat passe par l'OTP | Moyen à élevé | Différer/abandonner selon arbitrage produit — documenter le choix si l'OTP systématique est assumé |
| Auto-inscription vendeur avec validation GSG | `demande_vendeur_screen.dart` | Absent — onboarding vendeur 100% back-office | Moyen | Différer — à documenter comme choix arbitré si volontaire |
| Gestion catalogue et ventes côté vendeur (CRUD produits, onglet Ventes/portefeuille) | `mes_produits_screen.dart` | Absent | Élevé si rôle vendeur actif côté app | Différer — lié à l'arbitrage vendeur ci-dessus |
| **Gestion des stocks et anti-survente** | Champ `stock`, exclusion panier, statut `echecStock` | **Absent y compris en base** — `catalogues_produits` n'a aucune colonne de stock | **Élevé** | **Implémenter** — risque métier direct, indépendant du chantier paiement |
| Cycle de livraison en 2 étapes avec QR code (réception établissement + remise destinataire) | `reception_colis_screen.dart`, `remise_colis_screen.dart` | Absent — un seul palier de livraison | Moyen à élevé selon modèle logistique | Différer — à retravailler une fois le modèle de livraison clarifié |
| Restriction géographique acheteur/vendeur (badge « Hors zone ») | `_BandeauLocalisation` | Absent — `Commercant` cible n'a ni ville ni pays | Faible à moyen | Différer — pertinent seulement en déploiement multi-pays |
| Score de fiabilité vendeur (réputation) | `noteReputation` | Absent | Faible | Différer |
| SLA de livraison + remboursement automatique | `StatutCommande.rembourseeSla` | Absent | Moyen | Différer — à traiter avec le chantier paiement M16-M20 |

**Couvert sans écart notable** : catalogue, panier mono-vendeur (choix acté),
confirmation/suivi/détail commande, sous-comptes marchands par établissement,
détection d'anomalies de commandes par IA (nouveauté), comptabilité générale en
partie double (changement de paradigme plus rigoureux que la source, voir le
lien manquant avec l'encaissement élève ci-dessus), saisie tolérante hors-ligne.

---

## 11. Table récapitulative des recommandations « implémenter maintenant »

Ces écarts ont été proposés en priorité haute par les agents d'audit (impact
utilisateur élevé, coût de mise en œuvre raisonnable ou brique serveur déjà
prête) — **à confirmer un par un avec le porteur de projet** :

1. Parcours d'entrée Enseignant/Direction/Vendeur/Fondateur réseau (M0-M3) — **arbitré (carnet de gouvernance, répercuté ici le 2026-09-12) : différé, dette tracée, cible M2/M3**
2. Plafond de comptes parents liés à une fiche élève (M0-M3) — **arbitré (carnet de gouvernance, répercuté ici le 2026-09-12) : différé, dette tracée avec le mécanisme anti-brute-force existant (ch. 5.8), cible un futur module d'accueil (numéro de module pas encore attribué)**
3. ~~Création d'inscription + détection de double inscription (M5)~~ — **corrigé** (M15quater)
4. ~~Export PDF des bulletins~~ — **corrigé** (M15ter, export individuel). Reste : génération de bulletins pour une classe entière (M6) — **en cours d'arbitrage, voir `ANALYSE_GLOBALE.md` §4.4, M16 sous-livrable 6/7**.
5. Déclaration manuelle et changement de statut d'une sanction disciplinaire (M7) — **en cours d'arbitrage, voir `ANALYSE_GLOBALE.md` §4.4, M16 sous-livrable 6/7**.
6. Paie RH — vérifier si M14 comble le trou annoncé, sinon implémenter (M8) — **arbitré (carnet de gouvernance, répercuté ici le 2026-09-12) : différé, dette tracée, cible M8bis**
7. ~~Protection des mineurs — table serveur + RLS pour les groupes de classe~~ — **corrigé** (patch de sécurité d'urgence, voir §0.1). Reste : raccorder l'écran du prototype local à ce nouveau backend — **en cours d'arbitrage, voir `ANALYSE_GLOBALE.md` §4.4, M16 sous-livrable 6/7**.
8. Tableau de bord directeur consolidé Finances+Scolarité (M10) — **en cours d'arbitrage, voir `ANALYSE_GLOBALE.md` §4.4, M16 sous-livrable 6/7**. Distinct du « tableau de bord réseau multi-établissements » ci-dessus (hors périmètre de cet audit, futur audit réseau dédié) : celui-ci consolide Finances+Scolarité pour UN SEUL établissement, l'autre agrège PLUSIEURS établissements pour un rôle réseau.
9. Séances ponctuelles / annulation d'un cours (M11) — **arbitré (carnet de gouvernance, répercuté ici le 2026-09-12) : différé, dette tracée sous « planification », cible M11**
10. ~~Écran d'encaissement de frais de scolarité + reçu PDF (M13/M14)~~ — **corrigé** (M15quater : entité `encaissements_scolarite` dédiée, reçu PDF reconstruit dessus — voir §0.2).
11. Gestion des stocks et anti-survente (M13) — **arbitré (carnet de gouvernance, répercuté ici le 2026-09-12) : différé, dette tracée avec le stock marketplace, cible M15**

---

## 12. Prochaine étape

Ce rapport doit être examiné par le porteur de projet, écart par écart. Les
décisions (implémenter maintenant / différer vers quel module / abandonner et
pourquoi) sont reportées dans `ANALYSE_GLOBALE.md` §4.4 au fur et à mesure.
M15bis (thèmes internationaux & dark mode) n'était pas concerné par le
blocage transversal de M16 et a été traité en parallèle (cf.
`docs/contrats/M15bis_themes_dark_mode.md`).

**M15quater — Inscription, réinscription & encaissement de scolarité** est
livré (cf. `docs/contrats/M15quater_inscription_encaissement.md`) : création
d'inscription, réinscription, statut boursier, champs administratifs de la
fiche élève, paramètres établissement (tarifs/paliers), détection de double
inscription, et l'entité d'encaissement de scolarité dédiée qui a permis de
reconstruire le reçu PDF retiré de M15ter (§0.2). 261 tests Flutter passent,
`flutter analyze` propre ; 25 assertions pgTAP écrites, isolation
inter-établissement et annulation tracée vérifiées par preuve de code et
tests renforcés (§0.4) ; installation locale de Docker/Podman tentée et
bloquée par trois facteurs vérifiés (§0.4) — non exécutées localement, non
plus par manque de tentative.

**Statut de l'arbitrage au 2026-09-12** (mise à jour suite à une vérification
croisée avec le carnet de gouvernance du porteur de projet, en parallèle de
la clôture de M16 sous-livrable 5/7 — voir `ANALYSE_GLOBALE.md` §4.4) : sur
les 9 écarts non pleinement résolus listés ci-dessus, **5 avaient déjà été
arbitrés ailleurs** (carnet de gouvernance) mais jamais répercutés dans ce
document ni dans `ANALYSE_GLOBALE.md` — c'est désormais fait (items 1, 2, 6,
9, 11 ci-dessus, tous différés avec une cible). **Les 4 restants (items 4
reste, 5, 7 reste, 8) sont en cours d'arbitrage explicite dans le cadre de
M16 sous-livrable 6/7** (rapport d'écart global de clôture de M16), avec un
paragraphe de contexte dédié à chacun avant décision — voir
`ANALYSE_GLOBALE.md` §4.4.

---

## Annexe — Références de fichiers précises (source ↔ cible)

Chemins exacts relevés lors de l'audit, pour vérification directe par le
porteur de projet. Racine source : `C:\Users\delam\ProjetsFlutter\ecoshop_flutter`.
Racine cible : `C:\Users\delam\PlatformGSG\EcoShop`.

### M0 → M3 — Socle

| Écart | Fichiers `ecoshop_flutter` (source) | Fichiers/éléments EcoShop (cible) |
|---|---|---|
| Parcours d'entrée rôles à privilège | `lib/features/auth/screens/role_selection_screen.dart`, `invitation_code_screen.dart`, `direction_choix_screen.dart`, `demande_etablissement_screen.dart`, `en_attente_validation_screen.dart` | `apps/client_flutter/lib/features/auth/presentation/ecran_choix_role.dart`, `ecran_choix_espace.dart`, `.../auth/domain/destination_session.dart` (`GardeSession.resoudre`) ; RPC serveur `accepter_invitation`/`demandes_adhesion` déjà dans `supabase/migrations/20260906000300_m2_auth_federation.sql`, jamais appelées côté client |
| Décompte anti-brute-force imprécis | `functions/liaison_eleve_helpers.js` | `supabase/migrations/20260906000300_m2_auth_federation.sql` (`lier_compte_a_fiche`) ; `apps/client_flutter/lib/features/auth/application/connexion_controller.dart` |
| Plafond de comptes parents liés | `functions/liaison_eleve_helpers.js` (`MAX_PARENTS_LIES = 4`) | `supabase/migrations/20260906000500_m5_administration_scolarite.sql` lignes 372-431 (`lier_parent_a_fiche`) |
| Connexion GSG ID | `lib/features/auth/screens/gsg_id_login_screen.dart`, `lib/services/gsg_kernel_client.dart`, `GSG_KERNEL_PILOTE.md` | `apps/client_flutter/lib/features/auth/presentation/ecran_connexion.dart` (OTP seul) ; `ANALYSE_GLOBALE.md` §5.3 |
| Auto-gestion vendeur | doc de `role_selection_screen.dart`, `DemandeVendeurScreen`, `lib/features/gsg_backoffice/screens/validation_vendeurs_screen.dart`, `CommercantModel` | `supabase/migrations/20260906001300_m13_marketplace_assoshop.sql` lignes 310-328 (RLS `commercants`/`catalogues_produits`) |

### M4 → M5 — Référentiel & Administration/Scolarité

| Écart | Fichiers source | Fichiers/éléments cible |
|---|---|---|
| Création d'inscription | `lib/features/administration/screens/inscription_screen.dart`, `lib/models/eleve_model.dart` (`genererIdentifiantGenere`), `FirestoreService.creerInscriptionServeur` | `apps/client_flutter/lib/features/scolarite/domain/scolarite_repository.dart` (aucune méthode de création) ; `supabase/migrations/20260906000500_m5_administration_scolarite.sql` |
| Réinscription annuelle | `lib/features/administration/screens/reinscription_screen.dart`, `lib/models/inscription_model.dart` (`ReinscriptionModel`) | absent |
| Statut boursier | `lib/features/administration/screens/fiche_eleve_screen.dart` (`_basculerStatutBoursier`), `InscriptionModel.statutBoursier` | table `inscriptions`, `docs/contrats/M05_administration_scolarite.md` §2 |
| Champs administratifs dossier élève | `lib/models/eleve_model.dart` (`numeroClasse`, `nomPere`, `nomMere`, `quartier`, `personneUrgenceNom`, `personneUrgenceTelephone`, `redoublant`), `fiche_eleve_screen.dart` | table `fiches_eleves`, `docs/contrats/M05_administration_scolarite.md` §2 |
| Suivi financier fiche élève | `fiche_eleve_screen.dart`, `lib/services/financier_service.dart`, `lib/services/pdf_service.dart` (`genererFicheEleve`) | `apps/client_flutter/lib/features/scolarite/presentation/ecran_fiche_eleve.dart` (pas de section financière) |
| Historique réinscriptions | `fiche_eleve_screen.dart` (`streamReinscriptionsEleve`) | absent |
| Paramètres établissement (tarifs, paliers) | `lib/features/administration/screens/parametres_etablissement_screen.dart` | `apps/client_flutter/lib/features/etablissement/` (aucun écran équivalent), aucune table `frais_config`/`paliers_config` |
| Détection double inscription | `lib/models/eleve_model.dart` (`genererIdentifiantGenere`), `FirestoreService.verifierDoubleInscription`, Cloud Function `creerInscriptionInterne` | absent |

### M6 → M7 — Notes/Évaluations & Vie scolaire

| Écart | Fichiers source | Fichiers/éléments cible |
|---|---|---|
| **Bulletins PDF** | `lib/services/pdf_service.dart` (`genererBulletinA4`, `genererBulletinsClasseA4`, `_contenuBulletin`, `imprimer`), `lib/features/notes/screens/bulletin_screen.dart`, `generation_bulletins_screen.dart` | **Résolu (export individuel)** : `apps/client_flutter/lib/features/export_pdf/data/bulletin_pdf_builder.dart`, bouton d'export dans `ecran_bulletins.dart`. Génération groupée par classe toujours absente |
| Déclaration manuelle de sanction | `lib/features/vie_scolaire/screens/sanction_declaration_screen.dart`, `VieScolaireService.declarerSanction()` | `apps/client_flutter/lib/features/vie_scolaire/domain/vie_scolaire_repository.dart` (`proposerSanction` inutilisé), `.../presentation/ecran_sanctions.dart` |
| Changement de statut de sanction | `VieScolaireService.leverSanction()`, `sanction_declaration_screen.dart` (`_SanctionTile`) | `vie_scolaire_repository.dart`/`data/supabase_vie_scolaire_repository.dart` (`changerStatutSanction` inutilisé) |
| Exclusion définitive | `lib/models/vie_scolaire_model.dart` (`enum SanctionType`) | `type_sanction` (enum), `supabase/migrations/20260906000700_m7_absences_vie_scolaire.sql`, `docs/contrats/M07_absences_vie_scolaire.md` |
| Bourses | `lib/models/inscription_model.dart` (`statutBoursier`), `lib/services/firestore_service.dart` (`definirStatutBoursier`), `reinscription_screen.dart`, `fiche_eleve_screen.dart`, `pdf_service.dart` | absent, `docs/contrats/M07_absences_vie_scolaire.md` |
| Appréciations | `generation_bulletins_screen.dart` (`BulletinModel.appreciationGenerale`), `bulletin_screen.dart` | `apps/client_flutter/lib/features/notes/domain/appreciation.dart`, `data/notes_repository.dart` (aucun écran dans `presentation/`) |
| Score de risque continu par élève | `lib/services/notes_service.dart` (`recalculerRisqueEchec`, `_calculerRisque`) | **Résolu (M16)**, formule propre non importée — table `statistiques_agregats` (`type_agregat='risque_reussite'`, migration M6), matérialisée par `materialiser_risque_reussite`/exposée par `risque_reussite_actuel` (`supabase/migrations/20260906001504_m16_materialisation_risque_reussite.sql`) ; `apps/client_flutter/lib/features/vie_scolaire/presentation/ecran_suivi_vie_scolaire.dart` (alertes_decrochage, en complément) |
| Génération de bulletins pour une classe | `lib/features/notes/screens/generation_bulletins_screen.dart`, `NotesService.genererBulletin()` | absent, `supabase/migrations/20260906000600_m6_notes_evaluations.sql` |

### M8 → M9 — RH & Communication

| Écart | Fichiers source | Fichiers/éléments cible |
|---|---|---|
| **Protection des mineurs — messagerie de groupe** | `lib/features/communication/screens/groupe_chat_screen.dart` (lignes 181-192), `creer_groupe_screen.dart`, `gestion_groupe_screen.dart`, `traitement_signalements_screen.dart` ; `firestore/firestore.rules` lignes 1093-1224 (1123 `allow create: if false`, 1135-1145 update restreint, 1165-1176 messages texte seul, 1182-1189 soft-delete, 1216-1224 signalements) | **Résolu par le patch de sécurité de ce rapport** (cf. §0.1 mis à jour) : `supabase/migrations/20260906000901_m9_patch_securite_messagerie_groupe.sql`, `apps/client_flutter/lib/features/coquille/application/session_logout.dart`. Prototype local pré-patch : `apps/client_flutter/lib/features/communication/prototype/domain/entree_communication_locale.dart` (lignes 12-19), `data/communication_locale_repository.dart`, `presentation/ecran_messagerie_prototype.dart` (lignes 16-100), `presentation/ecran_annonces_prototype.dart` (lignes 22-24), `coquille_app.dart` (lignes 331-338, 354) |
| Annonces d'établissement | `lib/features/communication/screens/annonces_screen.dart`, `creer_annonce_screen.dart`, `lib/services/annonce_service.dart` | `apps/client_flutter/lib/features/communication/prototype/presentation/ecran_annonces_prototype.dart` (local uniquement) ; aucune table `annonces` dans `supabase/migrations/20260906000900_m9_communication_notifications.sql` |
| Cahier de liaison | (voir §8, hors focus prioritaire de cet audit) | `apps/client_flutter/lib/features/communication/prototype/presentation/ecran_cahier_liaison_prototype.dart` |
| Paie — cycle complet | `RH_PAIE.md`, `lib/features/rh/screens/generer_bulletin_paie_screen.dart`, `bulletin_paie_detail_screen.dart`, `primes_etablissement_screen.dart`, `avances_etablissement_screen.dart`, `bulletins_paie_etablissement_screen.dart`, Cloud Functions `paie.js`/`paie_helpers.js` | table `paie_bulletins` (`supabase/migrations/20260906000800_m8_rh_personnel.sql`) ; `apps/client_flutter/lib/features/rh_personnel/data/rh_repository.dart` lignes 30-32/53 (lecture seule, report annoncé vers M14) ; `supabase/migrations/20260906001400_m14_comptabilite_sans_ohada.sql` (aucune mention paie, report non tenu) |
| Dossier personnel — documents/qualifications/historique | `RH_PERSONNEL.md` §1-6 | table `employes` (`supabase/migrations/20260906000800_m8_rh_personnel.sql`, `categorie` figée par CHECK) |
| Congés — états, chevauchement, admin-on-behalf | `RH_CONGES.md` | enum `statut_conge`, policy `conges_insert_demande` (migration M8, ~lignes 642-647) ; `apps/client_flutter/lib/features/rh_personnel/presentation/ecran_conges.dart` ligne 27 (`peutDemander`, filtre d'affichage seulement) |
| Liaison compte personnel par matricule | `RH_PERSONNEL.md` §2/§6.5 | `employes.profile_id` `NOT NULL` (migration M8, ligne 69) |

### M10 → M12 — Rapports, Planification, Observabilité

| Écart | Fichiers source | Fichiers/éléments cible |
|---|---|---|
| Tableau de bord directeur consolidé | `lib/features/reporting/screens/tableau_bord_directeur_screen.dart`, Cloud Function `obtenirTableauBordDirecteur`, `TABLEAU_BORD_DIRECTEUR.md` §2-3 | `apps/client_flutter/lib/features/rapports/presentation/ecran_tableau_bord_rapports.dart`, `supabase/migrations/20260906001000_m10_rapports_statistiques.sql` (`indicateurs_cles`) |
| Bannière IA « élèves à risque » | `lib/features/dashboard/screens/dashboard_screen.dart` (`_AiBanner`), `TABLEAU_BORD_DIRECTEUR.md` §3bis | **Résolu (M16)** : indicateur `eleves_a_risque` (`consolider_indicateurs_etablissement`, migration `20260906001505_m16_banniere_eleves_a_risque.sql`), bannière `_BanniereRisque` (`apps/client_flutter/lib/features/rapports/presentation/ecran_tableau_bord_rapports.dart`). RPC `risque_classe` (migration M10/M11 §7.3) reste l'agrégat par classe, séparé |
| Score de risque par élève (pas classe) | `lib/services/notes_service.dart` (`recalculerRisqueEchec`) | **Résolu (M16)** — `risque_reussite_actuel(p_fiche)` (migration `20260906001504_m16_materialisation_risque_reussite.sql`), par élève, en plus de RPC `risque_classe(p_classe)` (agrégé classe) |
| Tableau de bord réseau | `lib/features/reseau/screens/tableau_bord_reseau_screen.dart` | aucun dossier `reseau` côté cible |
| Séances ponctuelles / annulation | doc `EMPLOI_DU_TEMPS.md` §2 (champs `type`/`statut`/`dateException`), `seance_form_screen.dart`, `FONCTIONNALITES.md` ligne 73 | table `emplois_du_temps` (`supabase/migrations/20260906001100_m11_planification_agenda.sql`), `apps/client_flutter/lib/features/planification/domain/emploi_du_temps.dart` |
| Notification d'annulation de séance | `functions/emploi_du_temps.js` (`onSeancePonctuelleCreated`), `FONCTIONNALITES.md` lignes 76/100 | absent (conséquence du point précédent) |
| Congé enseignant → annulation cours | `FONCTIONNALITES.md` ligne 127 | aucun lien entre `20260906000800_m8_rh_personnel.sql` et `20260906001100_m11_planification_agenda.sql` |
| Exclusion séance de remplacement (anti-bug conflit) | doc `EMPLOI_DU_TEMPS.md` §2 | RPC `detecter_conflits_emploi` (migration M11 §8.2) |
| M12 Observabilité | aucun équivalent (recherche négative) | `supabase/migrations/20260906001200_m12_observabilite.sql` |

### M13 → M15 — Marketplace & Comptabilité

| Écart | Fichiers source | Fichiers/éléments cible |
|---|---|---|
| **Reçus PDF** | `lib/services/pdf_service.dart` (`genererRecuThermique`, `genererRecuA4`, `imprimer`), `lib/features/financier/screens/recu_screen.dart` | **Résolu.** Livré une première fois par M15ter (`recu_pdf_builder.dart`, adossé à `EcritureComptable`), puis **retiré** avant tout push, puis **reconstruit** (M15quater) sur `EncaissementScolarite` — `apps/client_flutter/lib/features/export_pdf/data/recu_pdf_builder.dart` |
| Attestations | absent côté source (recherche négative) | absent (pas une régression) |
| **Encaissement de scolarité** | `lib/features/financier/screens/paiement_screen.dart`, `recu_screen.dart`, `cahier_journal_screen.dart`, `lib/services/financier_service.dart` | `apps/client_flutter/lib/features/comptabilite/` (comptabilité générale seulement), `docs/M13_ASSOSHOP_MARKETPLACE.md` §7 (promis, non livré), `supabase/migrations/20260906001400_m14_comptabilite_sans_ohada.sql` |
| Achat sans authentification | sans équivalent source | schéma présent (`supabase/migrations/20260906001500_m15_marketplace_sans_auth.sql` : `profils_publics`, `paniers.visiteur_id`) mais `apps/client_flutter/lib/features/marketplace/domain/panier.dart` (commentaire : parcours anonyme non couvert) |
| Auto-inscription vendeur | `lib/features/marketplace/screens/demande_vendeur_screen.dart` | RLS `supabase/migrations/20260906001300_m13_marketplace_assoshop.sql` §4 (`commercants`/`catalogues_produits` réservés back-office) |
| Gestion catalogue/ventes vendeur | `lib/features/marketplace/screens/mes_produits_screen.dart`, `produit_form_screen.dart` | `apps/client_flutter/lib/features/marketplace/presentation/ecran_produits_commercant.dart` (vue acheteur), `ecran_sous_comptes_marchands.dart` (vue établissement) |
| Stock / anti-survente | `models/produit_model.dart` (champ `stock`), `panier_screen.dart`, `enum StatutCommande.echecStock` | table `catalogues_produits` (migration M13, aucune colonne stock) |
| Livraison 2 étapes QR | `lib/features/marketplace/screens/suivi_commande_screen.dart`, `reception_colis_screen.dart`, `remise_colis_screen.dart` | `enum StatutCommande` cible (`expediee`/`livree` seulement), aucune dépendance QR/scanner |
| Restriction géographique | `catalogue_screen.dart` (`_BandeauLocalisation`), `produit_detail_screen.dart` (`_CarteVendeur`) | `apps/client_flutter/lib/features/marketplace/domain/commercant.dart` (pas de ville/pays) |
| Réputation vendeur | `produit_detail_screen.dart` (`_CarteVendeur`), `models/commercant_model.dart` | absent |
| SLA de livraison | `demande_vendeur_screen.dart`, `enum StatutCommande.rembourseeSla` | absent |
