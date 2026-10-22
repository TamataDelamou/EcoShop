# Tests RLS — Phase A (pgTAP)

Suite de tests **pgTAP** couvrant les **6 points RLS prioritaires** identifiés
dans `docs/ETAT_PHASE_A.md`. Ces scripts sont autonomes (chaque fichier crée ses
propres données puis annule tout par `ROLLBACK`) et prêts à être exécutés dès que
l'outillage Postgres/Supabase sera disponible.

## Couverture

| Fichier | Point contrôlé | Correspondance |
|---|---|---|
| `01_anti_elevation.sql` | Escalade de privilège impossible via `UPDATE` direct ; rôle fixé uniquement par `choisir_role_racine()`, restreint aux rôles auto-inscriptibles | C1 |
| `02_recursion_rls.sql` | Lecture des tables multi-tenant sans récursion RLS (`42P17`) | C2 |
| `03_hook_jwt.sql` | `custom_access_token_hook()` émet réellement `app_metadata.role_racine` ; n'émet plus `app_metadata.gsg_id` (KER-MUT K1), y compris hérité d'un ancien jeton ; colonne `gsg_id` supprimée, trigger de protection de `profiles` toujours opérant | C3 / KER-MUT K1 |
| `04_anti_brute_force.sql` | `lier_compte_a_fiche()` verrouille après 5 échecs/heure, même avec de bons identifiants | C4 / ch. 5.8 |
| `05_isolation_multi_tenant.sql` | Un membre ne voit que les données de ses propres établissements | multi-tenant |
| `06_invitations.sql` | Une invitation nominative n'est acceptée que par son destinataire | ch. 5.2 |
| `07_m5_isolation_structures.sql` | Isolation multi-tenant des structures M5 (périodes, classes, inscriptions, fiches) | M5 |
| `08_m5_lien_parent.sql` | Liaison parent ↔ élève : double facteur, rôle requis, visibilité limitée à l'enfant | M5 |
| `09_m5_affectations.sql` | Visibilité des affectations (enseignant, direction, élève exclu) | M5 |
| `10_m6_notes_visibilite.sql` | Visibilité des notes/évaluations (élève, parent, personnel, étranger) | M6 |
| `11_m6_saisie_notes.sql` | Saisie des notes : auteur, permission, non-auteur, clôture | M6 |
| `12_m6_evaluations_ecriture.sql` | Création d'évaluations (affecté seulement) + moyenne pondérée | M6 |
| `13_m7_presences_visibilite.sql` | Visibilité présences/retards/sanctions (élève, parent, personnel, étranger) | M7 |
| `14_m7_pointage_droits.sql` | Droits de pointage (affecté/scolarité) + visibilité des alertes | M7 |
| `15_m7_ia_fonctions.sql` | Fonctions IA : score décrochage, recommandation, prédiction de présence | M7 |
| `16_m8_rh_visibilite.sql` | Visibilité RH (direction voit tout, employé son dossier, isolation multi-tenant) | M8 |
| `17_m8_conges_validation.sql` | Congés : dépôt, interdiction d'auto-validation, validation humaine, retrait | M8 |
| `18_m8_ia_rh.sql` | Fonctions IA RH : score de turn-over, effectifs, formation, remplacements | M8 |
| `19_m9_notifications_visibilite.sql` | Visibilité des notifications (destinataire, direction, isolation multi-tenant) | M9 |
| `20_m9_notifications_lecture.sql` | Lecture/écriture : marquage « lue », intégrité du contenu, envoi direction | M9 |
| `21_m9_ia_comm.sql` | Fonctions IA communication : canal, timing, sentiment, A/B, taux de lecture | M9 |
| `22_m10_rapports_visibilite.sql` | Visibilité des rapports (personnel, parent, élève, étranger) + KPI réservés personnel | M10 |
| `23_m10_ia_fonctions.sql` | Fonctions IA M10 : consolidation, anomalies, risque classe, recommandation, résumé NLG | M10 |
| `24_m10_anomalies_validation.sql` | Validation humaine des anomalies et recommandations (permission administration) | M10 |
| `25_m11_emplois_visibilite.sql` | Visibilité des emplois du temps et de l'agenda (personnel, élève, parent, étranger) | M11 |
| `26_m11_ia_planification.sql` | Fonctions IA M11 : placement, conflits, charge, recommandation de séances | M11 |
| `27_m11_contraintes_ecriture.sql` | Permissions d'écriture de la planification (generer/administrer) | M11 |
| `28_m13_visibilite_catalogue.sql` | Visibilité catalogue (public) + isolation des sous-comptes marchands | M13 |
| `29_m13_panier_mono_vendeur.sql` | Garde-fou panier mono-vendeur (rejet d'un produit d'un autre commerçant) | M13 |
| `30_m13_commandes_paiement.sql` | Visibilité des commandes + cohérence fournisseur/sous-compte de paiement | M13 |
| `31_m14_plans_journaux.sql` | Visibilité/isolation du plan comptable et des journaux | M14 |
| `32_m14_ecritures.sql` | Saisie d'écritures + garde-fous (tenant, débit ≠ crédit) | M14 |
| `33_m14_fonctions_comptables.sql` | Journal, Grand Livre, Balance + détection d'anomalies | M14 |
| `34_m15_profils_publics.sql` | Profils publics invités (jeton, complétion, RLS fermée) | M15 |
| `35_m15_catalogue_public.sql` | Catalogue marketplace public (parcours invité sans auth) | M15 |
| `36_m15_panier_invite.sql` | Panier/commande invités (propriétaire = profil public) | M15 |
| `37_m9_patch_messagerie_groupe.sql` | Patch de sécurité — 7 règles absolues de protection des mineurs sur la messagerie de groupe (membre/parent/non-membre, création réservée adulte, modération, signalements) | M9 (patch) |
| `38_m15quater_inscription_encaissement.sql` | Création d'inscription (matricule serveur, permission), doublon, réinscription (contrainte unique), statut boursier tracé, paliers ≤ 100 %, solde scolaire serveur, encaissement (auteur forcé, visibilité, immutabilité, annulation motivée), isolation inter-établissement réelle (2 établissements distincts), annulation valide (succès + traçabilité + recalcul de solde) | M15quater |
| `49_facturation_entitlement_etablissement.sql` | Entitlement établissement (licence Pro/frais IA admin) : garde `est_admin_gsg()` anti-NULL, angle mort auto-déclaration par la direction concernée, isolation inter-établissements, barème par tranche | Facturation étape (a) |
| `50_facturation_cinetpay_generique.sql` | Brique CinetPay générique : frontière service_role (GRANT/REVOKE, pas `est_appel_service()` — inutilisable dans une fonction elle-même SECURITY DEFINER), recalcul serveur du montant, fonctions privées jamais appelables directement, rejet signature/écart de montant (statut echoue), rejeu webhook idempotent (aucun double crédit), recompte d'effectif EN DIRECT au crédit (jamais la valeur périmée capturée à l'initiation), isolation inter-établissements | Facturation étape (b) |
| `51_facturation_abonnement_premium_eleve.sql` | Abonnement Premium élève (flux individuel) : garde initiation refusant tiers/personnel de l'établissement/admin GSG, succès élève lui-même (même mineur) ET parent confirmé payant pour un autre enfant (payeur ≠ bénéficiaire jamais confondus), contrainte CHECK `transactions_cinetpay_coherence` (rejet même en bypass RLS), RLS `abonnements_premium_eleve` élève/parent/admin GSG mais PAS le personnel de l'établissement, renouvellement anticipé qui empile la durée (jamais un reset perdant du temps déjà payé), idempotence webhook, asymétrie assumée de la policy select (payeur voit, bénéficiaire distinct ne voit pas), RPC manuelle admin GSG | Facturation étape (c) |
| `52_facturation_quota_tuteur_ia.sql` | Quota Tuteur IA : contournement direct via INSERT brut dans `ai_messages` (jamais via `envoyer_message_ia`) bloqué par le trigger, frontière exacte `compte >= limite` (19e/20e acceptés, 21e refusé sur quota 20), anti-rafale universel même frontière, abonnement Premium actif -> quota périodique LEVÉ entièrement (25 messages, aucun refus), portée strictement élève+conversation libre (scan_exercice et chat libre non-élève y échappent), message assistant jamais compté, `verifier_quota_ia` appelée directement (pré-contrôle Edge Function), `detecter_anomalies_usage_ia` (garde personnel/admin_gsg, isolation inter-établissement, seuil) | Facturation étape (d) — chantier clos |
| `53_journalisation_audit.sql` | Journalisation et audit : visibilité PAR ENTITÉ déléguée à la règle déjà établie sur la table source (jamais une règle uniforme) — 2 anti-régressions explicites (congé refusé à un employé quelconque non-RH/non-intéressé ; signalement refusé à un membre du personnel non modérateur du groupe), asymétries assumées répliquées telles quelles (transaction CinetPay individuelle invisible à la direction, abonnement Premium invisible au personnel, commande visible à l'acheteur même non-membre), cycle de transitions répétées sur congé ET sanction (chaque transition captée, symétrie levée/annulation), copie de signalement inchangée après suppression du message source (vraie copie, pas une FK), immutabilité totale (UPDATE/DELETE sans effet même pour l'admin GSG et la direction de l'établissement concerné), isolation inter-établissement, `enregistrer_audit()` refusée en appel direct même par l'admin GSG, garde "is distinct from" prouvée silencieuse (colonne non suivie sans effet sur le journal) | Journalisation et audit (§34.3) — chantier clos |
| `54_cgu_consentement_generique.sql` | CGU / consentement générique : lecture publique des versions courantes, acceptation réservée au profil lui-même (insert), immutabilité du registre (aucune policy update/delete), publication réservée admin_gsg, `cgu_statut()` sans ligne pour un rôle non choisi ou un rôle plateforme (admin_gsg/admin_contenu, hors périmètre), bascule de version qui invalide l'acceptation précédente (nouvelle version = non accepté tant que non re-signée) | Bloquant lancement, item 1/4 (§34.10) |
| `55_verrou_definitif_notes_et_mention_examen.sql` | Verrou définitif des notes + mention finale : `definir_mention_finale` réservée à la Direction et bloquée par classe déjà examen/déjà proclamée, `proclamer_classe` exige mention posée sur tous les élèves actifs d'une classe d'examen, verrou total de `peut_saisir_notes`/`generer_bulletins_classe` après proclamation SANS exception admin_gsg, immutabilité totale de `proclamations_classes` (aucune policy update/delete, y compris admin_gsg), isolation inter-établissement, visibilité personnel/admin_gsg uniquement | Bloquant lancement, item 2/4 (§12.3, §12.4, §7.3) |
| `56_validation_vendeur_etablissement_marketplace.sql` | Validation vendeur (GSG, palier 1) + agrément établissement↔vendeur (Direction, palier 2) : `valider_vendeur` réservée admin_gsg, `decider_agrement_vendeur_etablissement` réservée à la Direction de l'établissement concerné ET bloquée tant que le vendeur n'est pas déjà validé GSG, porte RLS `commandes_insert` qui exige les deux paliers `valide` (`vendeur_actif_pour_etablissement`), isolation inter-établissement, visibilité personnel/admin_gsg/appel service | Bloquant lancement, item 3/4 (§27.1-27.2, §30.1-30.2) |
| `57_kernel_control_plane.sql` | Reporting vers le Control Plane du Kernel : aucune fonction `kernel_*` appelable par anon/authenticated, curseurs invisibles hors admin GSG, minimisation (jamais `ancienne_valeur`/`nouvelle_valeur`/`fiche_eleve_id`/`groupe_id` exportés), délai de sécurité de 2 min, export incrémental sans doublon ni perte, curseur qui ne recule jamais, départage numérique des id de métriques à horodatage égal, agrégats de `kernel_metriques_cles()` | KER-MUT K2/K3 |
| `58_orange_money_gn.sql` | Orange Money Guinée (circuit établissement) : activation réservée à la Direction de l'établissement concerné, identifiants illisibles par tout client (Direction comprise), payeur limité à l'élève/parent confirmé (ni tiers ni personnel), montant borné par le solde serveur et entier en GNF, une seule transaction en cours, aucune écriture directe, isolation inter-établissement, crédit réservé à service_role, écart de montant refusé, encaissement `mobile_money` créé (saisi_par = payeur) et solde recalculé, notification rejouée sans double crédit, journalisation ; marketplace : seul l'acheteur paie, montant = total + frais, paiement `orange_money_gn` + commande `payee`, échec sans crédit | REG-02 L1-L4 |
| `59_orange_money_relance_rapprochement.sql` | Relance et rapprochement Orange Money : fonctions de relance réservées à service_role, abandon des seules initiations orphelines (> 30 min sans jeton), sélection des transactions à revérifier (délai minimal, marquage anti-double-passage, signalement > 24 h), rapprochement réservé au personnel de l'établissement, totaux confirmés, aucune anomalie en nominal, détection d'un encaissement OM sans transaction et d'une annulation après coup | REG-02 L7 |
| `60_identite_visuelle_etablissement.sql` | Identité visuelle : `definir_identite_visuelle` réservée à la Direction de l'établissement concerné, couleur normalisée `#RRGGBB` (format invalide refusé, contrainte en base), logo obligatoirement dans le dossier de l'établissement, bucket public limité à 1 Mo, dépôt Storage autorisé dans son dossier et refusé ailleurs (autre établissement, nom mal formé, parent) | REG-07 B |
| `61_demande_creation_etablissement.sql` | Création d'établissement : soumission par un compte neuf (refus élève/parent), une seule demande en cours, pays et téléphone contrôlés, aucune écriture directe, visibilité limitée au demandeur, traitement réservé à l'admin GSG, refus motivé obligatoire, acceptation qui crée l'établissement (devise/langue/fuseau du pays, identifiant lisible), fait du demandeur la Direction rattachée avec établissement actif, demande non traitable deux fois, nouvelle demande possible après refus | REG-04 |
| `66_etats_financiers.sql` | États financiers : compte de résultat SYSCOHADA (TC, RK, RL, XI), actif immobilisé brut/amortissements/net, trésorerie, capital, résultat au passif, équilibre actif = passif, aucun compte hors rubriques, tableau de trésorerie ; produits constatés d'avance (aperçu au prorata de l'année scolaire, pièce au 31/12, extourne au 1er janvier, une seule fois, résultat corrigé, 477 au passif, équilibre maintenu, 477 soldé après extourne) ; tendances et doublons sur pièces, prévision de trésorerie ; SYCEBNL (présentation provisoire équilibrée) ; simplifié ; parent refusé | REG-03 C4 |
| `67_paie_comptabilisation.sql` | Paie → comptabilité : brouillon sans pièce ; validé → constatation 661/422/447 datée de fin de période (journal PAIE, libellé mois + salarié) ; payé → règlement 422/571, dette soldée ; idempotence ; prime corrigée → contre-passation des deux pièces et nouvelles pièces au bon montant ; retour en brouillon, archivage, suppression définitive → contre-passation ; sans exercice : paie acceptée, incident, état « paies à synchroniser », rattrapage ; SYCEBNL 66/422/44 ; pièce non annulable à la main ; fonction interne inaccessible ; simplifié sans règles : rien | REG-03 C5 |
| `68_registre_donateurs.sql` | Dons et donateurs : comptes SYCEBNL de la générosité chargés ; reçus numérotés par année ; don D 571 / C 7041, quête Orange Money 5521/7044, parrainage 7047 ; projet à fonds affectés C 165, emploi D 165 / C 7925 au journal OD, fonds insuffisants et emploi hors projet refusés, type de campagne figé ; annulation motivée → contre-passation et audit, double annulation refusée, dons immuables et sans écriture directe, donateur ayant donné non supprimable ; date future, nature, montant ; 2025 sans exercice → incident ; tableau de bord (total, année précédente, nouveaux, fidèles, à relancer, campagnes, meilleurs donateurs, retard de parrainage) ; reçu et relevé ; parent refusé ; SYSCOHADA 758 après rattrapage ; simplifié sans règles : registre seul | REG-03 C5 |
| `69_flux_tresorerie_notes_annexes.sql` | Tableau des flux : SYSCOHADA indirect (CAFG, créances, passif circulant, acquisition, capital, emprunt et remboursement, variation, clôture = bilan, écart nul, rapprochement avec les flux pièce par pièce, ligne de contrôle masquée) ; exercice suivant : ouverture par à-nouveaux sans flux fictif, colonne N-1 ; SYCEBNL direct (générosité, autres revenus, fournisseurs, personnel, acquisition, fonds affectés en fonds propres, emploi des fonds sans flux) ; simplifié ; notes annexes (immobilisations, créances, trésorerie, produits, personnel, méthodes ; SYCEBNL générosité, fonds affectés, intitulés) ; notes rédigées, rubriques contrôlées, figées après clôture ; parent refusé ; calcul interne inaccessible | REG-03 C5 |
| `70_changement_plan_historique.sql` | Changement de plan SYSCOHADA → SYCEBNL au 1/1/2027 : choix direct refusé, exercice vierge exigé, même plan refusé, parent refusé ; correspondances proposées (table connue, identique, même numéro à vérifier, rattachement, sous-compte), soldes, corrections (sous-compte gardé, cible non imputable / hors plan / hors changement refusées) ; application : archives des états 2026 publiés, pièces intactes, anciens comptes renumérotés, saisie refusée dessus, sous-compte recréé, règle réorientée, note sur le changement ; historique retraité (résultat inchangé, équilibre, balance, à-nouveaux, N-1 comparable, tableau des flux) ; écritures automatiques dans le nouveau plan ; double application refusée | REG-03 C6 |
| `71_comptabilite_hors_ligne.sql` | Saisies hors connexion rejouées : don envoyé deux fois avec la même clé d'appareil → un seul don, un seul reçu définitif, une seule écriture ; numéro provisoire et date de saisie conservés et rappelés sur le reçu ; numérotation continue ; clé d'une autre école refusée ; brouillard créé sous la clé de l'appareil, renvoyé modifié (même pièce), validé en ligne puis jamais retouché ; rejeu en période clôturée refusé sans rien créer ; parent refusé | REG-03 C7 |
| `72_inscriptions_en_ligne.sql` | Campagne réservée à la Direction, places par niveau ; réinscription par le parent (niveau suivant, frais, place réservée) et par l'élève lui-même dès le collège (payeur enregistré), refusée à l'élève de primaire ; impayé → « à examiner », jamais bloqué ; nouvel élève : pièces réclamées puis déposées, acceptation, liste d'attente, retrait → promotion ; second envoi de la même clé, clé d'un autre compte refusée, saisie hors connexion avant la date limite reçue après ; offre expirée ; frais payés par Orange Money (montant de l'école) → inscription et encaissement ; guichet → fiche et lien parent ; pièces et dossiers confidentiels | REG-08 |
| `73_pointage_portail_sms.sql` | Réglages et cartes réservés au personnel habilité, jetons illisibles des parents ; scans : préfixe QR, à l'heure / en retard (heure locale de l'école), renvoi idempotent, doublon < 2 min, carte inconnue, autre école refusée ; avis push aux parents ou à l'élève autonome ; sortie anticipée → alerte + SMS (sortie autorisée exclue), crédit décompté puis rendu si échec ; absences : rien tant que le portail n'a pas transmis, puis seulement l'élève non pointé (pas l'absent justifié), une fois par jour ; tableau du jour ; relances (tranche échue, payeur, SMS, une fois par semaine) ; pack payé par CinetPay → crédits ; jetons push | REG-09 |
| `74_encaissements_hors_ligne.sql` | Numéro de reçu continu par école et par année, attribué par le serveur ; encaissement saisi sans réseau : numéro provisoire et heure de saisie gardés ; renvoi de la même clé = déjà reçu ; ni le renvoi ni un refus ne consomment de numéro ; numéro immuable ; numérotation propre à chaque école ; parent refusé | REG-10 |
| `75_mise_en_service.sql` | Tâches quotidiennes de toutes les écoles actives (année courante, école suspendue sautée, serveur seulement) ; contrôle de préparation réservé à l'équipe GSG, sans aucune valeur secrète ; packs SMS sans prix signalés ; 8 tâches planifiées attendues | Mise en service |
| `65_comptabilisation_automatique.sql` | Écritures automatiques : encaissement accepté sans exercice avec incident consigné, rattrapage idempotent et incident résolu, pièce validée (journal CAI/OM, comptes 571/5521 et 70521/70522, date du paiement), une seule pièce par encaissement (index unique), annulation → contre-passation motivée, pièce automatique non annulable à la main, période clôturée signalée sans bloquer, état (non comptabilisés, incidents, comptes effectifs), règle vers un compte de regroupement refusée et sous-compte utilisé ensuite, parent refusé, fonction interne inaccessible, simplifié sans règles sans pièce ni incident | REG-03 C3 |
| `64_pieces_exercices_clotures.sql` | Pièces et clôtures : exercices (année civile OHADA, premier libre, contiguïté, chevauchement, droits), saisie (hors exercice, compte de regroupement, ligne à deux sens ou négative, parent refusé), brouillard multi-lignes sans numéro et corrigeable, validation équilibrée, numérotation continue sans trou, irréversibilité (fonctions et accès direct, lignes comprises), saisie M14 fermée en OHADA, contre-passation négative motivée unique et non ré-annulable, journal/grand livre/balance intégrant les pièces, clôture de période (brouillards bloquants, dates figées), clôture d'exercice par la Direction (résultat, à-nouveaux AN validés, exercice suivant créé, balance d'ouverture, produits remis à zéro, exercice clôturé intouchable), plan simplifié (écritures M14 figées en période close, compte 13), fonctions internes inaccessibles, isolation | REG-03 C2 |
| `63_referentiel_comptable.sql` | Référentiel comptable : recommandation (confessionnelle/association → SYCEBNL, société sous/au-dessus du seuil SMT, seuil GNF « à confirmer », refus de comptabilité réglementaire respecté mais signalé), choix réservé à la Direction de l'établissement, aucune écriture directe, chargement complet du plan de référence avec arborescence et sous-comptes EcoShop, anciens comptes libres retirés, comptes réglementaires ni renommables ni supprimables, sous-compte obligatoirement rattaché (nature et parent hérités), SMT ↔ normal possible malgré des écritures, changement de plan refusé avec écritures, retour au simplifié, historique | REG-03 C1 |
| `62_notifications_sortantes.sql` | File d'envoi des courriels : accusé de réception (adresse de la demande prioritaire sur celle du compte, normalisée), alerte à l'équipe GSG, messages d'acceptation et de refus motivé, aucun message sans adresse, idempotence par événement, file et fonctions inaccessibles à `authenticated`, réservation sous bail sans double prise, succès, échec temporaire reprogrammé, échec définitif, plafond de 6 tentatives, purge à 90 jours, indicateurs | REG-04 |

## Prérequis

1. **Migrations appliquées** : `20260904000000_core_schema.sql`,
   `20260906000100_fix_core_security.sql`, `20260906000200_m1_schema_avance.sql`,
   `20260906000300_m2_auth_federation.sql`, `20260906000400_m4_referentiel_pedagogique.sql`,
   `20260906000500_m5_administration_scolarite.sql`, `20260906000600_m6_notes_evaluations.sql`,
   `20260906000700_m7_absences_vie_scolaire.sql`, `20260906000800_m8_rh_personnel.sql`,
   `20260906000900_m9_communication_notifications.sql`,
   `20260906000901_m9_patch_securite_messagerie_groupe.sql`,
   `20260906001000_m10_rapports_statistiques.sql`,
   `20260906001100_m11_planification_agenda.sql`,
   `20260906001200_m12_observabilite.sql`,
   `20260906001300_m13_marketplace_assoshop.sql`,
   `20260906001400_m14_comptabilite_sans_ohada.sql`,
   `20260906001500_m15_marketplace_sans_auth.sql`,
   `20260906001501_m15quater_inscription_encaissement.sql`
   (dans cet ordre).
2. **Extension pgTAP installée** : `create extension if not exists pgtap;`
   (`supabase test db` l'installe automatiquement).
3. **Rôle d'exécution superutilisateur** (`postgres`) : les tests simulent les
   appels clients via `SET LOCAL ROLE authenticated` + `request.jwt.claims`,
   ce qui exige de pouvoir changer de rôle.

## Exécution

### Option A — `pg_prove` (Postgres accessible)

```bash
# PG* : variables de connexion vers la base du projet
export PGHOST=localhost PGPORT=54322 PGDATABASE=postgres PGUSER=postgres
pg_prove tests/rls/*.sql
```

### Option B — `supabase test db` (CLI Supabase + Docker)

Copier les fichiers sous `supabase/tests/rls/`, puis :

```bash
supabase test db --linked
```

### Option C — fichier par fichier (psql)

```bash
psql -v ON_ERROR_STOP=1 -f tests/rls/01_anti_elevation.sql
```

## Conventions des scripts

- Chaque script s'exécute dans une transaction (`BEGIN` / `ROLLBACK`) : aucune
  donnée résiduelle après passage.
- Le helper `pg_temp.creer_compte(phone, role)` crée un compte `auth.users` ;
  le trigger `handle_new_user` génère le profil associé. C'est le point unique
  d'adaptation si le schéma `auth.users` local diffère.
- La simulation d'un utilisateur connecté se fait par :
  `SET LOCAL ROLE authenticated;` puis
  `SELECT set_config('request.jwt.claims', json_build_object('sub', <uuid>, 'role', 'authenticated')::text, true);`
- Un script qui échoue ne doit jamais laisser un état modifié : tout est
  remis à zéro par le `ROLLBACK` final.
