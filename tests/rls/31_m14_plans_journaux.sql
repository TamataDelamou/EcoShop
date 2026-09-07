-- ============================================================================
-- EcoShop — Test RLS 31 : plan comptable & journaux (M14)
--
-- Vérifie que :
--   • la direction (comptable) de l'établissement voit plan et journaux ;
--   • la direction d'un autre établissement ne voit rien (isolation) ;
--   • un compte étranger ne voit rien.
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

SELECT plan(4);

-- ---------------------------------------------------------------------------
-- Tenants + plan + journal + comptes
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Cpta A', 'ecole-cpta-a') RETURNING id AS etab_a \gset
INSERT INTO public.etablissements (nom, slug) VALUES ('École Cpta B', 'ecole-cpta-b') RETURNING id AS etab_b \gset

INSERT INTO public.plans_comptables (etablissement_id, code, intitule, type)
VALUES (:'etab_a'::uuid, '520', 'Banque', 'banque');

INSERT INTO public.journaux (etablissement_id, code, intitule)
VALUES (:'etab_a'::uuid, 'BQ', 'Livre de banque');

SELECT pg_temp.creer_compte('224600001801', 'direction') AS direction_a \gset
SELECT pg_temp.creer_compte('224600001802', 'direction') AS direction_b \gset
SELECT pg_temp.creer_compte('224600001803', 'parent')    AS etranger \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'direction_a'::uuid, :'etab_a'::uuid, 'direction'),
  (:'direction_b'::uuid, :'etab_b'::uuid, 'direction');

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'direction_a', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.plans_comptables)::int, 1, 'direction A : voit son plan comptable');
SELECT is((SELECT count(*) FROM public.journaux)::int, 1, 'direction A : voit ses journaux');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'direction_b', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.plans_comptables)::int, 0, 'direction B : isolation (0 compte)');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'etranger', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.plans_comptables)::int, 0, 'étranger : aucun compte visible');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
