-- ============================================================================
-- EcoShop — Test RLS 82 : inscription en étapes (REG-18 B, migration 20260906001555)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

-- Compte tel que Supabase le crée à la demande d'un code (adresse pas
-- encore confirmée), éventuellement daté dans le passé.
CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_confirme boolean DEFAULT true,
                                          p_age interval DEFAULT '0'::interval, p_meta jsonb DEFAULT '{}')
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at, created_at, raw_user_meta_data)
  VALUES (v_id, p_email, CASE WHEN p_confirme THEN now() END, now() - p_age, p_meta);
  RETURN v_id;
END $$;

SELECT plan(23);

-- ---------------------------------------------------------------------------
-- 1. Compte nouveau : espace et nom appliqués après la vérification
-- ---------------------------------------------------------------------------
SELECT pg_temp.compte('nouveau@exemple.org') AS nouveau \gset

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'nouveau');
SELECT is(public.finaliser_inscription('parent', '  Awa ', 'Bah  '), 'appliquee', 'compte nouveau : inscription appliquée');
SELECT is((SELECT role_racine::text || '|' || prenom || '|' || nom FROM public.profiles WHERE id = :'nouveau'),
  'parent|Awa|Bah', 'espace et nom enregistrés (espaces retirés)');
SELECT ok((SELECT inscription_finalisee_le IS NOT NULL FROM public.profiles WHERE id = :'nouveau'), 'inscription marquée finalisée');
SELECT is(public.finaliser_inscription('eleve', 'Autre', 'Nom'), 'compte_existant', 'seconde finalisation : refusée sans erreur');
SELECT is((SELECT role_racine::text || '|' || prenom || '|' || nom FROM public.profiles WHERE id = :'nouveau'),
  'parent|Awa|Bah', 'seconde finalisation : rien n''a changé');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 2. Demande de code pour l'adresse d'un compte existant, avec un autre nom
--    et un autre espace : rien ne change
-- ---------------------------------------------------------------------------
SELECT pg_temp.compte('existant@exemple.org') AS existant \gset
UPDATE public.profiles SET role_racine = 'parent', prenom = 'Mariama', nom = 'Sow', inscription_finalisee_le = now()
 WHERE id = :'existant';
SELECT identifiant_ecoshop AS id_existant FROM public.profiles WHERE id = :'existant' \gset

-- Ce que ferait Supabase si la demande de code transportait des données :
-- les métadonnées du compte existant sont réécrites.
UPDATE auth.users
   SET raw_user_meta_data = '{"given_name":"Intrus","family_name":"Autre","espace":"eleve"}'
 WHERE id = :'existant';
SELECT is((SELECT role_racine::text || '|' || prenom || '|' || nom FROM public.profiles WHERE id = :'existant'),
  'parent|Mariama|Sow', 'métadonnées réécrites par une demande de code : profil inchangé');

-- Puis, une fois le code vérifié, l'application tente la finalisation avec
-- l'autre nom et l'autre espace saisis.
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'existant');
SELECT is(public.finaliser_inscription('eleve', 'Intrus', 'Autre'), 'compte_existant', 'compte existant : finalisation refusée');
SELECT is((SELECT role_racine::text || '|' || prenom || '|' || nom FROM public.profiles WHERE id = :'existant'),
  'parent|Mariama|Sow', 'compte existant : ni l''espace ni le nom n''ont changé');
SELECT is((SELECT identifiant_ecoshop FROM public.profiles WHERE id = :'existant'), :'id_existant',
  'compte existant : identifiant EcoShop inchangé');
RESET ROLE;

-- Compte créé avant REG-18 avec un rôle mais sans date de finalisation.
SELECT pg_temp.compte('ancien@exemple.org') AS ancien \gset
UPDATE public.profiles SET role_racine = 'eleve', prenom = 'Ibrahima', nom = 'Camara', inscription_finalisee_le = NULL
 WHERE id = :'ancien';
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'ancien');
SELECT is(public.finaliser_inscription('parent', 'Autre', 'Nom'), 'compte_existant', 'rôle déjà fixé : compte existant');
SELECT is((SELECT role_racine::text || '|' || prenom FROM public.profiles WHERE id = :'ancien'), 'eleve|Ibrahima',
  'rôle déjà fixé : inchangé');

-- ---------------------------------------------------------------------------
-- 3. Garde-fous
-- ---------------------------------------------------------------------------
RESET ROLE;
SELECT pg_temp.compte('autre@exemple.org') AS autre \gset
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'autre');
SELECT throws_ok($$ SELECT public.finaliser_inscription('direction', 'A', 'B') $$, '42501', 'ROLE_NON_AUTO_INSCRIPTIBLE',
  'espace direction : jamais par inscription');
SELECT throws_ok($$ SELECT public.finaliser_inscription('parent', 'a@b.c', 'B') $$, '22023', 'NOM_INVALIDE',
  'une adresse n''est pas un prénom');
SELECT throws_ok($$ SELECT public.finaliser_inscription('parent', '', 'B') $$, '22023', 'NOM_INVALIDE', 'prénom vide refusé');
UPDATE public.profiles SET inscription_finalisee_le = now(), role_racine = 'admin_gsg' WHERE id = :'autre';
SELECT ok((SELECT inscription_finalisee_le IS NULL AND role_racine IS NULL FROM public.profiles WHERE id = :'autre'),
  'le client n''écrit ni la finalisation ni le rôle directement');
SELECT is(public.finaliser_inscription('eleve', 'Fanta', 'Diallo'), 'appliquee', 'après la tentative directe : finalisation normale');
SELECT lives_ok($$ SELECT public.definir_mon_nom('Fanta Kadiatou', 'Diallo') $$, 'nom modifiable par le compte lui-même');
SELECT is((SELECT role_racine::text FROM public.profiles WHERE id = :'autre'), 'eleve', 'changer de nom ne touche pas au rôle');
SELECT throws_ok($$ SELECT public.purger_comptes_non_verifies() $$, '42501', NULL, 'purge : jamais depuis le client');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 4. Comptes jamais vérifiés : supprimés au bout de 24 h
-- ---------------------------------------------------------------------------
SELECT pg_temp.compte('abandon@exemple.org', false, '25 hours') AS abandon \gset
SELECT pg_temp.compte('en.cours@exemple.org', false, '1 hour') AS en_cours \gset
SELECT pg_temp.compte('verifie@exemple.org', true, '30 days') AS verifie \gset
SELECT pg_temp.compte('invite@exemple.org', false, '30 days') AS invite \gset
UPDATE auth.users SET invited_at = now() - interval '30 days' WHERE id = :'invite';
SELECT pg_temp.compte('personnel@exemple.org', false, '30 days') AS personnel \gset
UPDATE public.profiles SET role_racine = 'enseignant' WHERE id = :'personnel';
SELECT identifiant_ecoshop AS id_abandon FROM public.profiles WHERE id = :'abandon' \gset

SET LOCAL ROLE service_role;
SELECT ok(public.purger_comptes_non_verifies() >= 1, 'purge exécutée par la tâche planifiée (rôle service)');
RESET ROLE;
SELECT ok(NOT EXISTS (SELECT 1 FROM auth.users WHERE id = :'abandon')
          AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = :'abandon'),
  'abandonnée depuis plus de 24 h : compte et profil supprimés');
SELECT is((SELECT count(*)::int FROM auth.users WHERE id IN (:'en_cours', :'verifie', :'invite', :'personnel')), 4,
  'gardés : inscription en cours (< 24 h), adresse vérifiée, invitation, rôle attribué');
SELECT ok(EXISTS (SELECT 1 FROM public.identifiants_ecoshop_attribues WHERE valeur = :'id_abandon'),
  'identifiant du compte supprimé jamais réattribué');

SELECT * FROM finish();
ROLLBACK;
