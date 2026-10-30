-- ============================================================================
-- EcoShop — Test RLS 102 : paramètres en valeur nue, désignation de
-- l'Administrateur de contenu (migration 20260906001586)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.sur(p_uid uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  UPDATE public.profiles SET role_racine = p_role::public.role_racine, prenom = 'Test', nom = 'Test' WHERE id = v_id;
  RETURN v_id;
END $$;

SELECT plan(9);

SELECT pg_temp.compte('gsg.102@exemple.org', 'admin_gsg') AS gsg \gset
SELECT pg_temp.compte('contenu.102@exemple.org', 'parent') AS futur \gset
SELECT pg_temp.compte('dir.102@exemple.org', 'direction') AS dir \gset

SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'gsg');

SELECT is((public.definir_parametre_global('code_compte_obligatoire', 'true')).valeur, 'true'::jsonb,
  'une valeur nue se règle');
SELECT throws_ok($$ SELECT public.definir_parametre_global('code_compte_obligatoire', '{"valeur": true}') $$,
  '22023', 'TYPE_INVALIDE', 'elle garde sa forme');
SELECT throws_ok($$ SELECT public.definir_parametre_global('tarif_abonnement_premium_eleve_mensuel', '5000') $$,
  '22023', 'TYPE_INVALIDE', 'un objet reste un objet');

SELECT throws_ok($$ SELECT public.designer_admin_contenu('personne@exemple.org') $$,
  '22023', 'COMPTE_INTROUVABLE', 'compte inconnu');
SELECT throws_ok($$ SELECT public.designer_admin_contenu('dir.102@exemple.org') $$,
  '22023', 'COMPTE_DEJA_UTILISE', 'un compte de direction n''est pas détourné');
SELECT lives_ok($$ SELECT public.designer_admin_contenu('CONTENU.102@exemple.org') $$, 'compte dédié désigné');
SELECT is((SELECT count(*)::int FROM public.admins_contenu() WHERE courriel LIKE '%.102@%'), 1, 'il apparaît dans la liste');

SELECT pg_temp.sur(:'dir');
SELECT throws_ok($$ SELECT public.designer_admin_contenu('dir.102@exemple.org') $$,
  '42501', NULL, 'seul l''Administrateur GSG désigne');

SELECT pg_temp.sur(:'gsg');
SELECT public.retirer_admin_contenu(:'futur');
SELECT is((SELECT count(*)::int FROM public.admins_contenu() WHERE courriel LIKE '%.102@%'), 0, 'retiré');

SELECT * FROM finish();
ROLLBACK;
