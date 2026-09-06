-- ============================================================================
-- EcoShop — Test RLS 05 : isolation multi-tenant
--
-- Vérifie qu'un membre d'un établissement A ne voit aucune donnée d'un
-- établissement B : rattachements, fiches établissements, fiches élèves.
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
-- Données : deux établissements, deux membres, une fiche élève dans B.
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('Établissement A', 'etab-a') RETURNING id AS etab_a_id \gset
INSERT INTO public.etablissements (nom, slug) VALUES ('Établissement B', 'etab-b') RETURNING id AS etab_b_id \gset

SELECT pg_temp.creer_compte('224600000041', 'direction') AS compte_a_id \gset
SELECT pg_temp.creer_compte('224600000042', 'direction') AS compte_b_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'compte_a_id'::uuid, :'etab_a_id'::uuid, 'direction'),
  (:'compte_b_id'::uuid, :'etab_b_id'::uuid, 'direction');

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance)
VALUES (:'etab_b_id'::uuid, 'MAT-ISO-B-001', 'CAMARA', 'Moussa', '2006-03-12');

-- ---------------------------------------------------------------------------
-- Simulation : le membre A consulte.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'compte_a_id', 'role', 'authenticated')::text, true);

SELECT is(
  (SELECT count(*) FROM public.etablissements_membres)::int,
  1,
  'isolation : un seul rattachement visible (le sien)'
);

SELECT is(
  (SELECT etablissement_id::text FROM public.etablissements_membres),
  :'etab_a_id',
  'isolation : le rattachement visible appartient à l''établissement A'
);

SELECT is(
  (SELECT count(*) FROM public.etablissements)::int,
  1,
  'isolation : seul l''établissement A est lisible'
);

SELECT is(
  (SELECT count(*) FROM public.fiches_eleves)::int,
  0,
  'isolation : la fiche élève de l''établissement B est invisible'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
