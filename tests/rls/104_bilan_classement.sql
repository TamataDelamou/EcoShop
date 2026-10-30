-- ============================================================================
-- EcoShop — Test RLS 104 : bilan hebdomadaire, classement de la semaine,
-- mode examen (REG-37, migration 20260906001588)
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

-- Tentative directe (sans passer par l'API) pour préparer les données.
CREATE OR REPLACE FUNCTION pg_temp.tentative(p_id uuid, p_fiche uuid, p_mode text, p_n int, p_justes int, p_duree int)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.tentatives_revision (id, fiche_eleve_id, mode, nb_questions, nb_repondues, points, duree_s, termine, commence_le)
  VALUES (p_id, p_fiche, p_mode, p_n, p_n, p_justes, p_duree, true, now());
  INSERT INTO public.reponses_revision (tentative_id, question_id, version, ordre, score)
  SELECT p_id, ('d5000000-0000-0000-0000-0000000000' || lpad((g + 1)::text, 2, '0'))::uuid, 1, g,
         CASE WHEN g < p_justes THEN 1 ELSE 0 END
    FROM generate_series(0, p_n - 1) g;
END $$;

SELECT plan(13);

SELECT pg_temp.compte('contenu.104@exemple.org', 'admin_contenu') AS contenu \gset
SELECT pg_temp.compte('mere.104@exemple.org', 'parent') AS mere \gset
SELECT pg_temp.compte('autre.104@exemple.org', 'parent') AS autre \gset

SELECT id AS niveau FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND code = '7e' \gset
SELECT id AS cp1 FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND code = 'CP1' \gset
INSERT INTO public.programmes_officiels (id, pays_code, niveau_id, code, nom, statut)
VALUES ('d1000000-0000-0000-0000-000000000001', 'GN', :'niveau', 'TEST-7E-104', 'Programme test', 'publie');
INSERT INTO public.programmes_matieres (id, programme_id, code, nom, statut)
VALUES ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'MATH104', 'Maths 104', 'publie');
INSERT INTO public.competences_matiere (id, matiere_id, code, libelle)
VALUES ('d4000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'FRAC', 'Fractions');
-- Dix questions publiées de la même compétence.
INSERT INTO public.questions (id, matiere_id, statut, version_travail, version_publiee)
SELECT ('d5000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid,
       'd2000000-0000-0000-0000-000000000001', 'publiee', 1, 1
  FROM generate_series(1, 10) g;
INSERT INTO public.questions_versions (question_id, version, type, difficulte, competence_id, enonce, reponse, explication)
SELECT ('d5000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid, 1, 'vrai_faux', 'facile',
       'd4000000-0000-0000-0000-000000000001', 'Q' || g, '{"valeur": true}', 'E'
  FROM generate_series(1, 10) g;

INSERT INTO public.etablissements (id, nom, slug, devise_code)
VALUES ('d0000000-0000-0000-0000-00000000000a', 'École 104', 'ecole-104', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('d0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom, niveau_id) VALUES
  ('d0000000-0000-0000-0000-0000000000c1', 'd0000000-0000-0000-0000-00000000000a', 'd0000000-0000-0000-0000-0000000000a1', '7A', '7e A', :'niveau'),
  ('d0000000-0000-0000-0000-0000000000c2', 'd0000000-0000-0000-0000-00000000000a', 'd0000000-0000-0000-0000-0000000000a1', 'CP1A', 'CP1 A', :'cp1');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance) VALUES
  ('d0000000-0000-0000-0000-0000000000e1', 'd0000000-0000-0000-0000-00000000000a', 'E1041', 'BAH', 'Awa', '2013-02-03'),
  ('d0000000-0000-0000-0000-0000000000e2', 'd0000000-0000-0000-0000-00000000000a', 'E1042', 'DIALLO', 'Moussa', '2013-04-05'),
  ('d0000000-0000-0000-0000-0000000000e3', 'd0000000-0000-0000-0000-00000000000a', 'E1043', 'SOW', 'Binta', '2013-06-07'),
  ('d0000000-0000-0000-0000-0000000000e4', 'd0000000-0000-0000-0000-00000000000a', 'E1044', 'KABA', 'Ali', '2019-06-07');
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('d0000000-0000-0000-0000-00000000000a', 'd0000000-0000-0000-0000-0000000000e1', 'd0000000-0000-0000-0000-0000000000c1', 'd0000000-0000-0000-0000-0000000000a1'),
  ('d0000000-0000-0000-0000-00000000000a', 'd0000000-0000-0000-0000-0000000000e2', 'd0000000-0000-0000-0000-0000000000c1', 'd0000000-0000-0000-0000-0000000000a1'),
  ('d0000000-0000-0000-0000-00000000000a', 'd0000000-0000-0000-0000-0000000000e3', 'd0000000-0000-0000-0000-0000000000c1', 'd0000000-0000-0000-0000-0000000000a1'),
  ('d0000000-0000-0000-0000-00000000000a', 'd0000000-0000-0000-0000-0000000000e4', 'd0000000-0000-0000-0000-0000000000c2', 'd0000000-0000-0000-0000-0000000000a1');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise) VALUES
  ('d0000000-0000-0000-0000-00000000000a', :'mere', 'd0000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true),
  ('d0000000-0000-0000-0000-00000000000a', :'mere', 'd0000000-0000-0000-0000-0000000000e4', 'parent', 'confirmee', true);

-- Awa : un quiz de 5 (2 justes) → 20 + 50 = 70. Moussa : un examen de 10
-- (8 justes) → 80 + 100 = 180. Binta : 10 réponses parfaites en 5 s → écartée.
SELECT pg_temp.tentative('d6000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-0000000000e1', 'rapide', 5, 2, 120);
SELECT pg_temp.tentative('d6000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-0000000000e2', 'examen', 10, 8, 900);
SELECT pg_temp.tentative('d6000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-0000000000e3', 'standard', 10, 10, 5);

SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'mere');

-- ---------------------------------------------------------------------------
-- Classement
-- ---------------------------------------------------------------------------
SELECT public.classement_revision('d0000000-0000-0000-0000-0000000000e1') AS c \gset
SELECT is((:'c'::jsonb -> 'lignes' -> 0 ->> 'nom'), 'Moussa D.', 'prénom et initiale seulement, le premier en tête');
SELECT is((:'c'::jsonb ->> 'mon_rang')::int, 2, 'Awa est deuxième');
SELECT is((:'c'::jsonb ->> 'participants')::int, 2, 'une tentative trop rapide et parfaite est écartée (23.4)');
SELECT is((:'c'::jsonb -> 'lignes' -> 1 ->> 'points')::int, 70, 'barème 22.1 : bonnes réponses et quiz terminé');
SELECT is((public.classement_revision('d0000000-0000-0000-0000-0000000000e4') ->> 'raison'), 'PETITES_CLASSES',
  'pas de classement en CP1 (22.3)');

SELECT lives_ok($$ SELECT public.definir_classement_visible('d0000000-0000-0000-0000-0000000000e1', false) $$,
  'le parent retire son enfant du classement');
SELECT is((public.classement_revision('d0000000-0000-0000-0000-0000000000e1') ->> 'participants')::int, 1,
  'retirée, elle n''apparaît plus');
SELECT is((public.classement_revision('d0000000-0000-0000-0000-0000000000e1') ->> 'mes_points')::int, 70,
  'mais garde ses points');

SELECT pg_temp.sur(:'autre');
SELECT throws_ok($$ SELECT public.classement_revision('d0000000-0000-0000-0000-0000000000e1') $$,
  '42501', NULL, 'un autre parent ne voit rien');

-- ---------------------------------------------------------------------------
-- Bilan hebdomadaire
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'mere');
SELECT matches(public.bilan_revision('d0000000-0000-0000-0000-0000000000e1'),
  '^Cette semaine, Awa a révisé 2 min : 1 quiz terminé, 40 % de bonnes réponses\. À travailler : « Fractions »',
  'bilan concret : temps, quiz, réussite, compétence à travailler');
SELECT matches(public.bilan_revision('d0000000-0000-0000-0000-0000000000e4'), 'n''a pas révisé cette semaine',
  'sans activité : une invitation simple');

RESET ROLE;
SELECT ok(public.envoyer_bilans_revision() >= 1, 'bilan envoyé au parent dont l''enfant révise');
SELECT is(public.envoyer_bilans_revision(), 0, 'pas deux fois la même semaine');

SELECT * FROM finish();
ROLLBACK;
