-- ============================================================================
-- EcoShop — Test RLS 60 : identité visuelle par établissement (REG-07 B,
-- migration 20260906001531)
--
-- Couvre :
--   • definir_identite_visuelle() réservée à la Direction de l'établissement
--     concerné (refus parent, refus Direction d'un autre établissement) ;
--   • couleur normalisée (#RRGGBB majuscules), format invalide refusé ;
--   • logo obligatoirement rangé dans le dossier de l'établissement ;
--   • bucket public `logos-etablissements` (images, ≤ 1 Mo) ;
--   • dépôt d'un fichier Storage : autorisé dans son dossier, refusé dans
--     le dossier d'un autre établissement ou sous un nom mal formé.
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

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

SELECT plan(14);

INSERT INTO public.etablissements (id, nom, slug)
VALUES ('60000000-0000-0000-0000-000000000001', 'École identité', 'ecole-identite-60'),
       ('60000000-0000-0000-0000-000000000099', 'École B identité', 'ecole-b-identite-60');

SELECT pg_temp.creer_compte('224660000001', 'direction') AS dir_id    \gset
SELECT pg_temp.creer_compte('224660000002', 'parent')    AS parent_id \gset
SELECT pg_temp.creer_compte('224660000003', 'direction') AS dir_b_id  \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_id'::uuid, '60000000-0000-0000-0000-000000000001', 'direction'),
       (:'dir_b_id'::uuid, '60000000-0000-0000-0000-000000000099', 'direction');

-- Storage tel qu'en production : RLS active sur storage.objects.
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA storage TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON storage.objects TO authenticated;

SELECT results_eq(
  $$ SELECT public, file_size_limit FROM storage.buckets WHERE id = 'logos-etablissements' $$,
  $$ VALUES (true, 1048576::bigint) $$,
  'bucket des logos public, limité à 1 Mo');

SET LOCAL ROLE authenticated;

-- ---------------------------------------------------------------------------
-- definir_identite_visuelle
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok(
  $$ SELECT public.definir_identite_visuelle('60000000-0000-0000-0000-000000000001', '#1A7F5A', NULL) $$,
  '42501', NULL, 'un parent ne change pas l''identité de l''école');

SELECT pg_temp.en_tant_que(:'dir_b_id');
SELECT throws_ok(
  $$ SELECT public.definir_identite_visuelle('60000000-0000-0000-0000-000000000001', '#1A7F5A', NULL) $$,
  '42501', NULL, 'la Direction d''un autre établissement non plus');

SELECT pg_temp.en_tant_que(:'dir_id');
SELECT throws_ok(
  $$ SELECT public.definir_identite_visuelle('60000000-0000-0000-0000-000000000001', 'vert', NULL) $$,
  '22023', 'COULEUR_INVALIDE', 'couleur mal formée refusée');
SELECT throws_ok(
  $$ SELECT public.definir_identite_visuelle('60000000-0000-0000-0000-000000000001', '#1A7F5A',
       '60000000-0000-0000-0000-000000000099/logo.png') $$,
  '22023', 'LOGO_HORS_DOSSIER', 'logo rangé chez un autre établissement refusé');

SELECT lives_ok(
  $$ SELECT public.definir_identite_visuelle('60000000-0000-0000-0000-000000000001', '#1a7f5a',
       '60000000-0000-0000-0000-000000000001/logo-1.png') $$,
  'la Direction définit couleur et logo');
RESET ROLE;

SELECT results_eq(
  $$ SELECT couleur_identite, logo_chemin FROM public.etablissements WHERE id = '60000000-0000-0000-0000-000000000001' $$,
  $$ VALUES ('#1A7F5A', '60000000-0000-0000-0000-000000000001/logo-1.png') $$,
  'couleur normalisée en majuscules, chemin du logo enregistré');

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT lives_ok(
  $$ SELECT public.definir_identite_visuelle('60000000-0000-0000-0000-000000000001', NULL, NULL) $$,
  'retour à la charte par défaut (couleur et logo retirés)');
RESET ROLE;
SELECT is((SELECT couleur_identite FROM public.etablissements WHERE id = '60000000-0000-0000-0000-000000000001'), NULL,
  'couleur effacée');

-- Contrainte de format aussi en écriture directe (défense en profondeur).
SELECT throws_ok(
  $$ UPDATE public.etablissements SET couleur_identite = '#zzzzzz' WHERE id = '60000000-0000-0000-0000-000000000001' $$,
  '23514', NULL, 'contrainte de format sur la colonne');

-- ---------------------------------------------------------------------------
-- Storage
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT lives_ok(
  $$ INSERT INTO storage.objects (bucket_id, name) VALUES ('logos-etablissements', '60000000-0000-0000-0000-000000000001/logo-2.png') $$,
  'dépôt du logo dans le dossier de son établissement');
SELECT throws_ok(
  $$ INSERT INTO storage.objects (bucket_id, name) VALUES ('logos-etablissements', '60000000-0000-0000-0000-000000000099/pirate.png') $$,
  '42501', NULL, 'dépôt refusé dans le dossier d''un autre établissement');
SELECT throws_ok(
  $$ INSERT INTO storage.objects (bucket_id, name) VALUES ('logos-etablissements', 'pas-un-uuid/logo.png') $$,
  '42501', NULL, 'dépôt refusé sous un nom mal formé');

SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok(
  $$ INSERT INTO storage.objects (bucket_id, name) VALUES ('logos-etablissements', '60000000-0000-0000-0000-000000000001/parent.png') $$,
  '42501', NULL, 'un parent ne dépose pas de logo');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
