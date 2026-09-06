-- ============================================================================
-- EcoShop — Test RLS 17 : congés & validation humaine (M8)
--
-- Vérifie que :
--   • l'employé peut déposer sa propre demande de congé ;
--   • l'employé ne peut pas déposer de demande pour un collègue ;
--   • l'employé ne peut pas valider sa propre demande (validation humaine) ;
--   • la direction (RH) peut valider la demande ;
--   • l'employé peut retirer sa propre demande encore « demande ».
--
-- NB : les identifiants d'établissement et d'employés sont des UUID fixes afin
-- que les appels `throws_ok` restent des chaînes SQL statiques (aucune
-- interpolation psql dans les corps dollar-quotés).
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
-- Tenant (id fixe) + comptes + membres + dossiers employés (ids fixes)
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('20000000-0000-0000-0000-000000000001', 'École Congés M8', 'ecole-conges-m8');

SELECT pg_temp.creer_compte('224600001211', 'direction')  AS dir_id \gset
SELECT pg_temp.creer_compte('224600001212', 'enseignant') AS ens1_id \gset
SELECT pg_temp.creer_compte('224600001213', 'enseignant') AS ens2_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'dir_id'::uuid,  '20000000-0000-0000-0000-000000000001', 'direction'),
  (:'ens1_id'::uuid, '20000000-0000-0000-0000-000000000001', 'enseignant'),
  (:'ens2_id'::uuid, '20000000-0000-0000-0000-000000000001', 'enseignant');

INSERT INTO public.employes (id, etablissement_id, profile_id, matricule, categorie)
VALUES
  ('20000000-0000-0000-0000-00000000d001', '20000000-0000-0000-0000-000000000001', :'dir_id'::uuid,  'C-DIR',  'direction'),
  ('20000000-0000-0000-0000-00000000e001', '20000000-0000-0000-0000-000000000001', :'ens1_id'::uuid, 'C-ENS1', 'enseignant'),
  ('20000000-0000-0000-0000-00000000e002', '20000000-0000-0000-0000-000000000001', :'ens2_id'::uuid, 'C-ENS2', 'enseignant');

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

-- 1. L'employé dépose sa propre demande.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'ens1_id', 'role', 'authenticated')::text, true);
INSERT INTO public.conges (etablissement_id, employe_id, type, date_debut, date_fin, nb_jours, statut)
VALUES ('20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-00000000e001', 'annuel', '2026-10-20', '2026-10-22', 3, 'demande');
SELECT is((SELECT count(*) FROM public.conges)::int, 1, 'congé : dépôt de la propre demande autorisé');

-- 2. L'employé ne peut pas déposer de demande pour un collègue.
SELECT throws_ok(
  $$ INSERT INTO public.conges (etablissement_id, employe_id, type, date_debut, date_fin, nb_jours)
     VALUES ('20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-00000000d001', 'annuel', '2026-10-20', '2026-10-22', 3) $$,
  '42501',
  'congé : dépôt pour un collègue interdit'
);

-- 3. L'employé ne peut pas valider sa propre demande.
UPDATE public.conges SET statut = 'valide' WHERE employe_id = '20000000-0000-0000-0000-00000000e001';
SELECT is(
  (SELECT statut::text FROM public.conges WHERE employe_id = '20000000-0000-0000-0000-00000000e001'),
  'demande',
  'congé : auto-validation impossible (validation humaine requise)'
);

-- 4. La direction valide la demande.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
UPDATE public.conges SET statut = 'valide' WHERE employe_id = '20000000-0000-0000-0000-00000000e001';
SELECT is(
  (SELECT statut::text FROM public.conges WHERE employe_id = '20000000-0000-0000-0000-00000000e001'),
  'valide',
  'congé : validation par la direction autorisée'
);

-- 5. L'employé peut retirer sa propre demande tant qu'elle est « demande ».
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'ens1_id', 'role', 'authenticated')::text, true);
INSERT INTO public.conges (etablissement_id, employe_id, type, date_debut, date_fin, nb_jours, statut)
VALUES ('20000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-00000000e001', 'annuel', '2026-11-10', '2026-11-11', 2, 'demande');
DELETE FROM public.conges WHERE statut = 'demande' AND employe_id = '20000000-0000-0000-0000-00000000e001';
SELECT is((SELECT count(*) FROM public.conges WHERE statut = 'demande')::int, 0, 'congé : retrait de sa propre demande autorisé');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
