-- ============================================================================
-- EcoShop — Test RLS 03 : Custom Access Token Hook opérant (C3)
--
-- Vérifie que custom_access_token_hook() émet effectivement les claims
-- app_metadata.role_racine et app_metadata.gsg_id à partir de la table
-- profiles (source de vérité), sous le rôle d'exécution du hook
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

SELECT plan(2);

-- ---------------------------------------------------------------------------
-- Données : un enseignant avec un gsg_id renseigné.
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224600000021', 'enseignant') AS prof_id \gset

UPDATE public.profiles
   SET gsg_id = gen_random_uuid()
 WHERE id = :'prof_id'::uuid
RETURNING gsg_id::text AS gsg_id \gset
CREATE OR REPLACE FUNCTION pg_temp.debug_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  claims jsonb;
  prof record;
BEGIN
  claims := coalesce(event->'claims', '{}'::jsonb);
  RAISE NOTICE 'DIAG ctx: user=% session=% rls=%', current_user, session_user, current_setting('row_security', true);
  select role_racine, gsg_id, statut_compte into prof
  from public.profiles
  where id = (event->>'user_id')::uuid
    and deleted_at is null;
  RAISE NOTICE 'DIAG found=%', FOUND;
  if found then
    RAISE NOTICE 'DIAG prof: role=% gsg=% stat=%', prof.role_racine, prof.gsg_id, prof.statut_compte;
    if prof.role_racine is not null then
      claims := jsonb_set(claims, '{app_metadata,role_racine}', to_jsonb(prof.role_racine::text), true);
    end if;
    if prof.gsg_id is not null then
      claims := jsonb_set(claims, '{app_metadata,gsg_id}', to_jsonb(prof.gsg_id::text), true);
    end if;
    claims := jsonb_set(claims, '{app_metadata,statut_compte}', to_jsonb(prof.statut_compte::text), true);
  end if;
  return jsonb_build_object('claims', claims);
END;
$$;

DO $$
DECLARE
  v_id uuid;
  v_out jsonb;
BEGIN
  SELECT id INTO v_id FROM public.profiles WHERE identifiant_canonique = '+224600000021';
  v_out := pg_temp.debug_hook(jsonb_build_object('user_id', v_id, 'claims', '{}'::jsonb));
  RAISE NOTICE 'DIAG debug_hook out: %', v_out::text;
END $$;

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
  :'gsg_id',
  'C3 : gsg_id émis dans app_metadata'
);

SELECT * FROM finish();
ROLLBACK;
