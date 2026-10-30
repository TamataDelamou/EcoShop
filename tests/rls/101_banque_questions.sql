-- ============================================================================
-- EcoShop — Test RLS 101 : banque de questions (REG-37 lot R1, migration
-- 20260906001585)
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

SELECT plan(30);

-- Programmes de test : 7e (collège) et CP1 (petites classes), Guinée.
INSERT INTO public.programmes_officiels (id, pays_code, niveau_id, code, nom, statut)
SELECT 'b1000000-0000-0000-0000-000000000001', 'GN', id, 'TEST-7E-101', 'Programme test 7e', 'publie'
  FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND code = '7e';
INSERT INTO public.programmes_officiels (id, pays_code, niveau_id, code, nom, statut)
SELECT 'b1000000-0000-0000-0000-000000000002', 'GN', id, 'TEST-CP1-101', 'Programme test CP1', 'publie'
  FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND code = 'CP1';
INSERT INTO public.programmes_matieres (id, programme_id, code, nom, statut) VALUES
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'MATH', 'Mathématiques', 'publie'),
  ('b2000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000002', 'FR', 'Français', 'publie');

SELECT pg_temp.compte('contenu1.101@exemple.org', 'admin_contenu') AS contenu \gset
SELECT pg_temp.compte('gsg.101@exemple.org', 'admin_gsg') AS gsg \gset
SELECT pg_temp.compte('eleve1.101@exemple.org', 'eleve') AS e1 \gset
SELECT pg_temp.compte('eleve2.101@exemple.org', 'eleve') AS e2 \gset
SELECT pg_temp.compte('eleve3.101@exemple.org', 'eleve') AS e3 \gset

SET LOCAL ROLE authenticated;

-- ---------------------------------------------------------------------------
-- 1. Structure de la matière : réservée à l'Administrateur de contenu
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'gsg');
SELECT throws_ok($$
  INSERT INTO public.competences_matiere (matiere_id, code, libelle)
  VALUES ('b2000000-0000-0000-0000-000000000001', 'C1', 'Calcul')
$$, '42501', NULL, 'l''Administrateur GSG n''écrit pas le contenu pédagogique');

SELECT pg_temp.sur(:'contenu');
SELECT lives_ok($$
  INSERT INTO public.chapitres_matiere (id, matiere_id, titre, ordre)
  VALUES ('b3000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'Fractions', 1)
$$, 'l''Administrateur de contenu crée un chapitre');
SELECT lives_ok($$
  INSERT INTO public.competences_matiere (id, matiere_id, code, libelle) VALUES
    ('b4000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'FRAC-1', 'Simplifier une fraction'),
    ('b4000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000002', 'LECT-1', 'Reconnaître une lettre')
$$, 'l''Administrateur de contenu crée chapitres et compétences');

-- ---------------------------------------------------------------------------
-- 2. Enregistrement et contrôles de forme
-- ---------------------------------------------------------------------------
SELECT lives_ok($$
  SELECT public.enregistrer_question(
    'b5000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'qcm_simple', 'facile',
    'b4000000-0000-0000-0000-000000000001', 'Simplifier 2/4',
    '{"choix":[{"id":"a","texte":"1/2"},{"id":"b","texte":"2/2"},{"id":"c","texte":"1/4"}]}',
    '{"bonnes":["a"]}', 'On divise le numérateur et le dénominateur par 2.',
    'b3000000-0000-0000-0000-000000000001')
$$, 'QCM simple enregistré en brouillon');
SELECT is((SELECT statut::text FROM public.questions WHERE id = 'b5000000-0000-0000-0000-000000000001'), 'brouillon', 'statut brouillon');

SELECT throws_ok($$
  SELECT public.enregistrer_question(gen_random_uuid(), 'b2000000-0000-0000-0000-000000000001', 'qcm_simple', 'facile',
    'b4000000-0000-0000-0000-000000000001', 'Q', '{"choix":[{"id":"a","texte":"1"},{"id":"b","texte":"2"}]}',
    '{"bonnes":["a"]}', '  ')
$$, '22023', 'EXPLICATION_REQUISE', 'pas de question sans explication');
SELECT throws_ok($$
  SELECT public.enregistrer_question(gen_random_uuid(), 'b2000000-0000-0000-0000-000000000001', 'qcm_simple', 'facile',
    NULL, 'Q', '{"choix":[{"id":"a","texte":"1"},{"id":"b","texte":"2"}]}', '{"bonnes":["a"]}', 'E')
$$, '22023', 'COMPETENCE_REQUISE', 'pas de question sans compétence');
SELECT throws_ok($$
  SELECT public.enregistrer_question(gen_random_uuid(), 'b2000000-0000-0000-0000-000000000001', 'qcm_simple', 'facile',
    'b4000000-0000-0000-0000-000000000001', 'Q', '{"choix":[{"id":"a","texte":"1"},{"id":"b","texte":"2"}]}',
    '{"bonnes":["z"]}', 'E')
$$, '22023', 'REPONSE_INVALIDE', 'la bonne réponse doit être un des choix');
SELECT throws_ok($$
  SELECT public.enregistrer_question(gen_random_uuid(), 'b2000000-0000-0000-0000-000000000001', 'qcm_multiple', 'moyen',
    'b4000000-0000-0000-0000-000000000001', 'Q', '{}', '{"bonnes":["a"]}', 'E')
$$, '22023', 'CHOIX_INVALIDES', 'un QCM sans choix est refusé');
SELECT throws_ok($$
  SELECT public.enregistrer_question(gen_random_uuid(), 'b2000000-0000-0000-0000-000000000001', 'texte_a_trous', 'moyen',
    'b4000000-0000-0000-0000-000000000001', 'La moitié de 8 est [[1]].', '{}', '{"trous":{"2":["4"]}}', 'E')
$$, '22023', 'TROU_ABSENT_ENONCE', 'chaque trou doit figurer dans l''énoncé');
SELECT lives_ok($$
  SELECT public.enregistrer_question(gen_random_uuid(), 'b2000000-0000-0000-0000-000000000001', 'classement', 'moyen',
    'b4000000-0000-0000-0000-000000000001', 'Du plus petit au plus grand',
    '{"elements":[{"id":"x","texte":"1/4"},{"id":"y","texte":"1/2"},{"id":"z","texte":"3/4"}]}',
    '{"ordre":["x","y","z"]}', 'Même dénominateur : on compare les numérateurs.')
$$, 'classement correct accepté');
SELECT throws_ok($$
  SELECT public.enregistrer_question(gen_random_uuid(), 'b2000000-0000-0000-0000-000000000001', 'calcul', 'difficile',
    'b4000000-0000-0000-0000-000000000001', '3 × 4 ?', '{}', '{"valeur":"douze"}', 'E')
$$, '22023', 'REPONSE_INVALIDE', 'un calcul attend un nombre');
SELECT throws_ok($$
  SELECT public.enregistrer_question(gen_random_uuid(), 'b2000000-0000-0000-0000-000000000001', 'vrai_faux', 'facile',
    'b4000000-0000-0000-0000-000000000002', 'A est une voyelle', '{}', '{"valeur":true}', 'E')
$$, '22023', 'COMPETENCE_HORS_MATIERE', 'la compétence appartient à la matière');

-- Petites classes (CP1) : types adaptés et trois choix au plus.
SELECT throws_ok($$
  SELECT public.enregistrer_question(gen_random_uuid(), 'b2000000-0000-0000-0000-000000000002', 'reponse_courte', 'facile',
    'b4000000-0000-0000-0000-000000000002', 'Écris la lettre A', '{}', '{"acceptees":["A"]}', 'E')
$$, '22023', 'TYPE_NON_ADAPTE_PETITES_CLASSES', 'pas de saisie libre en CP1');
SELECT throws_ok($$
  SELECT public.enregistrer_question(gen_random_uuid(), 'b2000000-0000-0000-0000-000000000002', 'qcm_simple', 'facile',
    'b4000000-0000-0000-0000-000000000002', 'Quelle est la lettre A ?',
    '{"choix":[{"id":"a","texte":"A"},{"id":"b","texte":"B"},{"id":"c","texte":"C"},{"id":"d","texte":"D"}]}',
    '{"bonnes":["a"]}', 'E')
$$, '22023', 'TROP_DE_CHOIX_PETITES_CLASSES', 'trois choix au plus en CP1');

-- ---------------------------------------------------------------------------
-- 3. Circuit de publication et diffusion
-- ---------------------------------------------------------------------------
SELECT throws_ok($$ SELECT public.changer_statut_question('b5000000-0000-0000-0000-000000000001', 'publier') $$,
  '22023', 'VALIDATION_REQUISE', 'pas de publication sans validation');

SELECT pg_temp.sur(:'e1');
SELECT is((SELECT count(*)::int FROM public.questions_versions), 0, 'un brouillon n''est pas diffusé aux élèves');
SELECT throws_ok($$ SELECT public.changer_statut_question('b5000000-0000-0000-0000-000000000001', 'soumettre') $$,
  '42501', NULL, 'un élève ne touche pas au circuit');

SELECT pg_temp.sur(:'contenu');
SELECT lives_ok($$ SELECT public.changer_statut_question('b5000000-0000-0000-0000-000000000001', 'soumettre') $$, 'soumise');
SELECT lives_ok($$ SELECT public.changer_statut_question('b5000000-0000-0000-0000-000000000001', 'valider') $$,
  'validée (l''auteur est Administrateur de contenu)');
SELECT lives_ok($$ SELECT public.changer_statut_question('b5000000-0000-0000-0000-000000000001', 'publier') $$, 'publiée');

SELECT pg_temp.sur(:'e1');
SELECT is((SELECT enonce FROM public.questions_versions WHERE question_id = 'b5000000-0000-0000-0000-000000000001'),
  'Simplifier 2/4', 'la question publiée est diffusée');

-- Modifier une question publiée : nouvelle version, l'ancienne reste servie.
SELECT pg_temp.sur(:'contenu');
SELECT public.enregistrer_question(
  'b5000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'qcm_simple', 'facile',
  'b4000000-0000-0000-0000-000000000001', 'Simplifier la fraction 2/4',
  '{"choix":[{"id":"a","texte":"1/2"},{"id":"b","texte":"2/2"},{"id":"c","texte":"1/4"}]}',
  '{"bonnes":["a"]}', 'On divise le numérateur et le dénominateur par 2.', 'b3000000-0000-0000-0000-000000000001');
SELECT is((SELECT version_travail || '/' || version_publiee FROM public.questions WHERE id = 'b5000000-0000-0000-0000-000000000001'),
  '2/1', 'version 2 en travail, version 1 publiée');
SELECT pg_temp.sur(:'e2');
SELECT is((SELECT enonce FROM public.questions_versions WHERE question_id = 'b5000000-0000-0000-0000-000000000001'),
  'Simplifier 2/4', 'les élèves gardent la version publiée pendant la correction');

-- ---------------------------------------------------------------------------
-- 4. Signalements : trois personnes distinctes → suspension
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'e1');
SELECT is(public.signaler_question('b5000000-0000-0000-0000-000000000001', 'enonce_confus'), false, 'premier signalement');
SELECT is(public.signaler_question('b5000000-0000-0000-0000-000000000001', 'enonce_confus'), false,
  'le même élève ne compte qu''une fois');
SELECT pg_temp.sur(:'e2');
SELECT is(public.signaler_question('b5000000-0000-0000-0000-000000000001', 'reponse_fausse'), false, 'deuxième personne');
SELECT pg_temp.sur(:'e3');
SELECT is(public.signaler_question('b5000000-0000-0000-0000-000000000001', 'faute'), true, 'troisième personne : suspension');
SELECT is((SELECT count(*)::int FROM public.questions_versions), 0, 'question suspendue retirée de la diffusion');

SELECT pg_temp.sur(:'contenu');
SELECT public.retablir_question('b5000000-0000-0000-0000-000000000001');
SELECT pg_temp.sur(:'e3');
SELECT is((SELECT count(*)::int FROM public.questions_versions), 1, 'rétablie après vérification');

SELECT * FROM finish();
ROLLBACK;
