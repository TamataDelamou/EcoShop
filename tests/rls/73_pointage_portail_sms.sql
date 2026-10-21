-- ============================================================================
-- EcoShop — Test RLS 73 : pointage au portail, alertes, crédits SMS,
-- relances d'impayés, push (REG-09, migrations 20260906001545-1546)
--
-- L'heure locale de l'école est rendue déterministe : le fuseau de
-- l'établissement est choisi pour qu'il soit entre 12 h et 13 h « là-bas »
-- au moment du test (heure limite 11 h 30, fin des cours 16 h).
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

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

SELECT plan(40);

-- Fuseau où il est entre 12 h et 13 h maintenant.
SELECT CASE WHEN n >= 0 THEN 'Etc/GMT+' || n ELSE 'Etc/GMT-' || (-n) END AS tz
FROM (SELECT extract(hour FROM now() AT TIME ZONE 'UTC')::int - 12 AS n) x \gset

INSERT INTO public.etablissements (id, nom, slug, devise_code, fuseau_horaire) VALUES
  ('73000000-0000-0000-0000-000000000001', 'École Portail', 'portail-73', 'GNF', :'tz'),
  ('73000000-0000-0000-0000-000000000002', 'Autre école', 'autre-73', 'GNF', :'tz');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('73000000-0000-0000-0000-0000000000a1', '73000000-0000-0000-0000-000000000001', '2026-2027',
   current_date - 60, current_date + 200, true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('73000000-0000-0000-0000-0000000000c1', '73000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-0000000000a1', '6A', '6e A');
INSERT INTO public.frais_scolarite_config (etablissement_id, annee_scolaire_id, niveau_id, montant_annuel) VALUES
  ('73000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-0000000000a1', NULL, 1000000);
INSERT INTO public.paliers_paiement_config (etablissement_id, annee_scolaire_id, nom, pourcentage, ordre, date_limite) VALUES
  ('73000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-0000000000a1', '1re tranche', 50, 1, current_date - 3),
  ('73000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-0000000000a1', '2e tranche', 50, 2, current_date + 60);

SELECT pg_temp.creer_compte('224673000001', 'direction') AS dir_id \gset
SELECT pg_temp.creer_compte('224673000002', 'parent') AS p1 \gset
SELECT pg_temp.creer_compte('224673000003', 'eleve') AS s2 \gset
SELECT pg_temp.creer_compte('224673000004', 'parent') AS p_autre \gset
SELECT pg_temp.creer_compte('224673000005', 'enseignant') AS ens \gset
SELECT pg_temp.creer_compte('224673000006', 'admin_gsg') AS admin \gset
SELECT pg_temp.creer_compte('224673000007', 'direction') AS dir2 \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_id', '73000000-0000-0000-0000-000000000001', 'direction'),
  (:'ens', '73000000-0000-0000-0000-000000000001', 'enseignant'),
  (:'dir2', '73000000-0000-0000-0000-000000000002', 'direction');

-- e1 (parent p1), e2 (élève autonome s2, payeur), e3 (parent p1, sortie
-- autorisée), e4 (personne au portail), e5 (absent justifié à l'appel).
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id, responsable_financier) VALUES
  ('73000000-0000-0000-0000-0000000000e1', '73000000-0000-0000-0000-000000000001', 'P-1', 'BAH', 'Aïssatou', '2014-01-01', NULL, 'parent'),
  ('73000000-0000-0000-0000-0000000000e2', '73000000-0000-0000-0000-000000000001', 'P-2', 'DIALLO', 'Mamadou', '2012-01-01', :'s2', 'eleve'),
  ('73000000-0000-0000-0000-0000000000e3', '73000000-0000-0000-0000-000000000001', 'P-3', 'CAMARA', 'Fanta', '2014-01-01', NULL, 'parent'),
  ('73000000-0000-0000-0000-0000000000e4', '73000000-0000-0000-0000-000000000001', 'P-4', 'SOW', 'Ibrahima', '2014-01-01', NULL, 'parent'),
  ('73000000-0000-0000-0000-0000000000e5', '73000000-0000-0000-0000-000000000001', 'P-5', 'BARRY', 'Kadiatou', '2014-01-01', NULL, 'parent');
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id)
SELECT '73000000-0000-0000-0000-000000000001', f.id, '73000000-0000-0000-0000-0000000000c1', '73000000-0000-0000-0000-0000000000a1'
FROM public.fiches_eleves f WHERE f.etablissement_id = '73000000-0000-0000-0000-000000000001';
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise) VALUES
  ('73000000-0000-0000-0000-000000000001', :'p1', '73000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true),
  ('73000000-0000-0000-0000-000000000001', :'p1', '73000000-0000-0000-0000-0000000000e3', 'parent', 'confirmee', true);
INSERT INTO public.presences (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, date_presence, statut, justifie, saisi_par)
VALUES ('73000000-0000-0000-0000-000000000001', '73000000-0000-0000-0000-0000000000a1', '73000000-0000-0000-0000-0000000000c1',
        '73000000-0000-0000-0000-0000000000e5', (now() AT TIME ZONE :'tz')::date, 'absent', true, :'dir_id');

-- ---------------------------------------------------------------------------
-- 1. Paramètres et cartes
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'ens');
SELECT throws_ok(
  $$ SELECT public.enregistrer_parametres_pointage('73000000-0000-0000-0000-000000000001', true, '11:30', '16:00') $$,
  '42501', NULL, 'un enseignant sans droit de présence ne règle pas le pointage');

SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.enregistrer_parametres_pointage('73000000-0000-0000-0000-000000000001', true, '11:30', '16:00', '{1,2,3,4,5,6,7}');
SELECT throws_ok(
  $$ SELECT public.enregistrer_parametres_pointage('73000000-0000-0000-0000-000000000001', true, '16:00', '11:30') $$,
  '22023', 'HEURES_INCOHERENTES', 'heure limite après la fin des cours : refusée');

SELECT public.cartes_classe('73000000-0000-0000-0000-0000000000c1') AS cartes \gset
SELECT is(jsonb_array_length(:'cartes'::jsonb), 5, 'une carte par élève de la classe');
SELECT c->>'jeton' AS j1 FROM jsonb_array_elements(:'cartes'::jsonb) c WHERE c->>'prenom' = 'Aïssatou' \gset
SELECT c->>'jeton' AS j2 FROM jsonb_array_elements(:'cartes'::jsonb) c WHERE c->>'prenom' = 'Mamadou' \gset
SELECT c->>'jeton' AS j3 FROM jsonb_array_elements(:'cartes'::jsonb) c WHERE c->>'prenom' = 'Fanta' \gset
SELECT ok(length(:'j1') >= 16, 'jeton secret et long (une carte ne se fabrique pas)');
SELECT is(jsonb_array_length(public.cartes_portail('73000000-0000-0000-0000-000000000001')->'cartes'), 5,
  'le téléphone du portail reçoit la liste des cartes valides');

SELECT pg_temp.en_tant_que(:'p1');
SELECT throws_ok($$ SELECT jeton FROM public.cartes_eleves $$, '42501', NULL, 'un parent ne lit jamais les jetons des cartes');

-- ---------------------------------------------------------------------------
-- 2. Absences : portail pas encore synchronisé → personne n'est alerté
-- ---------------------------------------------------------------------------
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT is(public.detecter_absences_portail('73000000-0000-0000-0000-000000000001')->0->>'etat', 'portail_non_synchronise',
  'portail sans nouvelles depuis l''heure limite : aucune alerte d''absence');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 3. Scans
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.enregistrer_pointage('73000000-0000-0000-0000-00000000aa01', '73000000-0000-0000-0000-000000000001',
  'ECO1.' || :'j1', 'arrivee', now() - interval '150 minutes', 'portail-1') AS r1 \gset
SELECT is(:'r1'::jsonb->>'statut', 'enregistre', 'arrivée enregistrée (préfixe ECO1. accepté)');
SELECT is((:'r1'::jsonb->>'en_retard')::boolean, false, 'arrivée avant l''heure limite : à l''heure');
SELECT is(public.enregistrer_pointage('73000000-0000-0000-0000-00000000aa01', '73000000-0000-0000-0000-000000000001',
  :'j1', 'arrivee', now() - interval '150 minutes', 'portail-1')->>'statut', 'deja_recu',
  'même scan renvoyé (file hors connexion) : déjà reçu');
SELECT is(public.enregistrer_pointage('73000000-0000-0000-0000-00000000aa02', '73000000-0000-0000-0000-000000000001',
  :'j1', 'arrivee', now() - interval '149 minutes', 'portail-1')->>'statut', 'doublon',
  'carte passée deux fois en moins de 2 minutes : doublon ignoré');
SELECT is(public.enregistrer_pointage('73000000-0000-0000-0000-00000000aa03', '73000000-0000-0000-0000-000000000001',
  'faux-jeton-123', 'arrivee', now(), 'portail-1')->>'statut', 'carte_inconnue', 'carte inconnue signalée');
SELECT is((public.enregistrer_pointage('73000000-0000-0000-0000-00000000aa04', '73000000-0000-0000-0000-000000000001',
  :'j2', 'arrivee', now() - interval '10 minutes', 'portail-1')->>'en_retard')::boolean, true,
  'arrivée après l''heure limite : en retard');
SELECT public.enregistrer_pointage('73000000-0000-0000-0000-00000000aa05', '73000000-0000-0000-0000-000000000001',
  :'j3', 'arrivee', now() - interval '140 minutes', 'portail-1');

SELECT pg_temp.en_tant_que(:'dir2');
SELECT throws_ok(
  format($$ SELECT public.enregistrer_pointage(gen_random_uuid(), '73000000-0000-0000-0000-000000000001', %L, 'arrivee', now(), 'x') $$, :'j1'),
  '42501', NULL, 'la Direction d''une autre école ne pointe pas ici');

RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications WHERE destinataire = :'p1' AND type = 'pointage_arrivee'), 2,
  'le parent reçoit l''arrivée de ses deux enfants (push)');
SELECT is((SELECT count(*)::int FROM public.notifications WHERE destinataire = :'s2' AND type = 'pointage_arrivee'), 1,
  'élève autonome sans parent lié : il reçoit lui-même l''avis');
SELECT ok((SELECT contenu FROM public.notifications WHERE destinataire = :'s2' AND type = 'pointage_arrivee') LIKE '%en retard%',
  'l''avis dit le retard');

-- ---------------------------------------------------------------------------
-- 4. Crédits SMS et sortie anticipée
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT throws_ok($$ SELECT public.crediter_sms('73000000-0000-0000-0000-000000000001', 100, 'cadeau') $$, '42501', NULL,
  'une école ne se crédite pas elle-même de SMS');
SELECT pg_temp.en_tant_que(:'admin');
SELECT is(public.crediter_sms('73000000-0000-0000-0000-000000000001', 10, 'Virement 2026-10-21'), 10, 'GSG crédite 10 SMS');

SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.autoriser_sortie('73000000-0000-0000-0000-0000000000e3', (now() AT TIME ZONE :'tz')::date, 'Rendez-vous médical');
SELECT public.enregistrer_pointage('73000000-0000-0000-0000-00000000bb01', '73000000-0000-0000-0000-000000000001',
  :'j1', 'sortie', now() - interval '5 minutes', 'portail-1');
SELECT public.enregistrer_pointage('73000000-0000-0000-0000-00000000bb02', '73000000-0000-0000-0000-000000000001',
  :'j3', 'sortie', now() - interval '4 minutes', 'portail-1');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.alertes_presence WHERE type = 'sortie_anticipee'), 1,
  'sortie avant la fin des cours sans autorisation : une alerte (la sortie autorisée n''en crée pas)');
SELECT is((SELECT count(*)::int FROM public.notifications_sortantes WHERE canal = 'sms' AND destinataire = '224673000002'), 1,
  'SMS envoyé au parent pour la sortie anticipée');
SELECT is((SELECT solde FROM public.credits_sms WHERE etablissement_id = '73000000-0000-0000-0000-000000000001'), 9,
  'un crédit décompté');
SELECT ok((SELECT donnees->>'message' FROM public.notifications_sortantes WHERE canal = 'sms') NOT LIKE '%ê%',
  'texte du SMS en alphabet GSM (160 caractères par SMS)');

-- SMS en échec définitif : crédit rendu.
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT count(*) FROM public.reserver_notifications(50);
SELECT public.marquer_notification_echec((SELECT id FROM public.notifications_sortantes WHERE canal = 'sms'), 'NUMERO_INVALIDE', true);
RESET ROLE;
SELECT is((SELECT solde FROM public.credits_sms WHERE etablissement_id = '73000000-0000-0000-0000-000000000001'), 10,
  'SMS non distribué : crédit rendu à l''école');

-- ---------------------------------------------------------------------------
-- 5. Absences : portail synchronisé
-- ---------------------------------------------------------------------------
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT is(public.detecter_absences_portail('73000000-0000-0000-0000-000000000001')->0->>'alertes', '1',
  'une seule alerte : l''élève non pointé, pas l''absent justifié à l''appel');
SELECT is(jsonb_array_length(public.detecter_absences_portail('73000000-0000-0000-0000-000000000001')), 0,
  'une seule détection par jour');
RESET ROLE;
SELECT is((SELECT fiche_eleve_id FROM public.alertes_presence WHERE type = 'absence'),
  '73000000-0000-0000-0000-0000000000e4'::uuid, 'l''alerte vise l''élève jamais arrivé');

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.presence_du_jour('73000000-0000-0000-0000-000000000001') AS jour \gset
SELECT is((:'jour'::jsonb->>'arrives')::int, 3, 'tableau du jour : 3 arrivés');
SELECT is((:'jour'::jsonb->>'en_retard')::int, 1, 'tableau du jour : 1 retard');

SELECT pg_temp.en_tant_que(:'ens');
SELECT throws_ok($$ SELECT public.presence_du_jour('73000000-0000-0000-0000-000000000001') $$, '42501', NULL,
  'tableau réservé au personnel chargé des présences');

-- Parents : seulement leurs enfants.
SELECT pg_temp.en_tant_que(:'p1');
SELECT is((SELECT count(DISTINCT fiche_eleve_id)::int FROM public.pointages_portail), 2, 'le parent voit les pointages de ses enfants');
SELECT pg_temp.en_tant_que(:'p_autre');
SELECT is((SELECT count(*)::int FROM public.pointages_portail), 0, 'un autre parent ne voit rien');

-- ---------------------------------------------------------------------------
-- 6. Relances d'impayés (1re tranche de 50 % échue, rien payé)
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT is(jsonb_array_length(public.apercu_relances_impayes('73000000-0000-0000-0000-000000000001')->'familles'), 5,
  'cinq élèves en retard de 500 000 GNF');
SELECT public.relancer_impayes('73000000-0000-0000-0000-000000000001', true) AS rel \gset
SELECT is((:'rel'::jsonb->>'familles')::int, 5, 'cinq familles relancées');
SELECT is((:'rel'::jsonb->>'sms')::int, 3, 'SMS aux payeurs qui ont un numéro (le parent pour ses deux enfants, l''élève autonome)');
SELECT is((public.relancer_impayes('73000000-0000-0000-0000-000000000001', true)->>'deja_relancees')::int, 5,
  'pas de seconde relance dans la semaine');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications WHERE destinataire = :'s2' AND type = 'relance_impaye'), 1,
  'l''élève à sa propre charge reçoit lui-même la relance');

-- ---------------------------------------------------------------------------
-- 7. Achat d'un pack (CinetPay, circuit GSG) et push
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT throws_ok($$ SELECT public.initier_achat_credits_sms('73000000-0000-0000-0000-000000000001', 'sms_500') $$,
  '22023', 'PACK_INDISPONIBLE', 'pack sans prix fixé par GSG : indisponible');
SELECT pg_temp.en_tant_que(:'admin');
SELECT public.definir_pack_sms('sms_500', '500 SMS', 500, 50000, true);
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT (public.initier_achat_credits_sms('73000000-0000-0000-0000-000000000001', 'sms_500')).id AS tx \gset
RESET ROLE;
UPDATE public.parametres_secrets_integration
SET valeur = jsonb_set(valeur, '{secret_verification_webhook}', '"secret-73"') WHERE cle = 'cinetpay_config';
SELECT encode(extensions.hmac((:'tx' || ':' || 50000::text || ':orange_money')::bytea, 'secret-73'::bytea, 'sha256'), 'hex') AS sig \gset
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT public.traiter_webhook_cinetpay(:'tx'::uuid, :'sig', 50000, 'orange_money');
RESET ROLE;
SELECT ok((SELECT solde FROM public.credits_sms WHERE etablissement_id = '73000000-0000-0000-0000-000000000001') >= 500,
  'pack payé : 500 SMS crédités');

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'p1');
SELECT public.enregistrer_jeton_push('jeton-fcm-de-test-parent-0001', 'android');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT ok((SELECT bool_or('jeton-fcm-de-test-parent-0001' = ANY (jetons)) FROM public.reserver_notifications_push(500)),
  'les notifications push partent vers le jeton du téléphone du parent');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
