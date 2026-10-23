-- ============================================================================
-- EcoShop — Test RLS 86 : cahier de liaison (REG-19 lot 2, migration 1559)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  UPDATE public.profiles SET role_racine = p_role::public.role_racine, prenom = 'Test', nom = initcap(split_part(p_email, '@', 1))
   WHERE id = v_id;
  RETURN v_id;
END $$;

SELECT plan(41);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('86000000-0000-0000-0000-00000000000a', 'École A', 'ecole-a-86', 'GNF'),
  ('86000000-0000-0000-0000-00000000000b', 'École B', 'ecole-b-86', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('86000000-0000-0000-0000-0000000000a1', '86000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('86000000-0000-0000-0000-0000000000c1', '86000000-0000-0000-0000-00000000000a', '86000000-0000-0000-0000-0000000000a1', 'CM1', 'CM1'),
  ('86000000-0000-0000-0000-0000000000c2', '86000000-0000-0000-0000-00000000000a', '86000000-0000-0000-0000-0000000000a1', 'CM2', 'CM2');

SELECT pg_temp.compte('dir.a@exemple.org', 'direction') AS dir_a \gset
SELECT pg_temp.compte('dir.b@exemple.org', 'direction') AS dir_b \gset
SELECT pg_temp.compte('prof.cm1@exemple.org', 'enseignant') AS prof_a \gset
SELECT pg_temp.compte('prof.cm2@exemple.org', 'enseignant') AS prof_b \gset
SELECT pg_temp.compte('p1@exemple.org', 'parent') AS p1 \gset
SELECT pg_temp.compte('p2@exemple.org', 'parent') AS p2 \gset
SELECT pg_temp.compte('attente@exemple.org', 'parent') AS p_attente \gset
SELECT pg_temp.compte('inconnu@exemple.org', 'parent') AS p_x \gset
SELECT pg_temp.compte('eleve1@exemple.org', 'eleve') AS el1 \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_a', '86000000-0000-0000-0000-00000000000a', 'direction'),
  (:'dir_b', '86000000-0000-0000-0000-00000000000b', 'direction'),
  (:'prof_a', '86000000-0000-0000-0000-00000000000a', 'enseignant'),
  (:'prof_b', '86000000-0000-0000-0000-00000000000a', 'enseignant');
INSERT INTO public.affectations_enseignants (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id) VALUES
  ('86000000-0000-0000-0000-00000000000a', '86000000-0000-0000-0000-0000000000a1', :'prof_a', '86000000-0000-0000-0000-0000000000c1'),
  ('86000000-0000-0000-0000-00000000000a', '86000000-0000-0000-0000-0000000000a1', :'prof_b', '86000000-0000-0000-0000-0000000000c2');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id) VALUES
  ('86000000-0000-0000-0000-0000000000e1', '86000000-0000-0000-0000-00000000000a', 'A86-1', 'BAH', 'Awa', '2015-01-01', :'el1'),
  ('86000000-0000-0000-0000-0000000000e2', '86000000-0000-0000-0000-00000000000a', 'A86-2', 'DIALLO', 'Ousmane', '2014-01-01', NULL);
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('86000000-0000-0000-0000-00000000000a', '86000000-0000-0000-0000-0000000000e1', '86000000-0000-0000-0000-0000000000c1', '86000000-0000-0000-0000-0000000000a1'),
  ('86000000-0000-0000-0000-00000000000a', '86000000-0000-0000-0000-0000000000e2', '86000000-0000-0000-0000-0000000000c2', '86000000-0000-0000-0000-0000000000a1');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise) VALUES
  ('86000000-0000-0000-0000-00000000000a', :'p1', '86000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true),
  ('86000000-0000-0000-0000-00000000000a', :'p2', '86000000-0000-0000-0000-0000000000e2', 'parent', 'confirmee', true),
  ('86000000-0000-0000-0000-00000000000a', :'p_attente', '86000000-0000-0000-0000-0000000000e1', 'parent', 'en_attente', true);

-- ---------------------------------------------------------------------------
-- 1. Qui écrit : enseignant de la classe de l'élève, ou direction
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'prof_a');
SELECT is((public.ecrire_mot_liaison('86000000-0000-0000-0000-0000000000f1', '86000000-0000-0000-0000-0000000000e1',
  'Awa a oublié son cahier de maths.') ->> 'parents')::int, 1, 'enseignant de la classe : mot écrit, un parent confirmé prévenu');
SELECT is((public.ecrire_mot_liaison('86000000-0000-0000-0000-0000000000f1', '86000000-0000-0000-0000-0000000000e1',
  'Awa a oublié son cahier de maths.') ->> 'deja_recu')::boolean, true, 'renvoi avec la même clé : rien ne repart');
SELECT throws_ok($$ SELECT public.ecrire_mot_liaison(gen_random_uuid(), '86000000-0000-0000-0000-0000000000e2', 'Bonjour') $$,
  '42501', 'PERMISSION_REFUSEE', 'enseignant : pas un élève d''une autre classe');
SELECT pg_temp.en_tant_que(:'prof_b');
SELECT throws_ok($$ SELECT public.ecrire_mot_liaison(gen_random_uuid(), '86000000-0000-0000-0000-0000000000e1', 'Bonjour') $$,
  '42501', 'PERMISSION_REFUSEE', 'enseignant d''une autre classe : refusé');
SELECT throws_ok($$ SELECT public.ecrire_mot_liaison('86000000-0000-0000-0000-0000000000f1', '86000000-0000-0000-0000-0000000000e1', 'Bonjour') $$,
  '23505', 'CLE_DEJA_UTILISEE', 'clé d''un autre auteur : refusée');
SELECT pg_temp.en_tant_que(:'dir_b');
SELECT throws_ok($$ SELECT public.ecrire_mot_liaison(gen_random_uuid(), '86000000-0000-0000-0000-0000000000e1', 'Bonjour') $$,
  '42501', 'PERMISSION_REFUSEE', 'direction d''une autre école : refusé');
SELECT pg_temp.en_tant_que(:'p1');
SELECT throws_ok($$ SELECT public.ecrire_mot_liaison(gen_random_uuid(), '86000000-0000-0000-0000-0000000000e1', 'Bonjour') $$,
  '42501', 'PERMISSION_REFUSEE', 'un parent n''ouvre pas de fil (il répond)');
SELECT throws_ok($$ INSERT INTO public.messages_liaison (id, etablissement_id, fiche_eleve_id, auteur_id, corps)
  VALUES (gen_random_uuid(), '86000000-0000-0000-0000-00000000000a', '86000000-0000-0000-0000-0000000000e1', auth.uid(), 'Direct') $$,
  '42501', NULL, 'aucune écriture directe');
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT lives_ok($$ SELECT public.ecrire_mot_liaison('86000000-0000-0000-0000-0000000000f2', '86000000-0000-0000-0000-0000000000e2',
  'Réunion avec la direction lundi.') $$, 'direction : écrit au sujet de tout élève de l''école');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications WHERE type = 'cahier_liaison' AND destinataire = :'p1'), 1,
  'parent confirmé prévenu une fois (pas au renvoi)');
SELECT is((SELECT count(*)::int FROM public.notifications WHERE type = 'cahier_liaison' AND destinataire IN (:'p_attente', :'el1')), 0,
  'ni le parent en attente, ni l''élève');

-- ---------------------------------------------------------------------------
-- 2. Qui lit : parents confirmés de l'élève seulement
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'p1');
SELECT is(jsonb_array_length(public.cahier_liaison('86000000-0000-0000-0000-0000000000e1')), 1, 'parent confirmé : le mot de son enfant');
SELECT is((SELECT count(*)::int FROM public.messages_liaison), 1, 'lecture directe : seulement les messages de son enfant');
SELECT throws_ok($$ SELECT public.cahier_liaison('86000000-0000-0000-0000-0000000000e2') $$, '42501', 'PERMISSION_REFUSEE',
  'parent : pas le cahier d''un autre élève');
SELECT pg_temp.en_tant_que(:'p_attente');
SELECT throws_ok($$ SELECT public.cahier_liaison('86000000-0000-0000-0000-0000000000e1') $$, '42501', 'PERMISSION_REFUSEE',
  'parent en attente de l''école : rien');
SELECT pg_temp.en_tant_que(:'el1');
SELECT throws_ok($$ SELECT public.cahier_liaison('86000000-0000-0000-0000-0000000000e1') $$, '42501', 'PERMISSION_REFUSEE',
  'l''élève lui-même : rien (réservé aux parents)');
SELECT pg_temp.en_tant_que(:'p_x');
SELECT throws_ok($$ SELECT public.cahier_liaison('86000000-0000-0000-0000-0000000000e1') $$, '42501', 'PERMISSION_REFUSEE',
  'parent non lié : rien');
SELECT is_empty($$ SELECT id FROM public.messages_liaison $$, 'parent non lié : table illisible');
SELECT throws_ok($$ SELECT public.repondre_liaison(gen_random_uuid(), '86000000-0000-0000-0000-0000000000f1', 'Je réponds') $$,
  '42501', 'PERMISSION_REFUSEE', 'parent non lié : ne répond pas');
SELECT pg_temp.en_tant_que(:'dir_b');
SELECT throws_ok($$ SELECT public.cahier_liaison('86000000-0000-0000-0000-0000000000e1') $$, '42501', 'PERMISSION_REFUSEE',
  'autre école : rien');
SELECT pg_temp.en_tant_que(:'prof_b');
SELECT throws_ok($$ SELECT public.cahier_liaison('86000000-0000-0000-0000-0000000000e1') $$, '42501', 'PERMISSION_REFUSEE',
  'enseignant d''une autre classe : rien');

-- ---------------------------------------------------------------------------
-- 3. Lecture confirmée, réponses
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'p2');
SELECT throws_ok($$ SELECT public.confirmer_lecture_liaison('86000000-0000-0000-0000-0000000000f1') $$, '42501', 'PERMISSION_REFUSEE',
  'un autre parent ne confirme pas');
SELECT pg_temp.en_tant_que(:'p1');
SELECT lives_ok($$ SELECT public.confirmer_lecture_liaison('86000000-0000-0000-0000-0000000000f1') $$, 'parent : confirme la lecture');
SELECT is((public.repondre_liaison('86000000-0000-0000-0000-0000000000d1', '86000000-0000-0000-0000-0000000000f1',
  'Merci, je le lui rappelle.') ->> 'deja_recu')::boolean, false, 'parent : répond');
SELECT pg_temp.en_tant_que(:'prof_a');
SELECT is((SELECT (m ->> 'lectures')::int || '/' || (m ->> 'parents') FROM jsonb_array_elements(public.cahier_liaison('86000000-0000-0000-0000-0000000000e1')) m),
  '1/1', 'enseignant : un parent sur un a confirmé la lecture');
SELECT lives_ok($$ SELECT public.repondre_liaison('86000000-0000-0000-0000-0000000000d2', '86000000-0000-0000-0000-0000000000f1', 'Parfait, merci.') $$,
  'enseignant : répond dans le fil');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications WHERE type = 'cahier_liaison' AND destinataire = :'prof_a'), 1,
  'réponse du parent : l''auteur du mot est prévenu');
SELECT is((SELECT count(*)::int FROM public.notifications WHERE type = 'cahier_liaison' AND destinataire = :'p1'), 2,
  'réponse de l''enseignant : le parent est prévenu');
SELECT is((SELECT count(*)::int FROM public.messages_liaison WHERE fiche_eleve_id = '86000000-0000-0000-0000-0000000000e1'), 3,
  'chaque message reste rattaché à l''élève');

-- ---------------------------------------------------------------------------
-- 4. Modération : la direction masque, journalisé
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'prof_a');
SELECT throws_ok($$ SELECT public.masquer_message_liaison('86000000-0000-0000-0000-0000000000d1', 'Propos déplacés') $$,
  '42501', 'PERMISSION_REFUSEE', 'un enseignant ne masque pas');
SELECT pg_temp.en_tant_que(:'dir_b');
SELECT throws_ok($$ SELECT public.masquer_message_liaison('86000000-0000-0000-0000-0000000000d1', 'Propos déplacés') $$,
  '42501', 'PERMISSION_REFUSEE', 'une autre école ne masque pas');
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT throws_ok($$ SELECT public.masquer_message_liaison('86000000-0000-0000-0000-0000000000d1', ' ') $$,
  '22023', 'MOTIF_REQUIS', 'raison obligatoire');
SELECT lives_ok($$ SELECT public.masquer_message_liaison('86000000-0000-0000-0000-0000000000d1', 'Propos déplacés') $$,
  'direction : masque la réponse');
SELECT is((SELECT count(*)::int FROM public.journal_audit WHERE entite = 'mot_liaison'
           AND entite_id = '86000000-0000-0000-0000-0000000000d1' AND auteur_id = :'dir_a'
           AND fiche_eleve_id = '86000000-0000-0000-0000-0000000000e1' AND nouvelle_valeur ->> 'motif' = 'Propos déplacés'), 1,
  'journal d''audit : qui, quand, raison, élève');
SELECT pg_temp.en_tant_que(:'prof_a');
SELECT is((SELECT jsonb_array_length(m -> 'reponses') FROM jsonb_array_elements(public.cahier_liaison('86000000-0000-0000-0000-0000000000e1')) m),
  2, 'personnel : la réponse masquée reste visible (marquée)');
SELECT pg_temp.en_tant_que(:'p1');
SELECT is((SELECT jsonb_array_length(m -> 'reponses') FROM jsonb_array_elements(public.cahier_liaison('86000000-0000-0000-0000-0000000000e1')) m),
  1, 'parent : la réponse masquée disparaît');
SELECT is_empty($$ SELECT id FROM public.journal_audit WHERE entite = 'mot_liaison' $$, 'journal illisible pour un parent');
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT public.masquer_message_liaison('86000000-0000-0000-0000-0000000000f1', 'Envoyé par erreur');
SELECT pg_temp.en_tant_que(:'p1');
SELECT is(jsonb_array_length(public.cahier_liaison('86000000-0000-0000-0000-0000000000e1')), 0, 'mot masqué : disparaît pour le parent');
SELECT throws_ok($$ SELECT public.repondre_liaison(gen_random_uuid(), '86000000-0000-0000-0000-0000000000f1', 'Encore moi') $$,
  '42501', 'PERMISSION_REFUSEE', 'mot masqué : plus de réponse du parent');

-- ---------------------------------------------------------------------------
-- 5. Élèves du cahier
-- ---------------------------------------------------------------------------
SELECT is(jsonb_array_length(public.eleves_cahier_liaison()), 1, 'parent : ses enfants confirmés');
SELECT pg_temp.en_tant_que(:'prof_a');
SELECT is(jsonb_array_length(public.eleves_cahier_liaison('86000000-0000-0000-0000-00000000000a')), 1, 'enseignant : les élèves de sa classe');

SELECT * FROM finish();
ROLLBACK;
