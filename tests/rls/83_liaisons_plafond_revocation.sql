-- ============================================================================
-- EcoShop — Test RLS 83 : comptes multiples, protections à la liaison
-- (REG-18 E, migration 20260906001556)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text, p_prenom text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  UPDATE public.profiles SET role_racine = p_role::public.role_racine, prenom = p_prenom, nom = 'Test' WHERE id = v_id;
  RETURN v_id;
END $$;

SELECT plan(32);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('83000000-0000-0000-0000-00000000000a', 'École A', 'ecole-a-83', 'GNF'),
  ('83000000-0000-0000-0000-00000000000b', 'École B', 'ecole-b-83', 'GNF');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance) VALUES
  ('83000000-0000-0000-0000-0000000000e1', '83000000-0000-0000-0000-00000000000a', 'A83-1', 'CAMARA', 'Fanta', '2014-05-06'),
  ('83000000-0000-0000-0000-0000000000e2', '83000000-0000-0000-0000-00000000000a', 'A83-2', 'BAH', 'Ousmane', '2013-01-02');

SELECT pg_temp.compte('dir.a@exemple.org', 'direction', 'Directrice') AS dir_a \gset
SELECT pg_temp.compte('dir.b@exemple.org', 'direction', 'Directeur') AS dir_b \gset
SELECT pg_temp.compte('prof.a@exemple.org', 'enseignant', 'Prof') AS prof_a \gset
SELECT pg_temp.compte('p1@exemple.org', 'parent', 'Un') AS p1 \gset
SELECT pg_temp.compte('p2@exemple.org', 'parent', 'Deux') AS p2 \gset
SELECT pg_temp.compte('p3@exemple.org', 'parent', 'Trois') AS p3 \gset
SELECT pg_temp.compte('eleve@exemple.org', 'eleve', 'Fanta') AS eleve \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_a', '83000000-0000-0000-0000-00000000000a', 'direction'),
  (:'dir_b', '83000000-0000-0000-0000-00000000000b', 'direction'),
  (:'prof_a', '83000000-0000-0000-0000-00000000000a', 'enseignant');

-- ---------------------------------------------------------------------------
-- 1. Plafond par défaut : 2 parents confirmés, le troisième attend
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'p1');
SELECT public.lier_parent_a_fiche('A83-1', '2014-05-06') AS rel1 \gset
SELECT is(public.statut_ma_liaison(:'rel1'), 'confirmee', '1er parent : liaison confirmée');
SELECT pg_temp.en_tant_que(:'p2');
SELECT public.lier_parent_a_fiche('A83-1', '2014-05-06') AS rel2 \gset
SELECT is(public.statut_ma_liaison(:'rel2'), 'confirmee', '2e parent : liaison confirmée');
SELECT pg_temp.en_tant_que(:'p3');
SELECT public.lier_parent_a_fiche('A83-1', '2014-05-06') AS rel3 \gset
SELECT is(public.statut_ma_liaison(:'rel3'), 'en_attente', '3e parent : au-delà du plafond, en attente');
SELECT ok(NOT public.est_parent_confirme('83000000-0000-0000-0000-0000000000e1'), 'en attente : aucun accès à la fiche');
SELECT is_empty($$ SELECT id FROM public.fiches_eleves WHERE id = '83000000-0000-0000-0000-0000000000e1' $$,
  'en attente : fiche invisible (RLS)');
SELECT is(public.lier_parent_a_fiche('A83-1', '2014-05-06'), :'rel3'::uuid, 'refaire la liaison en attente : même demande, rien de plus');
SELECT is(public.statut_ma_liaison(:'rel3'), 'en_attente', 'refaire la liaison ne la confirme pas');
SELECT throws_ok(format('SELECT public.decider_liaison_parent(%L, true)', :'rel3'), '42501', 'PERMISSION_REFUSEE',
  'le parent ne s''accepte pas lui-même');
UPDATE public.relations_parent_eleve SET statut = 'confirmee' WHERE id = :'rel3';
SELECT is(public.statut_ma_liaison(:'rel3'), 'en_attente', 'ni par une écriture directe (RLS)');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 2. La direction est prévenue de chaque liaison
-- ---------------------------------------------------------------------------
SELECT is((SELECT count(*)::int FROM public.notifications
           WHERE destinataire = :'dir_a' AND type = 'liaison_compte'), 3, 'direction A : une notification par liaison');
SELECT ok(EXISTS (SELECT 1 FROM public.notifications WHERE destinataire = :'dir_a' AND type = 'liaison_compte'
                  AND variables ->> 'statut' = 'en_attente' AND contenu LIKE '%en attente de votre accord%'),
  'la demande au-delà du plafond est signalée comme en attente');
SELECT is((SELECT count(*)::int FROM public.notifications WHERE destinataire = :'dir_b' AND type = 'liaison_compte'), 0,
  'direction B : rien sur les élèves de l''école A');

-- ---------------------------------------------------------------------------
-- 3. Tableau de bord : liste, décisions, cloisonnement
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT is((SELECT count(*)::int FROM public.liaisons_comptes('83000000-0000-0000-0000-00000000000a')), 3,
  'direction A : trois liaisons listées');
SELECT ok((SELECT identifiant_ecoshop FROM public.liaisons_comptes('83000000-0000-0000-0000-00000000000a') WHERE compte_id = :'p3')
          ~ '^EC-', 'chaque compte est montré avec son identifiant EcoShop');
SELECT pg_temp.en_tant_que(:'dir_b');
SELECT throws_ok($$ SELECT * FROM public.liaisons_comptes('83000000-0000-0000-0000-00000000000a') $$, '42501', 'PERMISSION_REFUSEE',
  'direction d''une autre école : liste refusée');
SELECT throws_ok(format('SELECT public.decider_liaison_parent(%L, true)', :'rel3'), '42501', 'PERMISSION_REFUSEE',
  'direction d''une autre école : décision refusée');
SELECT throws_ok(format('SELECT public.revoquer_liaison_parent(%L)', :'rel1'), '42501', 'PERMISSION_REFUSEE',
  'direction d''une autre école : révocation refusée');
SELECT pg_temp.en_tant_que(:'prof_a');
SELECT throws_ok($$ SELECT * FROM public.liaisons_comptes('83000000-0000-0000-0000-00000000000a') $$, '42501', 'PERMISSION_REFUSEE',
  'enseignant de l''école : liste refusée');

SELECT pg_temp.en_tant_que(:'dir_a');
SELECT is(public.decider_liaison_parent(:'rel3', true), 'confirmee', 'direction A accepte la demande en attente');
SELECT throws_ok(format('SELECT public.decider_liaison_parent(%L, false)', :'rel3'), '22023', 'LIAISON_DEJA_TRAITEE',
  'une décision ne se rejoue pas');
RESET ROLE;
SELECT ok(EXISTS (SELECT 1 FROM public.notifications WHERE destinataire = :'p3' AND type = 'liaison_compte'
                  AND variables ->> 'statut' = 'confirmee'), 'le parent est prévenu de l''accord');

-- ---------------------------------------------------------------------------
-- 4. Révocation : plus d'accès, jamais reconfirmée seule
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT lives_ok(format('SELECT public.revoquer_liaison_parent(%L)', :'rel1'), 'direction A révoque le 1er parent');
SELECT lives_ok($$ SELECT public.definir_plafond_parents('83000000-0000-0000-0000-00000000000a', 5) $$, 'plafond porté à 5');
SELECT pg_temp.en_tant_que(:'p1');
SELECT ok(NOT public.est_parent_confirme('83000000-0000-0000-0000-0000000000e1'), 'parent révoqué : plus d''accès');
SELECT public.lier_parent_a_fiche('A83-1', '2014-05-06') AS rel1bis \gset
SELECT is(public.statut_ma_liaison(:'rel1bis'), 'en_attente', 'parent révoqué qui refait la liaison : en attente, même sous le plafond');

-- ---------------------------------------------------------------------------
-- 5. Réglage du plafond
-- ---------------------------------------------------------------------------
SELECT throws_ok($$ SELECT public.definir_plafond_parents('83000000-0000-0000-0000-00000000000a', 9) $$, '42501', 'PERMISSION_REFUSEE',
  'un parent ne règle pas le plafond');
SELECT pg_temp.en_tant_que(:'prof_a');
SELECT throws_ok($$ SELECT public.definir_plafond_parents('83000000-0000-0000-0000-00000000000a', 9) $$, '42501', 'PERMISSION_REFUSEE',
  'un enseignant non plus');
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT throws_ok($$ SELECT public.definir_plafond_parents('83000000-0000-0000-0000-00000000000a', 0) $$, '22023', 'PLAFOND_INVALIDE',
  'plafond 0 refusé');

-- ---------------------------------------------------------------------------
-- 6. Compte élève : direction prévenue, révocation
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'eleve');
SELECT lives_ok($$ SELECT public.lier_compte_a_fiche('A83-1', '2014-05-06') $$, 'l''élève lie son compte');
RESET ROLE;
SELECT ok(EXISTS (SELECT 1 FROM public.notifications WHERE destinataire = :'dir_a' AND type = 'liaison_compte'
                  AND variables ->> 'nature' = 'eleve'), 'direction prévenue de la liaison du compte élève');
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT lives_ok($$ SELECT public.revoquer_liaison_eleve('83000000-0000-0000-0000-0000000000e1') $$, 'direction révoque le compte élève');
RESET ROLE;
SELECT ok((SELECT profile_id IS NULL FROM public.fiches_eleves WHERE id = '83000000-0000-0000-0000-0000000000e1')
          AND NOT (SELECT actif FROM public.etablissements_membres
                   WHERE profile_id = :'eleve' AND etablissement_id = '83000000-0000-0000-0000-00000000000a'),
  'fiche libérée, compte élève plus membre de l''école');

SELECT * FROM finish();
ROLLBACK;
