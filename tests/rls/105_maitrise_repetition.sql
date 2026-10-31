-- ============================================================================
-- EcoShop — Test RLS 105 : répétition espacée, profil de maîtrise, vue de
-- classe, plan de révision (REG-37 lot R4, migration 20260906001589)
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

-- Une réponse à la question q, il y a p_jours jours.
CREATE OR REPLACE FUNCTION pg_temp.repondre(p_fiche uuid, p_question uuid, p_score numeric, p_jours int)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_t uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.tentatives_revision (id, fiche_eleve_id, mode, nb_questions, nb_repondues, points, duree_s, termine, commence_le)
  VALUES (v_t, p_fiche, 'rapide', 1, 1, p_score, 30, true, now() - make_interval(days => p_jours));
  INSERT INTO public.reponses_revision (tentative_id, question_id, version, ordre, score)
  VALUES (v_t, p_question, 1, 0, p_score);
END $$;

SELECT plan(14);

SELECT pg_temp.compte('mere.105@exemple.org', 'parent') AS mere \gset
SELECT pg_temp.compte('prof.105@exemple.org', 'enseignant') AS prof \gset
SELECT pg_temp.compte('autreprof.105@exemple.org', 'enseignant') AS autreprof \gset

SELECT id AS niveau FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND code = '7e' \gset
INSERT INTO public.programmes_officiels (id, pays_code, niveau_id, code, nom, statut)
VALUES ('e1000000-0000-0000-0000-000000000001', 'GN', :'niveau', 'TEST-7E-105', 'Programme test', 'publie');
INSERT INTO public.programmes_matieres (id, programme_id, code, nom, statut, coefficient)
VALUES ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'MATH105', 'Maths 105', 'publie', 4);
INSERT INTO public.competences_matiere (id, matiere_id, code, libelle) VALUES
  ('e4000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000001', 'FRAC', 'Fractions'),
  ('e4000000-0000-0000-0000-000000000002', 'e2000000-0000-0000-0000-000000000001', 'GEO', 'Géométrie');
INSERT INTO public.questions (id, matiere_id, statut, version_travail, version_publiee)
SELECT ('e5000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid,
       'e2000000-0000-0000-0000-000000000001', 'publiee', 1, 1
  FROM generate_series(1, 6) g;
INSERT INTO public.questions_versions (question_id, version, type, difficulte, competence_id, enonce, reponse, explication)
SELECT ('e5000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid, 1, 'vrai_faux', 'facile',
       CASE WHEN g <= 3 THEN 'e4000000-0000-0000-0000-000000000001'::uuid ELSE 'e4000000-0000-0000-0000-000000000002'::uuid END,
       'Q' || g, '{"valeur": true}', 'E'
  FROM generate_series(1, 6) g;

INSERT INTO public.etablissements (id, nom, slug, devise_code)
VALUES ('e0000000-0000-0000-0000-00000000000a', 'École 105', 'ecole-105', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('e0000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom, niveau_id, enseignant_principal_id)
VALUES ('e0000000-0000-0000-0000-0000000000c1', 'e0000000-0000-0000-0000-00000000000a',
        'e0000000-0000-0000-0000-0000000000a1', '7A', '7e A', :'niveau', :'prof');
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'prof', 'e0000000-0000-0000-0000-00000000000a', 'enseignant'),
  (:'autreprof', 'e0000000-0000-0000-0000-00000000000a', 'enseignant');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance) VALUES
  ('e0000000-0000-0000-0000-0000000000e1', 'e0000000-0000-0000-0000-00000000000a', 'E1051', 'BAH', 'Awa', '2013-02-03'),
  ('e0000000-0000-0000-0000-0000000000e2', 'e0000000-0000-0000-0000-00000000000a', 'E1052', 'DIALLO', 'Moussa', '2013-04-05');
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('e0000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-0000000000e1', 'e0000000-0000-0000-0000-0000000000c1', 'e0000000-0000-0000-0000-0000000000a1'),
  ('e0000000-0000-0000-0000-00000000000a', 'e0000000-0000-0000-0000-0000000000e2', 'e0000000-0000-0000-0000-0000000000c1', 'e0000000-0000-0000-0000-0000000000a1');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
VALUES ('e0000000-0000-0000-0000-00000000000a', :'mere', 'e0000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true);

-- ---------------------------------------------------------------------------
-- 1. Paliers J1 → J2 → J4 → J7 ; échec : palier précédent
-- ---------------------------------------------------------------------------
-- Q1 : juste il y a 10 j (palier 1), juste il y a 9 j à l'échéance (palier 2),
-- juste il y a 7 j (palier 3, revue dans 3 j) : à revoir aujourd'hui.
SELECT pg_temp.repondre('e0000000-0000-0000-0000-0000000000e1', 'e5000000-0000-0000-0000-000000000001', 1, 10);
SELECT pg_temp.repondre('e0000000-0000-0000-0000-0000000000e1', 'e5000000-0000-0000-0000-000000000001', 1, 9);
SELECT pg_temp.repondre('e0000000-0000-0000-0000-0000000000e1', 'e5000000-0000-0000-0000-000000000001', 1, 7);
SELECT is((SELECT palier FROM public.cartes_revision WHERE question_id = 'e5000000-0000-0000-0000-000000000001'), 3,
  'trois réussites à l''échéance : palier J7');
SELECT is((SELECT echeance FROM public.cartes_revision WHERE question_id = 'e5000000-0000-0000-0000-000000000001'),
  (now() - interval '7 days' + interval '3 days')::date, 'prochaine révision trois jours plus tard');
-- Échec il y a 2 j : redescend d'un palier, revue le lendemain.
SELECT pg_temp.repondre('e0000000-0000-0000-0000-0000000000e1', 'e5000000-0000-0000-0000-000000000001', 0, 2);
SELECT is((SELECT palier FROM public.cartes_revision WHERE question_id = 'e5000000-0000-0000-0000-000000000001'), 2,
  'échec : palier précédent, pas retour à zéro (15.1)');
-- Q2 : juste aujourd'hui : pas encore due. Réponse ancienne arrivée en retard : ignorée.
SELECT pg_temp.repondre('e0000000-0000-0000-0000-0000000000e1', 'e5000000-0000-0000-0000-000000000002', 1, 0);
SELECT pg_temp.repondre('e0000000-0000-0000-0000-0000000000e1', 'e5000000-0000-0000-0000-000000000002', 0, 5);
SELECT is((SELECT palier FROM public.cartes_revision WHERE question_id = 'e5000000-0000-0000-0000-000000000002'), 1,
  'une réponse plus ancienne envoyée en retard ne recule pas le calendrier');

-- Géométrie : trois échecs (Q4, Q5, Q6).
SELECT pg_temp.repondre('e0000000-0000-0000-0000-0000000000e1', ('e5000000-0000-0000-0000-00000000000' || g)::uuid, 0, 1)
  FROM generate_series(4, 6) g;
-- Moussa : géométrie réussie.
SELECT pg_temp.repondre('e0000000-0000-0000-0000-0000000000e2', ('e5000000-0000-0000-0000-00000000000' || g)::uuid, 1, 1)
  FROM generate_series(4, 6) g;

SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'mere');
SELECT is((public.revisions_du_jour('e0000000-0000-0000-0000-0000000000e1') ->> 'dues')::int, 4,
  'à revoir aujourd''hui : Q1 et les trois de géométrie');
SELECT is(jsonb_array_length(public.revisions_du_jour('e0000000-0000-0000-0000-0000000000e1', 2) -> 'cartes'), 2,
  'nombre de cartes plafonné');

-- ---------------------------------------------------------------------------
-- 2. Profil de maîtrise
-- ---------------------------------------------------------------------------
SELECT public.profil_maitrise('e0000000-0000-0000-0000-0000000000e1') AS profil \gset
SELECT ok((SELECT (x ->> 'maitrise')::numeric < 0.5 FROM jsonb_array_elements(:'profil'::jsonb) x
            WHERE x ->> 'competence_id' = 'e4000000-0000-0000-0000-000000000002'), 'géométrie sous 50 % : point faible');
SELECT is((SELECT (x ->> 'echecs_repetes')::boolean FROM jsonb_array_elements(:'profil'::jsonb) x
            WHERE x ->> 'competence_id' = 'e4000000-0000-0000-0000-000000000002'), true, 'trois échecs de suite repérés');
SELECT ok((SELECT (x ->> 'maitrise')::numeric BETWEEN 0.5 AND 0.99 FROM jsonb_array_elements(:'profil'::jsonb) x
            WHERE x ->> 'competence_id' = 'e4000000-0000-0000-0000-000000000001'),
  'fractions : jamais 100 % d''emblée, la dernière réponse ratée pèse le plus');

-- ---------------------------------------------------------------------------
-- 3. Vue de la classe
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'prof');
SELECT public.maitrise_classe('e0000000-0000-0000-0000-0000000000c1') AS classe \gset
SELECT is((SELECT (x ->> 'sous_seuil')::int FROM jsonb_array_elements(:'classe'::jsonb -> 'competences') x
            WHERE x ->> 'libelle' = 'Géométrie'), 1, 'l''enseignant voit une élève sous le seuil en géométrie');
SELECT is((SELECT x -> 'eleves_sous_seuil' ->> 0 FROM jsonb_array_elements(:'classe'::jsonb -> 'competences') x
            WHERE x ->> 'libelle' = 'Géométrie'), 'Awa BAH', 'et qui, pour l''aider');
SELECT pg_temp.sur(:'autreprof');
SELECT throws_ok($$ SELECT public.maitrise_classe('e0000000-0000-0000-0000-0000000000c1') $$,
  '42501', NULL, 'un enseignant qui n''a pas la classe ne la voit pas');

-- ---------------------------------------------------------------------------
-- 4. Plan de révision
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'mere');
SELECT lives_ok($$ SELECT public.definir_plan_revision('e0000000-0000-0000-0000-0000000000e1', 'BEPC blanc',
  current_date + 60, array['e2000000-0000-0000-0000-000000000001']::uuid[], 10) $$, 'le parent fixe un plan à 60 jours');
SELECT throws_ok($$ SELECT public.definir_plan_revision('e0000000-0000-0000-0000-0000000000e1', 'X',
  current_date - 1, array['e2000000-0000-0000-0000-000000000001']::uuid[]) $$, '22023', 'ECHEANCE_INVALIDE',
  'pas d''échéance dans le passé');

SELECT * FROM finish();
ROLLBACK;
