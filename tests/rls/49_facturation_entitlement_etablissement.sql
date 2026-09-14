-- ============================================================================
-- EcoShop — Test RLS 49 : Facturation/Quota IA — étape (a), primitive
-- d'entitlement établissement (migration 20260906001514).
--
-- Couvre les deux corrections de sécurité actées avant écriture :
--   1. coalesce(est_admin_gsg(), false) dans les deux RPC d'écriture —
--      testé avec un compte SANS role_racine choisi (anti-patron NULL).
--   2. entitlement_actif() vérifie est_personnel/est_admin_gsg avant de
--      répondre — testé dans les deux sens habituels (tiers sans lien,
--      direction d'un AUTRE établissement).
--
-- Angle mort propre à cette primitive, testé explicitement : la direction
-- de l'établissement CONCERNÉ lui-même (sans droit admin_gsg) doit être
-- refusée sur les RPC d'écriture — le risque ici est l'auto-déclaration
-- d'un paiement fictif, pas un tiers externe.
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

SELECT plan(37);

-- ---------------------------------------------------------------------------
-- Fixture : deux établissements réels (A = cible, B = isolation), un
-- établissement C sans aucune année scolaire déclarée (cas limite).
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('49000000-0000-0000-0000-000000000001', 'École QA A', 'ecole-qa49-a');
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('49000000-0000-0000-0000-000000000099', 'École QA B (isolation)', 'ecole-qa49-b');
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('49000000-0000-0000-0000-000000000098', 'École QA C (sans annee)', 'ecole-qa49-c');

-- Établissement A : année courante + une seconde année (non courante), pour
-- vérifier le scoping par période.
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('49000000-0000-0000-0000-000000000002', '49000000-0000-0000-0000-000000000001', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('49000000-0000-0000-0000-000000000003', '49000000-0000-0000-0000-000000000001', '2027-2028', '2027-10-01', '2028-06-30', false);

-- Établissement B : sa propre année, utilisée pour le test de cohérence
-- croisée établissement/année (contournement : année d'un AUTRE établissement).
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('49000000-0000-0000-0000-000000000004', '49000000-0000-0000-0000-000000000099', '2026-2027', '2026-10-01', '2027-06-30', true);

SELECT pg_temp.creer_compte('224600005001', 'direction')  AS dir_a_id      \gset
SELECT pg_temp.creer_compte('224600005002', 'direction')  AS dir_b_id      \gset
SELECT pg_temp.creer_compte('224600005003', 'admin_gsg')  AS admin_gsg_id  \gset
SELECT pg_temp.creer_compte('224600005004')               AS sans_role_id  \gset
SELECT pg_temp.creer_compte('224600005005', 'eleve')      AS etranger_id   \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_a_id'::uuid, '49000000-0000-0000-0000-000000000001', 'direction');
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_b_id'::uuid, '49000000-0000-0000-0000-000000000099', 'direction');

SET LOCAL ROLE authenticated;

-- Précondition : sans_role_id n'a réellement aucun role_racine (état normal
-- post-signup, pas un cas exotique).
SELECT is(
  (SELECT role_racine FROM public.profiles WHERE id = :'sans_role_id'::uuid),
  NULL,
  'précondition : sans_role_id n''a aucun role_racine choisi'
);

-- ===========================================================================
-- 1. entitlement_actif() — correction de sécurité 2, les deux sens habituels
-- ===========================================================================
SELECT set_config('request.jwt.claims', json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.entitlement_actif('49000000-0000-0000-0000-000000000001', 'licence_pro') $$,
  '42501', NULL, 'entitlement_actif : tiers sans lien refusé (ne peut pas sonder le statut de paiement)'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_b_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.entitlement_actif('49000000-0000-0000-0000-000000000001', 'licence_pro') $$,
  '42501', NULL, 'entitlement_actif : direction d''un AUTRE établissement refusée'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT ok(
  public.entitlement_actif('49000000-0000-0000-0000-000000000001', 'licence_pro') is false,
  'entitlement_actif : personnel de l''établissement autorisé, licence_pro faux avant tout paiement'
);
SELECT ok(
  public.entitlement_actif('49000000-0000-0000-0000-000000000001', 'frais_ia_admin') is false,
  'entitlement_actif : frais_ia_admin faux avant tout paiement'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT ok(
  public.entitlement_actif('49000000-0000-0000-0000-000000000001', 'licence_pro') is false,
  'entitlement_actif : Administrateur GSG autorisé sur n''importe quel établissement'
);
SELECT ok(
  public.entitlement_actif('49000000-0000-0000-0000-000000000098', 'licence_pro') is false,
  'entitlement_actif : établissement sans aucune année scolaire déclarée renvoie faux sans erreur'
);

-- ===========================================================================
-- 2. enregistrer_paiement_licence_pro() — correction de sécurité 1 +
-- angle mort (auto-déclaration par l'établissement lui-même)
-- ===========================================================================
SELECT set_config('request.jwt.claims', json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.enregistrer_paiement_licence_pro('49000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000002', 250, 300) $$,
  '42501', NULL, 'enregistrer_paiement_licence_pro : tiers sans lien refusé'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.enregistrer_paiement_licence_pro('49000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000002', 250, 300) $$,
  '42501', NULL, 'enregistrer_paiement_licence_pro : direction de l''établissement CONCERNÉ (angle mort) refusée, pas admin GSG'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'sans_role_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.enregistrer_paiement_licence_pro('49000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000002', 250, 300) $$,
  '42501', NULL, 'enregistrer_paiement_licence_pro : compte sans role_racine choisi refusé (anti-patron NULL corrigé)'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.enregistrer_paiement_licence_pro('49000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000004', 250, 300) $$,
  '23514', NULL, 'enregistrer_paiement_licence_pro : année scolaire d''un AUTRE établissement rejetée'
);
SELECT throws_ok(
  $$ SELECT public.enregistrer_paiement_licence_pro('49000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000002', -1, 300) $$,
  '22023', NULL, 'enregistrer_paiement_licence_pro : effectif négatif rejeté'
);
SELECT throws_ok(
  $$ SELECT public.enregistrer_paiement_licence_pro('49000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000002', 250, -1) $$,
  '22023', NULL, 'enregistrer_paiement_licence_pro : montant négatif rejeté'
);

-- Cas normal : effectif 250 -> tranche 1 (barème placeholder 101-400).
SELECT is(
  (SELECT tranche_actuelle FROM public.enregistrer_paiement_licence_pro(
    '49000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000002', 250, 300)),
  1,
  'enregistrer_paiement_licence_pro : admin GSG autorisé, effectif 250 -> tranche 1'
);

SELECT ok(
  public.entitlement_actif('49000000-0000-0000-0000-000000000001', 'licence_pro') is true,
  'entitlement_actif : licence_pro vrai immédiatement après paiement (recalculé en direct)'
);
SELECT ok(
  public.entitlement_actif('49000000-0000-0000-0000-000000000001', 'frais_ia_admin') is false,
  'entitlement_actif : frais_ia_admin reste faux -- payer licence_pro ne débloque jamais frais_ia_admin (règle 8)'
);
SELECT ok(
  public.entitlement_actif('49000000-0000-0000-0000-000000000001', 'licence_pro', '49000000-0000-0000-0000-000000000003') is false,
  'entitlement_actif : une AUTRE année scolaire du même établissement reste faux (scoping par période)'
);
SELECT ok(
  public.entitlement_actif('49000000-0000-0000-0000-000000000099', 'licence_pro') is false,
  'entitlement_actif : établissement B (jamais payé) reste faux -- indépendance inter-établissements'
);

-- Deuxième paiement : effectif 500 (régime plancher) -> tranche 2, montant
-- cumulé (300 + 300 = 600), jamais un tarif plat recalculé depuis zéro.
SELECT is(
  (SELECT tranche_actuelle FROM public.enregistrer_paiement_licence_pro(
    '49000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000002', 500, 300)),
  2,
  'enregistrer_paiement_licence_pro : effectif 500 (régime plancher) -> tranche 2'
);
SELECT is(
  (SELECT montant_total_paye_periode FROM public.etablissements_licence_pro
   WHERE etablissement_id = '49000000-0000-0000-0000-000000000001' AND annee_scolaire_id = '49000000-0000-0000-0000-000000000002'),
  600.00,
  'enregistrer_paiement_licence_pro : montant_total_paye_periode accumulé (300 + 300), jamais écrasé'
);

-- ===========================================================================
-- 3. enregistrer_paiement_frais_ia_admin() — même discipline
-- ===========================================================================
SELECT set_config('request.jwt.claims', json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.enregistrer_paiement_frais_ia_admin('49000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000002', 1) $$,
  '42501', NULL, 'enregistrer_paiement_frais_ia_admin : tiers sans lien refusé'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.enregistrer_paiement_frais_ia_admin('49000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000002', 1) $$,
  '42501', NULL, 'enregistrer_paiement_frais_ia_admin : direction de l''établissement CONCERNÉ (angle mort) refusée'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'sans_role_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.enregistrer_paiement_frais_ia_admin('49000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000002', 1) $$,
  '42501', NULL, 'enregistrer_paiement_frais_ia_admin : compte sans role_racine choisi refusé (anti-patron NULL corrigé)'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.enregistrer_paiement_frais_ia_admin('49000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000004', 1) $$,
  '23514', NULL, 'enregistrer_paiement_frais_ia_admin : année scolaire d''un AUTRE établissement rejetée'
);
SELECT throws_ok(
  $$ SELECT public.enregistrer_paiement_frais_ia_admin('49000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000002', -1) $$,
  '22023', NULL, 'enregistrer_paiement_frais_ia_admin : montant négatif rejeté'
);

SELECT ok(
  (SELECT paye FROM public.enregistrer_paiement_frais_ia_admin(
    '49000000-0000-0000-0000-000000000001', '49000000-0000-0000-0000-000000000002', 1)),
  'enregistrer_paiement_frais_ia_admin : admin GSG autorisé'
);
SELECT ok(
  public.entitlement_actif('49000000-0000-0000-0000-000000000001', 'frais_ia_admin') is true,
  'entitlement_actif : frais_ia_admin vrai immédiatement après paiement'
);
SELECT ok(
  public.entitlement_actif('49000000-0000-0000-0000-000000000099', 'frais_ia_admin') is false,
  'entitlement_actif : frais_ia_admin de l''établissement B reste faux -- pas de fuite inter-établissements'
);

-- ===========================================================================
-- 4. calculer_tranche_pro() / calculer_montant_cumule_pro() -- fonctions
-- pures, barème placeholder (seuil 100 ; tranche 1 = 101-400 ; plancher
-- départ tranche 2 à 401, largeur 300)
-- ===========================================================================
SELECT is(public.calculer_tranche_pro(50), 0, 'calculer_tranche_pro : sous le seuil gratuit -> 0');
SELECT is(public.calculer_tranche_pro(100), 0, 'calculer_tranche_pro : exactement au seuil gratuit -> 0');
SELECT is(public.calculer_tranche_pro(250), 1, 'calculer_tranche_pro : dans la tranche 1 explicite -> 1');
SELECT is(public.calculer_tranche_pro(500), 2, 'calculer_tranche_pro : régime plancher, premier bloc -> 2');
SELECT is(public.calculer_tranche_pro(750), 3, 'calculer_tranche_pro : régime plancher, deuxième bloc -> 3');

SELECT is(public.calculer_montant_cumule_pro(0), 0::numeric, 'calculer_montant_cumule_pro : tranche 0 -> 0');
SELECT is(public.calculer_montant_cumule_pro(1), 300::numeric, 'calculer_montant_cumule_pro : tranche 1 -> bloc unique');
SELECT is(public.calculer_montant_cumule_pro(2), 600::numeric, 'calculer_montant_cumule_pro : tranche 2 -> cumul tranche 1 + premier bloc plancher');
SELECT is(public.calculer_montant_cumule_pro(3), 900::numeric, 'calculer_montant_cumule_pro : tranche 3 -> cumul tranche 1 + deux blocs plancher');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
