-- ============================================================================
-- EcoShop — Test RLS 19 : visibilité des notifications (M9)
--
-- Vérifie que :
--   • le destinataire voit ses propres notifications (tous établissements) ;
--   • la direction voit toutes les notifications de son établissement ;
--   • un parent ne voit pas celles des autres ;
--   • un parent ne peut pas envoyer de notification (direction/admin seuls) ;
--   • la direction ne voit pas les notifications d'un autre établissement.
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
-- Tenants (ids fixes) + comptes
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (id, nom, slug)
VALUES
  ('30000000-0000-0000-0000-000000000001', 'École Comm A M9', 'ecole-comm-a-m9'),
  ('30000000-0000-0000-0000-000000000002', 'École Comm B M9', 'ecole-comm-b-m9');

SELECT pg_temp.creer_compte('224600001301', 'direction') AS dir_id \gset
SELECT pg_temp.creer_compte('224600001302', 'parent')    AS parent1_id \gset
SELECT pg_temp.creer_compte('224600001303', 'parent')    AS parent2_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_id'::uuid, '30000000-0000-0000-0000-000000000001', 'direction');

-- ---------------------------------------------------------------------------
-- Notifications (insertion serveur, hors RLS)
-- ---------------------------------------------------------------------------
INSERT INTO public.notifications (etablissement_id, destinataire, type, canal, contenu, statut)
VALUES
  ('30000000-0000-0000-0000-000000000001', :'parent1_id'::uuid, 'absence', 'sms', 'Absence Aicha', 'envoyee'),
  ('30000000-0000-0000-0000-000000000001', :'parent2_id'::uuid, 'note',    'sms', 'Note Ibrahim',  'envoyee'),
  ('30000000-0000-0000-0000-000000000001', :'dir_id'::uuid,     'alerte',  'email', 'Alerte',       'en_attente'),
  ('30000000-0000-0000-0000-000000000002', :'parent1_id'::uuid, 'note',    'sms', 'Note autre école', 'envoyee');

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

-- 1. Le parent voit ses propres notifications (tous établissements).
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'parent1_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.notifications)::int, 2, 'parent : voit ses propres notifications');

-- 2. La direction voit toutes les notifications de son établissement.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.notifications WHERE etablissement_id = '30000000-0000-0000-0000-000000000001')::int,
  3,
  'direction : voit toutes les notifications de son établissement'
);

-- 3. Un parent ne voit pas celles des autres.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'parent2_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.notifications)::int, 1, 'parent : ne voit pas les notifications des autres');

-- 4. Un parent ne peut pas envoyer de notification.
SELECT throws_ok(
  $$ INSERT INTO public.notifications (etablissement_id, destinataire, type, canal, contenu)
     VALUES ('30000000-0000-0000-0000-000000000001', auth.uid(), 'absence', 'sms', 'test') $$,
  '42501',
  NULL
);

-- 5. Isolation multi-tenant : la direction ne voit pas un autre établissement.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.notifications WHERE etablissement_id = '30000000-0000-0000-0000-000000000002')::int,
  0,
  'isolation : aucune notification visible hors établissement'
);

-- 6. Non-régression (patch 20260906001503) : la direction peut réellement
-- enregistrer une notification via INSERT ... RETURNING — la policy SELECT
-- s'appuyait auparavant sur notif_visible(id), une fonction auto-
-- référentielle (re-interroge notifications par id) qui ne voit pas la
-- ligne tout juste insérée au moment où Postgres vérifie implicitement la
-- policy SELECT pour construire le résultat de RETURNING : l'INSERT seul
-- réussissait, mais INSERT ... RETURNING échouait en 42501 pour tout le
-- monde — exactement le chemin réel qu'emprunte
-- SupabaseCommRepository.creerNotification() (.insert(...).select().single()).
INSERT INTO public.notifications (etablissement_id, destinataire, type, canal, contenu)
VALUES ('30000000-0000-0000-0000-000000000001', :'parent1_id'::uuid, 'absence', 'sms', 'non-regression RETURNING')
RETURNING id AS notif_regression_id \gset
SELECT ok(
  :'notif_regression_id' IS NOT NULL,
  'non-régression : INSERT ... RETURNING réussit pour la direction (policy SELECT non auto-référentielle)'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
