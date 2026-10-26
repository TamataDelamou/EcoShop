-- ============================================================================
-- EcoShop — Test RLS 90 : code du compte, compléments de l'application
-- (REG-22 partie A, migration 1563)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.sur(p_uid uuid, p_session uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'session_id', p_session)::text, true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text DEFAULT NULL, p_prenom text DEFAULT 'Test')
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  UPDATE public.profiles SET role_racine = p_role::public.role_racine, prenom = p_prenom, nom = 'Test' WHERE id = v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.connexion(p_uid uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.sessions (id, user_id, created_at, updated_at) VALUES (v_id, p_uid, now(), now());
  RETURN v_id;
END $$;

SELECT plan(18);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('90000000-0000-0000-0000-00000000000a', 'École A', 'ecole-a-90', 'GNF'),
  ('90000000-0000-0000-0000-00000000000b', 'École B', 'ecole-b-90', 'GNF');
SELECT pg_temp.compte('awa@exemple.org', NULL, 'Awa') AS awa \gset
SELECT pg_temp.compte('dir.a@exemple.org', 'direction', 'Directrice') AS dir_a \gset
SELECT pg_temp.compte('dir2.a@exemple.org', 'direction', 'Adjoint') AS dir2_a \gset
SELECT pg_temp.compte('dir.b@exemple.org', 'direction', 'Autre') AS dir_b \gset
SELECT pg_temp.compte('prof@exemple.org', 'enseignant', 'Mamadou') AS prof \gset
SELECT pg_temp.compte('parent@exemple.org', 'parent', 'Fatou') AS parent \gset
SELECT pg_temp.compte('eleve@exemple.org', 'eleve', 'Ibrahima') AS eleve \gset
SELECT pg_temp.compte('gsg@exemple.org', 'admin_gsg', 'Équipe') AS gsg \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'awa', '90000000-0000-0000-0000-00000000000a', 'personnel'),
  (:'dir_a', '90000000-0000-0000-0000-00000000000a', 'direction'),
  (:'dir2_a', '90000000-0000-0000-0000-00000000000a', 'direction'),
  (:'dir_b', '90000000-0000-0000-0000-00000000000b', 'direction'),
  (:'prof', '90000000-0000-0000-0000-00000000000a', 'enseignant');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id) VALUES
  ('90000000-0000-0000-0000-0000000000e1', '90000000-0000-0000-0000-00000000000a', 'A90-1', 'Test', 'Ibrahima', '2012-01-01', :'eleve');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise) VALUES
  ('90000000-0000-0000-0000-00000000000a', :'parent', '90000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true);

SELECT pg_temp.connexion(:'awa') AS s1 \gset
SELECT pg_temp.connexion(:'awa') AS s2 \gset
SELECT pg_temp.connexion(:'awa') AS s3 \gset
SELECT pg_temp.connexion(:'dir_a') AS sd \gset
SELECT pg_temp.connexion(:'dir_b') AS sdb \gset
SELECT pg_temp.connexion(:'prof') AS sp \gset
SELECT pg_temp.connexion(:'gsg') AS sg \gset

-- ---------------------------------------------------------------------------
-- 1. Après une autorisation : nouveau code, 15 minutes, une fois
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'awa', :'s1');
SELECT public.definir_code_compte('739146');
SELECT pg_temp.sur(:'awa', :'s2');
SELECT public.enregistrer_appareil('Tecno Spark 10', 'Android 13', '1.4.0');
SELECT throws_ok($$ SELECT public.choisir_code_apres_autorisation('582014') $$, '42501', 'CHOIX_EXPIRE',
  'appareil à vérifier : ne choisit pas de code');
SELECT public.demander_approbation_appareil() ->> 'id' AS dem \gset
SELECT pg_temp.sur(:'awa', :'s1');
SELECT public.approuver_appareil(:'dem');
SELECT throws_ok($$ SELECT public.choisir_code_apres_autorisation('582014') $$, '42501', 'CHOIX_EXPIRE',
  'l''appareil connu qui autorise ne choisit pas le code par cette voie');
SELECT pg_temp.sur(:'awa', :'s2');
SELECT throws_ok($$ SELECT public.choisir_code_apres_autorisation('123456') $$, '22023', 'CODE_EVIDENT', 'code évident refusé');
SELECT is(public.choisir_code_apres_autorisation('582014') ->> 'version_code', '2', 'appareil autorisé : nouveau code du compte');
SELECT throws_ok($$ SELECT public.choisir_code_apres_autorisation('602417') $$, '42501', 'CHOIX_EXPIRE', 'une seule fois');
SELECT pg_temp.sur(:'awa', :'s3');
SELECT public.enregistrer_appareil('Itel A70', 'Android 13', '1.4.0');
SELECT is(public.verifier_code_compte('582014') ->> 'resultat', 'bon', 'le nouveau code vaut pour le compte');
SELECT public.demander_approbation_appareil();
RESET ROLE;
-- Autorisation de s3 par s1, puis 15 minutes écoulées.
UPDATE public.sessions_appareils SET statut = 'a_verifier' WHERE session_id = :'s3';
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'awa', :'s3');
SELECT public.demander_approbation_appareil() ->> 'id' AS dem3 \gset
SELECT pg_temp.sur(:'awa', :'s1');
SELECT public.approuver_appareil(:'dem3');
RESET ROLE;
UPDATE public.sessions_appareils SET code_a_choisir_avant = now() - interval '1 second' WHERE session_id = :'s3';
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'awa', :'s3');
SELECT throws_ok($$ SELECT public.choisir_code_apres_autorisation('602417') $$, '42501', 'CHOIX_EXPIRE', 'après 15 minutes : refusé');

-- ---------------------------------------------------------------------------
-- 2. Personnes que la direction peut débloquer
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'dir_a', :'sd');
SELECT is((SELECT string_agg(qualite, ',' ORDER BY qualite) FROM public.personnes_debloquables('90000000-0000-0000-0000-00000000000a')),
  'Élève,Enseignant,Parent,Personnel', 'direction : personnel, enseignant, élève et parent de son école');
SELECT is((SELECT count(*)::int FROM public.personnes_debloquables('90000000-0000-0000-0000-00000000000a')
            WHERE profile_id IN (:'dir_a', :'dir2_a')), 0, 'ni elle-même ni un autre membre de la direction');
SELECT is((SELECT a_un_code FROM public.personnes_debloquables('90000000-0000-0000-0000-00000000000a', 'awa')), true,
  'recherche par le nom ; « a un code » indiqué');
SELECT is((SELECT count(*)::int FROM public.personnes_debloquables('90000000-0000-0000-0000-00000000000a', 'fatou')), 1,
  'recherche : le parent');
SELECT throws_ok($$ SELECT * FROM public.personnes_debloquables('90000000-0000-0000-0000-00000000000b') $$,
  '42501', 'PERMISSION_REFUSEE', 'direction : pas la liste d''une autre école');
SELECT pg_temp.sur(:'prof', :'sp');
SELECT throws_ok($$ SELECT * FROM public.personnes_debloquables('90000000-0000-0000-0000-00000000000a') $$,
  '42501', 'PERMISSION_REFUSEE', 'un enseignant : pas de liste');

-- ---------------------------------------------------------------------------
-- 3. Administrateur GSG : retrouver un compte
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'dir_a', :'sd');
SELECT throws_ok($$ SELECT * FROM public.chercher_compte_gsg('dir2.a@exemple.org') $$, '42501', 'PERMISSION_REFUSEE',
  'direction : ne cherche pas dans toute la plateforme');
SELECT pg_temp.sur(:'gsg', :'sg');
SELECT is((SELECT profile_id FROM public.chercher_compte_gsg('DIR2.A@exemple.org')), :'dir2_a'::uuid, 'adresse exacte, sans casse');
SELECT ok((SELECT roles FROM public.chercher_compte_gsg('dir2.a@exemple.org')) LIKE '%École A (direction)%', 'école et rôle affichés');
SELECT is((SELECT count(*)::int FROM public.chercher_compte_gsg('dir2')), 0, 'pas de recherche approchée (adresse ou identifiant exacts)');
SELECT is((SELECT count(*)::int FROM public.chercher_compte_gsg('exemple.org')), 0, 'pas de liste par domaine');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
