-- ============================================================================
-- EcoShop — Test RLS 07 : isolation multi-tenant des structures M5
--
-- Vérifie qu'un membre (direction) d'un établissement A ne voit aucune donnée
-- de l'établissement B : périodes, classes, inscriptions, fiches élèves.
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
-- Deux établissements, chacun avec une année, une période, une classe,
-- une fiche élève et une inscription.
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École M5 A', 'ecole-m5-a') RETURNING id AS etab_a_id \gset
INSERT INTO public.etablissements (nom, slug) VALUES ('École M5 B', 'ecole-m5-b') RETURNING id AS etab_b_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_a_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_a_id \gset
INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_b_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_b_id \gset

INSERT INTO public.periodes_scolaires (etablissement_id, annee_scolaire_id, code, libelle, type, ordre, date_debut, date_fin)
VALUES (:'etab_a_id'::uuid, :'annee_a_id'::uuid, 'T1', '1er trimestre', 'trimestre', 1, '2026-10-01', '2026-12-23'),
       (:'etab_b_id'::uuid, :'annee_b_id'::uuid, 'T1', '1er trimestre', 'trimestre', 1, '2026-10-01', '2026-12-23');

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_a_id'::uuid, :'annee_a_id'::uuid, '6A', '6e A'),
       (:'etab_b_id'::uuid, :'annee_b_id'::uuid, '6A', '6e A');

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance)
VALUES (:'etab_a_id'::uuid, 'MAT-M5-A-001', 'DIALLO', 'Moussa', '2010-01-15'),
       (:'etab_b_id'::uuid, 'MAT-M5-B-001', 'BARRY', 'Aminata', '2010-02-20');

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id)
SELECT :'etab_a_id'::uuid, f.id, c.id, :'annee_a_id'::uuid
FROM public.fiches_eleves f, public.classes c
WHERE f.etablissement_id = :'etab_a_id'::uuid AND c.etablissement_id = :'etab_a_id'::uuid;

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id)
SELECT :'etab_b_id'::uuid, f.id, c.id, :'annee_b_id'::uuid
FROM public.fiches_eleves f, public.classes c
WHERE f.etablissement_id = :'etab_b_id'::uuid AND c.etablissement_id = :'etab_b_id'::uuid;

-- ---------------------------------------------------------------------------
-- Deux directions, une par établissement.
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224600001031', 'direction') AS dir_a_id \gset
SELECT pg_temp.creer_compte('224600001032', 'direction') AS dir_b_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_a_id'::uuid, :'etab_a_id'::uuid, 'direction'),
       (:'dir_b_id'::uuid, :'etab_b_id'::uuid, 'direction');

-- ---------------------------------------------------------------------------
-- Simulation : la direction A consulte.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);

SELECT is((SELECT count(*) FROM public.periodes_scolaires)::int, 1, 'périodes : isolation');
SELECT is((SELECT count(*) FROM public.classes)::int, 1, 'classes : isolation');
SELECT is((SELECT count(*) FROM public.inscriptions)::int, 1, 'inscriptions : isolation');
SELECT is((SELECT count(*) FROM public.fiches_eleves)::int, 1, 'fiches élèves : isolation');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
