-- ============================================================================
-- EcoShop — Test RLS 58 : Orange Money Guinée, circuit établissement
-- (REG-02 lot L1, migrations 20260906001528 / 20260906001529)
--
-- Couvre :
--   • activation (identifiants marchands) réservée à la Direction de
--     l'établissement concerné ; identifiants jamais lisibles par un client,
--     y compris par cette Direction ;
--   • initiation scolarité : payeur limité à l'élève lui-même ou un parent
--     confirmé, montant borné par le solde calculé serveur, GNF entiers,
--     refus sans sous-compte Orange actif, une seule transaction en cours ;
--   • aucune écriture directe sur transactions_mobile_money ; visibilité
--     payeur / personnel, isolation inter-établissement ;
--   • traiter_resultat_mobile_money() réservée à service_role ; écart de
--     montant refusé ; succès => encaissement de scolarité « mobile_money »
--     créé (saisi_par = payeur) et solde recalculé ; notification rejouée
--     sans double crédit ; journalisation du statut ;
--   • marketplace : seul l'acheteur paie sa commande, montant = total +
--     frais (jamais celui du client), succès => paiement « orange_money_gn »
--     + commande « payee », échec => rien n'est crédité.
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

SELECT plan(32);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (id, nom, slug, devise_code)
VALUES ('58000000-0000-0000-0000-000000000001', 'École pilote OM', 'ecole-pilote-om-58', 'GNF'),
       ('58000000-0000-0000-0000-000000000099', 'École B OM', 'ecole-b-om-58', 'GNF');

INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('58000000-0000-0000-0000-000000000002', '58000000-0000-0000-0000-000000000001', '2026-2027', '2026-10-01', '2027-06-30', true);

INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom)
VALUES ('58000000-0000-0000-0000-000000000003', '58000000-0000-0000-0000-000000000001',
        '58000000-0000-0000-0000-000000000002', '6A-OM', '6e A');

INSERT INTO public.frais_scolarite_config (etablissement_id, annee_scolaire_id, niveau_id, montant_annuel)
VALUES ('58000000-0000-0000-0000-000000000001', '58000000-0000-0000-0000-000000000002', null, 1500000);

SELECT pg_temp.creer_compte('224658000001', 'direction') AS dir_id      \gset
SELECT pg_temp.creer_compte('224658000002', 'parent')    AS parent_id   \gset
SELECT pg_temp.creer_compte('224658000003', 'eleve')     AS etranger_id \gset
SELECT pg_temp.creer_compte('224658000004', 'direction') AS dir_b_id    \gset
SELECT pg_temp.creer_compte('224658000005', 'parent')    AS acheteur_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_id'::uuid, '58000000-0000-0000-0000-000000000001', 'direction'),
       (:'dir_b_id'::uuid, '58000000-0000-0000-0000-000000000099', 'direction');

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.creer_inscription_nouvel_eleve(
  '58000000-0000-0000-0000-000000000001', 'BAH', 'Aïssatou', '2014-02-03',
  '58000000-0000-0000-0000-000000000003', '58000000-0000-0000-0000-000000000002', 'F'
) AS fiche_id \gset
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
VALUES ('58000000-0000-0000-0000-000000000001', :'parent_id'::uuid, :'fiche_id'::uuid, 'parent', 'confirmee', true);
RESET ROLE;

SELECT id AS inscription_id FROM public.inscriptions WHERE fiche_eleve_id = :'fiche_id'::uuid \gset

-- ---------------------------------------------------------------------------
-- 1. Activation et confidentialité des identifiants
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok(
  $$ SELECT public.enregistrer_identifiants_orange_money('58000000-0000-0000-0000-000000000001', 'cid', 'csecret', 'mkey') $$,
  '42501', NULL, 'un parent ne peut pas activer Orange Money pour l''établissement');

SELECT pg_temp.en_tant_que(:'dir_b_id');
SELECT throws_ok(
  $$ SELECT public.enregistrer_identifiants_orange_money('58000000-0000-0000-0000-000000000001', 'cid', 'csecret', 'mkey') $$,
  '42501', NULL, 'la Direction d''un AUTRE établissement ne peut pas activer Orange Money');

SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok(
  format($$ SELECT public.initier_transaction_mobile_money('scolarite', %L, 500000) $$, :'inscription_id'),
  '55000', 'ORANGE_MONEY_NON_ACTIVE', 'initiation refusée tant qu''Orange Money n''est pas activé');

SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.enregistrer_identifiants_orange_money(
  '58000000-0000-0000-0000-000000000001', 'client-58', 'secret-58', 'MERCHANTKEY0058', 'test'
) AS sous_compte_id \gset
SELECT isnt(:'sous_compte_id'::uuid, NULL::uuid, 'la Direction active Orange Money (sous-compte créé)');

SELECT is(
  (SELECT reference_compte FROM public.sous_comptes_marchands WHERE id = :'sous_compte_id'::uuid),
  'OM-0058', 'la référence publique du sous-compte ne contient jamais la clé complète');

SELECT throws_ok($$ SELECT * FROM public.secrets_sous_comptes_marchands $$, '42501', NULL,
  'identifiants illisibles même pour la Direction de l''établissement');
SELECT throws_ok(format($$ SELECT public.lire_identifiants_sous_compte(%L) $$, :'sous_compte_id'), '42501', NULL,
  'lire_identifiants_sous_compte refusée à un client');

-- ---------------------------------------------------------------------------
-- 2. Initiation scolarité
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'etranger_id');
SELECT throws_ok(
  format($$ SELECT public.initier_transaction_mobile_money('scolarite', %L, 500000) $$, :'inscription_id'),
  '42501', NULL, 'un tiers sans lien avec l''élève ne peut pas payer');

SELECT pg_temp.en_tant_que(:'dir_id');
SELECT throws_ok(
  format($$ SELECT public.initier_transaction_mobile_money('scolarite', %L, 500000) $$, :'inscription_id'),
  '42501', NULL, 'le personnel ne paie pas en ligne (encaissement manuel au guichet)');

SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok(
  format($$ SELECT public.initier_transaction_mobile_money('scolarite', %L, 2000000) $$, :'inscription_id'),
  '22023', 'MONTANT_SUPERIEUR_AU_SOLDE', 'montant borné par le solde calculé serveur');
SELECT throws_ok(
  format($$ SELECT public.initier_transaction_mobile_money('scolarite', %L, 1000.5) $$, :'inscription_id'),
  '22023', 'MONTANT_GNF_ENTIER_REQUIS', 'GNF : montant entier exigé');

SELECT (public.initier_transaction_mobile_money('scolarite', :'inscription_id'::uuid, 500000)) ->> 'transaction_id' AS tx1 \gset
SELECT is((SELECT montant FROM public.transactions_mobile_money WHERE id = :'tx1'::uuid), 500000::numeric(12,2),
  'parent confirmé : transaction initiée au montant demandé');

SELECT throws_ok(
  format($$ SELECT public.initier_transaction_mobile_money('scolarite', %L, 100000) $$, :'inscription_id'),
  '55000', 'PAIEMENT_DEJA_EN_COURS', 'une seule transaction en cours par inscription');

SELECT throws_ok(
  format($$ UPDATE public.transactions_mobile_money SET statut = 'reussi' WHERE id = %L $$, :'tx1'),
  '42501', NULL, 'le payeur ne peut pas modifier sa transaction directement');

SELECT is((SELECT count(*) FROM public.transactions_mobile_money WHERE id = :'tx1'::uuid), 1::bigint,
  'le payeur voit sa transaction');

SELECT pg_temp.en_tant_que(:'dir_b_id');
SELECT is((SELECT count(*) FROM public.transactions_mobile_money WHERE id = :'tx1'::uuid), 0::bigint,
  'isolation : la Direction d''un autre établissement ne la voit pas');

SELECT throws_ok(
  format($$ SELECT public.traiter_resultat_mobile_money(%L, 'reussi', 500000, 'OM123') $$, :'tx1'),
  '42501', NULL, 'traiter_resultat_mobile_money refusée à un client');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 3. Traitement serveur (service_role)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

SELECT is(public.traiter_resultat_mobile_money(:'tx1'::uuid, 'reussi', 499000, 'OM-ECART'), 'ecart_montant',
  'écart entre montant confirmé et montant attendu : refusé');
SELECT is((SELECT count(*) FROM public.encaissements_scolarite WHERE inscription_id = :'inscription_id'::uuid), 0::bigint,
  'aucun encaissement après un écart de montant');
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'parent_id');
SELECT (public.initier_transaction_mobile_money('scolarite', :'inscription_id'::uuid, 500000)) ->> 'transaction_id' AS tx2 \gset
RESET ROLE;

SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT is(public.traiter_resultat_mobile_money(:'tx2'::uuid, 'reussi', 500000, 'OM-778899'), 'reussi',
  'paiement confirmé : crédité');
SELECT is(public.traiter_resultat_mobile_money(:'tx2'::uuid, 'reussi', 500000, 'OM-778899'), 'deja_traitee',
  'notification rejouée : sans effet');
RESET ROLE;

SELECT is((SELECT count(*) FROM public.encaissements_scolarite WHERE inscription_id = :'inscription_id'::uuid), 1::bigint,
  'un seul encaissement malgré la notification rejouée');
SELECT results_eq(
  format($$ SELECT moyen_paiement::text, montant, saisi_par, reference_paiement FROM public.encaissements_scolarite WHERE inscription_id = %L $$, :'inscription_id'),
  format($$ VALUES ('mobile_money', 500000::numeric(12,2), %L::uuid, 'OM:OM-778899') $$, :'parent_id'),
  'encaissement mobile_money créé, saisi_par = payeur, référence opérateur conservée');
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'parent_id');
SELECT is((SELECT solde FROM public.solde_scolarite(:'inscription_id'::uuid)), 1000000::numeric,
  'le solde de scolarité se recalcule aussitôt (vu par le parent)');
RESET ROLE;
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'transaction_mobile_money' AND entite_id = :'tx2'::uuid), 1::bigint,
  'le changement de statut est journalisé');

-- ---------------------------------------------------------------------------
-- 4. Marketplace
-- ---------------------------------------------------------------------------
INSERT INTO public.commercants (nom) VALUES ('Vendeur 58') RETURNING id AS comm_id \gset
INSERT INTO public.commandes (etablissement_id, commercant_id, profile_id, reference, statut, montant_total, montant_frais, devise)
VALUES ('58000000-0000-0000-0000-000000000001', :'comm_id'::uuid, :'acheteur_id'::uuid, 'CMD-58-1', 'confirmee', 120000, 5000, 'GNF')
RETURNING id AS cmd1 \gset
INSERT INTO public.commandes (etablissement_id, commercant_id, profile_id, reference, statut, montant_total, montant_frais, devise)
VALUES ('58000000-0000-0000-0000-000000000001', :'comm_id'::uuid, :'acheteur_id'::uuid, 'CMD-58-2', 'confirmee', 30000, 0, 'GNF')
RETURNING id AS cmd2 \gset

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok(
  format($$ SELECT public.initier_transaction_mobile_money('commande_marketplace', %L) $$, :'cmd1'),
  '42501', NULL, 'on ne paie pas la commande d''un autre');

SELECT pg_temp.en_tant_que(:'acheteur_id');
SELECT (public.initier_transaction_mobile_money('commande_marketplace', :'cmd1'::uuid, 1)) ->> 'transaction_id' AS tx3 \gset
SELECT is((SELECT montant FROM public.transactions_mobile_money WHERE id = :'tx3'::uuid), 125000::numeric(12,2),
  'montant de commande = total + frais, le montant du client est ignoré');
SELECT (public.initier_transaction_mobile_money('commande_marketplace', :'cmd2'::uuid)) ->> 'transaction_id' AS tx4 \gset
RESET ROLE;

SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT is(public.traiter_resultat_mobile_money(:'tx3'::uuid, 'reussi', 125000, 'OM-CMD1'), 'reussi', 'commande payée');
SELECT is(public.traiter_resultat_mobile_money(:'tx4'::uuid, 'echoue', NULL, NULL, 'refusé par le client'), 'echoue', 'échec enregistré');
RESET ROLE;

SELECT results_eq(
  format($$ SELECT fournisseur::text, statut::text, montant FROM public.paiements WHERE commande_id = %L $$, :'cmd1'),
  $$ VALUES ('orange_money_gn', 'reussi', 125000::numeric(12,2)) $$,
  'paiement marketplace « orange_money_gn » créé');
SELECT is((SELECT statut::text FROM public.commandes WHERE id = :'cmd1'::uuid), 'payee', 'commande passée en « payee »');
SELECT ok(
  (SELECT count(*) FROM public.paiements WHERE commande_id = :'cmd2'::uuid) = 0
  AND (SELECT statut::text FROM public.commandes WHERE id = :'cmd2'::uuid) = 'confirmee',
  'paiement échoué : ni paiement crédité ni changement de commande');

SELECT * FROM finish();
ROLLBACK;
