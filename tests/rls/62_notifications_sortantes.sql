-- ============================================================================
-- EcoShop — Test RLS 62 : file d'envoi des notifications (REG-04 fin,
-- migration 20260906001533)
--
-- Couvre :
--   • soumission d'une demande => accusé de réception au fondateur (adresse
--     du compte à défaut de celle de la demande) + alerte à l'équipe GSG ;
--   • acceptation et refus => message correspondant, motif inclus ;
--   • compte sans courriel => aucun message au fondateur (pas d'erreur) ;
--   • idempotence : un même événement ne produit jamais deux messages ;
--   • table et fonctions inaccessibles à authenticated ;
--   • réservation (bail, tentatives), succès, échec temporaire (reprogrammé
--     dans le futur), échec définitif, plafond de 6 tentatives, purge.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.creer_compte(p_phone text, p_role text DEFAULT NULL, p_email text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public, auth, pg_catalog
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, phone, email) VALUES (v_id, p_phone, p_email);
  IF p_role IS NOT NULL THEN
    UPDATE public.profiles SET role_racine = p_role::public.role_racine WHERE id = v_id;
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

SELECT plan(26);

INSERT INTO public.systemes_educatifs (code, nom)
SELECT 'francophone_cfa', 'Francophone CFA'
WHERE NOT EXISTS (SELECT 1 FROM public.systemes_educatifs WHERE code = 'francophone_cfa');
INSERT INTO public.pays_pedagogiques (code_iso, nom, type_systeme, langue_enseignement_principale, devise_code, statut_deploiement)
VALUES ('GN', 'Guinée', 'francophone_cfa', 'fr', 'GNF', 'deploye')
ON CONFLICT (code_iso) DO NOTHING;

SELECT pg_temp.creer_compte('224662000001', NULL, 'Fondateur@Exemple.org') AS fondateur_id \gset
SELECT pg_temp.creer_compte('224662000002', NULL, 'refuse@exemple.org')    AS refuse_id    \gset
SELECT pg_temp.creer_compte('224662000003')                                AS sans_mail_id \gset
SELECT pg_temp.creer_compte('224662000009', 'admin_gsg')                   AS admin_id     \gset

-- ---------------------------------------------------------------------------
-- 1. Soumission => accusé de réception + alerte GSG
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'fondateur_id');
SELECT public.soumettre_demande_etablissement('École Bambino Test', 'GN', 'Conakry', '+224 620 00 00 01') AS d1 \gset
SELECT pg_temp.en_tant_que(:'refuse_id');
SELECT public.soumettre_demande_etablissement('Groupe Scolaire Refus', 'GN', 'Kindia', '+224 620 00 00 02',
  NULL, 'contact@ecole-refus.org') AS d2 \gset
SELECT pg_temp.en_tant_que(:'sans_mail_id');
SELECT public.soumettre_demande_etablissement('École Sans Courriel', 'GN', 'Labé', '+224 620 00 00 03') AS d3 \gset
RESET ROLE;

SELECT is(
  (SELECT destinataire FROM public.notifications_sortantes WHERE cle_idempotence = 'demande_recue:' || :'d1'),
  'fondateur@exemple.org',
  'accusé de réception envoyé à l''adresse du compte, normalisée en minuscules');
SELECT is(
  (SELECT donnees->>'nom_etablissement' FROM public.notifications_sortantes WHERE cle_idempotence = 'demande_recue:' || :'d1'),
  'École Bambino Test',
  'le message porte le nom de l''établissement');
SELECT is(
  (SELECT donnees->>'pays' FROM public.notifications_sortantes WHERE cle_idempotence = 'demande_recue:' || :'d1'),
  'Guinée',
  'le message porte le nom du pays, pas son code');
SELECT is(
  (SELECT destinataire FROM public.notifications_sortantes WHERE cle_idempotence = 'demande_recue:' || :'d2'),
  'contact@ecole-refus.org',
  'l''adresse saisie dans la demande prime sur celle du compte');
SELECT is(
  (SELECT count(*)::int FROM public.notifications_sortantes WHERE cle_idempotence = 'demande_recue:' || :'d3'),
  0,
  'compte sans courriel : aucun accusé de réception (et aucune erreur)');
SELECT is(
  (SELECT count(*)::int FROM public.notifications_sortantes
    WHERE modele = 'demande_etablissement_a_traiter' AND destinataire_role = 'admin_gsg'),
  3,
  'l''équipe GSG est prévenue de chaque nouvelle demande, y compris sans courriel du fondateur');

-- ---------------------------------------------------------------------------
-- 2. Accès refusé aux clients
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'fondateur_id');
SELECT throws_ok('SELECT count(*) FROM public.notifications_sortantes', '42501', NULL,
  'authenticated ne peut pas lire la file');
SELECT throws_ok('SELECT * FROM public.reserver_notifications(5)', '42501', NULL,
  'authenticated ne peut pas réserver de messages');
SELECT throws_ok($$SELECT public.mettre_notification_en_file('x_y_z', 'k', '{}', 'a@b.co')$$, '42501', NULL,
  'authenticated ne peut pas fabriquer un message');

-- ---------------------------------------------------------------------------
-- 3. Décisions => messages
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'admin_id');
SELECT public.traiter_demande_etablissement(:'d1', 'acceptee');
SELECT public.traiter_demande_etablissement(:'d2', 'refusee', 'Autorisation d''ouverture illisible');
RESET ROLE;

SELECT is(
  (SELECT destinataire FROM public.notifications_sortantes WHERE cle_idempotence = 'demande_acceptee:' || :'d1'),
  'fondateur@exemple.org',
  'acceptation : le fondateur est prévenu');
SELECT is(
  (SELECT donnees->>'motif' FROM public.notifications_sortantes WHERE cle_idempotence = 'demande_refusee:' || :'d2'),
  'Autorisation d''ouverture illisible',
  'refus : le motif figure dans le message');

-- Idempotence : rejouer la mise en file d'un même événement ne duplique rien.
SELECT is(
  public.mettre_notification_en_file('demande_etablissement_acceptee', 'demande_acceptee:' || :'d1', '{}', 'autre@exemple.org'),
  NULL,
  'même clé d''idempotence : aucun second message');
SELECT is(
  (SELECT count(*)::int FROM public.notifications_sortantes WHERE cle_idempotence = 'demande_acceptee:' || :'d1'),
  1,
  'un seul message par événement');
SELECT is(
  public.mettre_notification_en_file('demande_etablissement_recue', 'cle-invalide', '{}', 'pas-une-adresse'),
  NULL,
  'adresse mal formée : rien n''est mis en file');

-- ---------------------------------------------------------------------------
-- 4. Cycle d'envoi (service_role)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

CREATE TEMP TABLE lot AS SELECT * FROM public.reserver_notifications(100);
SELECT is((SELECT count(*)::int FROM lot), 7, 'tous les messages dus sont réservés (2 accusés, 3 alertes, 2 décisions)');
SELECT is(
  (SELECT count(*)::int FROM public.notifications_sortantes WHERE statut = 'en_cours' AND verrou_jusqu_a > now() AND tentatives = 1),
  7,
  'messages réservés : en cours, sous bail, première tentative');
SELECT is((SELECT count(*)::int FROM public.reserver_notifications(100)), 0,
  'un second passage ne reprend pas des messages sous bail');

SELECT id AS m_ok FROM lot WHERE cle_idempotence = 'demande_recue:' || :'d1' \gset
SELECT id AS m_temp FROM lot WHERE cle_idempotence = 'demande_recue:' || :'d2' \gset
SELECT id AS m_def FROM lot WHERE cle_idempotence = 'demande_acceptee:' || :'d1' \gset

SELECT ok(public.marquer_notification_envoyee(:'m_ok', '<msg-1@brevo>'), 'succès enregistré');
SELECT is((SELECT statut || '|' || identifiant_fournisseur FROM public.notifications_sortantes WHERE id = :'m_ok'),
  'envoyee|<msg-1@brevo>', 'statut envoyé et identifiant Brevo conservés');
SELECT ok(NOT public.marquer_notification_envoyee(:'m_ok', 'x'), 'un message déjà envoyé ne se re-marque pas');

SELECT is(public.marquer_notification_echec(:'m_temp', 'HTTP 503', false), 'a_envoyer',
  'échec temporaire : remis en file');
SELECT ok((SELECT prochaine_tentative_le > now() FROM public.notifications_sortantes WHERE id = :'m_temp'),
  'échec temporaire : reprogrammé plus tard (attente croissante)');

SELECT is(public.marquer_notification_echec(:'m_def', 'HTTP 400 adresse refusée', true), 'echec_definitif',
  'échec définitif : arrêt immédiat');

-- Plafond : à la 6e tentative, un échec même temporaire est définitif.
UPDATE public.notifications_sortantes SET tentatives = 6 WHERE id = :'m_temp';
UPDATE public.notifications_sortantes SET statut = 'en_cours' WHERE id = :'m_temp';
SELECT is(public.marquer_notification_echec(:'m_temp', 'HTTP 503', false), 'echec_definitif',
  'au-delà de 6 tentatives, plus de nouvel essai');

-- Purge : les messages terminés anciens disparaissent, pas les autres.
RESET ROLE;
ALTER TABLE public.notifications_sortantes DISABLE TRIGGER notifications_set_updated_at;
UPDATE public.notifications_sortantes SET updated_at = now() - interval '120 days' WHERE id IN (:'m_ok', :'m_def');
ALTER TABLE public.notifications_sortantes ENABLE TRIGGER notifications_set_updated_at;
SET LOCAL ROLE service_role;
SELECT is(public.purger_notifications(90), 2, 'purge des messages terminés de plus de 90 jours');

SELECT is((public.indicateurs_notifications()->>'en_cours')::int, 4, 'indicateurs de supervision disponibles');

SELECT * FROM finish();
ROLLBACK;
