-- ============================================================================
-- EcoShop — Test RLS 75 : kit de mise en service (migration 20260906001548)
-- Tâches quotidiennes de toutes les écoles, contrôle de préparation.
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

CREATE OR REPLACE FUNCTION pg_temp.controle(p_etat jsonb, p_nom text) RETURNS boolean
LANGUAGE sql AS $$
  SELECT (c ->> 'ok')::boolean FROM jsonb_array_elements(p_etat -> 'controles') c WHERE c ->> 'controle' = p_nom;
$$;

SELECT plan(11);

-- Écoles déjà présentes (jeu de démonstration seed.sql) traitées elles aussi
-- par les tâches quotidiennes : comptées à part.
SELECT count(DISTINCT e.id)::int AS deja_la
FROM public.etablissements e
JOIN public.annees_scolaires a ON a.etablissement_id = e.id AND a.courante
WHERE e.statut = 'actif' \gset

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('75000000-0000-0000-0000-000000000001', 'École A', 'ecole-a-75', 'GNF'),
  ('75000000-0000-0000-0000-000000000002', 'École B', 'ecole-b-75', 'GNF'),
  ('75000000-0000-0000-0000-000000000003', 'École fermée', 'ecole-c-75', 'GNF');
UPDATE public.etablissements SET statut = 'suspendu' WHERE id = '75000000-0000-0000-0000-000000000003';
INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('75000000-0000-0000-0000-000000000001', '2026-2027', '2026-10-01', '2027-06-30', true),
  ('75000000-0000-0000-0000-000000000002', '2026-2027', '2026-10-01', '2027-06-30', true),
  ('75000000-0000-0000-0000-000000000002', '2025-2026', '2025-10-01', '2026-06-30', false),
  ('75000000-0000-0000-0000-000000000003', '2026-2027', '2026-10-01', '2027-06-30', true);

SELECT pg_temp.creer_compte('224675000001', 'parent') AS parent \gset
SELECT pg_temp.creer_compte('224675000002', 'admin_gsg') AS admin \gset

-- Tâches quotidiennes : serveur seulement.
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'parent');
SELECT throws_ok($$ SELECT public.executer_taches_quotidiennes() $$, '42501', NULL,
  'un utilisateur ne lance pas les tâches quotidiennes');
RESET ROLE;

SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT public.executer_taches_quotidiennes() AS bilan \gset
RESET ROLE;
SELECT is((:'bilan'::jsonb ->> 'ecoles')::int, :deja_la + 2,'chaque école active passe, une seule fois (année courante), l''école suspendue est sautée');
SELECT is(jsonb_array_length(:'bilan'::jsonb -> 'erreurs'), 0, 'aucune erreur');

-- Contrôle de préparation : équipe GSG seulement.
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'parent');
SELECT throws_ok($$ SELECT public.etat_mise_en_service() $$, '42501', NULL,
  'un parent ne lit pas l''état de mise en service');

SELECT pg_temp.en_tant_que(:'admin');
SELECT public.etat_mise_en_service() AS etat \gset
SELECT is(jsonb_array_length(:'etat'::jsonb -> 'controles'), 2 + 9 + 3 + 2, 'extensions, 9 tâches, 3 secrets, administrateur, packs SMS');
SELECT is(pg_temp.controle(:'etat', 'Administrateur GSG'), true, 'administrateur GSG désigné');
SELECT is(pg_temp.controle(:'etat', 'Packs SMS en vente'), false, 'packs SMS encore sans prix');
SELECT is((:'etat'::jsonb ->> 'pret')::boolean, false, 'pas prêt tant qu''un contrôle manque');
SELECT ok(:'etat'::text NOT LIKE '%decrypted%', 'aucune valeur secrète dans le rapport');
RESET ROLE;

UPDATE public.packs_sms SET prix = 150000, actif = true WHERE code = 'sms_500';
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'admin');
SELECT is(pg_temp.controle(public.etat_mise_en_service(), 'Packs SMS en vente'), true, 'pack au prix fixé : contrôle vert');
RESET ROLE;

SELECT is((SELECT count(*)::int FROM public.taches_planifiees_attendues()), 9,
  'neuf tâches planifiées attendues (dont la purge des inscriptions abandonnées, REG-18)');

SELECT * FROM finish();
ROLLBACK;
