-- ============================================================================
-- EcoShop — Test RLS 96 : espaces par école (REG-32, migration 1578)
--
-- Vérifie que :
--   • un enseignant de l'école A, parent d'un élève de l'école B, a deux
--     espaces : (enseignant, A) et (parent, B) — jamais (parent, A) ;
--   • un enseignant peut relier son enfant (avant : réservé aux comptes
--     dont le rôle principal est « parent ») ; un élève, non ;
--   • un lien en attente ou retiré ne donne pas d'espace parent ;
--   • un parent sans rattachement voit ses écoles par ses enfants.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  UPDATE public.profiles SET role_racine = p_role::public.role_racine,
         prenom = initcap(split_part(p_email, '@', 1)), nom = 'Test' WHERE id = v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.sur(p_uid uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.espaces() RETURNS text LANGUAGE sql AS $$
  SELECT coalesce(string_agg(role || '@' || etablissement_nom || '(' || enfants || ')', ', '
                  ORDER BY etablissement_nom, role), '')
  FROM public.mes_espaces();
$$;

SELECT plan(9);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('96000000-0000-0000-0000-00000000000a', 'École A', 'ecole-a-96', 'GNF'),
  ('96000000-0000-0000-0000-00000000000b', 'École B', 'ecole-b-96', 'GNF');

SELECT pg_temp.compte('prof@exemple.gn', 'enseignant') AS prof \gset
SELECT pg_temp.compte('maman@exemple.gn', 'parent') AS maman \gset
SELECT pg_temp.compte('eleve@exemple.gn', 'eleve') AS eleve \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'prof', '96000000-0000-0000-0000-00000000000a', 'enseignant');

INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance) VALUES
  ('96000000-0000-0000-0000-0000000000f1', '96000000-0000-0000-0000-00000000000b', 'MAT-96-B1', 'CAMARA', 'Fanta', '2015-04-10'),
  ('96000000-0000-0000-0000-0000000000f2', '96000000-0000-0000-0000-00000000000b', 'MAT-96-B2', 'CAMARA', 'Sekou', '2013-09-01'),
  ('96000000-0000-0000-0000-0000000000f3', '96000000-0000-0000-0000-00000000000a', 'MAT-96-A1', 'BARRY', 'Aminata', '2014-01-20');

-- ---------------------------------------------------------------------------
-- 1. L'enseignant de l'école A relie son enfant de l'école B
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'prof');
SET LOCAL ROLE authenticated;

SELECT is(pg_temp.espaces(), 'enseignant@École A(0)', 'avant la liaison : espace enseignant seulement');
SELECT ok(public.lier_parent_a_fiche('MAT-96-B1', '2015-04-10') IS NOT NULL,
          'un enseignant peut relier son enfant (rôle principal enseignant)');
SELECT is(pg_temp.espaces(), 'enseignant@École A(0), parent@École B(1)',
          'enseignant dans l''école A, parent dans l''école B — pas parent dans l''école A');
SELECT ok(public.lier_parent_a_fiche('MAT-96-B2', '2013-09-01') IS NOT NULL, 'deuxième enfant dans l''école B');
SELECT is(pg_temp.espaces(), 'enseignant@École A(0), parent@École B(2)', 'un seul espace parent par école, avec ses enfants');

-- ---------------------------------------------------------------------------
-- 2. Lien retiré par l'école : plus d'espace parent
-- ---------------------------------------------------------------------------
RESET ROLE;
UPDATE public.relations_parent_eleve SET statut = 'en_attente'
 WHERE parent_profile_id = :'prof' AND fiche_eleve_id = '96000000-0000-0000-0000-0000000000f2';
UPDATE public.relations_parent_eleve SET autorise = false
 WHERE parent_profile_id = :'prof' AND fiche_eleve_id = '96000000-0000-0000-0000-0000000000f1';
SELECT pg_temp.sur(:'prof');
SET LOCAL ROLE authenticated;
SELECT is(pg_temp.espaces(), 'enseignant@École A(0)', 'lien en attente ou retiré : pas d''espace parent');

-- ---------------------------------------------------------------------------
-- 3. Parent sans rattachement ; élève refusé
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'maman');
SELECT ok(public.lier_parent_a_fiche('MAT-96-A1', '2014-01-20') IS NOT NULL, 'un parent relie son enfant');
SELECT is(pg_temp.espaces(), 'parent@École A(1)', 'parent sans rattachement : son école vient de son enfant');

SELECT pg_temp.sur(:'eleve');
SELECT throws_ok($$ SELECT public.lier_parent_a_fiche('MAT-96-A1', '2014-01-20') $$, '42501', NULL,
                 'un compte élève ne relie pas d''enfant');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
