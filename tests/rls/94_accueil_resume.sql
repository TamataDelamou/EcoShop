-- ============================================================================
-- EcoShop — Test RLS 94 : accueil, compteurs « À faire » et cours du jour
-- (REG-21, migration 1569)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  UPDATE public.profiles SET role_racine = p_role::public.role_racine, prenom = 'Test', nom = initcap(split_part(p_email, '@', 1))
   WHERE id = v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.au_poste(p_email text, p_modele text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_id uuid := pg_temp.compte(p_email, 'personnel');
BEGIN
  INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement, poste_id)
  SELECT v_id, '94000000-0000-0000-0000-00000000000a', 'personnel', p.id
    FROM public.postes p WHERE p.etablissement_id = '94000000-0000-0000-0000-00000000000a' AND p.modele_code = p_modele;
  RETURN v_id;
END $$;

-- Clés présentes dans le résumé, triées.
CREATE OR REPLACE FUNCTION pg_temp.cles(p_fiche uuid DEFAULT NULL) RETURNS text LANGUAGE sql AS $$
  SELECT string_agg(k, ',' ORDER BY k)
    FROM jsonb_object_keys(public.accueil_resume('94000000-0000-0000-0000-00000000000a', p_fiche)) k;
$$;
CREATE OR REPLACE FUNCTION pg_temp.n(p_cle text, p_fiche uuid DEFAULT NULL) RETURNS int LANGUAGE sql AS $$
  SELECT (public.accueil_resume('94000000-0000-0000-0000-00000000000a', p_fiche) ->> p_cle)::int;
$$;

SELECT plan(22);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('94000000-0000-0000-0000-00000000000a', 'École A', 'ecole-a-94', 'GNF'),
  ('94000000-0000-0000-0000-00000000000b', 'École B', 'ecole-b-94', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('94000000-0000-0000-0000-0000000000a1', '94000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('94000000-0000-0000-0000-0000000000c1', '94000000-0000-0000-0000-00000000000a', '94000000-0000-0000-0000-0000000000a1', 'CM1B', 'CM1 B');
INSERT INTO public.salles (id, etablissement_id, code, nom) VALUES
  ('94000000-0000-0000-0000-0000000000a5', '94000000-0000-0000-0000-00000000000a', 'S4', 'Salle 4');

SELECT pg_temp.compte('dir.a@exemple.org', 'direction') AS dir_a \gset
SELECT pg_temp.compte('dir.b@exemple.org', 'direction') AS dir_b \gset
SELECT pg_temp.compte('prof@exemple.org', 'enseignant') AS prof \gset
SELECT pg_temp.compte('parent@exemple.org', 'parent') AS parent \gset
SELECT pg_temp.compte('autre.parent@exemple.org', 'parent') AS autre_parent \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_a', '94000000-0000-0000-0000-00000000000a', 'direction'),
  (:'dir_b', '94000000-0000-0000-0000-00000000000b', 'direction'),
  (:'prof', '94000000-0000-0000-0000-00000000000a', 'enseignant');
INSERT INTO public.affectations_enseignants (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id) VALUES
  ('94000000-0000-0000-0000-00000000000a', '94000000-0000-0000-0000-0000000000a1', :'prof', '94000000-0000-0000-0000-0000000000c1');
SELECT pg_temp.au_poste('portail@exemple.org', 'agent_portail') AS portail \gset
SELECT pg_temp.au_poste('caissier@exemple.org', 'caissier') AS caissier \gset

INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance) VALUES
  ('94000000-0000-0000-0000-0000000000e1', '94000000-0000-0000-0000-00000000000a', 'A94-1', 'SOW', 'Aïcha', '2016-01-01'),
  ('94000000-0000-0000-0000-0000000000e2', '94000000-0000-0000-0000-00000000000a', 'A94-2', 'BAH', 'Ali', '2016-01-01');
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('94000000-0000-0000-0000-00000000000a', '94000000-0000-0000-0000-0000000000e1', '94000000-0000-0000-0000-0000000000c1', '94000000-0000-0000-0000-0000000000a1'),
  ('94000000-0000-0000-0000-00000000000a', '94000000-0000-0000-0000-0000000000e2', '94000000-0000-0000-0000-0000000000c1', '94000000-0000-0000-0000-0000000000a1');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise) VALUES
  ('94000000-0000-0000-0000-00000000000a', :'parent', '94000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true),
  ('94000000-0000-0000-0000-00000000000a', :'autre_parent', '94000000-0000-0000-0000-0000000000e2', 'parent', 'en_attente', true);
-- Un cours aujourd'hui, une évaluation en brouillon, une note publiée.
INSERT INTO public.emplois_du_temps (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, salle_id, jour_semaine, heure_debut, heure_fin, type)
VALUES ('94000000-0000-0000-0000-00000000000a', '94000000-0000-0000-0000-0000000000a1', '94000000-0000-0000-0000-0000000000c1', :'prof',
        '94000000-0000-0000-0000-0000000000a5', extract(isodow from current_date)::int, '08:00', '10:00', 'cours');
INSERT INTO public.evaluations (id, etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, type, libelle, statut, publie_le) VALUES
  ('94000000-0000-0000-0000-0000000000d1', '94000000-0000-0000-0000-00000000000a', '94000000-0000-0000-0000-0000000000a1',
   '94000000-0000-0000-0000-0000000000c1', :'prof', 'controle', 'Dictée', 'brouillon', NULL),
  ('94000000-0000-0000-0000-0000000000d2', '94000000-0000-0000-0000-00000000000a', '94000000-0000-0000-0000-0000000000a1',
   '94000000-0000-0000-0000-0000000000c1', :'prof', 'controle', 'Calcul', 'publiee', now());
INSERT INTO public.notes (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par) VALUES
  ('94000000-0000-0000-0000-00000000000a', '94000000-0000-0000-0000-0000000000d2', '94000000-0000-0000-0000-0000000000e1', 15, :'prof');
-- Une annonce reçue par le parent.
INSERT INTO public.annonces_ecole (id, etablissement_id, portee, titre, corps, publiee_par) VALUES
  ('94000000-0000-0000-0000-0000000000f1', '94000000-0000-0000-0000-00000000000a', 'ecole', 'Réunion', 'Samedi 10 h', :'dir_a');
INSERT INTO public.annonces_destinataires (annonce_id, profile_id, fiche_eleve_id) VALUES
  ('94000000-0000-0000-0000-0000000000f1', :'parent', '94000000-0000-0000-0000-0000000000e1');

SET LOCAL ROLE authenticated;

-- Direction : tous ses compteurs.
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT is(pg_temp.cles(), 'alertes_ouvertes,annonces_non_lues,cahier_non_lu,dossiers_inscription,familles_en_retard,groupes_non_lus,liaisons_a_valider,numeros_a_confirmer',
  'direction : liaisons, numéros, dossiers, retards de paiement, alertes, annonces, cahier');
SELECT is(pg_temp.n('liaisons_a_valider'), 1, 'direction : une demande de liaison à valider');

-- Personnel : selon le poste.
SELECT pg_temp.en_tant_que(:'portail');
SELECT is(pg_temp.cles(), 'annonces_non_lues,cahier_non_lu,groupes_non_lus', 'agent du portail : ni liaisons, ni paiements, ni alertes');
SELECT pg_temp.en_tant_que(:'caissier');
SELECT is(pg_temp.cles(), 'annonces_non_lues,cahier_non_lu,familles_en_retard,groupes_non_lus', 'caissier : les familles en retard de paiement, rien d''autre');

-- Enseignant : appel à faire, notes à saisir ; plus d'appel après la saisie.
SELECT pg_temp.en_tant_que(:'prof');
SELECT is(pg_temp.n('appels_a_faire'), 1, 'enseignant : appel du CM1 B à faire');
SELECT is(pg_temp.n('notes_a_saisir'), 1, 'enseignant : une évaluation à compléter');
SELECT ok(pg_temp.cles() NOT LIKE '%liaisons_a_valider%' AND pg_temp.cles() NOT LIKE '%familles_en_retard%',
  'enseignant : ni liaisons ni paiements');
SELECT is((SELECT matiere IS NULL AND classe = 'CM1 B' AND salle = 'Salle 4' AND heure_debut = '08:00'
             FROM public.mon_aujourdhui('94000000-0000-0000-0000-00000000000a')), true, 'enseignant : son cours d''aujourd''hui (classe, salle, heure)');
RESET ROLE;
INSERT INTO public.presences (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, statut, saisi_par) VALUES
  ('94000000-0000-0000-0000-00000000000a', '94000000-0000-0000-0000-0000000000a1', '94000000-0000-0000-0000-0000000000c1',
   '94000000-0000-0000-0000-0000000000e1', 'present', :'prof');
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'prof');
SELECT is(pg_temp.n('appels_a_faire'), 0, 'appel fait : plus rien à faire');

-- Parent : son enfant seulement.
SELECT pg_temp.en_tant_que(:'parent');
SELECT is(pg_temp.n('nouvelles_notes', '94000000-0000-0000-0000-0000000000e1'), 1, 'parent : une nouvelle note de son enfant');
SELECT is(pg_temp.n('annonces_non_lues', '94000000-0000-0000-0000-0000000000e1'), 1, 'parent : une annonce non lue');
SELECT ok(pg_temp.cles('94000000-0000-0000-0000-0000000000e1') LIKE '%livres_a_rendre%tranches_a_payer%',
  'parent : livres à rendre et tranches à payer');
SELECT ok(pg_temp.cles('94000000-0000-0000-0000-0000000000e1') NOT LIKE '%liaisons%' AND pg_temp.cles('94000000-0000-0000-0000-0000000000e1') NOT LIKE '%familles%',
  'parent : aucun compteur de l''école');
SELECT is((SELECT count(*)::int FROM public.mon_aujourdhui('94000000-0000-0000-0000-00000000000a', '94000000-0000-0000-0000-0000000000e1')), 1,
  'parent : le cours du jour de la classe de son enfant');
SELECT throws_ok($$ SELECT public.accueil_resume('94000000-0000-0000-0000-00000000000a', '94000000-0000-0000-0000-0000000000e2') $$,
  '42501', 'PERMISSION_REFUSEE', 'parent : rien sur l''enfant d''un autre');
SELECT throws_ok($$ SELECT * FROM public.mon_aujourdhui('94000000-0000-0000-0000-00000000000a', '94000000-0000-0000-0000-0000000000e2') $$,
  '42501', 'PERMISSION_REFUSEE', 'parent : pas l''emploi du temps d''un autre enfant');
RESET ROLE;
INSERT INTO public.annonces_lectures (annonce_id, profile_id) VALUES ('94000000-0000-0000-0000-0000000000f1', :'parent');
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'parent');
SELECT is(pg_temp.n('annonces_non_lues', '94000000-0000-0000-0000-0000000000e1'), 0, 'annonce lue : compteur à zéro');

-- Parent en attente : rien.
SELECT pg_temp.en_tant_que(:'autre_parent');
SELECT throws_ok($$ SELECT public.accueil_resume('94000000-0000-0000-0000-00000000000a', '94000000-0000-0000-0000-0000000000e2') $$,
  '42501', 'PERMISSION_REFUSEE', 'parent en attente de l''école : rien');

-- Autre école.
SELECT pg_temp.en_tant_que(:'dir_b');
SELECT throws_ok($$ SELECT public.accueil_resume('94000000-0000-0000-0000-00000000000a') $$, '42501', 'PERMISSION_REFUSEE',
  'direction d''une autre école : refusée');
SELECT throws_ok($$ SELECT * FROM public.mon_aujourdhui('94000000-0000-0000-0000-00000000000a') $$, '42501', 'PERMISSION_REFUSEE',
  'direction d''une autre école : pas l''emploi du temps');
SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);
SELECT throws_ok($$ SELECT public.accueil_resume('94000000-0000-0000-0000-00000000000a') $$, '42501', 'AUTH_REQUISE', 'sans compte : refusé');
SELECT throws_ok($$ SELECT * FROM public.mon_aujourdhui('94000000-0000-0000-0000-00000000000a') $$, '42501', 'AUTH_REQUISE',
  'sans compte : pas d''emploi du temps');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
