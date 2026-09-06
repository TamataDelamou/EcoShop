-- ============================================================================
-- EcoShop — Test RLS 01 : anti-élévation de privilège (C1)
--
-- Vérifie qu'un client authentifié ne peut pas élever son propre rôle :
--   • un UPDATE direct sur profiles.role_racine est neutralisé par le trigger
--     profiles_protege_colonnes ;
--   • choisir_role_racine() n'accepte que les rôles auto-inscriptibles
--     (eleve, parent) et ne peut être appelé qu'une seule fois.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- Helper : créer un compte auth.users (le trigger handle_new_user crée le profil)
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
-- Données : un élève (rôle déjà défini) et un compte sans rôle.
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224600000001', 'eleve') AS eleve_id \gset
SELECT pg_temp.creer_compte('224600000002', NULL)    AS compte2_id \gset

-- ---------------------------------------------------------------------------
-- 1. L'élève tente de se promouvoir admin_gsg par un UPDATE direct : la policy
--    profiles_update_own laisse passer, mais le trigger restaure le rôle.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);

UPDATE public.profiles SET role_racine = 'admin_gsg' WHERE id = :'eleve_id'::uuid;

SELECT is(
  (SELECT role_racine::text FROM public.profiles WHERE id = :'eleve_id'::uuid),
  'eleve',
  'C1 : un UPDATE direct ne peut pas modifier role_racine'
);

-- ---------------------------------------------------------------------------
-- 2-4. Sur le compte sans rôle : un rôle privilégié est refusé, un rôle
--      auto-inscriptible est accepté une seule fois.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'compte2_id', 'role', 'authenticated')::text, true);

SELECT throws_ok(
  $$ SELECT public.choisir_role_racine('enseignant') $$,
  '42501',
  'ROLE_NON_AUTO_INSCRIPTIBLE',
  'C1 : rôle privilégié refusé à l''auto-inscription'
);

SELECT is(
  (SELECT public.choisir_role_racine('parent'))::text,
  'parent',
  'C1 : rôle auto-inscriptible accepté'
);

SELECT throws_ok(
  $$ SELECT public.choisir_role_racine('eleve') $$,
  '23505',
  'ROLE_DEJA_DEFINI',
  'C1 : le rôle ne peut être choisi qu''une fois'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
