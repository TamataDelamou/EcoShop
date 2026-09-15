-- ============================================================================
-- EcoShop — Test RLS 52 : Facturation/Quota IA — étape (d), quota Tuteur IA
-- (migration 20260906001520).
--
-- Point central de ce fichier, PAS un cas parmi d'autres : chaque insertion
-- ci-dessous est un INSERT SQL brut dans ai_messages (exactement ce qu'un
-- client ferait via PostgREST), JAMAIS un appel préalable à
-- verifier_quota_ia, JAMAIS un passage par envoyer_message_ia. Si le
-- trigger ne bloquait pas, ces tests le montreraient directement -- c'est
-- la raison d'être de cette étape (voir découverte structurante en tête de
-- la migration 20260906001520).
--
-- Couvre aussi :
--   • frontière exacte "compte >= limite" (pas "compte >") : sur le quota
--     placeholder de 20, le 19e et le 20e message réussissent, le 21e est
--     refusé.
--   • même frontière pour l'anti-rafale (fenêtre glissante).
--   • abonnement Premium actif -> quota périodique LEVÉ entièrement (pas un
--     second plafond plus haut) -- 25 messages, aucun refus.
--   • portée du plafond périodique strictement limitée à élève+conversation
--     libre : scan_exercice et le chat libre d'un rôle non-élève (ici
--     direction) échappent au plafond périodique (seul l'anti-rafale
--     s'applique, générant volontairement large pour ce test).
--   • un message 'assistant' ne consomme jamais de quota.
--   • verifier_quota_ia appelée directement (simule le pré-contrôle Edge
--     Function) : succès élève Premium, refus élève FREE à quota épuisé.
--   • detecter_anomalies_usage_ia : garde personnel/admin_gsg, isolation
--     inter-établissement, signalement au-delà du seuil seulement.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.creer_compte(p_phone text, p_role text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public, auth, pg_catalog
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, phone) VALUES (v_id, p_phone);
  IF p_role IS NOT NULL THEN
    UPDATE public.profiles SET role_racine = p_role::public.role_racine WHERE id = v_id;
  END IF;
  RETURN v_id;
END;
$$;

SELECT plan(20);

-- ---------------------------------------------------------------------------
-- Fixture : un établissement A (cible) + un établissement B (isolation),
-- quatre profils élèves distincts (un par scénario, pour ne jamais mélanger
-- les compteurs), une direction par établissement, un admin GSG, un tiers.
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('52000000-0000-0000-0000-000000000001', 'École QA Quota IA', 'ecole-qa52');
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('52000000-0000-0000-0000-000000000099', 'École QA Quota IA B (isolation)', 'ecole-qa52-b');

SELECT pg_temp.creer_compte('224600008001', 'eleve')      AS eleve_quota_id    \gset
SELECT pg_temp.creer_compte('224600008002', 'eleve')      AS eleve_rafale_id   \gset
SELECT pg_temp.creer_compte('224600008003', 'eleve')      AS eleve_premium_id  \gset
SELECT pg_temp.creer_compte('224600008004', 'eleve')      AS eleve_scan_id     \gset
SELECT pg_temp.creer_compte('224600008005', 'eleve')      AS eleve_tiers_id    \gset
SELECT pg_temp.creer_compte('224600008006', 'direction')  AS direction_a_id    \gset
SELECT pg_temp.creer_compte('224600008007', 'direction')  AS direction_b_id    \gset
SELECT pg_temp.creer_compte('224600008008', 'admin_gsg')  AS admin_gsg_id      \gset

INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES ('52000000-0000-0000-0000-000000000011', '52000000-0000-0000-0000-000000000001', 'QA52-001', 'Quota', 'Eleve', '2011-01-01', :'eleve_quota_id'::uuid, now());
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES ('52000000-0000-0000-0000-000000000012', '52000000-0000-0000-0000-000000000001', 'QA52-002', 'Rafale', 'Eleve', '2012-01-01', :'eleve_rafale_id'::uuid, now());
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES ('52000000-0000-0000-0000-000000000013', '52000000-0000-0000-0000-000000000001', 'QA52-003', 'Premium', 'Eleve', '2013-01-01', :'eleve_premium_id'::uuid, now());
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES ('52000000-0000-0000-0000-000000000014', '52000000-0000-0000-0000-000000000001', 'QA52-004', 'Scan', 'Eleve', '2014-01-01', :'eleve_scan_id'::uuid, now());

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'direction_a_id'::uuid, '52000000-0000-0000-0000-000000000001', 'direction');
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'direction_b_id'::uuid, '52000000-0000-0000-0000-000000000099', 'direction');

-- ===========================================================================
-- 1. Anti-rafale (universel, fenêtre réduite pour ce scénario) — frontière
-- + contournement direct.
-- ===========================================================================
UPDATE public.parametres_globaux SET valeur = '{"max_messages": 3, "fenetre_minutes": 5}'::jsonb WHERE cle = 'anti_rafale_ia';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_rafale_id', 'role', 'authenticated')::text, true);
SELECT public.obtenir_conversation_libre('52000000-0000-0000-0000-000000000001') AS conv_rafale_id \gset

SELECT lives_ok(
  format($$ insert into public.ai_messages (conversation_id, sender, content) values ('%s', 'user', 'msg rafale 1') $$, :'conv_rafale_id'),
  'ai_messages (INSERT direct, contournement de envoyer_message_ia) : message 1/3 anti-rafale accepté'
);
SELECT lives_ok(
  format($$ insert into public.ai_messages (conversation_id, sender, content) values ('%s', 'user', 'msg rafale 2') $$, :'conv_rafale_id'),
  'ai_messages (INSERT direct) : message 2/3 anti-rafale accepté'
);
SELECT lives_ok(
  format($$ insert into public.ai_messages (conversation_id, sender, content) values ('%s', 'user', 'msg rafale 3') $$, :'conv_rafale_id'),
  'ai_messages (INSERT direct) : message 3/3 anti-rafale accepté -- frontière (compte existant 2 >= 3 faux)'
);
SELECT throws_ok(
  format($$ insert into public.ai_messages (conversation_id, sender, content) values ('%s', 'user', 'msg rafale 4 refuse') $$, :'conv_rafale_id'),
  '54000', NULL,
  'ai_messages (INSERT direct, CONTOURNEMENT BLOQUÉ) : message 4/3 anti-rafale refusé -- compte existant 3 >= 3'
);

-- Un message 'assistant' ne consomme jamais de quota (même profil déjà à sa limite anti-rafale).
SELECT lives_ok(
  format($$ insert into public.ai_messages (conversation_id, sender, content) values ('%s', 'assistant', 'reponse assistant') $$, :'conv_rafale_id'),
  'ai_messages (INSERT direct) : message assistant jamais soumis au quota, même profil déjà à sa limite anti-rafale'
);

-- ===========================================================================
-- 2. Quota périodique Tuteur IA (élève, conversation libre) — frontière
-- exacte 19e/20e accepté, 21e refusé, sur le placeholder réel (20).
-- Anti-rafale élargie pour ne pas interférer avec ce scénario.
-- ===========================================================================
RESET ROLE;
UPDATE public.parametres_globaux SET valeur = '{"max_messages": 1000, "fenetre_minutes": 60}'::jsonb WHERE cle = 'anti_rafale_ia';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_quota_id', 'role', 'authenticated')::text, true);
SELECT public.obtenir_conversation_libre('52000000-0000-0000-0000-000000000001') AS conv_quota_id \gset

-- 18 premiers messages -- chacun un INSERT direct séparé (\gexec génère une
-- instruction par ligne, jamais un seul INSERT multi-lignes, pour éviter
-- toute ambiguïté sur la visibilité des lignes précédentes dans le compte).
SELECT format(
  $$ insert into public.ai_messages (conversation_id, sender, content) values ('%s', 'user', 'msg quota %s') $$,
  :'conv_quota_id', g
) FROM generate_series(1, 18) AS g;
\gexec

SELECT is(
  (SELECT count(*) FROM public.ai_messages WHERE conversation_id = :'conv_quota_id'::uuid AND sender = 'user'),
  18::bigint,
  'précondition : 18 messages Tuteur IA déjà acceptés pour cet élève FREE ce mois-ci'
);

SELECT lives_ok(
  format($$ insert into public.ai_messages (conversation_id, sender, content) values ('%s', 'user', 'msg quota 19') $$, :'conv_quota_id'),
  'ai_messages (INSERT direct) : 19e message Tuteur IA accepté -- compte existant 18 < 20'
);
SELECT lives_ok(
  format($$ insert into public.ai_messages (conversation_id, sender, content) values ('%s', 'user', 'msg quota 20') $$, :'conv_quota_id'),
  'ai_messages (INSERT direct) : 20e message Tuteur IA accepté -- frontière, compte existant 19 < 20'
);
SELECT throws_ok(
  format($$ insert into public.ai_messages (conversation_id, sender, content) values ('%s', 'user', 'msg quota 21 refuse') $$, :'conv_quota_id'),
  '22023', NULL,
  'ai_messages (INSERT direct, CONTOURNEMENT BLOQUÉ) : 21e message Tuteur IA refusé -- QUOTA_TUTEUR_IA_ATTEINT, compte existant 20 >= 20'
);

-- Rejet d'une conversation étrangère : le trigger ne doit ni masquer ni
-- remplacer le refus RLS normal par une erreur de quota.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_tiers_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ insert into public.ai_messages (conversation_id, sender, content) values ('%s', 'user', 'intrusion') $$, :'conv_quota_id'),
  '42501', NULL,
  'ai_messages : insertion dans la conversation D''UN AUTRE élève refusée par la RLS (pas par le trigger de quota)'
);

-- ===========================================================================
-- 3. Abonnement Premium actif -> quota périodique LEVÉ entièrement.
-- ===========================================================================
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT public.enregistrer_paiement_abonnement_premium_eleve('52000000-0000-0000-0000-000000000013', 'mensuel', 5);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_premium_id', 'role', 'authenticated')::text, true);
SELECT public.obtenir_conversation_libre('52000000-0000-0000-0000-000000000001') AS conv_premium_id \gset

SELECT format(
  $$ insert into public.ai_messages (conversation_id, sender, content) values ('%s', 'user', 'msg premium %s') $$,
  :'conv_premium_id', g
) FROM generate_series(1, 25) AS g;
\gexec

SELECT is(
  (SELECT count(*) FROM public.ai_messages WHERE conversation_id = :'conv_premium_id'::uuid AND sender = 'user'),
  25::bigint,
  'CORRECTION : élève Premium envoie 25 messages Tuteur IA (> plafond FREE de 20) sans jamais être refusé -- quota LEVÉ, pas relevé'
);

-- verifier_quota_ia appelée DIRECTEMENT (simule le pré-contrôle Edge
-- Function) : élève Premium toujours autorisé, élève FREE à quota épuisé
-- refusé -- prouve que le pré-contrôle intercepterait AVANT tout appel
-- Anthropic, avec la même fonction que le trigger.
SELECT lives_ok(
  $$ SELECT public.verifier_quota_ia('52000000-0000-0000-0000-000000000001', 'libre') $$,
  'verifier_quota_ia (appel direct, pré-contrôle Edge Function) : élève Premium toujours autorisé'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_quota_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.verifier_quota_ia('52000000-0000-0000-0000-000000000001', 'libre') $$,
  '22023', NULL,
  'verifier_quota_ia (appel direct, pré-contrôle Edge Function) : élève FREE à quota épuisé refusé AVANT tout appel Anthropic'
);

-- ===========================================================================
-- 4. Portée du plafond périodique — scan_exercice et chat libre d'un rôle
-- non-élève y échappent (seul l'anti-rafale, déjà élargie, s'applique).
-- ===========================================================================
RESET ROLE;
INSERT INTO public.ai_conversations (id, etablissement_id, profile_id, type, grounding)
VALUES ('52000000-0000-0000-0000-000000000021', '52000000-0000-0000-0000-000000000001', :'eleve_scan_id'::uuid, 'scan_exercice', false);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_scan_id', 'role', 'authenticated')::text, true);
SELECT format(
  $$ insert into public.ai_messages (conversation_id, sender, content) values ('52000000-0000-0000-0000-000000000021', 'user', 'msg scan %s') $$,
  g
) FROM generate_series(1, 25) AS g;
\gexec

SELECT is(
  (SELECT count(*) FROM public.ai_messages WHERE conversation_id = '52000000-0000-0000-0000-000000000021'::uuid AND sender = 'user'),
  25::bigint,
  'scan_exercice (élève FREE) : 25 messages envoyés sans plafond périodique -- portée exclue par construction (M16 5/7)'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT public.obtenir_conversation_libre('52000000-0000-0000-0000-000000000001') AS conv_direction_id \gset

SELECT format(
  $$ insert into public.ai_messages (conversation_id, sender, content) values ('%s', 'user', 'msg direction %s') $$,
  :'conv_direction_id', g
) FROM generate_series(1, 25) AS g;
\gexec

SELECT is(
  (SELECT count(*) FROM public.ai_messages WHERE conversation_id = :'conv_direction_id'::uuid AND sender = 'user'),
  25::bigint,
  'Chat libre direction : 25 messages sans plafond périodique -- seul le rôle élève y est soumis'
);

-- ===========================================================================
-- 5. detecter_anomalies_usage_ia — garde personnel/admin_gsg, isolation,
-- signalement au-delà du seuil seulement (jamais de détection de partage
-- de compte -- volume total uniquement).
-- ===========================================================================
RESET ROLE;
UPDATE public.parametres_globaux SET valeur = '{"valeur": 10}'::jsonb WHERE cle = 'seuil_anomalie_usage_ia_quotidien';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.detecter_anomalies_usage_ia('52000000-0000-0000-0000-000000000001')),
  4::bigint,
  'detecter_anomalies_usage_ia : 4 profils au-dessus du seuil de 10 (20/25/25/25 messages)'
);
SELECT is(
  (SELECT count(*) FROM public.detecter_anomalies_usage_ia('52000000-0000-0000-0000-000000000001') WHERE profile_id = :'eleve_rafale_id'::uuid),
  0::bigint,
  'detecter_anomalies_usage_ia : élève limité par l''anti-rafale (3 messages, sous le seuil) absent du signalement'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.detecter_anomalies_usage_ia('52000000-0000-0000-0000-000000000001')),
  4::bigint,
  'detecter_anomalies_usage_ia : admin GSG autorisé, même résultat'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_tiers_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT * FROM public.detecter_anomalies_usage_ia('52000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'detecter_anomalies_usage_ia : tiers sans lien avec l''établissement refusé'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_b_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT * FROM public.detecter_anomalies_usage_ia('52000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'detecter_anomalies_usage_ia : direction d''un AUTRE établissement refusée'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
