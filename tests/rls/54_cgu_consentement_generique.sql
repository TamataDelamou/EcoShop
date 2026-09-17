-- ============================================================================
-- EcoShop — Test RLS 54 : CGU / consentement générique (cahier §34.10,
-- migration 20260906001523).
--
-- Couvre : mapping rôle -> parcours (simplifie/complet), aucune ligne pour un
-- rôle non choisi ou un rôle plateforme (admin_gsg), acceptation self-service
-- (refus de spoofing d'un autre profil), immutabilité du registre
-- (UPDATE silencieusement sans effet, pas de policy), visibilité restreinte
-- (soi-même + admin_gsg), publication de version réservée admin_gsg, et
-- ré-ouverture du statut "non accepté" après publication d'une nouvelle
-- version.
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

SELECT plan(19);

SELECT pg_temp.creer_compte('224610001001', NULL)               AS sans_role_id       \gset
SELECT pg_temp.creer_compte('224610001002', 'admin_gsg')        AS admin_gsg_id       \gset
SELECT pg_temp.creer_compte('224610001003', 'eleve')            AS eleve_id           \gset
SELECT pg_temp.creer_compte('224610001004', 'parent')           AS parent_id          \gset
SELECT pg_temp.creer_compte('224610001005', 'enseignant')       AS enseignant_id      \gset
SELECT pg_temp.creer_compte('224610001006', 'direction')        AS direction_id       \gset
SELECT pg_temp.creer_compte('224610001007', 'vendeur')          AS vendeur_id         \gset
SELECT pg_temp.creer_compte('224610001008', 'fondateur_reseau') AS fondateur_id       \gset
SELECT pg_temp.creer_compte('224610001009', 'eleve')            AS eleve_tiers_id     \gset

-- ===========================================================================
-- 1. cgu_statut() : aucune ligne pour un rôle non choisi ou un rôle plateforme.
-- ===========================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'sans_role_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.cgu_statut()),
  0::bigint,
  'cgu_statut() : aucune ligne pour un profil sans role_racine choisi'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.cgu_statut()),
  0::bigint,
  'cgu_statut() : aucune ligne pour admin_gsg -- role plateforme hors perimetre §34.10'
);

-- ===========================================================================
-- 2. Mapping rôle -> parcours.
-- ===========================================================================
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT parcours::text FROM public.cgu_statut()),
  'simplifie',
  'cgu_statut() : eleve -> parcours simplifie'
);
SELECT is(
  (SELECT acceptee FROM public.cgu_statut()),
  false,
  'cgu_statut() : eleve -> non acceptee avant toute acceptation'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'parent_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT parcours::text FROM public.cgu_statut()), 'complet', 'cgu_statut() : parent -> parcours complet');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'enseignant_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT parcours::text FROM public.cgu_statut()), 'complet', 'cgu_statut() : enseignant -> parcours complet (decision porteur de projet, absent du texte §34.10)');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT parcours::text FROM public.cgu_statut()), 'complet', 'cgu_statut() : direction -> parcours complet');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'vendeur_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT parcours::text FROM public.cgu_statut()), 'complet', 'cgu_statut() : vendeur -> parcours complet');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'fondateur_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT parcours::text FROM public.cgu_statut()), 'complet', 'cgu_statut() : fondateur_reseau -> parcours complet');

-- ===========================================================================
-- 3. Acceptation self-service, refus de spoofing, immutabilite, visibilite.
-- ===========================================================================
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);

SELECT lives_ok(
  format(
    $$ insert into public.cgu_acceptations (profile_id, cgu_version_id) values ('%s', (select cgu_version_id from public.cgu_statut())) $$,
    :'eleve_id'
  ),
  'cgu_acceptations : eleve accepte sa propre CGU courante -- succes'
);

SELECT is(
  (SELECT acceptee FROM public.cgu_statut()),
  true,
  'cgu_statut() : acceptee devient true immediatement apres l''acceptation'
);

SELECT throws_ok(
  format(
    $$ insert into public.cgu_acceptations (profile_id, cgu_version_id) values ('%s', (select cgu_version_id from public.cgu_statut())) $$,
    :'eleve_tiers_id'
  ),
  '42501', NULL,
  'cgu_acceptations : un compte ne peut PAS enregistrer une acceptation pour un AUTRE profil (spoofing bloque par la RLS)'
);

-- Immutabilite : aucune policy UPDATE -> 0 ligne affectee, jamais une erreur.
-- (WITH modificateur au niveau superieur de l'instruction, exige par Postgres.)
WITH upd AS (
  UPDATE public.cgu_acceptations SET accepte_le = now() WHERE profile_id = :'eleve_id'::uuid RETURNING 1
)
SELECT is(
  (SELECT count(*) FROM upd),
  0::bigint,
  'cgu_acceptations : UPDATE sans effet (aucune policy update) -- registre de consentement immuable'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_tiers_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.cgu_acceptations WHERE profile_id = :'eleve_id'::uuid),
  0::bigint,
  'cgu_acceptations : un tiers ne voit PAS l''acceptation d''un autre profil'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.cgu_acceptations WHERE profile_id = :'eleve_id'::uuid),
  1::bigint,
  'cgu_acceptations : admin_gsg voit l''acceptation de n''importe quel profil'
);

-- ===========================================================================
-- 4. Publication de version -- reservee admin_gsg -- et reouverture du statut
-- "non acceptee" apres publication d'une nouvelle version.
-- ===========================================================================
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.publier_version_cgu('simplifie', '2026-09-16-v2', 'nouveau texte') $$,
  '42501', NULL,
  'publier_version_cgu : refuse a un compte non admin_gsg (ici direction, pourtant role legitime ailleurs)'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT lives_ok(
  $$ SELECT public.publier_version_cgu('simplifie', '2026-09-16-v2', 'nouveau texte simplifie v2') $$,
  'publier_version_cgu : admin_gsg peut publier une nouvelle version du parcours simplifie'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT numero_version FROM public.cgu_statut()),
  '2026-09-16-v2',
  'cgu_statut() : la nouvelle version devient la version courante pour le parcours simplifie'
);
SELECT is(
  (SELECT acceptee FROM public.cgu_statut()),
  false,
  'cgu_statut() : l''acceptation de l''ancienne version ne vaut pas pour la nouvelle -- statut redevient non accepte'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
