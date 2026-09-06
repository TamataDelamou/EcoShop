-- ============================================================================
-- EcoShop — Test 21 : fonctions IA communication (M9)
--
-- Vérifie :
--   • prescriptif : choisir_canal (canal préféré du destinataire) ;
--   • prédictif : suggere_heure_envoi (créneau préféré) ;
--   • prescriptif : analyser_feedback (sentiment positif/négatif) ;
--   • A/B : selectionner_variante (affectation déterministe A/B) ;
--   • descriptif : analyser_envois (taux de lecture par canal).
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

SELECT plan(6);

-- ---------------------------------------------------------------------------
-- Tenant + comptes + préférences + notifications
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('50000000-0000-0000-0000-000000000001', 'École IA Comm M9', 'ecole-ia-comm-m9');

SELECT pg_temp.creer_compte('224600001321', 'direction') AS dir_id \gset
SELECT pg_temp.creer_compte('224600001322', 'parent')    AS parent_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_id'::uuid, '50000000-0000-0000-0000-000000000001', 'direction');

INSERT INTO public.preferences_canaux (profile_id, canal, actif, horaire_debut, horaire_fin, frequence)
VALUES (:'parent_id'::uuid, 'whatsapp', true, '10:30', '18:00', 'immediat');

INSERT INTO public.notifications (etablissement_id, destinataire, type, canal, contenu, statut, date_lecture)
VALUES
  ('50000000-0000-0000-0000-000000000001', :'parent_id'::uuid, 'note', 'sms',      'Note lue',      'envoyee', now()),
  ('50000000-0000-0000-0000-000000000001', :'parent_id'::uuid, 'note', 'sms',      'Note non lue',  'envoyee', null),
  ('50000000-0000-0000-0000-000000000001', :'parent_id'::uuid, 'note', 'whatsapp', 'Note WhatsApp', 'lue',     now());

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

-- 1. Canal préféré : WhatsApp (seule préférence active du parent).
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'parent_id', 'role', 'authenticated')::text, true);
SELECT is(
  public.choisir_canal(:'parent_id'::uuid, 'note'),
  'whatsapp',
  'IA prescriptive : canal préféré du destinataire'
);

-- 2. Moment opportun : créneau de préférence 10:30.
SELECT is(
  public.suggere_heure_envoi(:'parent_id'::uuid),
  time '10:30',
  'IA prédictive : créneau d''envoi préféré'
);

-- 3. Analyse sémantique : sentiment positif.
SELECT is(public.analyser_feedback('Merci beaucoup, bien reçu'), 'positif',
          'IA sémantique : retour positif détecté');

-- 4. Analyse sémantique : sentiment négatif.
SELECT is(public.analyser_feedback('Il y a une erreur dans la note'), 'negatif',
          'IA sémantique : retour négatif détecté');

-- 5. A/B : affectation déterministe dans {A, B}.
SELECT ok(
  (SELECT public.selectionner_variante(:'parent_id'::uuid, 'note')) IN ('A', 'B'),
  'A/B : variante déterministe A ou B'
);

-- 6. Descriptif : taux de lecture SMS = 1/2 = 0.50.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT taux_lecture FROM public.analyser_envois('50000000-0000-0000-0000-000000000001', '2020-01-01', '2030-01-01') WHERE canal = 'sms'),
  0.50::numeric,
  'IA descriptive : taux de lecture SMS correct'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
