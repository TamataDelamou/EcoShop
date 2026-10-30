-- ============================================================================
-- EcoShop — Test RLS 103 : quiz de révision (REG-37 lot R2, migration
-- 20260906001587)
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

SELECT plan(14);

SELECT pg_temp.compte('contenu.103@exemple.org', 'admin_contenu') AS contenu \gset
SELECT pg_temp.compte('eleve.103@exemple.org', 'eleve') AS eleve \gset
SELECT pg_temp.compte('mere.103@exemple.org', 'parent') AS mere \gset
SELECT pg_temp.compte('autre.103@exemple.org', 'parent') AS autre \gset

-- Niveau 7e de Guinée, programme et matière de test, une école et un élève.
SELECT id AS niveau FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND code = '7e' \gset
INSERT INTO public.programmes_officiels (id, pays_code, niveau_id, code, nom, statut)
VALUES ('c1000000-0000-0000-0000-000000000001', 'GN', :'niveau', 'TEST-7E-103', 'Programme test', 'publie');
INSERT INTO public.programmes_matieres (id, programme_id, code, nom, statut)
VALUES ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'MATH103', 'Maths 103', 'publie');

INSERT INTO public.etablissements (id, nom, slug, devise_code)
VALUES ('c0000000-0000-0000-0000-00000000000a', 'École 103', 'ecole-103', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('c0000000-0000-0000-0000-0000000000a1', 'c0000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom, niveau_id)
VALUES ('c0000000-0000-0000-0000-0000000000c1', 'c0000000-0000-0000-0000-00000000000a',
        'c0000000-0000-0000-0000-0000000000a1', '7A', '7e A', :'niveau');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id)
VALUES ('c0000000-0000-0000-0000-0000000000e1', 'c0000000-0000-0000-0000-00000000000a', 'E103', 'BAH', 'Awa', '2013-02-03', :'eleve');
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id)
VALUES ('c0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-0000000000e1',
        'c0000000-0000-0000-0000-0000000000c1', 'c0000000-0000-0000-0000-0000000000a1');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
VALUES ('c0000000-0000-0000-0000-00000000000a', :'mere', 'c0000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true);

SET LOCAL ROLE authenticated;

-- Une question publiée par l'Administrateur de contenu.
SELECT pg_temp.sur(:'contenu');
INSERT INTO public.competences_matiere (id, matiere_id, code, libelle)
VALUES ('c4000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'K1', 'Compétence 1');
SELECT public.enregistrer_question('c5000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001',
  'vrai_faux', 'facile', 'c4000000-0000-0000-0000-000000000001', '2 + 2 = 4', '{}', '{"valeur": true}', 'On compte.');
SELECT public.changer_statut_question('c5000000-0000-0000-0000-000000000001', 'soumettre');
SELECT public.changer_statut_question('c5000000-0000-0000-0000-000000000001', 'valider');
SELECT public.changer_statut_question('c5000000-0000-0000-0000-000000000001', 'publier');

-- ---------------------------------------------------------------------------
-- 1. Niveau et paquet
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'eleve');
SELECT is((SELECT niveau_id FROM public.niveau_revision_fiche('c0000000-0000-0000-0000-0000000000e1')), :'niveau'::uuid,
  'le niveau de l''élève vient de sa classe');
SELECT is(jsonb_array_length(public.paquet_revision(:'niveau') -> 'questions'), 1, 'le paquet porte la question publiée');
SELECT public.paquet_revision(:'niveau') ->> 'empreinte' AS empreinte \gset
SELECT is((public.paquet_revision(:'niveau', NULL, :'empreinte') ->> 'inchange')::boolean, true,
  'même empreinte : rien à retélécharger');

SELECT pg_temp.sur(:'autre');
SELECT throws_ok($$ SELECT * FROM public.niveau_revision_fiche('c0000000-0000-0000-0000-0000000000e1') $$,
  '42501', NULL, 'un autre parent ne lit pas le niveau de l''enfant');

-- ---------------------------------------------------------------------------
-- 2. Tentatives : élève, parent, rejeu
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'eleve');
SELECT is(public.enregistrer_tentative_revision('{
  "id": "c6000000-0000-0000-0000-000000000001", "fiche_eleve_id": "c0000000-0000-0000-0000-0000000000e1",
  "mode": "rapide", "nb_questions": 1, "duree_s": 40, "termine": true, "commence_le": "2026-10-30T10:00:00Z",
  "reponses": [{"question_id": "c5000000-0000-0000-0000-000000000001", "version": 1, "ordre": 0, "score": 1, "duree_s": 40, "reponse": true}]
}'), true, 'l''élève enregistre un quiz terminé');
SELECT is(public.enregistrer_tentative_revision('{
  "id": "c6000000-0000-0000-0000-000000000001", "fiche_eleve_id": "c0000000-0000-0000-0000-0000000000e1",
  "mode": "rapide", "nb_questions": 1, "termine": true, "reponses": []
}'), false, 'rejeu après coupure : pas de double');

SELECT pg_temp.sur(:'mere');
SELECT is(public.enregistrer_tentative_revision('{
  "id": "c6000000-0000-0000-0000-000000000002", "fiche_eleve_id": "c0000000-0000-0000-0000-0000000000e1",
  "mode": "standard", "nb_questions": 10, "duree_s": 120, "termine": false, "commence_le": "2026-10-30T11:00:00Z",
  "reponses": [{"question_id": "c5000000-0000-0000-0000-000000000001", "version": 1, "ordre": 0, "score": 0}]
}'), true, 'la mère révise avec son enfant sur son téléphone (quiz abandonné)');
SELECT is((SELECT joue_par FROM public.tentatives_revision WHERE id = 'c6000000-0000-0000-0000-000000000002'), :'mere'::uuid,
  'on sait qui tenait le téléphone');

SELECT pg_temp.sur(:'autre');
SELECT throws_ok($$ SELECT public.enregistrer_tentative_revision('{
  "id": "c6000000-0000-0000-0000-000000000003", "fiche_eleve_id": "c0000000-0000-0000-0000-0000000000e1",
  "mode": "rapide", "nb_questions": 1, "termine": true, "reponses": []}') $$,
  '42501', NULL, 'un autre parent ne peut rien enregistrer pour cet enfant');
SELECT is((SELECT count(*)::int FROM public.tentatives_revision), 0, 'ni voir ses quiz');

-- ---------------------------------------------------------------------------
-- 3. Résumé : l'abandon compte dans le temps, pas dans la réussite
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'mere');
SELECT is((public.resume_revision('c0000000-0000-0000-0000-0000000000e1', 3650) ->> 'temps_s')::int, 160,
  'temps de travail : quiz terminé et quiz abandonné');
SELECT is((public.resume_revision('c0000000-0000-0000-0000-0000000000e1', 3650) ->> 'quiz_termines')::int, 1,
  'un seul quiz terminé');
SELECT is((public.resume_revision('c0000000-0000-0000-0000-0000000000e1', 3650) ->> 'points')::numeric, 1.000,
  'réussite : seulement le quiz terminé');
SELECT is(public.resume_revision('c0000000-0000-0000-0000-0000000000e1', 3650) #> '{competences,0,scores}', '[1.000]'::jsonb,
  'dernières réponses de la compétence (quiz terminés)');

SELECT * FROM finish();
ROLLBACK;
