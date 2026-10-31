-- ============================================================================
-- EcoShop — Test RLS 106 : espaces de préparation aux examens (REG-38 lot
-- E1, migration 20260906001590)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.sur(p_uid uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  UPDATE public.profiles SET role_racine = p_role::public.role_racine, prenom = 'Test', nom = 'Test' WHERE id = v_id;
  RETURN v_id;
END $$;

SELECT plan(16);

SELECT pg_temp.compte('contenu.106@exemple.org', 'admin_contenu') AS contenu \gset
SELECT pg_temp.compte('mere.106@exemple.org', 'parent') AS mere \gset

SELECT id AS n10 FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND code = '10e' \gset
SELECT id AS n9 FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND code = '9e' \gset
SELECT id AS bepc FROM public.examens_nationaux WHERE pays_code = 'GN' AND code = 'BEPC' \gset
SELECT id AS bfem FROM public.examens_nationaux WHERE pays_code = 'SN' AND code = 'BFEM' \gset

INSERT INTO public.programmes_officiels (id, pays_code, niveau_id, code, nom, statut)
VALUES ('f1000000-0000-0000-0000-000000000001', 'GN', :'n10', 'TEST-10E-106', 'Programme test 10e', 'publie');
INSERT INTO public.programmes_matieres (id, programme_id, code, nom, statut)
VALUES ('f2000000-0000-0000-0000-000000000001', 'f1000000-0000-0000-0000-000000000001', 'MATH', 'Mathématiques', 'publie');

INSERT INTO public.etablissements (id, nom, slug, devise_code)
VALUES ('f0000000-0000-0000-0000-00000000000a', 'École 106', 'ecole-106', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('f0000000-0000-0000-0000-0000000000a1', 'f0000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom, niveau_id) VALUES
  ('f0000000-0000-0000-0000-0000000000c1', 'f0000000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-0000000000a1', '10A', '10e A', :'n10'),
  ('f0000000-0000-0000-0000-0000000000c2', 'f0000000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-0000000000a1', '9A', '9e A', :'n9');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance) VALUES
  ('f0000000-0000-0000-0000-0000000000e1', 'f0000000-0000-0000-0000-00000000000a', 'E1061', 'BAH', 'Awa', '2011-02-03'),
  ('f0000000-0000-0000-0000-0000000000e2', 'f0000000-0000-0000-0000-00000000000a', 'E1062', 'SOW', 'Ali', '2012-02-03');
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('f0000000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-0000000000e1', 'f0000000-0000-0000-0000-0000000000c1', 'f0000000-0000-0000-0000-0000000000a1'),
  ('f0000000-0000-0000-0000-00000000000a', 'f0000000-0000-0000-0000-0000000000e2', 'f0000000-0000-0000-0000-0000000000c2', 'f0000000-0000-0000-0000-0000000000a1');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise) VALUES
  ('f0000000-0000-0000-0000-00000000000a', :'mere', 'f0000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true),
  ('f0000000-0000-0000-0000-00000000000a', :'mere', 'f0000000-0000-0000-0000-0000000000e2', 'parent', 'confirmee', true);

SET LOCAL ROLE authenticated;

-- ---------------------------------------------------------------------------
-- 1. Format de l'examen, par l'Administrateur de contenu
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'mere');
SELECT throws_ok($$ INSERT INTO public.epreuves_examen (examen_id, matiere_code, libelle, duree_min)
  SELECT id, 'MATH', 'Mathématiques', 120 FROM public.examens_nationaux WHERE pays_code = 'GN' AND code = 'BEPC' $$,
  '42501', NULL, 'un parent ne déclare pas d''épreuve');

SELECT pg_temp.sur(:'contenu');
SELECT lives_ok($$
  INSERT INTO public.epreuves_examen (id, examen_id, matiere_code, libelle, duree_min, coefficient, questions_blanc)
  SELECT 'f7000000-0000-0000-0000-000000000001', id, 'math', 'Mathématiques', 120, 3, 20
    FROM public.examens_nationaux WHERE pays_code = 'GN' AND code = 'BEPC'
$$, 'épreuve de mathématiques du BEPC (2 h, coefficient 3)');
SELECT lives_ok($$
  INSERT INTO public.sessions_examen (examen_id, annee, date_debut)
  SELECT id, extract(year from current_date)::int + 1, current_date + 200
    FROM public.examens_nationaux WHERE pays_code = 'GN' AND code = 'BEPC'
$$, 'date de la prochaine session');

-- ---------------------------------------------------------------------------
-- 2. Annales : droit de diffusion et circuit
-- ---------------------------------------------------------------------------
SELECT lives_ok($$ SELECT public.enregistrer_annale('f8000000-0000-0000-0000-000000000001',
  (SELECT id FROM public.examens_nationaux WHERE pays_code = 'GN' AND code = 'BEPC'), 2025,
  'BEPC 2025 — Mathématiques', 'Ministère de l''Éducation nationale', 'a_verifier', 'normale',
  'f7000000-0000-0000-0000-000000000001', NULL, 'bepc/2025-math.pdf') $$, 'annale enregistrée, droit à vérifier');
SELECT public.changer_statut_annale('f8000000-0000-0000-0000-000000000001', 'soumettre');
SELECT public.changer_statut_annale('f8000000-0000-0000-0000-000000000001', 'valider');
SELECT throws_ok($$ SELECT public.changer_statut_annale('f8000000-0000-0000-0000-000000000001', 'publier') $$,
  '22023', 'DROIT_DIFFUSION_A_VERIFIER', 'pas de publication tant que le droit n''est pas établi (RG-013-01)');

SELECT pg_temp.sur(:'mere');
SELECT is((SELECT count(*)::int FROM public.annales), 0, 'une annale non publiée est invisible');

SELECT pg_temp.sur(:'contenu');
SELECT public.enregistrer_annale('f8000000-0000-0000-0000-000000000001', :'bepc', 2025,
  'BEPC 2025 — Mathématiques', 'Ministère de l''Éducation nationale', 'source_officielle', 'normale',
  'f7000000-0000-0000-0000-000000000001', NULL, 'bepc/2025-math.pdf');
SELECT is((SELECT statut::text FROM public.annales WHERE id = 'f8000000-0000-0000-0000-000000000001'), 'brouillon',
  'une modification remet l''annale au brouillon');
SELECT public.changer_statut_annale('f8000000-0000-0000-0000-000000000001', 'soumettre');
SELECT public.changer_statut_annale('f8000000-0000-0000-0000-000000000001', 'valider');
SELECT lives_ok($$ SELECT public.changer_statut_annale('f8000000-0000-0000-0000-000000000001', 'publier') $$,
  'source officielle, validée : publiée');

-- ---------------------------------------------------------------------------
-- 3. Espace de l'élève
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'mere');
SELECT public.espaces_preparation('f0000000-0000-0000-0000-0000000000e1') AS esp \gset
SELECT is(jsonb_array_length(:'esp'::jsonb), 1, 'classe de 10e : un espace');
SELECT is(:'esp'::jsonb -> 0 ->> 'code', 'BEPC', 'celui du BEPC de Guinée, pas le BFEM du Sénégal');
SELECT is(:'esp'::jsonb #>> '{0,epreuves,0,matiere_id}', 'f2000000-0000-0000-0000-000000000001',
  'l''épreuve est reliée à la matière du programme de 10e');
SELECT is(jsonb_array_length(:'esp'::jsonb #> '{0,annales}'), 1, 'l''annale publiée apparaît');
SELECT ok(:'esp'::jsonb #> '{0,session}' IS NOT NULL AND :'esp'::jsonb #> '{0,session}' <> 'null'::jsonb,
  'date de session pour le compte à rebours');
SELECT is(public.espaces_preparation('f0000000-0000-0000-0000-0000000000e2'), '[]'::jsonb,
  'classe de 9e (intermédiaire) : aucun espace (13.1)');

-- Examen blanc marqué par examen et épreuve.
SELECT lives_ok(format($$ SELECT public.enregistrer_tentative_revision('{
  "id": "f9000000-0000-0000-0000-000000000001", "fiche_eleve_id": "f0000000-0000-0000-0000-0000000000e1",
  "mode": "examen", "nb_questions": 4, "duree_s": 3600, "termine": true,
  "examen_id": "%s", "epreuve_id": "f7000000-0000-0000-0000-000000000001", "reponses": []}') $$, :'bepc'),
  'épreuve blanche enregistrée');
SELECT is((public.espaces_preparation('f0000000-0000-0000-0000-0000000000e1') #>> '{0,blancs,0,nombre}')::int, 1,
  'statistiques propres à l''examen (RG-013-02)');

SELECT * FROM finish();
ROLLBACK;
