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

### 0.1 Protection des mineurs dans les conversations de classe — **ALERTE SÉCURITÉ**

Contrairement à ce que l'on pourrait supposer d'un simple report de fonctionnalité,
ce n'est pas seulement une fonctionnalité manquante : c'est une **régression de
sécurité active**.

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

### 0.2 Génération de documents depuis des modèles (bulletins, reçus, attestations)

- **Bulletins** (M6) : absents des deux côtés en tant que « système de modèles »
  paramétrable — mais la source avait au moins un **export PDF codé en dur**
  (mise en page A4, impression). La cible n'a **aucune capacité d'export** : le
  bulletin est un simple affichage écran d'un champ JSON.
- **Reçus de paiement** (M13/M14) : la source génère un reçu thermique 58 mm à
  chaque encaissement et un reçu A4 annuel ; la cible n'a **aucune dépendance
  PDF/impression** et aucun écran de reçu. Le propre document cible
  (`docs/COMPTABILITE.md` §9) reconnaît ce trou et le renvoie à un « M14
  complément ou M20 ».
- **Attestations** (scolarité/inscription/paiement) : recherche exhaustive côté
  source — **cette fonctionnalité n'existe pas dans ecoshop_flutter non plus**.
  Ce n'est donc pas une régression, mais une fonctionnalité à instruire comme
  nouvelle si le besoin est confirmé.

**Recommandation** : traiter l'export PDF des bulletins et des reçus comme un
chantier prioritaire avant mise en production réelle en établissement — ce sont
des usages quotidiens (remise au parent, archivage, impression) dans le contexte
visé. Détail complet en [§6](#6-m6--notes--évaluations) et [§13-15](#13-15-m13-marketplace-assoshop--m14-comptabilité--m15-marketplace-public).

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
| Création d'une inscription (nouvel élève) | `inscription_screen.dart`, génération serveur de matricule, détection de double inscription, frais distinct de l'annuité | Absent — `ScolariteRepository` n'a aucune méthode de création, aucune RPC dédiée | Élevé | Implémenter maintenant si M5 doit devenir opérationnel — sinon différer explicitement |
| Réinscription annuelle avec vérifications automatiques (impayés, admission, sanction, boursier) | `reinscription_screen.dart` | Absent — aucun concept de réinscription distinct | Élevé | Implémenter, une fois les briques financier/vie scolaire disponibles |
| Statut boursier annuel avec traçabilité (qui/quand) | `InscriptionModel.statutBoursier` | Absent du schéma `inscriptions` | Moyen à élevé | Différer vers futur module financier ; signaler dès maintenant dans le contrat M05 |
| Champs administratifs du dossier élève (filiation, quartier, contact d'urgence, redoublant, n° classe) | `EleveModel` | Absent — M5 n'ajoute que sexe/lieu de naissance/nationalité/statut/est_supervise | Moyen | Implémenter à moindre coût (colonnes supplémentaires) lors d'une prochaine itération |
| Suivi financier consolidé sur la fiche élève (solde, historique paiements, PDF) | `fiche_eleve_screen.dart`, `FinancierService`, `PdfService.genererFicheEleve` | Absent — aucun module financier/paiement élève dans le monorepo cible | Élevé | Différer vers futur module « Financier/Paiements élève » dédié, assumé et planifié |
| Historique des réinscriptions sur la fiche élève | `streamReinscriptionsEleve` | Absent — conséquence directe du point réinscription | Faible isolément | Traiter avec la réinscription |
| Paramètres établissement : tarification, paliers de paiement, activation paiement en ligne | `parametres_etablissement_screen.dart` | Absent — aucun écran ni table équivalente | Élevé | Différer vers le même chantier financier |
| Détection de double inscription inter-établissements (identifiant déterministe) | `genererIdentifiantGenere`, `verifierDoubleInscription` | Absent — conséquence de l'absence de création d'inscription | Moyen | Implémenter avec la création d'inscription, comme règle serveur |

**Couvert sans écart notable** : liaison parent↔fiche (RPC `lier_parent_a_fiche`,
anti-brute-force au moins aussi robuste), sélecteur multi-enfants, structure
classes/années/périodes (amélioration nette vs source), historique de classes,
référentiel pédagogique CEDEAO complet (M4, nouveauté sans risque de régression).

---

## 5. M6 — Notes & Évaluations

Voir aussi [§0.2](#02-génération-de-documents-depuis-des-modèles-bulletins-reçus-attestations)
pour le point prioritaire bulletins PDF.

| Écart | Source | État cible | Impact | Recommandation proposée |
|---|---|---|---|---|
| **Génération de bulletins PDF** | `pdf_service.dart` (mise en page A4 codée en dur, pas un système de gabarits paramétrable ; export individuel et par classe, impression) | **Absent** — aucune dépendance `pdf`/`printing`, aucun bouton d'export ; le bulletin cible n'est qu'un affichage écran du JSON | **Élevé** | **Implémenter en priorité** si un document imprimable est requis en usage réel |
| Génération administrative de bulletins pour toute une classe | `generation_bulletins_screen.dart`, `NotesService.genererBulletin()` | Absent côté UI — aucune RPC de calcul/composition automatique, aucun écran | Élevé | Implémenter maintenant — prérequis pour que l'export PDF ait un contenu |
| Rédaction d'appréciations (bulletin/matière) | Champ libre `appreciationGenerale` | Dégradé — modèle cible plus riche (table `appreciations` typée) mais **aucun écran ne l'utilise**, ni saisie ni affichage | Moyen | Implémenter un écran de saisie — la donnée existe déjà |
| Score de risque d'échec continu par élève (0-100, alimente un chatbot IA direction) | `NotesService.recalculerRisqueEchec()` | Dégradé/différent — la table `statistiques_agregats.risque_reussite` existe côté serveur mais n'est référencée nulle part côté client ; remplacé en pratique par les alertes de décrochage (M7), plus actionnables mais différentes | Moyen | Différer une décision de convergence — clarifier si les alertes M7 remplacent intégralement l'ancien score |

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

Voir [§0.1](#01-protection-des-mineurs-dans-les-conversations-de-classe--alerte-sécurité)
pour le détail complet du point prioritaire protection des mineurs — **alerte
de sécurité, pas un simple écart fonctionnel.**

| Écart | Source | État cible | Impact | Recommandation proposée |
|---|---|---|---|---|
| **Groupes de classe supervisés (7 règles absolues de protection des mineurs)** | Règles Firestore explicites : création serveur uniquement, adulte permanent, zéro MP élève↔élève, texte seul, modération réservée personnel, soft-delete, signalements dédiés | **Absent côté serveur** — aucune table `conversations`/`messages`/`groupes_discussion`/`signalements` ; remplacé par un prototype 100% local sans restriction de rôle, avec fuite de données entre comptes successifs sur appareil partagé (clé de cache `'global'` non isolée) | **Élevé — sécurité** | Ne pas exposer davantage à un rôle élève tant qu'aucune contrepartie serveur n'existe ; à documenter comme blocage de sécurité explicite, décision au porteur de projet |
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
| Bannière IA « élèves à risque » consolidée pour la direction | `dashboard_screen.dart _AiBanner` | Dégradé — donnée existe en base (`risque_reussite`) mais aucun écran ne l'agrège en compteur direction | Moyen | Différer — trancher d'abord si ce KPI vit dans M10 ou M6 |
| Score de risque par élève (pas seulement par classe) | `risqueEchecActuel` par élève | Dégradé — `risque_classe()` cible n'est qu'agrégé par classe | Moyen | Différer — vérifier si `statistiques_agregats` est déjà exploité ailleurs |
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

Voir [§0.2](#02-génération-de-documents-depuis-des-modèles-bulletins-reçus-attestations)
pour le point prioritaire reçus PDF.

| Écart | Source | État cible | Impact | Recommandation proposée |
|---|---|---|---|---|
| **Génération de reçus PDF** (thermique 58mm + A4 annuel) | `pdf_service.dart` (`genererRecuThermique`, `genererRecuA4`) | **Absent** — aucune dépendance `pdf`/`printing`, aucun écran de reçu ; gap reconnu par `docs/COMPTABILITE.md` §9 lui-même | **Élevé** | **Implémenter** — besoin quotidien de caisse, indépendant de l'intégration CinetPay complète |
| Attestations (scolarité/inscription/paiement) | **Absent aussi côté source** (recherche exhaustive négative) | Absent | Nul pour cet audit | Différer — hors périmètre des deux bases, à instruire comme nouveauté si besoin confirmé |
| **Encaissement de frais de scolarité** (écran dédié, solde élève, reçu automatique) | `paiement_screen.dart`, `cahier_journal_screen.dart` | **Absent** — M14 livré est une comptabilité générale en partie double pure, sans solde élève ni lien automatique paiement→écriture ; le périmètre annoncé (« M14 — Paiement, reçus, encaissements scolarité ») n'a pas été livré tel quel | **Élevé** | **Implémenter** — fonctionnalité cœur de métier ; à cadrer (nouveau module vs extension M14) |
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

1. Parcours d'entrée Enseignant/Direction/Vendeur/Fondateur réseau (M0-M3)
2. Plafond de comptes parents liés à une fiche élève (M0-M3)
3. Création d'inscription + détection de double inscription (M5)
4. Export PDF des bulletins + génération de bulletins pour une classe entière (M6)
5. Déclaration manuelle et changement de statut d'une sanction disciplinaire (M7)
6. Paie RH — vérifier si M14 comble le trou annoncé, sinon implémenter (M8)
7. Protection des mineurs — table serveur + RLS pour les groupes de classe, **avant toute exposition élargie** (M9 — sécurité, pas une priorité produit ordinaire)
8. Tableau de bord directeur consolidé Finances+Scolarité (M10)
9. Séances ponctuelles / annulation d'un cours (M11)
10. Écran d'encaissement de frais de scolarité + reçu PDF (M13/M14)
11. Gestion des stocks et anti-survente (M13)

---

## 12. Prochaine étape

Ce rapport doit être examiné par le porteur de projet, écart par écart. Les
décisions (implémenter maintenant / différer vers quel module / abandonner et
pourquoi) seront reportées dans `ANALYSE_GLOBALE.md` §4.4 au fur et à mesure.
**M16 (IA à rôles) reste bloqué tant que cet arbitrage n'a pas eu lieu.**
M15bis (thèmes internationaux & dark mode) n'est pas concerné par ce blocage et
est traité en parallèle (cf. `docs/contrats/M15bis_themes_dark_mode.md`).
