-- ============================================================================
-- EcoShop — Test RLS 08 : liaison parent ↔ élève (sélecteur d'enfant)
--
-- Vérifie que :
--   • un compte « parent » lie une fiche par matricule + date de naissance ;
--   • il ne voit ensuite que son enfant (pas les autres fiches) ;
--   • un compte non-parent est refusé (ROLE_PARENT_REQUIS).
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
-- Un établissement, deux fiches élèves (l'une liée à un compte élève),
-- un compte parent et un compte enseignant.
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Lien Parent', 'ecole-lien-parent') RETURNING id AS etab_id \gset

SELECT pg_temp.creer_compte('224600001041', 'eleve')      AS eleve_id \gset
SELECT pg_temp.creer_compte('224600001042', 'parent')     AS parent_id \gset
SELECT pg_temp.creer_compte('224600001043', 'enseignant') AS prof_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES
  (:'etab_id'::uuid, 'MAT-PAR-001', 'DIALLO', 'Aïcha', '2009-05-12', :'eleve_id'::uuid, now()),
  (:'etab_id'::uuid, 'MAT-PAR-002', 'CAMARA', 'Ousmane', '2008-01-10', NULL, NULL);

-- ---------------------------------------------------------------------------
-- 1. Le parent lie la fiche de son enfant.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'parent_id', 'role', 'authenticated')::text, true);

SELECT ok(
  (SELECT public.lier_parent_a_fiche('MAT-PAR-001', '2009-05-12')) IS NOT NULL,
  'lien parent : liaison réussie par double facteur'
);

-- ---------------------------------------------------------------------------
-- 2. Le parent ne voit que son enfant (pas l''autre fiche).
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT count(*) FROM public.fiches_eleves)::int,
  1,
  'lien parent : visibilité limitée à l''enfant lié'
);

-- ---------------------------------------------------------------------------
-- 3. Un enseignant (non-parent) est refusé.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);

SELECT throws_ok(
  $$ SELECT public.lier_parent_a_fiche('MAT-PAR-001', '2009-05-12') $$,
  '42501',
  'ROLE_PARENT_REQUIS',
  'lien parent : rôle non-parent refusé'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
