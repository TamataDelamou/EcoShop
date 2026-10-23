-- ============================================================================
-- EcoShop — Test RLS 81 : identifiant EcoShop (REG-18 D, migration 20260906001554)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.compte_email(p_email text, p_role text DEFAULT 'parent')
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  UPDATE public.profiles SET role_racine = p_role::public.role_racine WHERE id = v_id;
  RETURN v_id;
END $$;

SELECT plan(20);

-- ---------------------------------------------------------------------------
-- 1. Caractère de contrôle et normalisation
-- ---------------------------------------------------------------------------
SELECT is(public.identifiant_ecoshop_controle('7K4M2Q'), 'M', 'Luhn mod 32 : 7K4M2Q -> M (calcul fait à la main)');
SELECT is(public.normaliser_identifiant_ecoshop('ec 7k4m 2qm'), 'EC-7K4M-2QM', 'saisie en minuscules avec espaces normalisée');
SELECT is(public.normaliser_identifiant_ecoshop('EC-7K4M-2QM'), 'EC-7K4M-2QM', 'forme affichée acceptée telle quelle');
SELECT is(public.normaliser_identifiant_ecoshop('EC-7K4M-2Q9'), NULL, 'mauvais caractère de contrôle : refusé');
SELECT is(public.normaliser_identifiant_ecoshop('EC-7K4M-Q2M'), NULL, 'deux caractères voisins inversés : refusé');
SELECT is(public.normaliser_identifiant_ecoshop('EC-7K4M-2QMX'), NULL, 'un caractère de trop : refusé');
-- O lu comme 0, I et L lus comme 1 (alphabet de Crockford).
SELECT is(public.normaliser_identifiant_ecoshop('EC-' || '1' || 'K4M-2Q' || public.identifiant_ecoshop_controle('1K4M2Q')),
          public.normaliser_identifiant_ecoshop('EC-' || 'L' || 'K4M-2Q' || public.identifiant_ecoshop_controle('1K4M2Q')),
          'L saisi à la place de 1 : même identifiant');

-- ---------------------------------------------------------------------------
-- 2. Attribution à la création, unicité, registre
-- ---------------------------------------------------------------------------
SELECT pg_temp.compte_email('awa@exemple.org') AS awa \gset
SELECT pg_temp.compte_email('binta@exemple.org') AS binta \gset

SELECT matches((SELECT identifiant_ecoshop FROM public.profiles WHERE id = :'awa'),
  '^EC-[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{3}$', 'identifiant attribué à la création, au bon format');
SELECT is(public.normaliser_identifiant_ecoshop((SELECT identifiant_ecoshop FROM public.profiles WHERE id = :'awa')),
  (SELECT identifiant_ecoshop FROM public.profiles WHERE id = :'awa'), 'caractère de contrôle valide');
SELECT isnt((SELECT identifiant_ecoshop FROM public.profiles WHERE id = :'awa'),
  (SELECT identifiant_ecoshop FROM public.profiles WHERE id = :'binta'), 'deux comptes, deux identifiants');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.profiles WHERE identifiant_ecoshop IS NULL), 'aucun profil sans identifiant (comptes existants inclus)');

SELECT identifiant_ecoshop AS id_awa FROM public.profiles WHERE id = :'awa' \gset

-- ---------------------------------------------------------------------------
-- 3. Jamais modifiable par le client, jamais lisible dans le registre
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'awa');
UPDATE public.profiles SET identifiant_ecoshop = 'EC-0000-000' WHERE id = :'awa';
SELECT is((SELECT identifiant_ecoshop FROM public.profiles WHERE id = :'awa'), :'id_awa', 'le client ne change pas son identifiant');
SELECT is_empty($$ SELECT valeur FROM public.identifiants_ecoshop_attribues $$, 'registre illisible depuis le client');
SELECT throws_ok($$ SELECT public.email_pour_identifiant_ecoshop('x') $$, '42501', NULL,
  'adresse d''un identifiant : jamais depuis le client');
SELECT throws_ok($$ SELECT public.noter_essai_connexion_identifiant('x', 'envoi', 15, 5) $$, '42501', NULL,
  'compteur d''essais : jamais depuis le client');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 4. Connexion par identifiant (Edge Function, rôle service)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE service_role;
SELECT is(public.email_pour_identifiant_ecoshop(lower(replace(:'id_awa', '-', ' '))), 'awa@exemple.org',
  'identifiant saisi en minuscules : adresse du compte retrouvée');
SELECT is(public.email_pour_identifiant_ecoshop('EC-7K4M-2QM'), NULL, 'identifiant inconnu : rien');
SELECT ok(public.noter_essai_connexion_identifiant('id:test', 'envoi', 15, 2)
      AND public.noter_essai_connexion_identifiant('id:test', 'envoi', 15, 2)
      AND NOT public.noter_essai_connexion_identifiant('id:test', 'envoi', 15, 2),
  'essais limités : le troisième envoi en 15 min est refusé');
RESET ROLE;

UPDATE public.profiles SET statut_compte = 'suspendu' WHERE id = :'binta';
SET LOCAL ROLE service_role;
SELECT is(public.email_pour_identifiant_ecoshop((SELECT identifiant_ecoshop FROM public.profiles WHERE id = :'binta')), NULL,
  'compte suspendu : aucun code envoyé');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 5. Jamais réattribué
-- ---------------------------------------------------------------------------
DELETE FROM auth.users WHERE id = :'awa';
SELECT ok(EXISTS (SELECT 1 FROM public.identifiants_ecoshop_attribues WHERE valeur = :'id_awa'),
  'compte supprimé : son identifiant reste au registre, il ne ressortira jamais');

SELECT * FROM finish();
ROLLBACK;
