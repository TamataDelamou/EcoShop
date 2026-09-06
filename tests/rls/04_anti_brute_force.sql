-- ============================================================================
-- EcoShop — Test RLS 04 : anti-brute-force liaison compte ↔ fiche (ch. 5.8)
--
-- Vérifie que lier_compte_a_fiche() :
--   • tolère 5 échecs par heure (double facteur matricule + date de naissance) ;
--   • verrouille à la 6e tentative, même avec les bons identifiants ;
--   • réussit pour un compte neuf disposant des bons identifiants.
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
-- Données : un établissement, une fiche élève, deux comptes.
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug)
VALUES ('École Brute-Force', 'ecole-brute-force')
RETURNING id AS etab_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance)
VALUES (:'etab_id'::uuid, 'MAT-BRUTE-001', 'DIALLO', 'Aïcha', '2005-05-05');

SELECT pg_temp.creer_compte('224600000031', NULL) AS compte1_id \gset
SELECT pg_temp.creer_compte('224600000032', NULL) AS compte2_id \gset

-- ---------------------------------------------------------------------------
-- 1. Cinq échecs consommés (bonne matricule, mauvaise date) → 42501 chacun.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'compte1_id', 'role', 'authenticated')::text, true);

DO $$
DECLARE
  code text;
BEGIN
  FOR i IN 1..5 LOOP
    BEGIN
      PERFORM public.lier_compte_a_fiche('MAT-BRUTE-001', '2000-01-01');
      RAISE EXCEPTION 'echec_non_leve';
    EXCEPTION WHEN OTHERS THEN
      code := SQLSTATE;
      IF code <> '42501' THEN
        RAISE EXCEPTION 'attendu 42501, recu %', code;
      END IF;
    END;
  END LOOP;
END $$;

SELECT pass('anti-brute-force : 5 échecs consommés en 42501');

-- ---------------------------------------------------------------------------
-- 2. La 6e tentative (mauvaise date) est verrouillée.
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT public.lier_compte_a_fiche('MAT-BRUTE-001', '2000-01-01') $$,
  '54000',
  'TROP_DE_TENTATIVES',
  'anti-brute-force : 6e tentative verrouillée'
);

-- ---------------------------------------------------------------------------
-- 3. Même les bons identifiants sont verrouillés pendant l'heure.
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT public.lier_compte_a_fiche('MAT-BRUTE-001', '2005-05-05') $$,
  '54000',
  'TROP_DE_TENTATIVES',
  'anti-brute-force : bons identifiants également verrouillés'
);

-- ---------------------------------------------------------------------------
-- 4. Un compte neuf avec les bons identifiants réussit la liaison.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'compte2_id', 'role', 'authenticated')::text, true);

SELECT ok(
  (SELECT public.lier_compte_a_fiche('MAT-BRUTE-001', '2005-05-05')) IS NOT NULL,
  'anti-brute-force : liaison réussie pour un compte neuf'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
