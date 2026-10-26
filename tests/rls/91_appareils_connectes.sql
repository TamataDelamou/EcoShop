-- ============================================================================
-- EcoShop — Test RLS 91 : appareils connectés (REG-22 partie B, migration 1565)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.sur(p_uid uuid, p_session uuid, p_chemin text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'session_id', p_session)::text, true),
         set_config('request.path', coalesce(p_chemin, ''), true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text) RETURNS uuid
LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  UPDATE public.profiles SET prenom = 'Awa', nom = 'Test' WHERE id = v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.connexion(p_uid uuid, p_il_y_a interval DEFAULT '0') RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.sessions (id, user_id, created_at, updated_at, refreshed_at)
  VALUES (v_id, p_uid, now() - p_il_y_a, now() - p_il_y_a, (now() - p_il_y_a / 2) AT TIME ZONE 'UTC');
  RETURN v_id;
END $$;

SELECT plan(22);

SELECT pg_temp.compte('awa@exemple.org') AS awa \gset
SELECT pg_temp.compte('autre@exemple.org') AS autre \gset
SELECT pg_temp.connexion(:'awa') AS s1 \gset
SELECT pg_temp.connexion(:'awa', '3 days') AS s3 \gset
SELECT pg_temp.connexion(:'awa', '1 day') AS s4 \gset
SELECT pg_temp.connexion(:'autre') AS sa \gset

SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'awa', :'s1');
SELECT public.enregistrer_appareil('Samsung Galaxy A14', 'Android 14', '1.4.0');
SELECT public.definir_code_compte('739146');
RESET ROLE;
-- Nouvel appareil, connecté après la définition du code : à vérifier.
SELECT pg_temp.connexion(:'awa', '10 days') AS s2 \gset
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'awa', :'s2');
SELECT public.enregistrer_appareil('Tecno Spark 10', 'Android 13', '1.4.0');

-- ---------------------------------------------------------------------------
-- 1. Liste
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'awa', :'s1');
SELECT is((SELECT count(*)::int FROM public.mes_appareils()), 4, 'mes appareils : les 4 connexions ouvertes, pas celles d''un autre compte');
SELECT is((SELECT modele FROM public.mes_appareils() WHERE cet_appareil), 'Samsung Galaxy A14', '« Cet appareil » en premier, avec son modèle');
SELECT ok((SELECT cet_appareil FROM public.mes_appareils() LIMIT 1), 'cet appareil en tête de liste');
SELECT is((SELECT modele FROM public.mes_appareils() WHERE session_id = :'s3'), 'Appareil inconnu', 'connexion d''une ancienne version : « Appareil inconnu »');
SELECT ok((SELECT derniere_utilisation > connecte_le FROM public.mes_appareils() WHERE session_id = :'s2'),
  'dernière utilisation : le dernier renouvellement du jeton');
SELECT is((SELECT statut FROM public.mes_appareils() WHERE session_id = :'s2'), 'a_verifier', 'statut affiché (appareil à vérifier)');
SELECT pg_temp.sur(:'autre', :'sa');
SELECT is((SELECT count(*)::int FROM public.mes_appareils()), 1, 'un autre compte ne voit que sa connexion');

-- ---------------------------------------------------------------------------
-- 2. Déconnecter un appareil
-- ---------------------------------------------------------------------------
SELECT throws_ok(format($$ SELECT public.deconnecter_appareil(%L) $$, :'s2'), 'P0002', 'APPAREIL_INCONNU',
  'pas la connexion d''un autre compte');
SELECT pg_temp.sur(:'awa', :'s2');
SELECT throws_ok(format($$ SELECT public.deconnecter_appareil(%L) $$, :'s3'), '42501', 'APPAREIL_A_VERIFIER',
  'un appareil à vérifier ne déconnecte pas les autres');
SELECT throws_ok($$ SELECT public.deconnecter_autres_appareils() $$, '42501', 'APPAREIL_A_VERIFIER',
  'un appareil à vérifier ne déconnecte pas tous les autres');
SELECT pg_temp.sur(:'awa', :'s1');
SELECT throws_ok(format($$ SELECT public.deconnecter_appareil(%L) $$, :'s1'), '22023', 'CET_APPAREIL',
  'cet appareil : « Se déconnecter », pas cette fonction');
SELECT lives_ok(format($$ SELECT public.deconnecter_appareil(%L) $$, :'s2'), 'appareil connu : déconnecte le Tecno Spark 10');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM auth.sessions WHERE id = :'s2'), 0, 'session supprimée (jetons de renouvellement compris)');
SELECT is((SELECT count(*)::int FROM public.sessions_appareils WHERE session_id = :'s2'), 0, 'sa description part avec elle');
UPDATE public.parametres_globaux SET valeur = 'true'::jsonb WHERE cle = 'code_compte_obligatoire';
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'awa', :'s2', '/notes');
SELECT throws_ok($$ SELECT public.controle_requete() $$, '42501', 'SESSION_REVOQUEE',
  'l''appareil déconnecté est refusé dès sa requête suivante, jeton encore valable');
SELECT pg_temp.sur(:'awa', :'s1');
SELECT is((SELECT count(*)::int FROM public.journal_audit WHERE entite = 'code_compte' AND champ = 'deconnexion_appareil'), 1,
  'journal : déconnexion inscrite, lisible par le titulaire');
SELECT pg_temp.sur(:'autre', :'sa');
SELECT is((SELECT count(*)::int FROM public.journal_audit WHERE entite = 'code_compte'), 0, 'journal : invisible pour un autre compte');
RESET ROLE;
SELECT is((SELECT donnees ->> 'modeles' FROM public.notifications_sortantes WHERE modele = 'appareils_deconnectes'
             AND destinataire = 'awa@exemple.org'), 'Tecno Spark 10', 'courriel « appareil déconnecté »');

-- ---------------------------------------------------------------------------
-- 3. Déconnecter tous les autres
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'awa', :'s1');
SELECT is(public.deconnecter_autres_appareils(), 2, 'tous les autres : 2 connexions fermées');
SELECT is((SELECT count(*)::int FROM public.mes_appareils()), 1, 'il ne reste que cet appareil');
SELECT is(public.deconnecter_autres_appareils(), 0, 'plus rien à fermer');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM auth.sessions WHERE user_id = :'autre'), 1, 'la connexion d''un autre compte n''est pas touchée');

SELECT * FROM finish();
ROLLBACK;
