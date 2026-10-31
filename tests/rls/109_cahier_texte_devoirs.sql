-- ============================================================================
-- EcoShop — Test RLS 109 : cahier de texte, travail à faire, devoirs
-- numériques (REG-40, migration 20260906001596)
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

SELECT plan(20);

SELECT pg_temp.compte('dir.109@exemple.org', 'direction') AS dir \gset
SELECT pg_temp.compte('prof.109@exemple.org', 'enseignant') AS prof \gset
SELECT pg_temp.compte('autre.109@exemple.org', 'enseignant') AS autre \gset
SELECT pg_temp.compte('eleve.109@exemple.org', 'eleve') AS eleve \gset
SELECT pg_temp.compte('mere.109@exemple.org', 'parent') AS mere \gset
SELECT pg_temp.compte('etranger.109@exemple.org', 'parent') AS etranger \gset

SELECT id AS gn10 FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND code = '10e' \gset

INSERT INTO public.programmes_officiels (id, pays_code, niveau_id, code, nom, statut)
VALUES ('b9100000-0000-0000-0000-000000000001', 'GN', :'gn10', 'TEST-109', 'Programme 109', 'publie');
INSERT INTO public.programmes_matieres (id, programme_id, code, nom, statut)
VALUES ('b9200000-0000-0000-0000-000000000001', 'b9100000-0000-0000-0000-000000000001', 'MATH', 'Maths', 'publie');
INSERT INTO public.chapitres_matiere (id, matiere_id, titre, ordre)
VALUES ('b9300000-0000-0000-0000-000000000001', 'b9200000-0000-0000-0000-000000000001', 'Fractions', 1);
INSERT INTO public.competences_matiere (id, matiere_id, code, libelle)
VALUES ('b9400000-0000-0000-0000-000000000001', 'b9200000-0000-0000-0000-000000000001', 'K', 'Calcul');
INSERT INTO public.questions (id, matiere_id, statut, version_travail, version_publiee)
SELECT ('b9500000-0000-0000-0000-00000000000' || g)::uuid, 'b9200000-0000-0000-0000-000000000001', 'publiee', 1, 1
  FROM generate_series(1, 2) g;
INSERT INTO public.questions_versions (question_id, version, type, difficulte, chapitre_id, competence_id, enonce, contenu, reponse, explication)
SELECT ('b9500000-0000-0000-0000-00000000000' || g)::uuid, 1, 'calcul', 'moyen', 'b9300000-0000-0000-0000-000000000001',
       'b9400000-0000-0000-0000-000000000001', g || ' + ' || g || ' ?', '{}', jsonb_build_object('valeur', 2 * g), 'On double.'
  FROM generate_series(1, 2) g;

INSERT INTO public.etablissements (id, nom, slug, devise_code, pays_code) VALUES
  ('b9000000-0000-0000-0000-00000000000a', 'Lycée 109', 'lycee-109-gn', 'GNF', 'GN');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('b9000000-0000-0000-0000-0000000000a1', 'b9000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom, niveau_id) VALUES
  ('b9000000-0000-0000-0000-0000000000c1', 'b9000000-0000-0000-0000-00000000000a', 'b9000000-0000-0000-0000-0000000000a1', '10A', '10e A', :'gn10'),
  ('b9000000-0000-0000-0000-0000000000c2', 'b9000000-0000-0000-0000-00000000000a', 'b9000000-0000-0000-0000-0000000000a1', '10B', '10e B', :'gn10');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id) VALUES
  ('b9000000-0000-0000-0000-0000000000e1', 'b9000000-0000-0000-0000-00000000000a', 'E1091', 'CAMARA', 'Ibrahima', '2011-02-03', :'eleve');
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('b9000000-0000-0000-0000-00000000000a', 'b9000000-0000-0000-0000-0000000000e1', 'b9000000-0000-0000-0000-0000000000c1', 'b9000000-0000-0000-0000-0000000000a1');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise) VALUES
  ('b9000000-0000-0000-0000-00000000000a', :'mere', 'b9000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true);
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir', 'b9000000-0000-0000-0000-00000000000a', 'direction'),
  (:'prof', 'b9000000-0000-0000-0000-00000000000a', 'enseignant'),
  (:'autre', 'b9000000-0000-0000-0000-00000000000a', 'enseignant');
INSERT INTO public.affectations_enseignants (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id, programme_matiere_id) VALUES
  ('b9000000-0000-0000-0000-00000000000a', 'b9000000-0000-0000-0000-0000000000a1', :'prof', 'b9000000-0000-0000-0000-0000000000c1', 'b9200000-0000-0000-0000-000000000001'),
  ('b9000000-0000-0000-0000-00000000000a', 'b9000000-0000-0000-0000-0000000000a1', :'autre', 'b9000000-0000-0000-0000-0000000000c2', 'b9200000-0000-0000-0000-000000000001');

SET LOCAL ROLE authenticated;

-- ---------------------------------------------------------------------------
-- 1. Écrire le cahier : l'enseignant de la classe, pas un autre
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'prof');
SELECT lives_ok($$ INSERT INTO public.cahier_texte (id, etablissement_id, annee_scolaire_id, classe_id, programme_matiere_id,
  chapitre_id, date_seance, titre, contenu) VALUES ('b9600000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-00000000000a',
  'b9000000-0000-0000-0000-0000000000a1', 'b9000000-0000-0000-0000-0000000000c1', 'b9200000-0000-0000-0000-000000000001',
  'b9300000-0000-0000-0000-000000000001', current_date, 'Addition de fractions', 'Méthode et exemples') $$,
  'l''enseignant de la classe écrit le cahier');
SELECT lives_ok($$ INSERT INTO public.travaux (id, etablissement_id, annee_scolaire_id, classe_id, programme_matiere_id, type, titre,
  pour_le, temps_estime_min) VALUES ('b9700000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-00000000000a',
  'b9000000-0000-0000-0000-0000000000a1', 'b9000000-0000-0000-0000-0000000000c1', 'b9200000-0000-0000-0000-000000000001',
  'exercices', 'Exercices 1 à 4 page 32', current_date + 1, 30) $$, 'il donne du travail');
SELECT lives_ok($$ INSERT INTO public.travaux (id, etablissement_id, annee_scolaire_id, classe_id, programme_matiere_id, chapitre_id,
  type, titre, pour_le, temps_estime_min, questions) VALUES ('b9700000-0000-0000-0000-000000000002', 'b9000000-0000-0000-0000-00000000000a',
  'b9000000-0000-0000-0000-0000000000a1', 'b9000000-0000-0000-0000-0000000000c1', 'b9200000-0000-0000-0000-000000000001',
  'b9300000-0000-0000-0000-000000000001', 'devoir_numerique', 'Devoir sur les fractions', current_date + 2, 15,
  '{b9500000-0000-0000-0000-000000000001,b9500000-0000-0000-0000-000000000002}') $$, 'et un devoir numérique');
SELECT throws_ok($$ INSERT INTO public.travaux (id, etablissement_id, annee_scolaire_id, classe_id, type, titre, pour_le)
  VALUES (gen_random_uuid(), 'b9000000-0000-0000-0000-00000000000a', 'b9000000-0000-0000-0000-0000000000a1',
  'b9000000-0000-0000-0000-0000000000c1', 'devoir_numerique', 'Sans questions', current_date + 1) $$,
  '23514', NULL, 'un devoir numérique a des questions');
SELECT is(jsonb_array_length(public.questions_pour_devoir('b9200000-0000-0000-0000-000000000001', 'b9300000-0000-0000-0000-000000000001')),
  2, 'questions publiées du chapitre pour composer le devoir');

SELECT pg_temp.sur(:'autre');
SELECT throws_ok($$ INSERT INTO public.cahier_texte (id, etablissement_id, annee_scolaire_id, classe_id, date_seance, titre)
  VALUES (gen_random_uuid(), 'b9000000-0000-0000-0000-00000000000a', 'b9000000-0000-0000-0000-0000000000a1',
  'b9000000-0000-0000-0000-0000000000c1', current_date, 'Intrus') $$, '42501', NULL,
  'un enseignant d''une autre classe n''écrit pas ce cahier');

-- ---------------------------------------------------------------------------
-- 2. Notifications aux élèves et parents
-- ---------------------------------------------------------------------------
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications WHERE type = 'travail_a_faire'
            AND variables ->> 'travail_id' = 'b9700000-0000-0000-0000-000000000001'), 2,
  'l''élève et sa mère sont prévenus du travail');
SET LOCAL ROLE authenticated;

-- ---------------------------------------------------------------------------
-- 3. Côté famille
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'mere');
SELECT is(jsonb_array_length(public.travaux_fiche('b9000000-0000-0000-0000-0000000000e1')), 2, 'la mère voit le travail de son enfant');
SELECT is(jsonb_array_length(public.cahier_fiche('b9000000-0000-0000-0000-0000000000e1')), 1, 'et le cahier de texte de sa classe');
SELECT is((public.accueil_resume('b9000000-0000-0000-0000-00000000000a', 'b9000000-0000-0000-0000-0000000000e1')
  ->> 'travaux_a_faire')::int, 2, 'badge de l''accueil : 2 travaux d''ici après-demain');
SELECT lives_ok($$ SELECT public.marquer_travail_fait('b9700000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-0000000000e1', true) $$,
  'la mère coche « fait »');
SELECT throws_ok($$ SELECT public.marquer_travail_fait('b9700000-0000-0000-0000-000000000002', 'b9000000-0000-0000-0000-0000000000e1', true) $$,
  '22023', 'DEVOIR_A_REMETTRE', 'un devoir numérique se remet, il ne se coche pas');

SELECT pg_temp.sur(:'eleve');
SELECT public.sujet_devoir('b9700000-0000-0000-0000-000000000002', 'b9000000-0000-0000-0000-0000000000e1', false) AS sujet \gset
SELECT is(jsonb_array_length(:'sujet'::jsonb -> 'questions'), 2, 'l''élève télécharge le sujet');
SELECT is(:'sujet'::jsonb #> '{questions,0,reponse}', '{}'::jsonb, 'sans les bonnes réponses');
SELECT is((public.remettre_devoir('b9700000-0000-0000-0000-000000000002', 'b9000000-0000-0000-0000-0000000000e1',
  '{"b9500000-0000-0000-0000-000000000001": "2", "b9500000-0000-0000-0000-000000000002": "5"}', 300) ->> 'score')::numeric,
  1.000, 'correction par le serveur : 1 sur 2');
SELECT is((public.remettre_devoir('b9700000-0000-0000-0000-000000000002', 'b9000000-0000-0000-0000-0000000000e1', '{}')
  ->> 'deja_remis')::boolean, true, 'une seule remise');

SELECT pg_temp.sur(:'etranger');
SELECT throws_ok($$ SELECT public.travaux_fiche('b9000000-0000-0000-0000-0000000000e1') $$, '42501', NULL,
  'un parent d''une autre famille ne voit rien');
SELECT is((SELECT count(*)::int FROM public.cahier_texte), 0, 'ni le cahier de texte');

-- ---------------------------------------------------------------------------
-- 4. Suivi de l'enseignant, avancement de la direction
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'prof');
SELECT is((public.suivi_travail('b9700000-0000-0000-0000-000000000002') #>> '{questions,0,reussite}')::numeric, 0.000,
  'la question la plus ratée vient en premier');

SELECT pg_temp.sur(:'dir');
SELECT lives_ok($$ SELECT public.avancement_cahier('b9000000-0000-0000-0000-00000000000a') $$, 'la direction suit l''avancement');

SELECT * FROM finish();
ROLLBACK;
