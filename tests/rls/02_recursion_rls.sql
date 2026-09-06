-- ============================================================================
-- EcoShop — Test RLS 02 : absence de récursion RLS (C2)
--
-- Vérifie que la lecture des tables multi-tenant en tant que client
-- authentifié ne provoque pas d'erreur de récursion (SQLSTATE 42P17). Les
-- policies reposent sur les fonctions SECURITY DEFINER mes_etablissements() /
-- est_membre_actif(), qui n'évaluent pas les policies des tables lues.
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
-- Données : un établissement et un membre direction.
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224600000011', 'direction') AS direction_id \gset

INSERT INTO public.etablissements (nom, slug)
VALUES ('École Test Recursion', 'ecole-test-recursion')
RETURNING id AS etab_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'direction_id'::uuid, :'etab_id'::uuid, 'direction');

-- ---------------------------------------------------------------------------
-- Simulation client : lecture en tant que membre.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'direction_id', 'role', 'authenticated')::text, true);

SELECT lives_ok(
  $$ SELECT count(*) FROM public.etablissements_membres $$,
  'C2 : lecture de etablissements_membres sans récursion 42P17'
);

SELECT is(
  (SELECT count(*) FROM public.etablissements_membres)::int,
  1,
  'C2 : exactement un rattachement visible'
);

SELECT is(
  (SELECT count(*) FROM public.mes_etablissements())::int,
  1,
  'C2 : mes_etablissements() retourne le tenant du membre'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
