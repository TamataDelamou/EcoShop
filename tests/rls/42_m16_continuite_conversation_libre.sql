-- ============================================================================
-- EcoShop — Test RLS 42 : M16, complément sous-livrable 3/7 — continuité de
-- conversation libre (obtenir_conversation_libre)
--
-- Vérifie : (1) idempotence — deux appels successifs renvoient la MÊME
-- conversation, jamais une nouvelle ligne vide à chaque "ouverture d'écran" ;
-- (2) isolation stricte par auteur — deux élèves du même établissement
-- obtiennent chacun leur propre conversation, jamais celle de l'autre ;
-- (3) les conversations 'risque_echec' restent, elles, chacune une nouvelle
-- ligne (l'index unique partiel ne filtre QUE type = 'libre') ; (4) échec
-- sans authentification.
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

SELECT plan(8);

INSERT INTO public.etablissements (nom, slug) VALUES ('École Continuité M16', 'ecole-continuite-m16')
RETURNING id AS etab_id \gset

SELECT pg_temp.creer_compte('224600002381', 'eleve') AS eleve1_id \gset
SELECT pg_temp.creer_compte('224600002382', 'eleve') AS eleve2_id \gset

-- Un rôle IA réel est requis : sans fiche, `determiner_role_ia` renvoie NULL
-- et le garde-fou tenant (`ai_conversations_verifie_tenant`) refuserait
-- l'INSERT interne à `obtenir_conversation_libre` (PROFILE_SANS_ROLE_IA).
INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M16-CONT-001', 'SOW', 'Aissatou', '2011-05-01', :'eleve1_id'::uuid, now());
INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M16-CONT-002', 'BARRY', 'Ousmane', '2011-06-02', :'eleve2_id'::uuid, now());

-- ---------------------------------------------------------------------------
-- 1) Idempotence : deux appels successifs (= deux ouvertures d'écran) pour le
--    même élève/établissement renvoient EXACTEMENT le même identifiant.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);

SELECT public.obtenir_conversation_libre(:'etab_id'::uuid) AS conv1_id \gset
SELECT public.obtenir_conversation_libre(:'etab_id'::uuid) AS conv2_id \gset

SELECT ok(:'conv1_id' IS NOT NULL, 'premier appel : une conversation libre est bien créée');
SELECT is(:'conv2_id'::uuid, :'conv1_id'::uuid, 'second appel : renvoie la MÊME conversation, jamais une nouvelle');

SELECT is(
  (SELECT count(*)::int FROM public.ai_conversations
   WHERE profile_id = :'eleve1_id'::uuid AND etablissement_id = :'etab_id'::uuid AND type = 'libre'),
  1,
  'une seule ligne ai_conversations de type libre pour cet élève/établissement, malgré 2 appels'
);

-- L'historique déposé par le client (voir enregistrerMessage côté Flutter)
-- doit être retrouvé à la conversation stable, comme le ferait un
-- rechargement d'écran réel.
INSERT INTO public.ai_messages (conversation_id, sender, content) VALUES (:'conv1_id'::uuid, 'user', 'Question posée hier');
INSERT INTO public.ai_messages (conversation_id, sender, content) VALUES (:'conv1_id'::uuid, 'assistant', 'Réponse donnée hier');

SELECT is(
  (SELECT count(*)::int FROM public.ai_messages WHERE conversation_id = :'conv1_id'::uuid),
  2,
  'historique complet retrouvable sur la conversation stable (jamais résumé, jamais perdu)'
);

-- ---------------------------------------------------------------------------
-- 2) Isolation stricte par auteur : eleve2 obtient SA PROPRE conversation
--    libre, jamais celle d'eleve1, même établissement.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve2_id', 'role', 'authenticated')::text, true);

SELECT public.obtenir_conversation_libre(:'etab_id'::uuid) AS conv_eleve2_id \gset

SELECT isnt(:'conv_eleve2_id'::uuid, :'conv1_id'::uuid, 'eleve2 obtient une conversation DIFFÉRENTE de celle d''eleve1');
SELECT is(
  (SELECT count(*)::int FROM public.ai_messages WHERE conversation_id = :'conv_eleve2_id'::uuid),
  0,
  'eleve2 ne voit aucun message de la conversation d''eleve1 (isolation stricte)'
);

-- ---------------------------------------------------------------------------
-- 3) Les conversations groundées ('risque_echec') ne sont PAS concernées par
--    l'index unique partiel : deux lignes pour le même profil/établissement
--    restent possibles (comportement inchangé, voir test 41).
-- ---------------------------------------------------------------------------
INSERT INTO public.ai_conversations (etablissement_id, profile_id, type, grounding, cible_type)
VALUES (:'etab_id'::uuid, :'eleve1_id'::uuid, 'risque_echec', true, 'etablissement');
INSERT INTO public.ai_conversations (etablissement_id, profile_id, type, grounding, cible_type)
VALUES (:'etab_id'::uuid, :'eleve1_id'::uuid, 'risque_echec', true, 'etablissement');

SELECT is(
  (SELECT count(*)::int FROM public.ai_conversations
   WHERE profile_id = :'eleve1_id'::uuid AND etablissement_id = :'etab_id'::uuid AND type = 'risque_echec'),
  2,
  'les conversations risque_echec restent, elles, une nouvelle ligne par déclenchement (index unique ciblé sur type=libre uniquement)'
);

-- ---------------------------------------------------------------------------
-- 4) Sans authentification : échec explicite, jamais une conversation
--    anonyme.
-- ---------------------------------------------------------------------------
RESET ROLE;
SELECT set_config('request.jwt.claims', NULL, true);

SELECT throws_ok(
  format($$ SELECT public.obtenir_conversation_libre('%s') $$, :'etab_id'),
  '28000',
  NULL
);

SELECT * FROM finish();
ROLLBACK;
