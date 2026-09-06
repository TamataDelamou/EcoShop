-- ============================================================================
-- EcoShop — Test RLS 09 : visibilité des affectations d'enseignants
--
-- Vérifie que :
--   • l'enseignant concerné voit sa propre affectation ;
--   • un élève (non personnel) n'en voit aucune ;
--   • la direction (personnel) voit les affectations de l'établissement.
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

SELECT plan(3);

-- ---------------------------------------------------------------------------
-- Établissement, année, classe, trois comptes (enseignant, élève, direction),
-- une affectation.
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Affectations', 'ecole-affectations') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

SELECT pg_temp.creer_compte('224600001051', 'enseignant') AS ens1_id \gset
SELECT pg_temp.creer_compte('224600001052', 'eleve')      AS eleve_id \gset
SELECT pg_temp.creer_compte('224600001053', 'direction')  AS dir_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'ens1_id'::uuid, :'etab_id'::uuid, 'enseignant'),
  (:'eleve_id'::uuid, :'etab_id'::uuid, 'eleve'),
  (:'dir_id'::uuid, :'etab_id'::uuid, 'direction');

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '7A', '7e A') RETURNING id AS classe_id \gset

INSERT INTO public.affectations_enseignants
  (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id, role_affectation)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'ens1_id'::uuid, :'classe_id'::uuid, 'titulaire');

-- ---------------------------------------------------------------------------
-- 1. L'enseignant concerné voit son affectation.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'ens1_id', 'role', 'authenticated')::text, true);

SELECT is((SELECT count(*) FROM public.affectations_enseignants)::int, 1,
  'affectations : l''enseignant voit la sienne');

-- ---------------------------------------------------------------------------
-- 2. Un élève (membre non personnel) n'en voit aucune.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);

SELECT is((SELECT count(*) FROM public.affectations_enseignants)::int, 0,
  'affectations : invisibles pour un élève');

-- ---------------------------------------------------------------------------
-- 3. La direction (personnel) voit les affectations de l'établissement.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);

SELECT is((SELECT count(*) FROM public.affectations_enseignants)::int, 1,
  'affectations : visibles par la direction');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
