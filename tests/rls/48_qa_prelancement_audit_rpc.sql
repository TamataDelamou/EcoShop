-- ============================================================================
-- EcoShop — Test RLS 48 : QA pré-lancement — audit sécurité RPC (toutes RPC)
--
-- Non-régression pour chaque défaut trouvé lors du balayage systématique
-- (voir migration 20260906001513) :
--   (a) fonctions sans AUCUNE vérification d'autorisation ;
--   (b) anti-patron NULL (`IF NOT a_permission(...)`/dérivées sans
--       `coalesce(..., false)`), reproduit avec un compte authentifié dont
--       `role_racine` n'est PAS encore choisi (`sans_role_id` ci-dessous) —
--       état normal d'un compte fraîchement créé, PAS un cas exotique.
--
-- Chaque correctif est vérifié dans les deux sens qui ont fait leurs preuves
-- sur solde_scolarite (D6) : un tiers sans lien est refusé, ET un compte
-- légitime d'un AUTRE établissement est refusé (pas seulement un tiers
-- total — l'angle mort qui avait laissé passer le bug D6 au départ).
--
-- Les 9 fonctions comptables (M14) partagent l'exact même garde
-- (`est_comptable`/`est_comptable_ecriture`) : 3 représentatives sont
-- testées ici (lecture simple, écriture, agrégat IA) plutôt que les 9
-- individuellement (relecture de code confirmant l'identité du patron pour
-- les 6 autres, cf. rapport). Même choix pour le trio M7
-- (analyse_comportement/calculer_score_decrochage représentatifs de
-- recommander_sanction_educative, garde strictement identique).
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.creer_compte(p_phone text, p_role text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public, auth, pg_catalog
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, phone) VALUES (v_id, p_phone);
  IF p_role IS NOT NULL THEN
    UPDATE public.profiles SET role_racine = p_role::public.role_racine WHERE id = v_id;
  END IF;
  RETURN v_id;
END;
$$;

SELECT plan(43);

-- ---------------------------------------------------------------------------
-- Fixture : deux établissements réels, comptes de tous types.
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('48000000-0000-0000-0000-000000000001', 'École QA A', 'ecole-qa-a');
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('48000000-0000-0000-0000-000000000099', 'École QA B (isolation)', 'ecole-qa-b');

INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('48000000-0000-0000-0000-000000000002', '48000000-0000-0000-0000-000000000001', '2026-2027', '2026-10-01', '2027-06-30', true);

INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom)
VALUES ('48000000-0000-0000-0000-000000000003', '48000000-0000-0000-0000-000000000001',
        '48000000-0000-0000-0000-000000000002', '6A-QA', '6e A');

INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance)
VALUES ('48000000-0000-0000-0000-000000000004', '48000000-0000-0000-0000-000000000001',
        'QA-00001', 'TRAORE', 'Awa', '2013-05-01');

INSERT INTO public.inscriptions (id, etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES ('48000000-0000-0000-0000-000000000005', '48000000-0000-0000-0000-000000000001',
        '48000000-0000-0000-0000-000000000004', '48000000-0000-0000-0000-000000000003',
        '48000000-0000-0000-0000-000000000002', 'active');

INSERT INTO public.journaux (id, etablissement_id, code, intitule)
VALUES ('48000000-0000-0000-0000-000000000006', '48000000-0000-0000-0000-000000000001', 'BQ', 'Banque');

-- Fiche « bruit » de l'établissement B, sans aucun lien avec la classe A
-- testée ci-dessous — reproduit les conditions exactes qui ont laissé
-- passer la régression classer_eleves_classe()/calculer_moyenne_classe()
-- corrigée par les migrations 20260906001516/20260906001517 (le
-- planificateur pouvait évaluer calculer_moyenne_eleve() sur cette fiche
-- AVANT le filtre de classe, faisant échouer injustement l'appelant
-- légitime de la classe A). Sans cette fiche, fiches_eleves n'aurait qu'une
-- seule ligne et le bug resterait invisible, comme il l'a été jusqu'ici.
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance)
VALUES ('48000000-0000-0000-0000-000000000008', '48000000-0000-0000-0000-000000000099',
        'QA-B-00001', 'ZZZ', 'Etranger', '2013-01-01');

SELECT pg_temp.creer_compte('224600004001', 'direction')  AS dir_a_id      \gset
SELECT pg_temp.creer_compte('224600004002', 'direction')  AS dir_b_id      \gset
SELECT pg_temp.creer_compte('224600004003', 'admin_gsg')  AS admin_gsg_id  \gset
SELECT pg_temp.creer_compte('224600004004')               AS sans_role_id  \gset
SELECT pg_temp.creer_compte('224600004005', 'eleve')      AS etranger_id   \gset
SELECT pg_temp.creer_compte('224600004006', 'enseignant') AS employe_a_id  \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_a_id'::uuid, '48000000-0000-0000-0000-000000000001', 'direction');
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_b_id'::uuid, '48000000-0000-0000-0000-000000000099', 'direction');

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'employe_a_id'::uuid, '48000000-0000-0000-0000-000000000001', 'enseignant');

INSERT INTO public.employes (id, etablissement_id, profile_id, matricule, categorie, statut, date_embauche)
VALUES ('48000000-0000-0000-0000-000000000007', '48000000-0000-0000-0000-000000000001',
        :'employe_a_id'::uuid, 'EMP-QA-001', 'enseignant', 'actif', '2020-09-01');

SET LOCAL ROLE authenticated;

-- Précondition du scénario NULL : sans_role_id n'a réellement aucun role_racine.
SELECT is(
  (SELECT role_racine FROM public.profiles WHERE id = :'sans_role_id'::uuid),
  NULL,
  'précondition : sans_role_id n''a aucun role_racine choisi (état normal post-signup)'
);

-- ===========================================================================
-- 1. calculer_moyenne_eleve / calculer_moyenne_classe (M6) — catégorie (a)
-- ===========================================================================
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT lives_ok(
  $$ SELECT public.calculer_moyenne_eleve('48000000-0000-0000-0000-000000000004') $$,
  'calculer_moyenne_eleve : personnel de l''établissement de la fiche autorisé'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.calculer_moyenne_eleve('48000000-0000-0000-0000-000000000004') $$,
  '42501', NULL, 'calculer_moyenne_eleve : tiers sans lien refusé'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_b_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.calculer_moyenne_eleve('48000000-0000-0000-0000-000000000004') $$,
  '42501', NULL, 'calculer_moyenne_eleve : direction d''un AUTRE établissement refusée'
);
SELECT throws_ok(
  $$ SELECT public.calculer_moyenne_classe('48000000-0000-0000-0000-000000000003') $$,
  '42501', NULL, 'calculer_moyenne_classe : direction d''un AUTRE établissement refusée'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT lives_ok(
  $$ SELECT public.calculer_moyenne_classe('48000000-0000-0000-0000-000000000003') $$,
  'calculer_moyenne_classe : direction de SA PROPRE classe autorisée malgré une fiche d''un autre établissement dans la même table (régression 20260906001517)'
);

-- ===========================================================================
-- 2. Comptabilité M14 (représentatives : lecture, écriture, IA agrégat)
-- ===========================================================================
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT lives_ok(
  $$ SELECT * FROM public.journal_comptable('48000000-0000-0000-0000-000000000001', '48000000-0000-0000-0000-000000000006', '2026-01-01', '2026-12-31') $$,
  'journal_comptable : comptable/direction de l''établissement autorisé'
);
SELECT lives_ok(
  $$ SELECT * FROM public.generer_balance('48000000-0000-0000-0000-000000000001', '2026-12-31') $$,
  'generer_balance : direction (écriture) autorisée'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT * FROM public.journal_comptable('48000000-0000-0000-0000-000000000001', '48000000-0000-0000-0000-000000000006', '2026-01-01', '2026-12-31') $$,
  '42501', NULL, 'journal_comptable : tiers sans lien refusé'
);
SELECT throws_ok(
  $$ SELECT * FROM public.detecter_anomalies_comptables('48000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'detecter_anomalies_comptables : tiers sans lien refusé'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_b_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT * FROM public.journal_comptable('48000000-0000-0000-0000-000000000001', '48000000-0000-0000-0000-000000000006', '2026-01-01', '2026-12-31') $$,
  '42501', NULL, 'journal_comptable : direction d''un AUTRE établissement refusée'
);
SELECT throws_ok(
  $$ SELECT * FROM public.generer_balance('48000000-0000-0000-0000-000000000001', '2026-12-31') $$,
  '42501', NULL, 'generer_balance : direction d''un AUTRE établissement refusée (écriture)'
);
SELECT throws_ok(
  $$ SELECT * FROM public.detecter_anomalies_comptables('48000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'detecter_anomalies_comptables : direction d''un AUTRE établissement refusée'
);

-- ===========================================================================
-- 3. Trio comportemental M7 (représentatives) — données disciplinaires
-- ===========================================================================
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT lives_ok(
  $$ SELECT public.analyse_comportement('48000000-0000-0000-0000-000000000004', '48000000-0000-0000-0000-000000000002') $$,
  'analyse_comportement : personnel de l''établissement autorisé'
);
SELECT lives_ok(
  $$ SELECT public.calculer_score_decrochage('48000000-0000-0000-0000-000000000004', '48000000-0000-0000-0000-000000000002') $$,
  'calculer_score_decrochage : personnel de l''établissement autorisé'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.analyse_comportement('48000000-0000-0000-0000-000000000004', '48000000-0000-0000-0000-000000000002') $$,
  '42501', NULL, 'analyse_comportement : tiers sans lien refusé (données disciplinaires d''un mineur)'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_b_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.analyse_comportement('48000000-0000-0000-0000-000000000004', '48000000-0000-0000-0000-000000000002') $$,
  '42501', NULL, 'analyse_comportement : direction d''un AUTRE établissement refusée'
);
SELECT throws_ok(
  $$ SELECT public.calculer_score_decrochage('48000000-0000-0000-0000-000000000004', '48000000-0000-0000-0000-000000000002') $$,
  '42501', NULL, 'calculer_score_decrochage : direction d''un AUTRE établissement refusée'
);
SELECT throws_ok(
  $$ SELECT public.recommander_sanction_educative('48000000-0000-0000-0000-000000000004', '48000000-0000-0000-0000-000000000002') $$,
  '42501', NULL, 'recommander_sanction_educative : direction d''un AUTRE établissement refusée'
);

-- ===========================================================================
-- 4. verifications_reinscription (M15quater)
-- ===========================================================================
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT lives_ok(
  $$ SELECT * FROM public.verifications_reinscription('48000000-0000-0000-0000-000000000004', '48000000-0000-0000-0000-000000000002') $$,
  'verifications_reinscription : direction de l''établissement autorisée'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT * FROM public.verifications_reinscription('48000000-0000-0000-0000-000000000004', '48000000-0000-0000-0000-000000000002') $$,
  '42501', NULL, 'verifications_reinscription : tiers sans lien refusé (fuite sanction/boursier corrigée)'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_b_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT * FROM public.verifications_reinscription('48000000-0000-0000-0000-000000000004', '48000000-0000-0000-0000-000000000002') $$,
  '42501', NULL, 'verifications_reinscription : direction d''un AUTRE établissement refusée'
);

-- Confirme que le contournement précis (annee_precedente_id fictive pour
-- éviter l'appel interne à solde_scolarite) reste bloqué en amont.
SELECT throws_ok(
  format(
    $$ SELECT * FROM public.verifications_reinscription(%L, gen_random_uuid()) $$,
    '48000000-0000-0000-0000-000000000004'
  ),
  '42501', NULL,
  'verifications_reinscription : contournement (année fictive) toujours bloqué par la garde amont'
);

-- ===========================================================================
-- 5. creer_inscription_nouvel_eleve / creer_reinscription — anti-patron NULL
-- ===========================================================================
SELECT set_config('request.jwt.claims', json_build_object('sub', :'sans_role_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.creer_inscription_nouvel_eleve(
       '48000000-0000-0000-0000-000000000001', 'FOFANA', 'Ibrahim', '2014-01-01',
       '48000000-0000-0000-0000-000000000003', '48000000-0000-0000-0000-000000000002') $$,
  '42501', NULL,
  'creer_inscription_nouvel_eleve : compte sans role_racine choisi refusé (anti-patron NULL corrigé)'
);
SELECT throws_ok(
  format(
    $$ SELECT public.creer_reinscription(%L, '48000000-0000-0000-0000-000000000003', '48000000-0000-0000-0000-000000000002') $$,
    '48000000-0000-0000-0000-000000000004'
  ),
  '42501', NULL,
  'creer_reinscription : compte sans role_racine choisi refusé (anti-patron NULL corrigé)'
);

-- Non-régression : la direction légitime continue de fonctionner normalement.
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT ok(
  public.creer_inscription_nouvel_eleve(
    '48000000-0000-0000-0000-000000000001', 'KEITA', 'Sekou', '2014-03-01',
    '48000000-0000-0000-0000-000000000003', '48000000-0000-0000-0000-000000000002') IS NOT NULL,
  'creer_inscription_nouvel_eleve : direction légitime toujours fonctionnelle (non-régression)'
);

-- ===========================================================================
-- 6. M8 RH — anti-patron NULL via est_rh
-- ===========================================================================
SELECT set_config('request.jwt.claims', json_build_object('sub', :'sans_role_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.calculer_score_turnover('48000000-0000-0000-0000-000000000007') $$,
  '42501', NULL,
  'calculer_score_turnover : compte sans role_racine choisi refusé (anti-patron NULL corrigé)'
);
SELECT throws_ok(
  $$ SELECT * FROM public.analyser_effectifs('48000000-0000-0000-0000-000000000001') $$,
  '42501', NULL,
  'analyser_effectifs : compte sans role_racine choisi refusé (anti-patron NULL corrigé)'
);
SELECT throws_ok(
  $$ SELECT public.charge_horaire('48000000-0000-0000-0000-000000000007') $$,
  '42501', NULL,
  'charge_horaire : compte sans role_racine choisi refusé (catégorie a, corrigé)'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_b_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.calculer_score_turnover('48000000-0000-0000-0000-000000000007') $$,
  '42501', NULL, 'calculer_score_turnover : direction d''un AUTRE établissement refusée'
);
SELECT throws_ok(
  $$ SELECT public.charge_horaire('48000000-0000-0000-0000-000000000007') $$,
  '42501', NULL, 'charge_horaire : direction d''un AUTRE établissement refusée'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT lives_ok(
  $$ SELECT public.calculer_score_turnover('48000000-0000-0000-0000-000000000007') $$,
  'calculer_score_turnover : RH/direction légitime toujours fonctionnelle (non-régression)'
);

-- ===========================================================================
-- 7. M9 — anti-patron NULL via est_comm
-- ===========================================================================
SELECT set_config('request.jwt.claims', json_build_object('sub', :'sans_role_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT * FROM public.analyser_envois('48000000-0000-0000-0000-000000000001', '2026-01-01', '2026-12-31') $$,
  '42501', NULL,
  'analyser_envois : compte sans role_racine choisi refusé (anti-patron NULL corrigé)'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_b_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT * FROM public.analyser_envois('48000000-0000-0000-0000-000000000001', '2026-01-01', '2026-12-31') $$,
  '42501', NULL, 'analyser_envois : direction d''un AUTRE établissement refusée'
);

-- ===========================================================================
-- 8. detecter_anomalies_commandes (M13)
-- ===========================================================================
SELECT set_config('request.jwt.claims', json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT * FROM public.detecter_anomalies_commandes('48000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'detecter_anomalies_commandes : tiers sans lien refusé'
);
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_b_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT * FROM public.detecter_anomalies_commandes('48000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'detecter_anomalies_commandes : direction d''un AUTRE établissement refusée'
);
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT lives_ok(
  $$ SELECT * FROM public.detecter_anomalies_commandes('48000000-0000-0000-0000-000000000001') $$,
  'detecter_anomalies_commandes : membre actif de l''établissement autorisé'
);

-- ===========================================================================
-- 9. M12 — predire_pics_charge / indicateurs_sante_base
-- ===========================================================================
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_b_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT * FROM public.predire_pics_charge('48000000-0000-0000-0000-000000000001', '48000000-0000-0000-0000-000000000002') $$,
  '42501', NULL, 'predire_pics_charge : direction d''un AUTRE établissement refusée'
);
SELECT throws_ok(
  $$ SELECT public.indicateurs_sante_base() $$,
  '42501', NULL, 'indicateurs_sante_base : direction (non admin GSG) refusée'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT lives_ok(
  $$ SELECT public.indicateurs_sante_base() $$,
  'indicateurs_sante_base : Administrateur GSG autorisé'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT lives_ok(
  $$ SELECT * FROM public.predire_pics_charge('48000000-0000-0000-0000-000000000001', '48000000-0000-0000-0000-000000000002') $$,
  'predire_pics_charge : personnel de l''établissement autorisé'
);

-- ===========================================================================
-- 10. predire_presence (M7)
-- ===========================================================================
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_b_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.predire_presence('48000000-0000-0000-0000-000000000001', '2026-11-01') $$,
  '42501', NULL, 'predire_presence : direction d''un AUTRE établissement refusée'
);
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT lives_ok(
  $$ SELECT public.predire_presence('48000000-0000-0000-0000-000000000001', '2026-11-01') $$,
  'predire_presence : personnel de l''établissement autorisé'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
