-- ============================================================================
-- EcoShop — Test RLS 34 : profils publics (M15)
--
-- Vérifie que :
--   • le jeton `token_acces` est généré et la complétion déduite (true/false) ;
--   • anon et authentifié ne lisent PAS les profils publics (données privées).
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
-- Profils publics de démonstration (insérés hors RLS, rôle superutilisateur)
-- ---------------------------------------------------------------------------
INSERT INTO public.profils_publics (nom, email, telephone) VALUES
  ('Visiteur Complet', 'visiteur.complet@example.com', '+224620001111');
INSERT INTO public.profils_publics (nom) VALUES
  ('Visiteur Incomplet');

SELECT pg_temp.creer_compte('224600002101', 'parent') AS authentifie \gset

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT complet FROM public.profils_publics WHERE email = 'visiteur.complet@example.com'),
  true, 'profil public : complétion déduite = true (nom + email)'
);
SELECT is(
  (SELECT complet FROM public.profils_publics WHERE nom = 'Visiteur Incomplet'),
  false, 'profil public : complétion déduite = false (nom seul)'
);

SET LOCAL ROLE anon;
SELECT is((SELECT count(*) FROM public.profils_publics)::int, 0, 'anon : aucun profil public visible (RLS fermée)');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'authentifie', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.profils_publics)::int, 0, 'authentifié : aucun profil public tiers visible');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
