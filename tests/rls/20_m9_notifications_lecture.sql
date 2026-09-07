-- ============================================================================
-- EcoShop — Test RLS 20 : lecture & écriture des notifications (M9)
--
-- Vérifie que :
--   • le destinataire peut marquer sa notification comme lue ;
--   • le destinataire ne peut pas altérer le contenu/canal (trigger) ;
--   • même la direction ne peut pas marquer « lue » à la place du destinataire ;
--   • la direction peut créer des notifications ;
--   • le destinataire ne voit que les siennes.
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

SELECT plan(5);

-- ---------------------------------------------------------------------------
-- Tenant (id fixe) + comptes + membres
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('40000000-0000-0000-0000-000000000001', 'École Lecture M9', 'ecole-lecture-m9');

SELECT pg_temp.creer_compte('224600001311', 'direction') AS dir_id \gset
SELECT pg_temp.creer_compte('224600001312', 'parent')    AS parent_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_id'::uuid, '40000000-0000-0000-0000-000000000001', 'direction');

-- Notifications (ids fixes pour les appels statiques throws_ok)
INSERT INTO public.notifications (id, etablissement_id, destinataire, type, canal, contenu, statut)
VALUES
  ('40000000-0000-0000-0000-00000000a001', '40000000-0000-0000-0000-000000000001', :'parent_id'::uuid, 'absence', 'sms', 'Absence Aicha', 'envoyee'),
  ('40000000-0000-0000-0000-00000000a002', '40000000-0000-0000-0000-000000000001', :'dir_id'::uuid,     'alerte',  'email', 'Alerte',       'envoyee');

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

-- 1. Le destinataire marque sa notification comme lue.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'parent_id', 'role', 'authenticated')::text, true);
UPDATE public.notifications SET statut = 'lue', date_lecture = now()
WHERE id = '40000000-0000-0000-0000-00000000a001';
SELECT is(
  (SELECT statut::text FROM public.notifications WHERE id = '40000000-0000-0000-0000-00000000a001'),
  'lue',
  'notification : marquage « lue » par le destinataire autorisé'
);

-- 2. Le destinataire ne peut pas altérer le contenu.
SELECT throws_ok(
  $$ UPDATE public.notifications SET contenu = 'contenu modifié'
     WHERE id = '40000000-0000-0000-0000-00000000a001' $$,
  '42501',
  NULL
);

-- 3. La direction ne peut pas marquer « lue » à la place du destinataire.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ UPDATE public.notifications SET date_lecture = now()
     WHERE id = '40000000-0000-0000-0000-00000000a001' $$,
  '42501',
  'notification : marquage « lue » réservé au destinataire (même la direction exclue)'
);

-- 4. La direction peut créer des notifications.
INSERT INTO public.notifications (etablissement_id, destinataire, type, canal, contenu, statut)
VALUES ('40000000-0000-0000-0000-000000000001', :'parent_id'::uuid, 'evenement', 'sms', 'Conseil de classe', 'en_attente');
SELECT is(
  (SELECT count(*) FROM public.notifications WHERE etablissement_id = '40000000-0000-0000-0000-000000000001')::int,
  3,
  'notification : création par la direction autorisée'
);

-- 5. Le parent ne voit que les siennes.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'parent_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.notifications)::int, 2, 'parent : ne voit que ses notifications');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
