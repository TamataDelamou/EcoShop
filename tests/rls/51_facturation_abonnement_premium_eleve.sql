-- ============================================================================
-- EcoShop — Test RLS 51 : Facturation/Quota IA — étape (c), Abonnement
-- Premium élève (migrations 20260906001518/20260906001519).
--
-- Chaque nouveau point d'autorisation introduit par cette étape est couvert
-- pour le refus ET le succès légitime, dans le même périmètre (règle actée
-- après la régression D5 bulletins) :
--   1. initier_transaction_cinetpay('abonnement_premium_eleve', ...) :
--      refus tiers/personnel de l'établissement/admin GSG (aucun des trois
--      n'est payeur ou bénéficiaire légitime) ; succès élève lui-même
--      (même mineur, autorisé explicitement) ET parent confirmé payant pour
--      un AUTRE enfant que le sien -- payeur (initiateur_id) et bénéficiaire
--      (beneficiaire_fiche_eleve_id) jamais confondus. Distinction fine
--      explicitement vérifiée (demandée en relecture avant push) : un
--      parent LIÉ à l'élève mais statut en_attente (pas confirmé), et un
--      parent confirmé mais autorise=false (droit révoqué), sont CHACUN
--      refusés -- deux clauses distinctes d'est_parent_confirme(), pas
--      seulement le cas trivial d'un tiers sans aucune ligne.
--   2. Contrainte CHECK transactions_cinetpay_coherence : refuse en base
--      même une écriture qui contournerait la RLS (rôle postgres).
--   3. entitlement_premium_eleve_actif() : refus tiers ET des deux mêmes cas
--      fins de parent lié mais non confirmé/non autorisé, succès élève/
--      parent confirmé/admin GSG.
--   4. RLS abonnements_premium_eleve : élève/parent confirmé/admin GSG
--      voient la ligne, PAS le personnel de l'établissement (délibéré, voir
--      migration 20260906001519 point 2), PAS un tiers sans lien, PAS un
--      parent lié mais non confirmé/non autorisé (mêmes deux cas fins).
--   5. Renouvellement anticipé : n'écrase jamais du temps déjà payé
--      (empilement des durées, jamais un simple reset à now()+durée).
--   6. enregistrer_paiement_abonnement_premium_eleve : refus direction,
--      succès admin GSG (rattrapage manuel).
--   7. appliquer_paiement_abonnement_premium_eleve : jamais appelable
--      directement (même par admin GSG).
--   8. Policy select transactions_cinetpay : payeur voit sa transaction,
--      bénéficiaire distinct du payeur ne la voit PAS (asymétrie actée par
--      le porteur de projet).
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

SELECT plan(37);

-- ---------------------------------------------------------------------------
-- Fixture : un établissement, trois fiches élèves, un parent confirmé
-- (uniquement de l'élève 2), un tiers sans aucun lien, la direction de
-- l'établissement, l'admin GSG.
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('51000000-0000-0000-0000-000000000001', 'École QA Premium', 'ecole-qa51');

SELECT pg_temp.creer_compte('224600007001', 'eleve')      AS eleve1_id      \gset
SELECT pg_temp.creer_compte('224600007002', 'eleve')      AS eleve2_id      \gset
SELECT pg_temp.creer_compte('224600007003', 'eleve')      AS eleve3_id      \gset
SELECT pg_temp.creer_compte('224600007004', 'parent')     AS parent1_id     \gset
SELECT pg_temp.creer_compte('224600007005', 'eleve')      AS eleve_tiers_id \gset
SELECT pg_temp.creer_compte('224600007006', 'direction')  AS direction_a_id \gset
SELECT pg_temp.creer_compte('224600007007', 'admin_gsg')  AS admin_gsg_id   \gset
-- Distincts d'un tiers totalement étranger : ces deux comptes ONT une ligne
-- relations_parent_eleve vers l'élève 1, mais chacun échoue sur UN filtre
-- différent d'est_parent_confirme() (statut, puis autorise) -- la nuance
-- explicitement demandée en relecture avant push.
SELECT pg_temp.creer_compte('224600007008', 'parent')     AS parent_en_attente_id    \gset
SELECT pg_temp.creer_compte('224600007009', 'parent')     AS parent_non_autorise_id  \gset

INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES ('51000000-0000-0000-0000-000000000011', '51000000-0000-0000-0000-000000000001', 'QA51-001', 'DIALLO', 'Aissatou', '2011-04-01', :'eleve1_id'::uuid, now());
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES ('51000000-0000-0000-0000-000000000012', '51000000-0000-0000-0000-000000000001', 'QA51-002', 'BARRY', 'Mamadou', '2012-06-15', :'eleve2_id'::uuid, now());
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES ('51000000-0000-0000-0000-000000000013', '51000000-0000-0000-0000-000000000001', 'QA51-003', 'CAMARA', 'Fatoumata', '2013-09-20', :'eleve3_id'::uuid, now());

-- Parent confirmé de l'élève 2 SEULEMENT (jamais de l'élève 1).
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
VALUES ('51000000-0000-0000-0000-000000000001', :'parent1_id'::uuid, '51000000-0000-0000-0000-000000000012', 'parent', 'confirmee', true);

-- Lié à l'élève 1, mais PAS encore confirmé (double facteur non complété, M5 §5.8).
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
VALUES ('51000000-0000-0000-0000-000000000001', :'parent_en_attente_id'::uuid, '51000000-0000-0000-0000-000000000011', 'parent', 'en_attente', true);

-- Lié à l'élève 1, statut confirmé, mais droit de consultation explicitement révoqué (autorise = false).
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
VALUES ('51000000-0000-0000-0000-000000000001', :'parent_non_autorise_id'::uuid, '51000000-0000-0000-0000-000000000011', 'parent', 'confirmee', false);

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'direction_a_id'::uuid, '51000000-0000-0000-0000-000000000001', 'direction');

-- Tarifs PLACEHOLDER de la migration remplacés par des valeurs distinctes
-- pour prouver que chaque formule lit bien SA propre clé de configuration.
UPDATE public.parametres_globaux SET valeur = '{"valeur": 5}'::jsonb WHERE cle = 'tarif_abonnement_premium_eleve_mensuel';
UPDATE public.parametres_globaux SET valeur = '{"valeur": 50}'::jsonb WHERE cle = 'tarif_abonnement_premium_eleve_annuel';

-- Secret webhook (déjà couvert côté rejet/CINETPAY_NON_CONFIGURE par le test 50 -- pas reproduit ici).
UPDATE public.parametres_secrets_integration
SET valeur = jsonb_set(valeur, '{secret_verification_webhook}', '"secret-test-51-cinetpay"')
WHERE cle = 'cinetpay_config';

-- ===========================================================================
-- 1. initier_transaction_cinetpay('abonnement_premium_eleve', ...) — refus
-- ===========================================================================
SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_tiers_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.initier_transaction_cinetpay('abonnement_premium_eleve', null, null, '51000000-0000-0000-0000-000000000011', 'mensuel') $$,
  '42501', NULL, 'initier_transaction_cinetpay/abonnement_premium_eleve : tiers sans lien (ni élève, ni parent confirmé) refusé'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'parent_en_attente_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.initier_transaction_cinetpay('abonnement_premium_eleve', null, null, '51000000-0000-0000-0000-000000000011', 'mensuel') $$,
  '42501', NULL, 'initier_transaction_cinetpay/abonnement_premium_eleve : parent LIÉ à l''élève mais statut en_attente (PAS confirmé) refusé -- distinct d''un tiers sans aucun lien'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'parent_non_autorise_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.initier_transaction_cinetpay('abonnement_premium_eleve', null, null, '51000000-0000-0000-0000-000000000011', 'mensuel') $$,
  '42501', NULL, 'initier_transaction_cinetpay/abonnement_premium_eleve : parent confirmé mais autorise=false (droit de consultation révoqué) refusé'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.initier_transaction_cinetpay('abonnement_premium_eleve', null, null, '51000000-0000-0000-0000-000000000011', 'mensuel') $$,
  '42501', NULL, 'initier_transaction_cinetpay/abonnement_premium_eleve : personnel de l''établissement refusé (est_personnel n''entre PAS dans la garde de ce flux individuel)'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.initier_transaction_cinetpay('abonnement_premium_eleve', null, null, '51000000-0000-0000-0000-000000000011', 'mensuel') $$,
  '42501', NULL, 'initier_transaction_cinetpay/abonnement_premium_eleve : admin GSG refusé (ne paie pas à la place de l''élève -- passe par la RPC manuelle dédiée)'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.initier_transaction_cinetpay('abonnement_premium_eleve', null) $$,
  '22023', NULL, 'initier_transaction_cinetpay/abonnement_premium_eleve : bénéficiaire/formule manquants -> PARAMETRES_ABONNEMENT_MANQUANTS'
);

-- ---------------------------------------------------------------------------
-- Succès : l'élève lui-même (même mineur -- autorisé explicitement §21.4/36.2).
-- ---------------------------------------------------------------------------
SELECT row_eq(
  $$ SELECT statut, montant_attendu, etablissement_id, beneficiaire_fiche_eleve_id, formule, initiateur_id
     FROM public.initier_transaction_cinetpay('abonnement_premium_eleve', null, null, '51000000-0000-0000-0000-000000000011', 'mensuel') $$,
  ROW(
    'initie'::public.statut_paiement, 5.00::numeric, NULL::uuid,
    '51000000-0000-0000-0000-000000000011'::uuid, 'mensuel'::public.formule_abonnement_premium_eleve,
    :'eleve1_id'::uuid
  ),
  'initier_transaction_cinetpay/abonnement_premium_eleve : élève lui-même, formule mensuelle, montant serveur (5), établissement NULL, payeur = bénéficiaire'
);

SELECT id AS tx_eleve1_id FROM public.transactions_cinetpay
  WHERE beneficiaire_fiche_eleve_id = '51000000-0000-0000-0000-000000000011' \gset

-- ---------------------------------------------------------------------------
-- Succès : parent confirmé payant pour SON enfant (élève 2) -- payeur
-- (parent1) et bénéficiaire (fiche élève 2) jamais confondus.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object('sub', :'parent1_id', 'role', 'authenticated')::text, true);
SELECT row_eq(
  $$ SELECT statut, montant_attendu, beneficiaire_fiche_eleve_id, formule, initiateur_id
     FROM public.initier_transaction_cinetpay('abonnement_premium_eleve', null, null, '51000000-0000-0000-0000-000000000012', 'annuel') $$,
  ROW(
    'initie'::public.statut_paiement, 50.00::numeric,
    '51000000-0000-0000-0000-000000000012'::uuid, 'annuel'::public.formule_abonnement_premium_eleve,
    :'parent1_id'::uuid
  ),
  'initier_transaction_cinetpay/abonnement_premium_eleve : parent confirmé payant pour son enfant, formule annuelle, montant serveur (50), payeur = parent != bénéficiaire = enfant'
);

SELECT id AS tx_eleve2_id FROM public.transactions_cinetpay
  WHERE beneficiaire_fiche_eleve_id = '51000000-0000-0000-0000-000000000012' \gset

-- ===========================================================================
-- 2. Contrainte CHECK transactions_cinetpay_coherence — refuse même une
-- écriture qui contournerait la RLS (rôle postgres, bypass RLS natif).
-- ===========================================================================
RESET ROLE;

SELECT throws_ok(
  $$ INSERT INTO public.transactions_cinetpay
       (type_objet_paye, etablissement_id, initiateur_id, montant_attendu, beneficiaire_fiche_eleve_id, formule)
     VALUES ('abonnement_premium_eleve', '51000000-0000-0000-0000-000000000001',
             (SELECT id FROM public.profiles LIMIT 1), 5, '51000000-0000-0000-0000-000000000011', 'mensuel') $$,
  '23514', NULL,
  'transactions_cinetpay_coherence : abonnement_premium_eleve avec etablissement_id renseigné rejeté (forme établissement/individuel jamais mélangée)'
);

SELECT throws_ok(
  $$ INSERT INTO public.transactions_cinetpay
       (type_objet_paye, etablissement_id, initiateur_id, montant_attendu, beneficiaire_fiche_eleve_id)
     VALUES ('frais_ia_admin_etablissement', '51000000-0000-0000-0000-000000000001',
             (SELECT id FROM public.profiles LIMIT 1), 1, '51000000-0000-0000-0000-000000000011') $$,
  '23514', NULL,
  'transactions_cinetpay_coherence : flux établissement portant un beneficiaire_fiche_eleve_id rejeté'
);

-- ===========================================================================
-- 3. Crédit réel (élève 1, mensuel) + entitlement.
-- ===========================================================================
SET LOCAL ROLE service_role;
SELECT is(
  (SELECT reference_cinetpay FROM public.finaliser_initiation_cinetpay(:'tx_eleve1_id'::uuid, 'ref-test-51-eleve1')),
  'ref-test-51-eleve1',
  'finaliser_initiation_cinetpay : abonnement_premium_eleve, référence enregistrée'
);

SELECT encode(extensions.hmac((:'tx_eleve1_id' || ':' || 5::text || ':orange_money')::bytea, 'secret-test-51-cinetpay'::bytea, 'sha256'), 'hex') AS sig_eleve1_ok \gset
SELECT is(
  (SELECT statut FROM public.traiter_webhook_cinetpay(:'tx_eleve1_id'::uuid, :'sig_eleve1_ok', 5, 'orange_money')),
  'reussi'::public.statut_paiement,
  'traiter_webhook_cinetpay : abonnement_premium_eleve (mensuel), signature + montant corrects -> reussi'
);

SELECT is(
  (SELECT expire_le FROM public.abonnements_premium_eleve WHERE fiche_eleve_id = '51000000-0000-0000-0000-000000000011'),
  (now() + interval '1 month'),
  'appliquer_paiement_abonnement_premium_eleve : première souscription mensuelle -> expire_le = now() + 1 mois'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);
SELECT ok(
  public.entitlement_premium_eleve_actif('51000000-0000-0000-0000-000000000011') is true,
  'entitlement_premium_eleve_actif : vrai pour l''élève lui-même après crédit CinetPay'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_tiers_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.entitlement_premium_eleve_actif('51000000-0000-0000-0000-000000000011') $$,
  '42501', NULL, 'entitlement_premium_eleve_actif : tiers sans lien refusé'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'parent_en_attente_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.entitlement_premium_eleve_actif('51000000-0000-0000-0000-000000000011') $$,
  '42501', NULL, 'entitlement_premium_eleve_actif : parent LIÉ mais statut en_attente (PAS confirmé) refusé, même après crédit réel de l''élève'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'parent_non_autorise_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.entitlement_premium_eleve_actif('51000000-0000-0000-0000-000000000011') $$,
  '42501', NULL, 'entitlement_premium_eleve_actif : parent confirmé mais autorise=false (droit révoqué) refusé'
);

-- ===========================================================================
-- 4. RLS abonnements_premium_eleve — visibilité élève/parent/admin GSG,
-- PAS le personnel de l'établissement, PAS un tiers.
-- ===========================================================================
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.abonnements_premium_eleve WHERE fiche_eleve_id = '51000000-0000-0000-0000-000000000011'),
  1::bigint,
  'abonnements_premium_eleve : l''élève lui-même voit sa ligne'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.abonnements_premium_eleve WHERE fiche_eleve_id = '51000000-0000-0000-0000-000000000011'),
  0::bigint,
  'abonnements_premium_eleve : la direction de l''établissement ne voit RIEN (délibéré, pas est_personnel)'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_tiers_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.abonnements_premium_eleve WHERE fiche_eleve_id = '51000000-0000-0000-0000-000000000011'),
  0::bigint,
  'abonnements_premium_eleve : un tiers sans lien ne voit rien'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'parent_en_attente_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.abonnements_premium_eleve WHERE fiche_eleve_id = '51000000-0000-0000-0000-000000000011'),
  0::bigint,
  'abonnements_premium_eleve : parent LIÉ mais statut en_attente (PAS confirmé) ne voit rien'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'parent_non_autorise_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.abonnements_premium_eleve WHERE fiche_eleve_id = '51000000-0000-0000-0000-000000000011'),
  0::bigint,
  'abonnements_premium_eleve : parent confirmé mais autorise=false (droit révoqué) ne voit rien'
);

-- Le parent de l'élève 2 ne voit pas la ligne de l'élève 1 (pas son enfant).
SELECT set_config('request.jwt.claims', json_build_object('sub', :'parent1_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.abonnements_premium_eleve WHERE fiche_eleve_id = '51000000-0000-0000-0000-000000000011'),
  0::bigint,
  'abonnements_premium_eleve : le parent d''un AUTRE élève ne voit pas cette ligne'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.abonnements_premium_eleve WHERE fiche_eleve_id = '51000000-0000-0000-0000-000000000011'),
  1::bigint,
  'abonnements_premium_eleve : admin GSG voit la ligne de n''importe quel élève'
);

-- ===========================================================================
-- 5. Renouvellement anticipé (élève 1, encore actif) — empile la durée,
-- n'écrase jamais du temps déjà payé.
-- ===========================================================================
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);
SELECT id AS tx_eleve1_renouv_id
  FROM public.initier_transaction_cinetpay('abonnement_premium_eleve', null, null, '51000000-0000-0000-0000-000000000011', 'mensuel')
  \gset

RESET ROLE;
SET LOCAL ROLE service_role;
SELECT encode(extensions.hmac((:'tx_eleve1_renouv_id' || ':' || 5::text || ':mtn')::bytea, 'secret-test-51-cinetpay'::bytea, 'sha256'), 'hex') AS sig_renouv_ok \gset
SELECT is(
  (SELECT statut FROM public.traiter_webhook_cinetpay(:'tx_eleve1_renouv_id'::uuid, :'sig_renouv_ok', 5, 'mtn')),
  'reussi'::public.statut_paiement,
  'traiter_webhook_cinetpay : renouvellement anticipé mensuel -> reussi'
);

SELECT is(
  (SELECT expire_le FROM public.abonnements_premium_eleve WHERE fiche_eleve_id = '51000000-0000-0000-0000-000000000011'),
  (now() + interval '2 months'),
  'CORRECTION : renouvellement anticipé -> expire_le = ancienne échéance + 1 mois (now() + 2 mois), jamais now() + 1 mois seul (aucun temps déjà payé perdu)'
);

-- ===========================================================================
-- 6. Idempotence sur le flux individuel (élève 2, annuel) — rejeu ne
-- recrédite/n'étend jamais une seconde fois.
-- ===========================================================================
SELECT is(
  (SELECT statut FROM public.traiter_webhook_cinetpay(:'tx_eleve2_id'::uuid, encode(extensions.hmac((:'tx_eleve2_id' || ':' || 50::text || ':orange_money')::bytea, 'secret-test-51-cinetpay'::bytea, 'sha256'), 'hex'), 50, 'orange_money')),
  'reussi'::public.statut_paiement,
  'traiter_webhook_cinetpay : abonnement_premium_eleve (annuel, payé par le parent), signature + montant corrects -> reussi'
);

SELECT expire_le AS eleve2_expire_avant FROM public.abonnements_premium_eleve WHERE fiche_eleve_id = '51000000-0000-0000-0000-000000000012' \gset

SELECT is(
  (SELECT statut FROM public.traiter_webhook_cinetpay(:'tx_eleve2_id'::uuid, encode(extensions.hmac((:'tx_eleve2_id' || ':' || 50::text || ':orange_money')::bytea, 'secret-test-51-cinetpay'::bytea, 'sha256'), 'hex'), 50, 'orange_money')),
  'reussi'::public.statut_paiement,
  'traiter_webhook_cinetpay : rejeu du webhook abonnement_premium_eleve -> no-op, toujours reussi'
);
SELECT is(
  (SELECT expire_le FROM public.abonnements_premium_eleve WHERE fiche_eleve_id = '51000000-0000-0000-0000-000000000012'),
  :'eleve2_expire_avant'::timestamptz,
  'CORRECTION : rejeu du webhook -> expire_le inchangée (aucune extension supplémentaire, aucun double crédit)'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve2_id', 'role', 'authenticated')::text, true);
SELECT ok(
  public.entitlement_premium_eleve_actif('51000000-0000-0000-0000-000000000012') is true,
  'entitlement_premium_eleve_actif : vrai pour l''élève bénéficiaire (payé par son parent)'
);
SELECT set_config('request.jwt.claims', json_build_object('sub', :'parent1_id', 'role', 'authenticated')::text, true);
SELECT ok(
  public.entitlement_premium_eleve_actif('51000000-0000-0000-0000-000000000012') is true,
  'entitlement_premium_eleve_actif : vrai pour le parent confirmé de l''élève bénéficiaire'
);

-- ===========================================================================
-- 7. Policy select transactions_cinetpay : payeur voit sa transaction, le
-- bénéficiaire distinct du payeur ne la voit PAS (asymétrie actée).
-- ===========================================================================
SELECT is(
  (SELECT count(*) FROM public.transactions_cinetpay WHERE id = :'tx_eleve2_id'::uuid),
  1::bigint,
  'transactions_cinetpay : le parent payeur voit la transaction qu''il a initiée'
);
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve2_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.transactions_cinetpay WHERE id = :'tx_eleve2_id'::uuid),
  0::bigint,
  'transactions_cinetpay : l''élève bénéficiaire (pas payeur) ne voit PAS le ledger de la transaction -- accepté par le porteur de projet'
);

-- ===========================================================================
-- 8. RPC manuelle enregistrer_paiement_abonnement_premium_eleve — refus
-- direction, succès admin GSG (rattrapage/support, élève 3 jamais payé).
-- ===========================================================================
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.enregistrer_paiement_abonnement_premium_eleve('51000000-0000-0000-0000-000000000013', 'mensuel', 5) $$,
  '42501', NULL, 'enregistrer_paiement_abonnement_premium_eleve : direction refusée (ADMIN_GSG_REQUIS)'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT ok(
  (SELECT public.enregistrer_paiement_abonnement_premium_eleve('51000000-0000-0000-0000-000000000013', 'annuel', 50)) is not null,
  'enregistrer_paiement_abonnement_premium_eleve : admin GSG autorisé (rattrapage manuel)'
);
SELECT ok(
  public.entitlement_premium_eleve_actif('51000000-0000-0000-0000-000000000013') is true,
  'entitlement_premium_eleve_actif : vrai pour l''élève 3 après enregistrement manuel par l''admin GSG'
);

-- ===========================================================================
-- 9. appliquer_paiement_abonnement_premium_eleve — jamais appelable
-- directement, même par admin GSG.
-- ===========================================================================
SELECT throws_ok(
  $$ SELECT public.appliquer_paiement_abonnement_premium_eleve('51000000-0000-0000-0000-000000000013', 'mensuel', 5) $$,
  '42501', NULL, 'appliquer_paiement_abonnement_premium_eleve : jamais appelable directement, même par admin GSG'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
