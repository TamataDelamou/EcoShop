-- ============================================================================
-- EcoShop — Test RLS 59 : Orange Money, relance et rapprochement (REG-02 L7,
-- migration 20260906001530)
--
-- Couvre :
--   • fonctions de relance réservées à service_role ;
--   • abandon des seules initiations jamais présentées au payeur (> 30 min,
--     sans jeton de paiement) ;
--   • sélection des transactions à revérifier : délai minimal, marquage
--     anti-double-passage, signalement des transactions de plus de 24 h ;
--   • rapprochement du jour : réservé au personnel de l'établissement,
--     totaux des paiements confirmés, aucune anomalie dans le cas nominal,
--     détection d'un encaissement « OM: » sans transaction et d'un
--     encaissement automatique annulé après coup.
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

SELECT plan(15);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (id, nom, slug, devise_code)
VALUES ('59000000-0000-0000-0000-000000000001', 'École relance OM', 'ecole-relance-om-59', 'GNF'),
       ('59000000-0000-0000-0000-000000000099', 'École B relance', 'ecole-b-relance-59', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('59000000-0000-0000-0000-000000000002', '59000000-0000-0000-0000-000000000001', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom)
VALUES ('59000000-0000-0000-0000-000000000003', '59000000-0000-0000-0000-000000000001',
        '59000000-0000-0000-0000-000000000002', '6A-RL', '6e A');
INSERT INTO public.frais_scolarite_config (etablissement_id, annee_scolaire_id, niveau_id, montant_annuel)
VALUES ('59000000-0000-0000-0000-000000000001', '59000000-0000-0000-0000-000000000002', null, 1500000);

SELECT pg_temp.creer_compte('224659000001', 'direction') AS dir_id    \gset
SELECT pg_temp.creer_compte('224659000002', 'parent')    AS parent_id \gset
SELECT pg_temp.creer_compte('224659000003', 'direction') AS dir_b_id  \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_id'::uuid, '59000000-0000-0000-0000-000000000001', 'direction'),
       (:'dir_b_id'::uuid, '59000000-0000-0000-0000-000000000099', 'direction');

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.creer_inscription_nouvel_eleve(
  '59000000-0000-0000-0000-000000000001', 'DIALLO', 'Fanta', '2014-05-06',
  '59000000-0000-0000-0000-000000000003', '59000000-0000-0000-0000-000000000002', 'F'
) AS fiche_id \gset
SELECT public.enregistrer_identifiants_orange_money(
  '59000000-0000-0000-0000-000000000001', 'cid', 'csecret', 'MK000059', 'test') AS sous_compte_id \gset
RESET ROLE;

SELECT id AS inscription_id FROM public.inscriptions WHERE fiche_eleve_id = :'fiche_id'::uuid \gset

-- Trois transactions en cours, insérées directement (âges contrôlés) :
--   A : présentée au payeur il y a 10 min      -> à revérifier
--   B : jamais présentée (sans jeton), 40 min  -> à abandonner
--   C : présentée il y a 25 h                  -> à revérifier, à expirer
INSERT INTO public.transactions_mobile_money
  (id, etablissement_id, sous_compte_id, fournisseur, objet, inscription_id, initiateur_id,
   montant, devise, reference_commande, pay_token, created_at)
VALUES
  ('59000000-0000-0000-0000-0000000000a1', '59000000-0000-0000-0000-000000000001', :'sous_compte_id'::uuid,
   'orange_money_gn', 'scolarite', :'inscription_id'::uuid, :'parent_id'::uuid, 400000, 'GNF', 'ECO59A', 'PT-A', now() - interval '10 minutes'),
  ('59000000-0000-0000-0000-0000000000b1', '59000000-0000-0000-0000-000000000001', :'sous_compte_id'::uuid,
   'orange_money_gn', 'scolarite', :'inscription_id'::uuid, :'parent_id'::uuid, 100000, 'GNF', 'ECO59B', NULL, now() - interval '40 minutes'),
  ('59000000-0000-0000-0000-0000000000c1', '59000000-0000-0000-0000-000000000001', :'sous_compte_id'::uuid,
   'orange_money_gn', 'scolarite', :'inscription_id'::uuid, :'parent_id'::uuid, 200000, 'GNF', 'ECO59C', 'PT-C', now() - interval '25 hours');

-- ---------------------------------------------------------------------------
-- 1. Droits
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT throws_ok($$ SELECT public.transactions_mobile_money_a_relancer(10) $$, '42501', NULL,
  'la relance est réservée au serveur, même pour la Direction');
SELECT throws_ok($$ SELECT public.abandonner_initiations_orphelines() $$, '42501', NULL,
  'l''abandon des initiations est réservé au serveur');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 2. Relance
-- ---------------------------------------------------------------------------
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

SELECT is(public.abandonner_initiations_orphelines(), 1, 'une seule initiation orpheline abandonnée');
SELECT results_eq(
  $$ SELECT statut::text, message FROM public.transactions_mobile_money WHERE id = '59000000-0000-0000-0000-0000000000b1' $$,
  $$ VALUES ('echoue', 'INITIATION_INCOMPLETE') $$,
  'transaction jamais présentée au payeur : close avec un motif explicite');

SELECT public.transactions_mobile_money_a_relancer(10) AS lot \gset
SELECT is(jsonb_array_length(:'lot'::jsonb), 2, 'deux transactions à revérifier auprès d''Orange');
SELECT is(
  (SELECT (e ->> 'a_expirer')::boolean FROM jsonb_array_elements(:'lot'::jsonb) e WHERE e ->> 'id' = '59000000-0000-0000-0000-0000000000c1'),
  true, 'la transaction de plus de 24 h est signalée à expirer');
SELECT is(
  (SELECT (e ->> 'a_expirer')::boolean FROM jsonb_array_elements(:'lot'::jsonb) e WHERE e ->> 'id' = '59000000-0000-0000-0000-0000000000a1'),
  false, 'la transaction récente n''est pas à expirer');
SELECT is(jsonb_array_length(public.transactions_mobile_money_a_relancer(10)), 0,
  'un second passage immédiat ne reprend pas les mêmes transactions');
SELECT is((SELECT nombre_verifications FROM public.transactions_mobile_money WHERE id = '59000000-0000-0000-0000-0000000000a1'), 1,
  'le nombre de vérifications est tracé');

-- Orange confirme A ; C expire sans confirmation.
SELECT public.traiter_resultat_mobile_money('59000000-0000-0000-0000-0000000000a1', 'reussi', 400000, 'MP-A');
SELECT public.traiter_resultat_mobile_money('59000000-0000-0000-0000-0000000000c1', 'echoue', NULL, NULL, 'EXPIREE_SANS_CONFIRMATION');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 3. Rapprochement
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok(
  $$ SELECT public.rapprochement_mobile_money('59000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'un parent n''a pas accès au rapprochement');
SELECT pg_temp.en_tant_que(:'dir_b_id');
SELECT throws_ok(
  $$ SELECT public.rapprochement_mobile_money('59000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'la Direction d''un autre établissement non plus');

SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.rapprochement_mobile_money('59000000-0000-0000-0000-000000000001') AS rappro \gset
SELECT is((:'rappro'::jsonb #>> '{confirmes,montant}')::numeric, 400000::numeric, 'montant confirmé du jour');
SELECT is((:'rappro'::jsonb ->> 'non_aboutis')::int, 2,
  'non aboutis du jour : l''orpheline et l''expirée');
SELECT is(jsonb_array_length(:'rappro'::jsonb -> 'anomalies'), 0, 'cas nominal : aucune anomalie');
RESET ROLE;

-- Anomalies : encaissement « OM: » saisi sans transaction, et annulation
-- après coup de l'encaissement automatique.
INSERT INTO public.encaissements_scolarite
  (etablissement_id, fiche_eleve_id, inscription_id, montant, moyen_paiement, reference_paiement, saisi_par)
VALUES ('59000000-0000-0000-0000-000000000001', :'fiche_id'::uuid, :'inscription_id'::uuid, 50000, 'mobile_money', 'OM:SAISIE-MANUELLE', :'dir_id'::uuid);
UPDATE public.encaissements_scolarite SET statut = 'annule', motif_annulation = 'Erreur de saisie'
 WHERE id = (SELECT encaissement_id FROM public.transactions_mobile_money WHERE id = '59000000-0000-0000-0000-0000000000a1');

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT results_eq(
  $$ SELECT a ->> 'type' FROM jsonb_array_elements(
       public.rapprochement_mobile_money('59000000-0000-0000-0000-000000000001') -> 'anomalies') a ORDER BY 1 $$,
  $$ VALUES ('ENCAISSEMENT_OM_ANNULE'), ('ENCAISSEMENT_OM_SANS_TRANSACTION'), ('PAIEMENT_SANS_ECRITURE') $$,
  'anomalies détectées : annulation après coup (et écriture devenue invalide), saisie OM sans transaction');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
