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
| `03_hook_jwt.sql` | `custom_access_token_hook()` émet réellement `app_metadata.role_racine` et `app_metadata.gsg_id` | C3 |
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
| `38_m15quater_inscription_encaissement.sql` | Création d'inscription (matricule serveur, permission), doublon, réinscription (contrainte unique), statut boursier tracé, paliers ≤ 100 %, solde scolaire serveur, encaissement (auteur forcé, visibilité, immutabilité, annulation motivée) | M15quater |

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
