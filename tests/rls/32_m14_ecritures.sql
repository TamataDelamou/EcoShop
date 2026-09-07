-- ============================================================================
-- EcoShop — Test RLS 32 : écritures comptables (M14)
--
-- Vérifie que :
--   • la direction saisit une écriture valide ;
--   • un compte d'un autre établissement est rejeté (garde-fou tenant) ;
--   • débit = crédit sur le même compte est rejeté ;
--   • la direction d'un autre établissement ne voit pas les écritures.
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
-- Tenants + comptes + journaux + directions
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Écriture A', 'ecole-ecriture-a') RETURNING id AS etab_a \gset
INSERT INTO public.etablissements (nom, slug) VALUES ('École Écriture B', 'ecole-ecriture-b') RETURNING id AS etab_b \gset

INSERT INTO public.plans_comptables (etablissement_id, code, intitule, type) VALUES
  (:'etab_a'::uuid, '520', 'Banque A', 'banque'),
  (:'etab_a'::uuid, '701', 'Scolarité A', 'produit'),
  (:'etab_b'::uuid, '520', 'Banque B', 'banque');

INSERT INTO public.journaux (etablissement_id, code, intitule) VALUES
  (:'etab_a'::uuid, 'BQ', 'Livre de banque A');

SELECT pg_temp.creer_compte('224600001901', 'direction') AS direction_a \gset
SELECT pg_temp.creer_compte('224600001902', 'direction') AS direction_b \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'direction_a'::uuid, :'etab_a'::uuid, 'direction'),
  (:'direction_b'::uuid, :'etab_b'::uuid, 'direction');

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

-- 1. Saisie valide par la direction A.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'direction_a', 'role', 'authenticated')::text, true);

INSERT INTO public.ecritures_comptables
  (etablissement_id, date_ecriture, libelle, compte_debit_id, compte_credit_id, montant, journal_id)
SELECT (SELECT id FROM public.etablissements WHERE slug = 'ecole-ecriture-a'),
       current_date, 'Scolarité', d.id, c.id, 100000, j.id
FROM public.plans_comptables d, public.plans_comptables c, public.journaux j
WHERE d.code = '520' AND d.etablissement_id = (SELECT id FROM public.etablissements WHERE slug = 'ecole-ecriture-a')
  AND c.code = '701' AND c.etablissement_id = (SELECT id FROM public.etablissements WHERE slug = 'ecole-ecriture-a')
  AND j.code = 'BQ' AND j.etablissement_id = (SELECT id FROM public.etablissements WHERE slug = 'ecole-ecriture-a');

SELECT is((SELECT count(*) FROM public.ecritures_comptables)::int, 1, 'direction A : saisie valide acceptée');

-- 2. Compte d'un autre établissement → rejet (garde-fou tenant, 23514).
RESET ROLE;
SELECT throws_ok(
  $sql$
    INSERT INTO public.ecritures_comptables
      (etablissement_id, date_ecriture, libelle, compte_debit_id, compte_credit_id, montant, journal_id)
    SELECT a.id, current_date, 'Fuite tenant', b.id, c.id, 5000, j.id
    FROM public.etablissements a,
         public.plans_comptables b,
         public.plans_comptables c,
         public.journaux j
    WHERE a.slug = 'ecole-ecriture-a'
      AND b.code = '520' AND b.etablissement_id = (SELECT id FROM public.etablissements WHERE slug = 'ecole-ecriture-b')
      AND c.code = '701' AND c.etablissement_id = (SELECT id FROM public.etablissements WHERE slug = 'ecole-ecriture-a')
      AND j.code = 'BQ' AND j.etablissement_id = (SELECT id FROM public.etablissements WHERE slug = 'ecole-ecriture-a')
  $sql$,
  '23514', NULL, 'compte d''un autre établissement : rejeté (ECRITURE_TENANT_INCOHERENT)'
);
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'direction_a', 'role', 'authenticated')::text, true);

-- 3. Débit = crédit sur le même compte → rejet (23514).
SELECT throws_ok(
  $sql$
    INSERT INTO public.ecritures_comptables
      (etablissement_id, date_ecriture, libelle, compte_debit_id, compte_credit_id, montant, journal_id)
    SELECT a.id, current_date, 'Comptes identiques', b.id, b.id, 5000, j.id
    FROM public.etablissements a,
         public.plans_comptables b,
         public.journaux j
    WHERE a.slug = 'ecole-ecriture-a'
      AND b.code = '520' AND b.etablissement_id = (SELECT id FROM public.etablissements WHERE slug = 'ecole-ecriture-a')
      AND j.code = 'BQ' AND j.etablissement_id = (SELECT id FROM public.etablissements WHERE slug = 'ecole-ecriture-a')
  $sql$,
  '23514', NULL, 'débit = crédit sur le même compte : rejeté (ECRITURE_COMPTES_IDENTIQUES)'
);

-- 4. Direction B : isolation des écritures.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'direction_b', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.ecritures_comptables)::int, 0, 'direction B : aucune écriture visible');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
