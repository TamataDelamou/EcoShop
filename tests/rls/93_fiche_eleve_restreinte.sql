-- ============================================================================
-- EcoShop — Test RLS 93 : fiche élève restreinte, cahier de liaison du
-- surveillant général (migration 1568)
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
  UPDATE public.profiles SET role_racine = p_role::public.role_racine, prenom = 'Test', nom = 'Test' WHERE id = v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.au_poste(p_email text, p_modele text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_id uuid := pg_temp.compte(p_email, 'personnel');
BEGIN
  INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement, poste_id)
  SELECT v_id, '93000000-0000-0000-0000-00000000000a', m.role, p.id
    FROM public.postes p JOIN public.modeles_postes m ON m.code = p.modele_code
   WHERE p.etablissement_id = '93000000-0000-0000-0000-00000000000a' AND p.modele_code = p_modele;
  RETURN v_id;
END $$;

-- Ce que l'appelant lit de l'élève : fiche (avec matricule et naissance),
-- inscription.
CREATE OR REPLACE FUNCTION pg_temp.fiche() RETURNS text LANGUAGE sql AS $$
  SELECT format('fiches=%s matricule=%s naissance=%s inscriptions=%s',
    (SELECT count(*) FROM public.fiches_eleves),
    coalesce((SELECT matricule FROM public.fiches_eleves LIMIT 1), '-'),
    coalesce((SELECT date_naissance::text FROM public.fiches_eleves LIMIT 1), '-'),
    (SELECT count(*) FROM public.inscriptions));
$$;

SELECT plan(32);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('93000000-0000-0000-0000-00000000000a', 'École A', 'ecole-a-93', 'GNF'),
  ('93000000-0000-0000-0000-00000000000b', 'École B', 'ecole-b-93', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('93000000-0000-0000-0000-0000000000a1', '93000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('93000000-0000-0000-0000-0000000000c1', '93000000-0000-0000-0000-00000000000a', '93000000-0000-0000-0000-0000000000a1', '6A', '6e A'),
  ('93000000-0000-0000-0000-0000000000c2', '93000000-0000-0000-0000-00000000000a', '93000000-0000-0000-0000-0000000000a1', '6B', '6e B');

SELECT pg_temp.compte('dir.a@exemple.org', 'direction') AS dir_a \gset
SELECT pg_temp.compte('dir.b@exemple.org', 'direction') AS dir_b \gset
SELECT pg_temp.compte('prof.c1@exemple.org', 'enseignant') AS prof_c1 \gset
SELECT pg_temp.compte('prof.c2@exemple.org', 'enseignant') AS prof_c2 \gset
SELECT pg_temp.compte('parent@exemple.org', 'parent') AS parent \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_a', '93000000-0000-0000-0000-00000000000a', 'direction'),
  (:'dir_b', '93000000-0000-0000-0000-00000000000b', 'direction'),
  (:'prof_c1', '93000000-0000-0000-0000-00000000000a', 'enseignant'),
  (:'prof_c2', '93000000-0000-0000-0000-00000000000a', 'enseignant');
INSERT INTO public.affectations_enseignants (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id) VALUES
  ('93000000-0000-0000-0000-00000000000a', '93000000-0000-0000-0000-0000000000a1', :'prof_c1', '93000000-0000-0000-0000-0000000000c1'),
  ('93000000-0000-0000-0000-00000000000a', '93000000-0000-0000-0000-0000000000a1', :'prof_c2', '93000000-0000-0000-0000-0000000000c2');
SELECT pg_temp.au_poste('chauffeur@exemple.org', 'chauffeur') AS chauffeur \gset
SELECT pg_temp.au_poste('portail@exemple.org', 'agent_portail') AS portail \gset
SELECT pg_temp.au_poste('biblio@exemple.org', 'bibliothecaire') AS biblio \gset
SELECT pg_temp.au_poste('caissier@exemple.org', 'caissier') AS caissier \gset
SELECT pg_temp.au_poste('secretaire@exemple.org', 'secretaire') AS secretaire \gset
SELECT pg_temp.au_poste('surveillant@exemple.org', 'surveillant_general') AS surveillant \gset
SELECT pg_temp.au_poste('censeur@exemple.org', 'directeur_etudes') AS censeur \gset

INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance) VALUES
  ('93000000-0000-0000-0000-0000000000e1', '93000000-0000-0000-0000-00000000000a', 'A93-1', 'BAH', 'Awa', '2014-03-15');
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('93000000-0000-0000-0000-00000000000a', '93000000-0000-0000-0000-0000000000e1',
   '93000000-0000-0000-0000-0000000000c1', '93000000-0000-0000-0000-0000000000a1');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise) VALUES
  ('93000000-0000-0000-0000-00000000000a', :'parent', '93000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true);

INSERT INTO public.evaluations (id, etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, type, libelle, statut) VALUES
  ('93000000-0000-0000-0000-0000000000d1', '93000000-0000-0000-0000-00000000000a', '93000000-0000-0000-0000-0000000000a1',
   '93000000-0000-0000-0000-0000000000c1', :'prof_c1', 'controle', 'Contrôle', 'publiee');

SET LOCAL ROLE authenticated;

-- Écrivain légitime sans la fiche complète : le contrôle d'école ne dépend
-- plus de ce qu'il voit.
SELECT pg_temp.en_tant_que(:'censeur');
SELECT is(pg_temp.fiche(), 'fiches=0 matricule=- naissance=- inscriptions=1', 'censeur : l''inscription (notes), pas la fiche');
SELECT lives_ok($$ INSERT INTO public.notes (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par)
  VALUES ('93000000-0000-0000-0000-00000000000a', '93000000-0000-0000-0000-0000000000d1', '93000000-0000-0000-0000-0000000000e1', 13, auth.uid()) $$,
  'censeur : saisit une note sans voir la fiche complète');

-- ---------------------------------------------------------------------------
-- 1. Fiche complète refusée : annuaire seulement
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'chauffeur');
SELECT is(pg_temp.fiche(), 'fiches=0 matricule=- naissance=- inscriptions=0', 'chauffeur : ni fiche, ni matricule, ni date de naissance');
SELECT is((SELECT nom || ' ' || prenom || ' · ' || classe FROM public.annuaire_eleves('93000000-0000-0000-0000-00000000000a')),
  'BAH Awa · 6e A', 'chauffeur : annuaire (nom, prénom, classe)');
SELECT ok(pg_get_function_result('public.annuaire_eleves(uuid,text,uuid)'::regprocedure) !~ 'matricule|naissance',
  'annuaire : ni matricule ni date de naissance parmi ses colonnes');

SELECT pg_temp.en_tant_que(:'portail');
SELECT is(pg_temp.fiche(), 'fiches=0 matricule=- naissance=- inscriptions=0', 'agent du portail : ni fiche, ni matricule, ni date de naissance');
SELECT is((SELECT count(*)::int FROM public.annuaire_eleves('93000000-0000-0000-0000-00000000000a', 'awa')), 1, 'agent du portail : recherche dans l''annuaire');
SELECT lives_ok($$ SELECT * FROM public.cartes_portail('93000000-0000-0000-0000-00000000000a') $$, 'agent du portail : cartes à scanner (inchangé)');

SELECT pg_temp.en_tant_que(:'biblio');
SELECT is(pg_temp.fiche(), 'fiches=0 matricule=- naissance=- inscriptions=0', 'bibliothécaire : ni fiche, ni matricule, ni date de naissance');
SELECT is((SELECT count(*)::int FROM public.annuaire_eleves('93000000-0000-0000-0000-00000000000a')), 1, 'bibliothécaire : annuaire');

SELECT pg_temp.en_tant_que(:'caissier');
SELECT is(pg_temp.fiche(), 'fiches=0 matricule=- naissance=- inscriptions=1', 'caissier : l''inscription (pour encaisser), pas la fiche');

SELECT pg_temp.en_tant_que(:'prof_c2');
SELECT is(pg_temp.fiche(), 'fiches=0 matricule=- naissance=- inscriptions=0', 'enseignant d''une autre classe : pas la fiche');
SELECT is((SELECT count(*)::int FROM public.annuaire_eleves('93000000-0000-0000-0000-00000000000a')), 1, 'enseignant d''une autre classe : annuaire');

SELECT pg_temp.en_tant_que(:'dir_b');
SELECT is(pg_temp.fiche(), 'fiches=0 matricule=- naissance=- inscriptions=0', 'direction d''une autre école : rien');
SELECT throws_ok($$ SELECT * FROM public.annuaire_eleves('93000000-0000-0000-0000-00000000000a') $$, '42501', 'PERMISSION_REFUSEE',
  'direction d''une autre école : pas l''annuaire');
SELECT pg_temp.en_tant_que(:'parent');
SELECT throws_ok($$ SELECT * FROM public.annuaire_eleves('93000000-0000-0000-0000-00000000000a') $$, '42501', 'PERMISSION_REFUSEE',
  'parent : pas l''annuaire de l''école');

-- ---------------------------------------------------------------------------
-- 2. Fiche complète permise
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT is(pg_temp.fiche(), 'fiches=1 matricule=A93-1 naissance=2014-03-15 inscriptions=1', 'direction : fiche complète');
SELECT pg_temp.en_tant_que(:'secretaire');
SELECT is(pg_temp.fiche(), 'fiches=1 matricule=A93-1 naissance=2014-03-15 inscriptions=1', 'secrétariat : fiche complète');
SELECT pg_temp.en_tant_que(:'surveillant');
SELECT is(pg_temp.fiche(), 'fiches=1 matricule=A93-1 naissance=2014-03-15 inscriptions=1', 'surveillant général : fiche complète');
SELECT pg_temp.en_tant_que(:'prof_c1');
SELECT is(pg_temp.fiche(), 'fiches=1 matricule=A93-1 naissance=2014-03-15 inscriptions=1', 'enseignant de la classe : fiche complète');
SELECT pg_temp.en_tant_que(:'parent');
SELECT is(pg_temp.fiche(), 'fiches=1 matricule=A93-1 naissance=2014-03-15 inscriptions=1', 'parent confirmé : la fiche de son enfant');

-- ---------------------------------------------------------------------------
-- 3. Cahier de liaison : surveillant général
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'surveillant');
SELECT is((public.ecrire_mot_liaison('93000000-0000-0000-0000-0000000000f1', '93000000-0000-0000-0000-0000000000e1',
  'Awa est arrivée en retard trois fois cette semaine.') ->> 'parents')::int, 1, 'surveillant général : mot écrit, parent prévenu');
SELECT is((SELECT fiche_eleve_id FROM public.messages_liaison WHERE id = '93000000-0000-0000-0000-0000000000f1'),
  '93000000-0000-0000-0000-0000000000e1'::uuid, 'mot rattaché à l''élève');
SELECT is(jsonb_array_length(public.cahier_liaison('93000000-0000-0000-0000-0000000000e1')), 1, 'surveillant général : lit le fil');
SELECT pg_temp.en_tant_que(:'portail');
SELECT throws_ok($$ SELECT public.ecrire_mot_liaison(gen_random_uuid(), '93000000-0000-0000-0000-0000000000e1', 'Bonjour') $$,
  '42501', 'PERMISSION_REFUSEE', 'agent du portail : n''écrit pas aux parents');
SELECT throws_ok($$ SELECT public.cahier_liaison('93000000-0000-0000-0000-0000000000e1') $$, '42501', 'PERMISSION_REFUSEE',
  'agent du portail : ne lit pas le cahier');
SELECT pg_temp.en_tant_que(:'caissier');
SELECT throws_ok($$ SELECT public.ecrire_mot_liaison(gen_random_uuid(), '93000000-0000-0000-0000-0000000000e1', 'Bonjour') $$,
  '42501', 'PERMISSION_REFUSEE', 'caissier : n''écrit pas aux parents');
SELECT pg_temp.en_tant_que(:'prof_c1');
SELECT lives_ok($$ SELECT public.ecrire_mot_liaison('93000000-0000-0000-0000-0000000000f2', '93000000-0000-0000-0000-0000000000e1', 'Cahier oublié.') $$,
  'enseignant de la classe : écrit toujours');
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT is((SELECT count(*)::int FROM public.journal_audit WHERE entite = 'mot_liaison' AND champ = 'ecrit'
            AND fiche_eleve_id = '93000000-0000-0000-0000-0000000000e1'), 2, 'journal : chaque mot écrit, rattaché à l''élève');
SELECT is((SELECT count(*)::int FROM public.journal_audit WHERE entite = 'mot_liaison' AND champ = 'ecrit'
            AND auteur_id = :'surveillant'), 1, 'journal : l''auteur (surveillant général)');
SELECT pg_temp.en_tant_que(:'surveillant');
SELECT is((SELECT count(*)::int FROM public.journal_audit WHERE entite = 'mot_liaison'), 0, 'journal réservé à la direction');
RESET ROLE;
SELECT ok((SELECT 'scolarite.liaison.ecrire' = ANY (codes) FROM public.modeles_postes WHERE code = 'surveillant_general'),
  'modèle « Surveillant général » : écrire aux parents');

SELECT * FROM finish();
ROLLBACK;
