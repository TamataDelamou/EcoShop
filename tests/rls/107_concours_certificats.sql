-- ============================================================================
-- EcoShop — Test RLS 107 : concours, olympiades, certificats (REG-38 lot
-- E2a, migration 20260906001591)
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

SELECT pg_temp.compte('gsg.107@exemple.org', 'admin_gsg') AS gsg \gset
SELECT pg_temp.compte('dir.107@exemple.org', 'direction') AS dir \gset
SELECT pg_temp.compte('mere.107@exemple.org', 'parent') AS mere \gset
SELECT pg_temp.compte('pere.107@exemple.org', 'parent') AS pere \gset

SELECT id AS gn10 FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND code = '10e' \gset
SELECT id AS sn3 FROM public.niveaux_educatifs WHERE pays_code = 'SN' AND code = '3e' \gset

-- Questions publiées : 2 emplacements, 3 variantes au premier.
INSERT INTO public.programmes_officiels (id, pays_code, niveau_id, code, nom, statut)
VALUES ('a7100000-0000-0000-0000-000000000001', 'GN', :'gn10', 'TEST-107', 'Programme 107', 'publie');
INSERT INTO public.programmes_matieres (id, programme_id, code, nom, statut)
VALUES ('a7200000-0000-0000-0000-000000000001', 'a7100000-0000-0000-0000-000000000001', 'MATH', 'Maths', 'publie');
INSERT INTO public.competences_matiere (id, matiere_id, code, libelle)
VALUES ('a7400000-0000-0000-0000-000000000001', 'a7200000-0000-0000-0000-000000000001', 'K', 'Calcul');
INSERT INTO public.questions (id, matiere_id, statut, version_travail, version_publiee)
SELECT ('a7500000-0000-0000-0000-00000000000' || g)::uuid, 'a7200000-0000-0000-0000-000000000001', 'publiee', 1, 1
  FROM generate_series(1, 4) g;
INSERT INTO public.questions_versions (question_id, version, type, difficulte, competence_id, enonce, contenu, reponse, explication)
SELECT ('a7500000-0000-0000-0000-00000000000' || g)::uuid, 1, 'calcul', 'moyen', 'a7400000-0000-0000-0000-000000000001',
       g || ' + ' || g || ' ?', '{}', jsonb_build_object('valeur', 2 * g), 'On double.'
  FROM generate_series(1, 3) g;
INSERT INTO public.questions_versions (question_id, version, type, difficulte, competence_id, enonce, contenu, reponse, explication)
VALUES ('a7500000-0000-0000-0000-000000000004', 1, 'reponse_courte', 'facile', 'a7400000-0000-0000-0000-000000000001',
        'Capitale de la Guinée ?', '{}', '{"acceptees": ["Conakry"]}', 'Conakry.');

INSERT INTO public.etablissements (id, nom, slug, devise_code, pays_code) VALUES
  ('a7000000-0000-0000-0000-00000000000a', 'Lycée Conakry', 'lycee-107-gn', 'GNF', 'GN'),
  ('a7000000-0000-0000-0000-00000000000b', 'Collège Dakar', 'college-107-sn', 'XOF', 'SN');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('a7000000-0000-0000-0000-0000000000a1', 'a7000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true),
  ('a7000000-0000-0000-0000-0000000000b1', 'a7000000-0000-0000-0000-00000000000b', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom, niveau_id) VALUES
  ('a7000000-0000-0000-0000-0000000000c1', 'a7000000-0000-0000-0000-00000000000a', 'a7000000-0000-0000-0000-0000000000a1', '10A', '10e A', :'gn10'),
  ('a7000000-0000-0000-0000-0000000000c2', 'a7000000-0000-0000-0000-00000000000b', 'a7000000-0000-0000-0000-0000000000b1', '3A', '3e A', :'sn3');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance) VALUES
  ('a7000000-0000-0000-0000-0000000000e1', 'a7000000-0000-0000-0000-00000000000a', 'E1071', 'BAH', 'Awa', '2011-02-03'),
  ('a7000000-0000-0000-0000-0000000000e2', 'a7000000-0000-0000-0000-00000000000b', 'E1072', 'NDIAYE', 'Fatou', '2011-04-05');
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('a7000000-0000-0000-0000-00000000000a', 'a7000000-0000-0000-0000-0000000000e1', 'a7000000-0000-0000-0000-0000000000c1', 'a7000000-0000-0000-0000-0000000000a1'),
  ('a7000000-0000-0000-0000-00000000000b', 'a7000000-0000-0000-0000-0000000000e2', 'a7000000-0000-0000-0000-0000000000c2', 'a7000000-0000-0000-0000-0000000000b1');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise) VALUES
  ('a7000000-0000-0000-0000-00000000000a', :'mere', 'a7000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true),
  ('a7000000-0000-0000-0000-00000000000b', :'pere', 'a7000000-0000-0000-0000-0000000000e2', 'parent', 'confirmee', true);
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir', 'a7000000-0000-0000-0000-00000000000a', 'direction');

SET LOCAL ROLE authenticated;

-- ---------------------------------------------------------------------------
-- 1. Organisation
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'dir');
SELECT throws_ok($$ SELECT public.enregistrer_concours(gen_random_uuid(), 'Olympiade', 'olympiade', NULL, NULL, 7, 13) $$,
  '42501', NULL, 'une direction n''organise pas d''événement de la plateforme');
SELECT lives_ok($$ SELECT public.enregistrer_concours('a7600000-0000-0000-0000-0000000000a1', 'Concours interne de maths',
  'concours_interne', 'a7000000-0000-0000-0000-00000000000a', NULL, 10, 10) $$, 'la direction crée un concours interne');

SELECT pg_temp.sur(:'gsg');
SELECT lives_ok($$ SELECT public.enregistrer_concours('a7600000-0000-0000-0000-000000000001', 'Olympiade ouest-africaine',
  'olympiade', NULL, NULL, 9, 13, 'Ouverte à toute la sous-région', 'Médailles', NULL, 50) $$, 'GSG crée une olympiade internationale');
SELECT lives_ok($$ SELECT public.enregistrer_manche('a7700000-0000-0000-0000-000000000001', 'a7600000-0000-0000-0000-000000000001',
  1, 'Première manche', now() - interval '1 hour', now() + interval '1 day', 30,
  '[{"emplacement": 1, "question_id": "a7500000-0000-0000-0000-000000000001"},
    {"emplacement": 1, "question_id": "a7500000-0000-0000-0000-000000000002"},
    {"emplacement": 1, "question_id": "a7500000-0000-0000-0000-000000000003"},
    {"emplacement": 2, "question_id": "a7500000-0000-0000-0000-000000000004"}]') $$, 'manche à variantes');
SELECT public.changer_statut_concours('a7600000-0000-0000-0000-000000000001', 'ouvert');

-- ---------------------------------------------------------------------------
-- 2. Élèves de deux pays
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'mere');
SELECT is(jsonb_array_length(public.concours_eleve('a7000000-0000-0000-0000-0000000000e1')), 1,
  'l''olympiade internationale est visible en Guinée (le concours interne est encore en brouillon)');
SELECT throws_ok($$ SELECT public.commencer_manche('a7700000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-0000000000e1') $$,
  '22023', 'NON_INSCRIT', 'il faut s''inscrire');
SELECT lives_ok($$ SELECT public.inscrire_concours('a7600000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-0000000000e1') $$,
  'la mère inscrit Awa');
SELECT public.commencer_manche('a7700000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-0000000000e1') AS sujet \gset
SELECT is(jsonb_array_length(:'sujet'::jsonb -> 'questions'), 2, 'une question par emplacement');
SELECT is(:'sujet'::jsonb #> '{questions,0,reponse}', '{}'::jsonb, 'les bonnes réponses ne quittent pas le serveur');
SELECT is((public.commencer_manche('a7700000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-0000000000e1') -> 'questions'),
  :'sujet'::jsonb -> 'questions', 'reprendre la manche redonne le même tirage');
SELECT throws_ok($$ SELECT * FROM public.manches_questions $$, '42501', NULL, 'le sujet n''est jamais lisible directement');

-- Réponses justes : la variante de l'emplacement 1 a pour réponse son double.
SELECT jsonb_object_agg(q ->> 'id',
         CASE WHEN q ->> 'type' = 'calcul' THEN to_jsonb(replace(split_part(q ->> 'enonce', ' ', 1), ' ', '')::int * 2 || ',0')
              ELSE to_jsonb(' CONAKRY. '::text) END) AS reponses
  FROM jsonb_array_elements(:'sujet'::jsonb -> 'questions') q \gset
SELECT is((public.remettre_manche('a7700000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-0000000000e1', :'reponses'::jsonb)
  ->> 'score')::numeric, 2.000, 'correction par le serveur : virgule et majuscules acceptées');
SELECT is((public.remettre_manche('a7700000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-0000000000e1', '{}'::jsonb)
  ->> 'deja_remis')::boolean, true, 'une seule copie par manche');

SELECT pg_temp.sur(:'pere');
SELECT public.inscrire_concours('a7600000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-0000000000e2');
SELECT public.commencer_manche('a7700000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-0000000000e2');
SELECT public.remettre_manche('a7700000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-0000000000e2', '{}'::jsonb);

-- ---------------------------------------------------------------------------
-- 3. Classement : général, ou par pays sans mélange (23.1)
-- ---------------------------------------------------------------------------
SELECT is((public.classement_concours('a7600000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-0000000000e2')
  -> 'lignes' -> 0 ->> 'nom'), 'Awa B.', 'classement général : Awa en tête');
SELECT is((public.classement_concours('a7600000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-0000000000e2', 'SN')
  ->> 'participants')::int, 1, 'classement du Sénégal : seulement ses élèves');

SELECT pg_temp.sur(:'mere');
SELECT throws_ok($$ SELECT public.classement_concours('a7600000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-0000000000e2') $$,
  '42501', NULL, 'un parent ne lit pas le classement au nom d''un autre enfant');

-- ---------------------------------------------------------------------------
-- 4. Certificats et vérification publique
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'gsg');
SELECT throws_ok($$ SELECT public.delivrer_certificats('a7600000-0000-0000-0000-000000000001') $$,
  '22023', 'CONCOURS_NON_TERMINE', 'certificats à la fin du concours');
SELECT public.changer_statut_concours('a7600000-0000-0000-0000-000000000001', 'termine');
SELECT is(public.delivrer_certificats('a7600000-0000-0000-0000-000000000001'), 1,
  'un certificat : Awa (100 %) ; Fatou (0 %) sous le seuil');

RESET ROLE;
SELECT code AS code FROM public.certificats WHERE fiche_eleve_id = 'a7000000-0000-0000-0000-0000000000e1' \gset
SET LOCAL ROLE anon;
SELECT is(public.verifier_certificat(lower(:'code')) ->> 'titulaire', 'Awa B.', 'vérifiable sans compte');
SELECT is((public.verifier_certificat('GSG-FAUX-FAUX-FAUX') ->> 'valide')::boolean, false, 'un faux code est refusé');

SELECT * FROM finish();
ROLLBACK;
