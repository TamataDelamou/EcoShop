-- ============================================================================
-- EcoShop — Test RLS 50 : Facturation/Quota IA — étape (b), brique CinetPay
-- générique (migration 20260906001515).
--
-- Couvre les points explicitement demandés en relecture avant push :
--   1. Frontière serveur : initier_transaction_cinetpay (authenticated),
--      finaliser_initiation_cinetpay et traiter_webhook_cinetpay
--      (service_role SEULEMENT — un compte authentifié, même admin_gsg, est
--      refusé) via GRANT/REVOKE Postgres natif -- PAS est_appel_service(),
--      inutilisable ici (voir migration 20260906001515 point 7 : ces deux
--      fonctions sont elles-mêmes SECURITY DEFINER, current_user y vaut
--      déjà leur propriétaire). Couvre aussi les fonctions privées de
--      calcul/upsert (compter_effectif_actif, appliquer_paiement_*),
--      jamais appelables directement par un client.
--   2. Recalcul serveur du montant (jamais une valeur client) pour les deux
--      types réels (frais_ia_admin_etablissement, licence_pro_etablissement).
--   3. Webhook = seule autorité de crédit : rejet signature absente/invalide,
--      rejet écart montant_confirme vs montant_attendu (statut echoue,
--      jamais de crédit silencieux), rejeu idempotent (no-op, jamais un
--      second crédit — prouvé par un montant cumulatif qui NE double PAS).
--   4. Correction actée : la branche licence_pro recompte l'effectif réel EN
--      DIRECT au moment du crédit — un effectif de 150 capturé à
--      l'initiation (tranche 1) doit produire tranche 2 si l'établissement
--      atteint 500 élèves actifs avant l'arrivée du webhook.
--   5. Isolation inter-établissements de la lecture de transactions_cinetpay.
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

SELECT plan(32);

-- ---------------------------------------------------------------------------
-- Fixture : deux établissements (A = cible, B = isolation), une année
-- scolaire courante pour chacun.
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('50000000-0000-0000-0000-000000000001', 'École QA A', 'ecole-qa50-a');
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('50000000-0000-0000-0000-000000000099', 'École QA B (isolation)', 'ecole-qa50-b');

INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('50000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000001', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('50000000-0000-0000-0000-000000000004', '50000000-0000-0000-0000-000000000099', '2026-2027', '2026-10-01', '2027-06-30', true);

INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom)
VALUES ('50000000-0000-0000-0000-000000000010', '50000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000002', 'QA50', 'Classe QA 50');

SELECT pg_temp.creer_compte('224600006001', 'direction')  AS dir_a_id      \gset
SELECT pg_temp.creer_compte('224600006002', 'direction')  AS dir_b_id      \gset
SELECT pg_temp.creer_compte('224600006003', 'admin_gsg')  AS admin_gsg_id  \gset
SELECT pg_temp.creer_compte('224600006004')               AS sans_role_id  \gset
SELECT pg_temp.creer_compte('224600006005', 'eleve')      AS etranger_id   \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_a_id'::uuid, '50000000-0000-0000-0000-000000000001', 'direction');
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_b_id'::uuid, '50000000-0000-0000-0000-000000000099', 'direction');

-- Secret webhook laissé NULL par la migration (aucun identifiant CinetPay
-- disponible) — vérifié en section 3 avant d'être fixé pour le reste du test.

-- ===========================================================================
-- 1. initier_transaction_cinetpay — frontière d'accès
-- ===========================================================================
SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims', json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.initier_transaction_cinetpay('frais_ia_admin_etablissement', '50000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'initier_transaction_cinetpay : tiers sans lien refusé'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'sans_role_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.initier_transaction_cinetpay('frais_ia_admin_etablissement', '50000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'initier_transaction_cinetpay : compte sans role_racine choisi refusé'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_b_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.initier_transaction_cinetpay('frais_ia_admin_etablissement', '50000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'initier_transaction_cinetpay : direction d''un AUTRE établissement refusée'
);

-- Recalcul serveur : avant tout élève actif, licence_pro n'a rien à facturer.
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.initier_transaction_cinetpay('licence_pro_etablissement', '50000000-0000-0000-0000-000000000001') $$,
  '22023', NULL, 'initier_transaction_cinetpay : licence_pro sans effectif facturable rejetée (AUCUN_MONTANT_DU)'
);

-- frais_ia_admin : montant recalculé serveur = tarif placeholder (1), jamais une valeur du client.
SELECT row_eq(
  $$ SELECT statut, montant_attendu, (contexte->>'annee_scolaire_id')::uuid
     FROM public.initier_transaction_cinetpay('frais_ia_admin_etablissement', '50000000-0000-0000-0000-000000000001') $$,
  ROW('initie'::public.statut_paiement, 1.00::numeric, '50000000-0000-0000-0000-000000000002'::uuid),
  'initier_transaction_cinetpay : frais_ia_admin, statut initie + montant recalculé serveur (placeholder 1) + contexte correct'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT id AS tx_frais_id FROM public.transactions_cinetpay
  WHERE etablissement_id = '50000000-0000-0000-0000-000000000001' AND type_objet_paye = 'frais_ia_admin_etablissement'
  \gset

-- ---------------------------------------------------------------------------
-- 1b. Fonctions privées de calcul/upsert — jamais appelables directement,
-- même par la direction concernée ou l'admin GSG (elles n'ont aucune
-- vérification d'autorisation propre, voir migration §3/§4 : seul le
-- GRANT/REVOKE Postgres les protège).
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT public.compter_effectif_actif('50000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000002') $$,
  '42501', NULL, 'compter_effectif_actif : jamais appelable directement par un compte authentifié (même personnel de l''établissement)'
);
SELECT throws_ok(
  $$ SELECT public.appliquer_paiement_licence_pro('50000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000002', 999999, 1) $$,
  '42501', NULL, 'appliquer_paiement_licence_pro : jamais appelable directement (contournerait tout contrôle d''autorisation)'
);
SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.appliquer_paiement_frais_ia_admin('50000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000002', 1) $$,
  '42501', NULL, 'appliquer_paiement_frais_ia_admin : jamais appelable directement, même par admin GSG (doit passer par la RPC dédiée)'
);
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);

-- ===========================================================================
-- 2. finaliser_initiation_cinetpay — réservée service_role, jamais un
-- compte authentifié (même admin_gsg).
-- ===========================================================================
SELECT throws_ok(
  format($$ SELECT public.finaliser_initiation_cinetpay('%s'::uuid, 'ref-test-1') $$, :'tx_frais_id'),
  '42501', NULL, 'finaliser_initiation_cinetpay : direction (authenticated) refusée'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.finaliser_initiation_cinetpay('%s'::uuid, 'ref-test-1') $$, :'tx_frais_id'),
  '42501', NULL, 'finaliser_initiation_cinetpay : admin GSG en tant que compte authenticated (pas service_role) refusé'
);

RESET ROLE;
SET LOCAL ROLE service_role;

SELECT is(
  (SELECT reference_cinetpay FROM public.finaliser_initiation_cinetpay(:'tx_frais_id'::uuid, 'ref-test-1')),
  'ref-test-1',
  'finaliser_initiation_cinetpay : service_role autorisé, référence enregistrée'
);

-- ===========================================================================
-- 3. traiter_webhook_cinetpay — frontière + secret non configuré
-- ===========================================================================
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.traiter_webhook_cinetpay('%s'::uuid, 'peu importe', 1, 'orange_money') $$, :'tx_frais_id'),
  '42501', NULL, 'traiter_webhook_cinetpay : direction (authenticated) refusée'
);

RESET ROLE;
SET LOCAL ROLE service_role;
SELECT throws_ok(
  format($$ SELECT public.traiter_webhook_cinetpay('%s'::uuid, 'peu importe', 1, 'orange_money') $$, :'tx_frais_id'),
  '55000', NULL, 'traiter_webhook_cinetpay : secret non configuré -> CINETPAY_NON_CONFIGURE, aucun crédit possible'
);

RESET ROLE;

-- Secret de test fixé pour le reste du script (jamais codé en dur dans les
-- fonctions -- simule l'admin GSG renseignant le vrai secret un jour).
UPDATE public.parametres_secrets_integration
SET valeur = jsonb_set(valeur, '{secret_verification_webhook}', '"secret-test-50-cinetpay"')
WHERE cle = 'cinetpay_config';

SET LOCAL ROLE service_role;

SELECT throws_ok(
  format($$ SELECT public.traiter_webhook_cinetpay('%s'::uuid, 'signature-bidon', 1, 'orange_money') $$, :'tx_frais_id'),
  '42501', NULL, 'traiter_webhook_cinetpay : signature invalide rejetée'
);

-- Signature correcte mais montant confirmé ≠ montant_attendu (1) -> echoue,
-- jamais de crédit. Testé sur une SECONDE transaction dédiée (tx_frais_id
-- reste intacte pour le scénario de succès qui suit -- 'echoue' est
-- terminal par conception, voir migration §8).
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT id AS tx_frais_mismatch_id FROM public.initier_transaction_cinetpay('frais_ia_admin_etablissement', '50000000-0000-0000-0000-000000000001') \gset
RESET ROLE;
SET LOCAL ROLE service_role;

SELECT encode(extensions.hmac((:'tx_frais_mismatch_id' || ':' || 99::text || ':orange_money')::bytea, 'secret-test-50-cinetpay'::bytea, 'sha256'), 'hex') AS sig_montant_faux \gset
SELECT is(
  (SELECT statut FROM public.traiter_webhook_cinetpay(:'tx_frais_mismatch_id'::uuid, :'sig_montant_faux', 99, 'orange_money')),
  'echoue'::public.statut_paiement,
  'traiter_webhook_cinetpay : écart de montant confirmé -> statut echoue, jamais un crédit silencieux'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT ok(
  public.entitlement_actif('50000000-0000-0000-0000-000000000001', 'frais_ia_admin') is false,
  'entitlement_actif : frais_ia_admin toujours faux après un webhook en echec'
);
RESET ROLE;
SET LOCAL ROLE service_role;

-- Signature + montant corrects -> crédit réel.
SELECT encode(extensions.hmac((:'tx_frais_id' || ':' || 1::text || ':orange_money')::bytea, 'secret-test-50-cinetpay'::bytea, 'sha256'), 'hex') AS sig_frais_ok \gset
SELECT is(
  (SELECT statut FROM public.traiter_webhook_cinetpay(:'tx_frais_id'::uuid, :'sig_frais_ok', 1, 'orange_money')),
  'reussi'::public.statut_paiement,
  'traiter_webhook_cinetpay : signature + montant corrects -> statut reussi'
);

SELECT updated_at AS tx_frais_updated_at FROM public.transactions_cinetpay WHERE id = :'tx_frais_id'::uuid \gset

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT ok(
  public.entitlement_actif('50000000-0000-0000-0000-000000000001', 'frais_ia_admin') is true,
  'entitlement_actif : frais_ia_admin vrai après crédit réel via webhook'
);

-- Ré-initier après paiement -> DEJA_PAYE.
SELECT throws_ok(
  $$ SELECT public.initier_transaction_cinetpay('frais_ia_admin_etablissement', '50000000-0000-0000-0000-000000000001') $$,
  '22023', NULL, 'initier_transaction_cinetpay : frais_ia_admin déjà payé -> DEJA_PAYE'
);

-- Rejeu idempotent : même appel exact ne recrédite jamais (updated_at inchangé).
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT is(
  (SELECT updated_at FROM public.traiter_webhook_cinetpay(:'tx_frais_id'::uuid, :'sig_frais_ok', 1, 'orange_money')),
  :'tx_frais_updated_at'::timestamptz,
  'traiter_webhook_cinetpay : rejeu du même webhook -> no-op (updated_at inchangé, aucun second traitement)'
);

-- ===========================================================================
-- 4. licence_pro_etablissement — recalcul serveur + recompte d'effectif EN
-- DIRECT au moment du crédit (pas la valeur capturée à l'initiation).
-- ===========================================================================
RESET ROLE;

-- 150 élèves actifs -> tranche 1 (barème placeholder 101-400), montant 300.
WITH nouvelles_fiches AS (
  INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance)
  SELECT gen_random_uuid(), '50000000-0000-0000-0000-000000000001', 'QA50-' || g, 'Nom' || g, 'Prenom' || g, '2012-01-01'
  FROM generate_series(1, 150) AS g
  RETURNING id
)
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
SELECT '50000000-0000-0000-0000-000000000001', id, '50000000-0000-0000-0000-000000000010', '50000000-0000-0000-0000-000000000002', 'active'
FROM nouvelles_fiches;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);

SELECT row_eq(
  $$ SELECT statut, montant_attendu, (contexte->>'effectif_a_l_initiation')::int
     FROM public.initier_transaction_cinetpay('licence_pro_etablissement', '50000000-0000-0000-0000-000000000001') $$,
  ROW('initie'::public.statut_paiement, 300.00::numeric, 150),
  'initier_transaction_cinetpay : licence_pro, 150 actifs -> tranche 1, montant 300, effectif capturé pour audit'
);

SELECT id AS tx_pro_id FROM public.transactions_cinetpay
  WHERE etablissement_id = '50000000-0000-0000-0000-000000000001' AND type_objet_paye = 'licence_pro_etablissement'
  \gset

RESET ROLE;
SET LOCAL ROLE service_role;
SELECT is(
  (SELECT reference_cinetpay FROM public.finaliser_initiation_cinetpay(:'tx_pro_id'::uuid, 'ref-test-pro-1')),
  'ref-test-pro-1',
  'finaliser_initiation_cinetpay : licence_pro, référence enregistrée'
);
RESET ROLE;

-- L'établissement grandit AVANT l'arrivée du webhook : 350 élèves actifs de
-- plus -> 500 au total (régime plancher, tranche 2). effectif_a_l_initiation
-- (150, encore dans contexte) doit être IGNORÉ au crédit.
WITH nouvelles_fiches AS (
  INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance)
  SELECT gen_random_uuid(), '50000000-0000-0000-0000-000000000001', 'QA50-B-' || g, 'Nom' || g, 'Prenom' || g, '2012-01-01'
  FROM generate_series(1, 350) AS g
  RETURNING id
)
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
SELECT '50000000-0000-0000-0000-000000000001', id, '50000000-0000-0000-0000-000000000010', '50000000-0000-0000-0000-000000000002', 'active'
FROM nouvelles_fiches;

SELECT is(
  public.compter_effectif_actif('50000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000002'),
  500,
  'précondition : 500 élèves actifs réellement recomptables avant le webhook'
);

SET LOCAL ROLE service_role;
SELECT encode(extensions.hmac((:'tx_pro_id' || ':' || 300::text || ':mtn')::bytea, 'secret-test-50-cinetpay'::bytea, 'sha256'), 'hex') AS sig_pro_ok \gset

SELECT is(
  (SELECT statut FROM public.traiter_webhook_cinetpay(:'tx_pro_id'::uuid, :'sig_pro_ok', 300, 'mtn')),
  'reussi'::public.statut_paiement,
  'traiter_webhook_cinetpay : licence_pro, montant confirmé = montant_attendu -> reussi'
);

SELECT is(
  (SELECT tranche_actuelle FROM public.etablissements_licence_pro
   WHERE etablissement_id = '50000000-0000-0000-0000-000000000001' AND annee_scolaire_id = '50000000-0000-0000-0000-000000000002'),
  2,
  'CORRECTION : tranche_actuelle = 2 -> recompte EN DIRECT (500 réels), pas la valeur périmée (150) capturée à l''initiation'
);

SELECT is(
  (SELECT montant_total_paye_periode FROM public.etablissements_licence_pro
   WHERE etablissement_id = '50000000-0000-0000-0000-000000000001' AND annee_scolaire_id = '50000000-0000-0000-0000-000000000002'),
  300.00,
  'traiter_webhook_cinetpay : montant_total_paye_periode = 300 après le premier crédit CinetPay'
);

-- Rejeu idempotent : le montant cumulatif ne double JAMAIS.
SELECT is(
  (SELECT statut FROM public.traiter_webhook_cinetpay(:'tx_pro_id'::uuid, :'sig_pro_ok', 300, 'mtn')),
  'reussi'::public.statut_paiement,
  'traiter_webhook_cinetpay : rejeu licence_pro -> no-op, toujours reussi'
);
SELECT is(
  (SELECT montant_total_paye_periode FROM public.etablissements_licence_pro
   WHERE etablissement_id = '50000000-0000-0000-0000-000000000001' AND annee_scolaire_id = '50000000-0000-0000-0000-000000000002'),
  300.00,
  'CORRECTION : rejeu du webhook -> montant_total_paye_periode reste 300 (jamais 600, aucun double crédit)'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_a_id', 'role', 'authenticated')::text, true);
SELECT ok(
  public.entitlement_actif('50000000-0000-0000-0000-000000000001', 'licence_pro') is true,
  'entitlement_actif : licence_pro vrai après crédit CinetPay'
);

-- ===========================================================================
-- 5. Isolation inter-établissements de la lecture des transactions.
-- ===========================================================================
SELECT is(
  (SELECT count(*) FROM public.transactions_cinetpay WHERE etablissement_id = '50000000-0000-0000-0000-000000000001'),
  3::bigint,
  'précondition : direction A voit ses 3 transactions (frais_ia_admin echoue + frais_ia_admin reussi + licence_pro)'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_b_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.transactions_cinetpay WHERE etablissement_id = '50000000-0000-0000-0000-000000000001'),
  0::bigint,
  'transactions_cinetpay : direction B ne voit AUCUNE transaction de l''établissement A (isolation réelle)'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.transactions_cinetpay WHERE etablissement_id = '50000000-0000-0000-0000-000000000001'),
  3::bigint,
  'transactions_cinetpay : admin GSG voit les transactions de n''importe quel établissement'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
