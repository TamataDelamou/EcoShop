-- ============================================================================
-- EcoShop — Test RLS 97 : séries, programmes de l'école, moyenne générale
-- pondérée (REG-33, migration 1579)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  UPDATE public.profiles SET role_racine = p_role::public.role_racine,
         prenom = initcap(split_part(p_email, '@', 1)), nom = 'Test' WHERE id = v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.sur(p_uid uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

SELECT plan(17);

-- ---------------------------------------------------------------------------
-- 1. Séries guinéennes : SM, SE, SS en 11e, 12e et Terminale, sans coefficient
-- ---------------------------------------------------------------------------
SELECT is((SELECT string_agg(f.code || ':' || n.code, ',' ORDER BY f.ordre, n.ordre)
             FROM public.filieres_educatives f
             JOIN public.filieres_niveaux fn ON fn.filiere_id = f.id
             JOIN public.niveaux_educatifs n ON n.id = fn.niveau_id
            WHERE f.pays_code = 'GN' AND f.code IN ('SM', 'SE', 'SS')),
          'SM:11e,SM:12e,SM:Terminale,SE:11e,SE:12e,SE:Terminale,SS:11e,SS:12e,SS:Terminale',
          'séries du Bac unique proposées sur les trois années du lycée');

INSERT INTO public.etablissements (id, nom, slug, devise_code, pays_code) VALUES
  ('97000000-0000-0000-0000-00000000000a', 'Lycée A', 'lycee-a-97', 'GNF', 'GN'),
  ('97000000-0000-0000-0000-00000000000b', 'Lycée B', 'lycee-b-97', 'GNF', 'GN');

SELECT pg_temp.compte('direction@a.gn', 'direction') AS dir_a \gset
SELECT pg_temp.compte('prof@a.gn', 'enseignant') AS prof_a \gset
SELECT pg_temp.compte('direction@b.gn', 'direction') AS dir_b \gset
SELECT pg_temp.compte('parent@a.gn', 'parent') AS parent_a \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_a', '97000000-0000-0000-0000-00000000000a', 'direction'),
  (:'prof_a', '97000000-0000-0000-0000-00000000000a', 'enseignant'),
  (:'dir_b', '97000000-0000-0000-0000-00000000000b', 'direction');

SELECT id AS niveau_11 FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND code = '11e' \gset
SELECT id AS niveau_12 FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND code = '12e' \gset
SELECT id AS serie_sm FROM public.filieres_educatives WHERE pays_code = 'GN' AND code = 'SM' \gset

-- ---------------------------------------------------------------------------
-- 2. Programme de l'école (pas de programme national : Guinée en production)
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'prof_a');
SET LOCAL ROLE authenticated;
SELECT throws_ok(format('SELECT public.adopter_programme_ecole(%L, %L, %L)',
                        '97000000-0000-0000-0000-00000000000a', :'niveau_11', :'serie_sm'),
                 '42501', NULL, 'un enseignant n''ajuste pas le programme de l''école');

SELECT pg_temp.sur(:'dir_a');
SELECT public.adopter_programme_ecole('97000000-0000-0000-0000-00000000000a', :'niveau_11', :'serie_sm') AS prog \gset
SELECT is(public.adopter_programme_ecole('97000000-0000-0000-0000-00000000000a', :'niveau_11', :'serie_sm'),
          :'prog'::uuid, 'un seul programme par niveau et série : le même est rendu');
SELECT is((SELECT count(*)::int FROM public.programmes_matieres WHERE programme_id = :'prog'), 0,
          'sans programme national : programme vide, matières créées par l''école');

SELECT public.enregistrer_matiere_ecole(:'prog', 'Mathématiques', 5, 216, 'specialite') AS maths \gset
SELECT public.enregistrer_matiere_ecole(:'prog', 'Français', 2) AS francais \gset
SELECT public.enregistrer_matiere_ecole(:'prog', 'Éducation physique') AS eps \gset
SELECT public.enregistrer_matiere_ecole(:'prog', 'Dessin', 1) AS dessin \gset
SELECT is((SELECT coefficient FROM public.programmes_matieres WHERE id = :'maths'), 5.00::numeric(5,2),
          'coefficient enregistré (décimal)');
SELECT is(public.enregistrer_matiere_ecole(:'prog', 'Français', 2.5, NULL, 'tronc_commun', :'francais'),
          :'francais'::uuid, 'coefficient modifié : 2,5');
SELECT throws_ok(format('SELECT public.enregistrer_matiere_ecole(%L, %L, 0)', :'prog', 'Chimie'),
                 '22023', NULL, 'coefficient nul refusé');
SELECT public.retirer_matiere_ecole(:'dessin');
SELECT is((SELECT count(*)::int FROM public.programmes_matieres WHERE programme_id = :'prog'), 3,
          'matière retirée : n''est plus lue');

-- ---------------------------------------------------------------------------
-- 3. Lecture : l'école et les parents de ses élèves, pas une autre école
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'dir_b');
SELECT is((SELECT count(*)::int FROM public.programmes_officiels WHERE id = :'prog'), 0,
          'une autre école ne lit pas ce programme');
SELECT throws_ok(format('SELECT public.enregistrer_matiere_ecole(%L, %L, 1)', :'prog', 'Intrus'),
                 '42501', NULL, 'une autre école ne modifie pas ce programme');
RESET ROLE;

INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance)
VALUES ('97000000-0000-0000-0000-0000000000f1', '97000000-0000-0000-0000-00000000000a', 'MAT-97', 'SOW', 'Aïssatou', '2010-02-02');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id)
VALUES ('97000000-0000-0000-0000-00000000000a', :'parent_a', '97000000-0000-0000-0000-0000000000f1');

SELECT pg_temp.sur(:'parent_a');
SET LOCAL ROLE authenticated;
SELECT is((SELECT count(*)::int FROM public.programmes_matieres WHERE programme_id = :'prog'), 3,
          'le parent d''un élève lit les matières de l''école (bulletin)');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 4. Copie du programme national, quand il existe
-- ---------------------------------------------------------------------------
INSERT INTO public.programmes_officiels (id, pays_code, niveau_id, filiere_id, code, nom, statut)
VALUES ('97000000-0000-0000-0000-0000000000a1', 'GN', :'niveau_12', :'serie_sm', 'GN-12-SM-TEST', '12e SM (national)', 'publie')
ON CONFLICT DO NOTHING;
INSERT INTO public.programmes_matieres (programme_id, code, nom, coefficient, volume_horaire_annuel, ordre, statut) VALUES
  ('97000000-0000-0000-0000-0000000000a1', 'maths', 'Mathématiques', 6, 252, 1, 'publie'),
  ('97000000-0000-0000-0000-0000000000a1', 'physique', 'Physique', 4, 144, 2, 'publie');
SELECT pg_temp.sur(:'dir_a');
SET LOCAL ROLE authenticated;
SELECT public.adopter_programme_ecole('97000000-0000-0000-0000-00000000000a', :'niveau_12', :'serie_sm') AS prog12 \gset
SELECT is((SELECT string_agg(nom || '=' || coefficient, ',' ORDER BY ordre) FROM public.programmes_matieres WHERE programme_id = :'prog12'),
          'Mathématiques=6.00,Physique=4.00', 'programme national copié : matières et coefficients, ajustables');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 5. Moyenne générale pondérée par les coefficients des matières
-- ---------------------------------------------------------------------------
INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('97000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee \gset
INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom, niveau_id, filiere_id)
VALUES ('97000000-0000-0000-0000-00000000000a', :'annee', '11SM', '11e SM', :'niveau_11', :'serie_sm') RETURNING id AS classe \gset

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES ('97000000-0000-0000-0000-00000000000a', '97000000-0000-0000-0000-0000000000f1', :'classe', :'annee', 'active');

-- Maths : 8/20 (coef. éval. 1) et 12/20 (coef. éval. 3) → 11 ; Français 18 ;
-- EPS 16 (pas de coefficient de matière → 1).
INSERT INTO public.evaluations (id, etablissement_id, annee_scolaire_id, classe_id, programme_matiere_id,
                                enseignant_profile_id, libelle, coefficient, bareme, statut) VALUES
  ('97000000-0000-0000-0000-0000000000e1', '97000000-0000-0000-0000-00000000000a', :'annee', :'classe', :'maths', :'prof_a', 'Devoir', 1, 20, 'publiee'),
  ('97000000-0000-0000-0000-0000000000e2', '97000000-0000-0000-0000-00000000000a', :'annee', :'classe', :'maths', :'prof_a', 'Composition', 3, 20, 'publiee'),
  ('97000000-0000-0000-0000-0000000000e3', '97000000-0000-0000-0000-00000000000a', :'annee', :'classe', :'francais', :'prof_a', 'Dictée', 1, 10, 'publiee'),
  ('97000000-0000-0000-0000-0000000000e4', '97000000-0000-0000-0000-00000000000a', :'annee', :'classe', :'eps', :'prof_a', 'Course', 1, 20, 'publiee');
INSERT INTO public.notes (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par) VALUES
  ('97000000-0000-0000-0000-00000000000a', '97000000-0000-0000-0000-0000000000e1', '97000000-0000-0000-0000-0000000000f1', 8, :'prof_a'),
  ('97000000-0000-0000-0000-00000000000a', '97000000-0000-0000-0000-0000000000e2', '97000000-0000-0000-0000-0000000000f1', 12, :'prof_a'),
  ('97000000-0000-0000-0000-00000000000a', '97000000-0000-0000-0000-0000000000e3', '97000000-0000-0000-0000-0000000000f1', 9, :'prof_a'),
  ('97000000-0000-0000-0000-00000000000a', '97000000-0000-0000-0000-0000000000e4', '97000000-0000-0000-0000-0000000000f1', 16, :'prof_a');

SELECT is(public.moyenne_eleve_interne('97000000-0000-0000-0000-0000000000f1', :'maths'), 11.00::numeric,
          'moyenne d''une matière : évaluations pondérées (inchangé)');
-- (11 × 5 + 18 × 2,5 + 16 × 1) / 8,5 = 116 / 8,5 = 13,65
SELECT is(public.moyenne_eleve_interne('97000000-0000-0000-0000-0000000000f1'), 13.65::numeric,
          'moyenne générale : moyennes de matières pondérées par leurs coefficients');
SELECT is((SELECT coefficient FROM public.detail_bulletin_matieres('97000000-0000-0000-0000-0000000000f1', :'classe') LIMIT 1),
          NULL::numeric, 'bulletin : sans cours affecté, aucune ligne (fonction recréée en décimal)');

-- Mise en route : la classe 11e SM a des matières ; une 12e SS n'en a pas.
INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom, niveau_id, filiere_id)
SELECT '97000000-0000-0000-0000-00000000000a', :'annee', '12SS', '12e SS', :'niveau_12', id
FROM public.filieres_educatives WHERE pays_code = 'GN' AND code = 'SS';
SELECT pg_temp.sur(:'dir_a');
SET LOCAL ROLE authenticated;
SELECT is((public.etat_configuration_etablissement('97000000-0000-0000-0000-00000000000a') ->> 'niveaux_classes')::int, 2,
          'mise en route : deux couples niveau-série dans les classes');
SELECT is((public.etat_configuration_etablissement('97000000-0000-0000-0000-00000000000a') ->> 'niveaux_sans_matieres')::int, 1,
          'mise en route : la 12e SS n''a encore aucune matière');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
