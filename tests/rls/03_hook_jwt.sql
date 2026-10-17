-- ============================================================================
-- EcoShop — Test RLS 03 : Custom Access Token Hook opérant (C3)
--
-- Vérifie que custom_access_token_hook() émet effectivement le claim
-- app_metadata.role_racine à partir de la table profiles (source de vérité),
-- sous le rôle d'exécution du hook (supabase_auth_admin). La fonction étant
-- SECURITY DEFINER, elle est appelable ici depuis le rôle de test
-- superutilisateur.
--
-- KER-MUT K1 (migrations 20260906001525 et 20260906001527) : la fédération
-- GSG ID est abandonnée — gsg_id n'est plus émis, un gsg_id hérité d'un
-- ancien jeton est retiré au rafraîchissement, et la colonne n'existe plus.
-- Le trigger de protection des colonnes de profiles fonctionne toujours
-- après sa suppression.
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

SELECT plan(6);

SELECT pg_temp.creer_compte('224600000021', 'enseignant') AS prof_id \gset

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
      'claims', jsonb_build_object('app_metadata', jsonb_build_object('gsg_id', gen_random_uuid()::text))
    )
  ) #>> '{claims,app_metadata,gsg_id}',
  NULL,
  'K1 : un gsg_id hérité d''un ancien jeton est retiré au rafraîchissement'
);

SELECT hasnt_column('public', 'profiles', 'gsg_id',
  'K1 : la colonne profiles.gsg_id est supprimée');

-- ---------------------------------------------------------------------------
-- Le trigger de protection ne référence plus la colonne supprimée : un
-- client peut toujours modifier son état civil, jamais son rôle.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
  json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);

SELECT lives_ok(
  format($$ UPDATE public.profiles SET prenom = 'Mariama', role_racine = 'admin_gsg' WHERE id = %L $$, :'prof_id'),
  'K1 : la mise à jour de son propre profil fonctionne après suppression de gsg_id'
);
RESET ROLE;

SELECT is(
  (SELECT role_racine::text FROM public.profiles WHERE id = :'prof_id'::uuid),
  'enseignant',
  'C1 : le rôle reste protégé par le trigger redéfini'
);

SELECT * FROM finish();
ROLLBACK;
