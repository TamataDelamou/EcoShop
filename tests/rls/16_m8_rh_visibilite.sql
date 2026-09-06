-- ============================================================================
-- EcoShop — Test RLS 16 : visibilité RH & isolation multi-tenant (M8)
--
-- Vérifie que :
--   • la direction (RH) voit tous les dossiers employés de l'établissement ;
--   • l'employé ne voit que son propre dossier et ses propres bulletins ;
--   • un employé ne peut pas créer de dossier employé (écriture RH seule) ;
--   • un membre d'un autre établissement ne voit aucun dossier (isolation).
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

SELECT plan(5);

-- ---------------------------------------------------------------------------
-- Tenant A + comptes
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École RH M8', 'ecole-rh-m8') RETURNING id AS etab_id \gset

SELECT pg_temp.creer_compte('224600001201', 'direction')  AS dir_id \gset
SELECT pg_temp.creer_compte('224600001202', 'enseignant') AS ens1_id \gset
SELECT pg_temp.creer_compte('224600001203', 'enseignant') AS ens2_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'dir_id'::uuid,  :'etab_id'::uuid, 'direction'),
  (:'ens1_id'::uuid, :'etab_id'::uuid, 'enseignant'),
  (:'ens2_id'::uuid, :'etab_id'::uuid, 'enseignant');

-- ---------------------------------------------------------------------------
-- Dossiers employés + contrats + bulletins (1 pour dir, 1 pour ens1)
-- ---------------------------------------------------------------------------
INSERT INTO public.employes (etablissement_id, profile_id, matricule, categorie, date_embauche)
VALUES
  (:'etab_id'::uuid, :'dir_id'::uuid,  'EMP-A', 'direction',  '2020-01-15'),
  (:'etab_id'::uuid, :'ens1_id'::uuid, 'EMP-B', 'enseignant', '2023-09-01'),
  (:'etab_id'::uuid, :'ens2_id'::uuid, 'EMP-C', 'enseignant', '2026-08-01');

INSERT INTO public.contrats (etablissement_id, employe_id, type, date_debut, salaire_base)
SELECT :'etab_id'::uuid, e.id, 'cdi', '2026-01-01', 3000000
FROM public.employes e
WHERE e.etablissement_id = :'etab_id'::uuid;

INSERT INTO public.paie_bulletins
  (etablissement_id, employe_id, contrat_id, periode_debut, periode_fin, salaire_base, net)
SELECT :'etab_id'::uuid, e.id, c.id, '2026-09-01', '2026-09-30', 3000000, 3000000
FROM public.employes e
JOIN public.contrats c ON c.employe_id = e.id
WHERE e.matricule IN ('EMP-A', 'EMP-B');

-- ---------------------------------------------------------------------------
-- Tenant B (isolation) : un compte membre d'un autre établissement
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École B M8', 'ecole-b-m8') RETURNING id AS etab_b_id \gset

SELECT pg_temp.creer_compte('224600001204', 'enseignant') AS autre_id \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'autre_id'::uuid, :'etab_b_id'::uuid, 'enseignant');

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

-- 1. La direction voit les 3 dossiers employés.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.employes)::int, 3, 'RH : la direction voit tous les employés');

-- 2. L'employé ne voit que son propre dossier.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'ens1_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.employes)::int, 1, 'employé : ne voit que son propre dossier');
SELECT is((SELECT matricule FROM public.employes), 'EMP-B', 'employé : son dossier est le bon');

-- 3. L'employé ne voit que ses propres bulletins de paie.
SELECT is((SELECT count(*) FROM public.paie_bulletins)::int, 1, 'employé : ne voit que son bulletin');

-- 4. L'employé ne peut pas créer de dossier employé (écriture RH seule).
--    Le SELECT lit établissements + membres (lisibles par tout membre) ; le
--    profile résolu est un membre actif (le trigger passe), puis la RLS
--    d'écriture RH bloque l'INSERT → 42501.
SELECT throws_ok(
  $$ INSERT INTO public.employes (etablissement_id, profile_id, matricule, categorie)
     SELECT e.id, m.profile_id, 'EMP-X', 'enseignant'
     FROM public.etablissements e
     JOIN public.etablissements_membres m ON m.etablissement_id = e.id
     WHERE e.slug = 'ecole-rh-m8' AND m.role_dans_etablissement = 'enseignant'
     LIMIT 1 $$,
  '42501',
  'employé : création de dossier interdite'
);

-- 5. Un membre d'un autre établissement ne voit aucun dossier du tenant A.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'autre_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.employes WHERE etablissement_id = :'etab_id'::uuid)::int, 0,
          'isolation : aucun dossier visible hors établissement');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
