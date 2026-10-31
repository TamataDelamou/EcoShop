-- ============================================================================
-- EcoShop — Test RLS 110 : absences des enseignants, remplacements, cours
-- assurés, semaines A/B (REG-41, migration 20260906001597)
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
  UPDATE public.profiles SET role_racine = p_role::public.role_racine, prenom = 'Test', nom = split_part(p_email, '.', 1) WHERE id = v_id;
  RETURN v_id;
END $$;

SELECT plan(19);

SELECT pg_temp.compte('dir.110@exemple.org', 'direction') AS dir \gset
SELECT pg_temp.compte('absent.110@exemple.org', 'enseignant') AS absent \gset
SELECT pg_temp.compte('libre.110@exemple.org', 'enseignant') AS libre \gset
SELECT pg_temp.compte('occupe.110@exemple.org', 'enseignant') AS occupe \gset
SELECT pg_temp.compte('eleve.110@exemple.org', 'eleve') AS eleve \gset
SELECT pg_temp.compte('mere.110@exemple.org', 'parent') AS mere \gset

SELECT (current_date + 1) AS demain \gset
SELECT extract(isodow from current_date + 1)::int AS jour \gset
SELECT id AS gn10 FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND code = '10e' \gset

INSERT INTO public.programmes_officiels (id, pays_code, niveau_id, code, nom, statut)
VALUES ('c1100000-0000-0000-0000-000000000001', 'GN', :'gn10', 'TEST-110', 'Programme 110', 'publie');
INSERT INTO public.programmes_matieres (id, programme_id, code, nom, statut)
VALUES ('c1200000-0000-0000-0000-000000000001', 'c1100000-0000-0000-0000-000000000001', 'MATH', 'Maths', 'publie'),
       ('c1200000-0000-0000-0000-000000000002', 'c1100000-0000-0000-0000-000000000001', 'FR', 'Français', 'publie');

INSERT INTO public.etablissements (id, nom, slug, devise_code, pays_code) VALUES
  ('c1000000-0000-0000-0000-00000000000a', 'Lycée 110', 'lycee-110-gn', 'GNF', 'GN');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('c1000000-0000-0000-0000-0000000000a1', 'c1000000-0000-0000-0000-00000000000a', '2026-2027',
   current_date - 60, current_date + 200, true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom, niveau_id) VALUES
  ('c1000000-0000-0000-0000-0000000000c1', 'c1000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-0000000000a1', '10A', '10e A', :'gn10'),
  ('c1000000-0000-0000-0000-0000000000c2', 'c1000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-0000000000a1', '10B', '10e B', :'gn10');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id) VALUES
  ('c1000000-0000-0000-0000-0000000000e1', 'c1000000-0000-0000-0000-00000000000a', 'E1101', 'SYLLA', 'Mariama', '2011-02-03', :'eleve');
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('c1000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-0000000000e1', 'c1000000-0000-0000-0000-0000000000c1', 'c1000000-0000-0000-0000-0000000000a1');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise) VALUES
  ('c1000000-0000-0000-0000-00000000000a', :'mere', 'c1000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true);
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir', 'c1000000-0000-0000-0000-00000000000a', 'direction'),
  (:'absent', 'c1000000-0000-0000-0000-00000000000a', 'enseignant'),
  (:'libre', 'c1000000-0000-0000-0000-00000000000a', 'enseignant'),
  (:'occupe', 'c1000000-0000-0000-0000-00000000000a', 'enseignant');
-- « libre » enseigne les maths en 10e B : même matière.
INSERT INTO public.affectations_enseignants (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id, programme_matiere_id) VALUES
  ('c1000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-0000000000a1', :'absent', 'c1000000-0000-0000-0000-0000000000c1', 'c1200000-0000-0000-0000-000000000001'),
  ('c1000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-0000000000a1', :'libre', 'c1000000-0000-0000-0000-0000000000c2', 'c1200000-0000-0000-0000-000000000001'),
  ('c1000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-0000000000a1', :'occupe', 'c1000000-0000-0000-0000-0000000000c2', 'c1200000-0000-0000-0000-000000000002');
-- Demain : maths de 10e A à 8 h (enseignant absent) ; « occupe » a cours à
-- 8 h en 10e B ; « libre » a cours à 10 h.
INSERT INTO public.emplois_du_temps (id, etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id,
                                     programme_matiere_id, jour_semaine, heure_debut, heure_fin) VALUES
  ('c1300000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-0000000000a1',
   'c1000000-0000-0000-0000-0000000000c1', :'absent', 'c1200000-0000-0000-0000-000000000001', :jour, '08:00', '09:00'),
  ('c1300000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-0000000000a1',
   'c1000000-0000-0000-0000-0000000000c2', :'occupe', 'c1200000-0000-0000-0000-000000000002', :jour, '08:00', '09:00'),
  ('c1300000-0000-0000-0000-000000000003', 'c1000000-0000-0000-0000-00000000000a', 'c1000000-0000-0000-0000-0000000000a1',
   'c1000000-0000-0000-0000-0000000000c2', :'libre', 'c1200000-0000-0000-0000-000000000001', :jour, '10:00', '11:00');

SET LOCAL ROLE authenticated;

-- ---------------------------------------------------------------------------
-- 1. L'enseignant prévient, la direction valide
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'absent');
SELECT is(public.declarer_absence_enseignant('c1400000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-00000000000a',
  :'absent', :'demain', :'demain'), 'signalee', 'l''enseignant prévient : absence signalée');
SELECT throws_ok(format($f$ SELECT public.declarer_absence_enseignant(gen_random_uuid(), 'c1000000-0000-0000-0000-00000000000a',
  %L::uuid, current_date + 1, current_date + 1) $f$, :'libre'),
  '42501', NULL, 'un enseignant ne déclare pas l''absence d''un collègue');

SELECT pg_temp.sur(:'dir');
SELECT is(jsonb_array_length(public.cours_a_remplacer('c1000000-0000-0000-0000-00000000000a', :'demain')), 0,
  'absence pas encore validée : rien à remplacer');
SELECT is((public.accueil_resume('c1000000-0000-0000-0000-00000000000a') ->> 'absences_a_valider')::int, 1,
  'badge : une absence à valider');
SELECT lives_ok($$ SELECT public.decider_absence_enseignant('c1400000-0000-0000-0000-000000000001', true) $$, 'la direction valide');
SELECT is(jsonb_array_length(public.cours_a_remplacer('c1000000-0000-0000-0000-00000000000a', :'demain')), 1,
  'le cours de maths de 8 h est à remplacer');

-- ---------------------------------------------------------------------------
-- 2. Remplaçants : libres à cette heure, même matière d'abord
-- ---------------------------------------------------------------------------
SELECT public.remplacants_possibles('c1300000-0000-0000-0000-000000000001', :'demain') AS candidats \gset
SELECT is((:'candidats'::jsonb -> 0 ->> 'profile_id')::uuid, :'libre'::uuid, 'le collègue de maths libre est proposé en premier');
SELECT is((:'candidats'::jsonb -> 0 ->> 'meme_matiere')::boolean, true, '… parce qu''il enseigne la même matière');
SELECT is((SELECT count(*)::int FROM jsonb_array_elements(:'candidats'::jsonb) x WHERE (x ->> 'profile_id')::uuid = :'occupe'::uuid),
  0, 'un enseignant qui a cours à cette heure n''est pas proposé');

-- ---------------------------------------------------------------------------
-- 3. Décision et notifications (décision 3)
-- ---------------------------------------------------------------------------
SELECT lives_ok(format($f$ SELECT public.decider_seance('c1500000-0000-0000-0000-000000000001', 'c1300000-0000-0000-0000-000000000001',
  current_date + 1, 'remplacement', %L::uuid) $f$, :'libre'), 'remplacement décidé');

RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications WHERE type = 'remplacement_a_assurer' AND destinataire = :'libre'), 1,
  'le remplaçant est prévenu');
SELECT is((SELECT count(*)::int FROM public.notifications WHERE type = 'cours_modifie' AND destinataire = :'eleve'), 1,
  'l''élève est prévenu');
SELECT is((SELECT count(*)::int FROM public.notifications WHERE type = 'cours_modifie' AND destinataire = :'mere'), 0,
  'simple remplacement : les parents ne sont pas dérangés');
SET LOCAL ROLE authenticated;

SELECT pg_temp.sur(:'dir');
SELECT public.decider_seance('c1500000-0000-0000-0000-000000000001', 'c1300000-0000-0000-0000-000000000001',
  :'demain', 'annule');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications WHERE type = 'cours_modifie' AND destinataire = :'mere'), 1,
  'cours annulé : la mère est prévenue');
SET LOCAL ROLE authenticated;

SELECT pg_temp.sur(:'mere');
SELECT is((public.changements_fiche('c1000000-0000-0000-0000-0000000000e1') -> 0 ->> 'solution'), 'annule',
  'la mère voit le cours annulé');

SELECT pg_temp.sur(:'libre');
SELECT throws_ok($$ SELECT public.cours_a_remplacer('c1000000-0000-0000-0000-00000000000a', current_date + 1) $$, '42501', NULL,
  'un enseignant n''organise pas les remplacements');

-- ---------------------------------------------------------------------------
-- 4. Cours assurés, compteur, semaines A/B
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'dir');
SELECT lives_ok($$ SELECT public.cours_assures('c1000000-0000-0000-0000-00000000000a', current_date - 30, current_date) $$,
  'taux de cours assurés');
SELECT lives_ok($$ SELECT public.compteur_remplacements('c1000000-0000-0000-0000-00000000000a', current_date - 30, current_date + 7) $$,
  'compteur des remplacements');
SELECT isnt(public.semaine_ab('c1000000-0000-0000-0000-00000000000a', current_date),
  public.semaine_ab('c1000000-0000-0000-0000-00000000000a', current_date + 7), 'semaines A et B alternent');

SELECT * FROM finish();
ROLLBACK;
