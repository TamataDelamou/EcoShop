-- ============================================================================
-- EcoShop — Test RLS 95 : suppression du compte par l'utilisateur (REG-31,
-- migration 1577)
--
-- Vérifie que :
--   • la demande, l'état et l'annulation marchent pour le titulaire seul ;
--   • une école ne reste jamais sans direction (refus, puis report) ;
--   • à l'échéance, le compte est anonymisé, ses accès effacés, ses liens
--     rompus, et les pièces de l'école gardées ;
--   • les fonctions internes ne sont pas appelables depuis l'application ;
--   • les conditions v1.0 sont les versions courantes.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  INSERT INTO auth.identities (user_id, provider, provider_id, identity_data)
  VALUES (v_id, 'email', v_id::text, jsonb_build_object('email', p_email));
  INSERT INTO auth.sessions (id, user_id) VALUES (gen_random_uuid(), v_id);
  UPDATE public.profiles SET role_racine = p_role::public.role_racine,
         prenom = initcap(split_part(p_email, '@', 1)), nom = 'Test' WHERE id = v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.sur(p_uid uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

SELECT plan(29);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('90000000-0000-0000-0000-00000000000a', 'École Suppression', 'ecole-suppression-90', 'GNF');

SELECT pg_temp.compte('direction1@exemple.gn', 'direction') AS d1 \gset
SELECT pg_temp.compte('direction2@exemple.gn', 'direction') AS d2 \gset
SELECT pg_temp.compte('parent@exemple.gn', 'parent') AS parent \gset
SELECT pg_temp.compte('voisin@exemple.gn', 'parent') AS voisin \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'d1', '90000000-0000-0000-0000-00000000000a', 'direction'),
  (:'parent', '90000000-0000-0000-0000-00000000000a', 'parent');

INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance)
VALUES ('90000000-0000-0000-0000-0000000000f1', '90000000-0000-0000-0000-00000000000a',
        'MAT-SUP-001', 'BAH', 'Mariama', '2014-03-02');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id)
VALUES ('90000000-0000-0000-0000-00000000000a', :'parent', '90000000-0000-0000-0000-0000000000f1');
INSERT INTO public.jetons_push (jeton, profile_id) VALUES ('jeton-parent-90', :'parent');

-- ---------------------------------------------------------------------------
-- 1. Demande, état, annulation (parent)
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'parent');
SET LOCAL ROLE authenticated;

SELECT is(public.etat_suppression_compte() ->> 'demandee', 'false', 'aucune demande au départ');
SELECT ok((public.demander_suppression_compte('Je change d''école') ->> 'effective_le')::timestamptz
          BETWEEN now() + interval '6 days 23 hours' AND now() + interval '7 days 1 hour',
          'demande : effet dans 7 jours');
SELECT is(public.etat_suppression_compte() ->> 'demandee', 'true', 'demande en cours visible');
SELECT is((SELECT count(*)::int FROM public.demandes_suppression_compte), 1, 'le titulaire lit sa demande');
SELECT ok(public.demander_suppression_compte() ? 'effective_le', 'deuxième demande : même échéance, pas de doublon');
SELECT is((SELECT count(*)::int FROM public.demandes_suppression_compte WHERE statut = 'en_attente'), 1,
          'une seule demande en attente');
SELECT is(public.annuler_suppression_compte(), true, 'annulation');
SELECT is(public.etat_suppression_compte() ->> 'demandee', 'false', 'plus de demande après annulation');
SELECT ok(public.demander_suppression_compte() ? 'effective_le', 'nouvelle demande après annulation');

-- Un autre compte ne voit pas la demande.
SELECT pg_temp.sur(:'voisin');
SELECT is((SELECT count(*)::int FROM public.demandes_suppression_compte), 0, 'demande invisible pour un autre compte');
SELECT is(public.annuler_suppression_compte(), false, 'un autre compte ne peut pas annuler');

-- ---------------------------------------------------------------------------
-- 2. Une école ne reste pas sans direction
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'d1');
SELECT is(public.demander_suppression_compte() ->> 'erreur', 'DIRECTION_SEULE', 'seule direction : refus');
SELECT is(public.demander_suppression_compte() -> 'ecoles' -> 0 ->> 'nom', 'École Suppression', 'l''école est nommée');

-- Fonctions internes : jamais depuis l'application.
SELECT throws_ok(format('SELECT public.anonymiser_compte(%L)', :'voisin'), '42501', NULL, 'anonymiser_compte refusé');
SELECT throws_ok('SELECT public.effectuer_suppressions_comptes()', '42501', NULL, 'tâche quotidienne refusée');
SELECT throws_ok(format('SELECT public.enregistrer_demande_suppression_web(%L)', :'voisin'), '42501', NULL,
                 'saisie d''une demande web réservée à GSG');
RESET ROLE;

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'d2', '90000000-0000-0000-0000-00000000000a', 'direction');
SELECT pg_temp.sur(:'d1');
SET LOCAL ROLE authenticated;
SELECT ok(public.demander_suppression_compte() ? 'effective_le', 'deuxième direction nommée : demande acceptée');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 3. Échéance : anonymisation du parent ; direction redevenue seule reportée
-- ---------------------------------------------------------------------------
UPDATE public.demandes_suppression_compte SET effective_le = now() - interval '1 minute';
UPDATE public.etablissements_membres SET actif = false WHERE profile_id = :'d2';

SELECT is(public.effectuer_suppressions_comptes(), 1, 'un compte supprimé (la direction est reportée)');

SELECT is((SELECT prenom || ' ' || nom FROM public.profiles WHERE id = :'parent'), 'Compte supprimé', 'nom effacé');
SELECT is((SELECT statut_compte::text FROM public.profiles WHERE id = :'parent'), 'supprime', 'statut supprimé');
SELECT ok((SELECT identifiant_canonique LIKE 'supprime:%' FROM public.profiles WHERE id = :'parent'),
          'adresse e-mail retirée du profil');
SELECT is((SELECT count(*)::int FROM public.identifiants_comptes WHERE profile_id = :'parent'), 0, 'identifiants effacés');
SELECT is((SELECT count(*)::int FROM public.jetons_push WHERE profile_id = :'parent'), 0, 'jetons de notification effacés');
SELECT ok((SELECT email IS NULL AND banned_until = 'infinity' FROM auth.users WHERE id = :'parent'),
          'connexion : e-mail effacé, compte bloqué');
SELECT is((SELECT count(*)::int FROM auth.identities WHERE user_id = :'parent')
        + (SELECT count(*)::int FROM auth.sessions WHERE user_id = :'parent'), 0, 'identités et sessions effacées');
SELECT ok((SELECT NOT autorise AND deleted_at IS NOT NULL FROM public.relations_parent_eleve WHERE parent_profile_id = :'parent'),
          'lien avec l''enfant rompu');
SELECT is((SELECT count(*)::int FROM public.fiches_eleves WHERE id = '90000000-0000-0000-0000-0000000000f1'), 1,
          'la fiche de l''élève reste à l''école');

SELECT is((SELECT statut FROM public.demandes_suppression_compte WHERE profile_id = :'d1'), 'en_attente',
          'direction redevenue seule : suppression reportée');

-- ---------------------------------------------------------------------------
-- 4. Conditions d'utilisation v1.0
-- ---------------------------------------------------------------------------
SELECT is((SELECT string_agg(parcours::text || '=' || numero_version, ',' ORDER BY parcours::text)
             FROM public.cgu_versions WHERE est_courante),
          'complet=1.0,simplifie=1.0', 'conditions v1.0 courantes pour les deux parcours');

SELECT * FROM finish();
ROLLBACK;
