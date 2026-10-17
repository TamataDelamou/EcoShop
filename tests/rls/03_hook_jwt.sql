-- ============================================================================
-- EcoShop — Test RLS 03 : Custom Access Token Hook opérant (C3)
--
-- Vérifie que custom_access_token_hook() émet effectivement le claim
-- app_metadata.role_racine à partir de la table profiles (source de vérité),
-- et n'émet PLUS app_metadata.gsg_id depuis KER-MUT K1 (fédération GSG ID
-- abandonnée, migration 20260906001525) — ni depuis profiles, ni recopié
-- d'un ancien jeton, sous le rôle d'exécution du hook
-- (supabase_auth_admin). La fonction étant SECURITY DEFINER, elle est
-- appelable ici depuis le rôle de test superutilisateur.
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
-- Données : un enseignant dont la colonne obsolète gsg_id est encore
-- renseignée (donnée héritée, conservée par la migration K1).
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224600000021', 'enseignant') AS prof_id \gset

UPDATE public.profiles
   SET gsg_id = gen_random_uuid()
 WHERE id = :'prof_id'::uuid
RETURNING gsg_id::text AS gsg_id \gset

-- ---------------------------------------------------------------------------
-- Le hook renvoie {"claims": {"app_metadata": {...}}}.
-- ---------------------------------------------------------------------------
SELECT is(
  public.custom_access_token_hook(
    jsonb_build_object('user_id', :'prof_id', 'claims', '{}'::jsonb)
  ) #>> '{claims,app_metadata,role_racine}',
  'enseignant',
  'C3 : role_racine émis dans app_metadata'
);

SELECT is(
  public.custom_access_token_hook(
    jsonb_build_object('user_id', :'prof_id', 'claims', '{}'::jsonb)
  ) #>> '{claims,app_metadata,gsg_id}',
  NULL,
  'K1 : gsg_id n''est plus émis dans app_metadata (fédération abandonnée)'
);

SELECT is(
  public.custom_access_token_hook(
    jsonb_build_object(
      'user_id', :'prof_id',
      'claims', jsonb_build_object('app_metadata', jsonb_build_object('gsg_id', :'gsg_id'))
    )
  ) #>> '{claims,app_metadata,gsg_id}',
  NULL,
  'K1 : un gsg_id hérité d''un ancien jeton est retiré au rafraîchissement'
);

SELECT * FROM finish();
ROLLBACK;
