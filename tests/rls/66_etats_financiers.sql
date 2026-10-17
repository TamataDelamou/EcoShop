-- ============================================================================
-- EcoShop — Test RLS 66 : états financiers, produits constatés d'avance,
-- signaux d'aide sur pièces (REG-03 C4, migration 20260906001537)
--
-- Scénario SYSCOHADA (école privée, société) : apport en capital, achat de
-- matériel amorti, frais de scolarité encaissés (écriture automatique),
-- salaires. Vérifie :
--   • compte de résultat (TC, RK, RL, XI) et bilan (AM brut / amort / net,
--     BS, CA, CJ), équilibre actif = passif, tableau de trésorerie ;
--   • produits constatés d'avance : prorata de l'année scolaire au-delà du
--     31/12, pièce au 31/12, extourne au 1er janvier, une seule fois ;
--     résultat et bilan corrigés, équilibre maintenu ;
--   • SYCEBNL (présentation provisoire) et simplifié ;
--   • tendances, prévision de trésorerie et anomalies sur pièces ;
--   • droits.
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

-- Pièce validée en deux lignes : débit p_d / crédit p_c (codes de comptes).
CREATE OR REPLACE FUNCTION pg_temp.piece(p_etab uuid, p_journal uuid, p_date date, p_libelle text, p_d text, p_c text, p_montant numeric)
RETURNS text LANGUAGE sql AS $$
  SELECT public.valider_piece(public.enregistrer_piece(p_etab, p_journal, p_date, p_libelle, jsonb_build_array(
    jsonb_build_object('compte_id', (SELECT id FROM public.plans_comptables WHERE etablissement_id = p_etab AND code = p_d AND deleted_at IS NULL), 'debit', p_montant),
    jsonb_build_object('compte_id', (SELECT id FROM public.plans_comptables WHERE etablissement_id = p_etab AND code = p_c AND deleted_at IS NULL), 'credit', p_montant))));
$$;

CREATE OR REPLACE FUNCTION pg_temp.ligne(p_etat jsonb, p_ref text, p_champ text DEFAULT 'montant') RETURNS numeric
LANGUAGE sql AS $$
  SELECT (l->>p_champ)::numeric FROM jsonb_array_elements(p_etat->'lignes') l WHERE l->>'reference' = p_ref
   AND (l->>'etat') = CASE WHEN p_ref ~ '^(C|D)' THEN 'passif' WHEN p_ref ~ '^(A|B)' THEN 'actif' ELSE 'resultat' END
  LIMIT 1;
$$;

SELECT plan(29);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('66000000-0000-0000-0000-000000000001', 'Lycée Privé C4', 'lycee-c4-66', 'GNF'),
  ('66000000-0000-0000-0000-000000000002', 'École Église C4', 'eglise-c4-66', 'GNF'),
  ('66000000-0000-0000-0000-000000000003', 'École Simple C4', 'simple-c4-66', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('66000000-0000-0000-0000-000000000011', '66000000-0000-0000-0000-000000000001', '2026-2027', '2026-09-01', '2027-06-30', true),
  ('66000000-0000-0000-0000-000000000012', '66000000-0000-0000-0000-000000000002', '2026-2027', '2026-09-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('66000000-0000-0000-0000-000000000021', '66000000-0000-0000-0000-000000000001', '66000000-0000-0000-0000-000000000011', 'T1', 'Terminale'),
  ('66000000-0000-0000-0000-000000000022', '66000000-0000-0000-0000-000000000002', '66000000-0000-0000-0000-000000000012', 'CP', 'CP');

SELECT pg_temp.creer_compte('224666000001', 'direction') AS dir_id \gset
SELECT pg_temp.creer_compte('224666000002', 'parent') AS parent_id \gset
SELECT pg_temp.creer_compte('224666000003', 'direction') AS dir2_id \gset
SELECT pg_temp.creer_compte('224666000004', 'direction') AS dir3_id \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_id', '66000000-0000-0000-0000-000000000001', 'direction'),
  (:'parent_id', '66000000-0000-0000-0000-000000000001', 'parent'),
  (:'dir2_id', '66000000-0000-0000-0000-000000000002', 'direction'),
  (:'dir3_id', '66000000-0000-0000-0000-000000000003', 'direction');

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.choisir_referentiel_comptable('66000000-0000-0000-0000-000000000001', 'syscohada_normal', 'societe');
SELECT public.ouvrir_exercice('66000000-0000-0000-0000-000000000001', '2026-01-01', '2026-12-31') AS ex \gset
INSERT INTO public.journaux (etablissement_id, code, intitule, type)
VALUES ('66000000-0000-0000-0000-000000000001', 'OP', 'Opérations', 'operations') RETURNING id AS jop \gset

SELECT pg_temp.piece('66000000-0000-0000-0000-000000000001', :'jop', '2026-01-05', 'Apport en capital', '521', '101', 1000000);
SELECT pg_temp.piece('66000000-0000-0000-0000-000000000001', :'jop', '2026-01-10', 'Ordinateurs', '2442', '521', 600000);
SELECT pg_temp.piece('66000000-0000-0000-0000-000000000001', :'jop', '2026-09-30', 'Amortissement ordinateurs', '681', '284', 50000);
SELECT pg_temp.piece('66000000-0000-0000-0000-000000000001', :'jop', '2026-09-30', 'Salaires de septembre', '661', '571', 400000);

SELECT public.creer_inscription_nouvel_eleve('66000000-0000-0000-0000-000000000001', 'DIALLO', 'Aminata', '2008-04-02',
  '66000000-0000-0000-0000-000000000021', '66000000-0000-0000-0000-000000000011', 'F') AS fiche \gset
INSERT INTO public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, type_frais, montant, moyen_paiement, date_paiement)
SELECT '66000000-0000-0000-0000-000000000001', :'fiche', id, 'scolarite', 3030000, 'especes', '2026-09-10'
  FROM public.inscriptions WHERE fiche_eleve_id = :'fiche';

-- ---------------------------------------------------------------------------
-- 1. États financiers SYSCOHADA
-- ---------------------------------------------------------------------------
SELECT public.etat_financier('66000000-0000-0000-0000-000000000001', :'ex') AS e1 \gset
SELECT is(pg_temp.ligne(:'e1', 'TC'), 3030000::numeric, 'TC — travaux, services vendus : frais de scolarité');
SELECT is(pg_temp.ligne(:'e1', 'RK'), 400000::numeric, 'RK — charges de personnel');
SELECT is(pg_temp.ligne(:'e1', 'RL'), 50000::numeric, 'RL — dotations aux amortissements');
SELECT is(pg_temp.ligne(:'e1', 'XI'), 2580000::numeric, 'XI — résultat net');
SELECT is(pg_temp.ligne(:'e1', 'AM', 'brut')::bigint || '|' || pg_temp.ligne(:'e1', 'AM', 'amortissements')::bigint || '|' || pg_temp.ligne(:'e1', 'AM')::bigint,
  '600000|50000|550000', 'AM — matériel : brut, amortissements, net');
SELECT is(pg_temp.ligne(:'e1', 'BS'), 3030000::numeric, 'BS — banque et caisse');
SELECT is(pg_temp.ligne(:'e1', 'CA'), 1000000::numeric, 'CA — capital');
SELECT is(pg_temp.ligne(:'e1', 'CJ'), 2580000::numeric, 'CJ — résultat porté au passif');
SELECT is((:'e1'::jsonb->>'total_actif')::numeric, 3580000::numeric, 'BZ — total actif');
SELECT ok((:'e1'::jsonb->>'equilibre')::boolean, 'bilan équilibré : actif = passif');
SELECT is(jsonb_array_length(:'e1'::jsonb->'non_classes'), 0, 'aucun compte laissé hors des états');
SELECT is((:'e1'::jsonb->'tresorerie'->>'solde_fin')::numeric, 3030000::numeric, 'tableau de trésorerie : solde de fin');

-- ---------------------------------------------------------------------------
-- 2. Produits constatés d'avance
-- ---------------------------------------------------------------------------
SELECT is((public.apercu_produits_constates_avance(:'ex')->>'total')::numeric, 1810000::numeric,
  'aperçu : 181 jours sur 303 de l''année scolaire après le 31/12 → 1 810 000');
SELECT public.passer_produits_constates_avance(:'ex') AS pca \gset
SELECT is((:'pca'::jsonb->>'montant')::numeric, 1810000::numeric, 'PCA passés');
SELECT is((SELECT reference || '|' || date_piece FROM public.pieces_comptables WHERE id = (:'pca'::jsonb->>'piece_id')::uuid),
  'OD-2026-000001|2026-12-31', 'pièce datée du 31/12 au journal OD');
SELECT is((SELECT reference || '|' || date_piece FROM public.pieces_comptables WHERE id = (:'pca'::jsonb->>'extourne_id')::uuid),
  'OD-2027-000001|2027-01-01', 'extourne au 1er janvier de l''exercice suivant');
SELECT throws_ok(format($$SELECT public.passer_produits_constates_avance(%L)$$, :'ex'), 'PCA_DEJA_PASSES',
  'une seule fois par exercice');
SELECT public.etat_financier('66000000-0000-0000-0000-000000000001', :'ex') AS e2 \gset
SELECT is(pg_temp.ligne(:'e2', 'XI'), 770000::numeric, 'résultat corrigé : seule la part de l''exercice reste en produit');
SELECT is(pg_temp.ligne(:'e2', 'DM'), 1810000::numeric, 'les produits constatés d''avance figurent au passif');
SELECT ok((:'e2'::jsonb->>'equilibre')::boolean, 'bilan toujours équilibré');

SELECT public.cloturer_exercice(:'ex');
SELECT is((SELECT solde_credit FROM public.balance_comptable('66000000-0000-0000-0000-000000000001', '2027-01-02') WHERE code = '70611'),
  1810000::numeric, '2027 : la part reportée revient en produit dès le 1er janvier');
SELECT is((SELECT solde_debit + solde_credit FROM public.balance_comptable('66000000-0000-0000-0000-000000000001', '2027-01-02') WHERE code = '477'),
  0::numeric, 'et le compte 477 est soldé');

-- ---------------------------------------------------------------------------
-- 3. Signaux d'aide sur pièces
-- ---------------------------------------------------------------------------
SELECT is((SELECT total_produits FROM public.analyser_tendances('66000000-0000-0000-0000-000000000001', 24) WHERE mois = '2026-09-01'),
  3030000::numeric, 'tendances : les pièces (automatiques comprises) sont prises en compte');
SELECT pg_temp.piece('66000000-0000-0000-0000-000000000001', (SELECT id FROM public.journaux WHERE etablissement_id = '66000000-0000-0000-0000-000000000001' AND code = 'OP'),
  '2027-01-15', 'Fournitures', '6055', '571', 25000);
SELECT pg_temp.piece('66000000-0000-0000-0000-000000000001', (SELECT id FROM public.journaux WHERE etablissement_id = '66000000-0000-0000-0000-000000000001' AND code = 'OP'),
  '2027-01-15', 'Fournitures', '6055', '571', 25000);
SELECT is((SELECT count(*)::int FROM public.detecter_anomalies_comptables('66000000-0000-0000-0000-000000000001') WHERE anomalie = 'double_saisie'),
  2, 'anomalies : double saisie détectée sur les pièces');
SELECT is((SELECT count(*)::int FROM public.predire_tresorerie('66000000-0000-0000-0000-000000000001', 30)), 31,
  'prévision de trésorerie disponible sur 30 jours');

-- ---------------------------------------------------------------------------
-- 4. SYCEBNL et simplifié
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir2_id');
SELECT public.choisir_referentiel_comptable('66000000-0000-0000-0000-000000000002', 'sycebnl', 'confessionnelle');
SELECT public.ouvrir_exercice('66000000-0000-0000-0000-000000000002', '2026-01-01', '2026-12-31') AS ex2 \gset
SELECT public.creer_inscription_nouvel_eleve('66000000-0000-0000-0000-000000000002', 'SOW', 'Ibrahima', '2019-01-01',
  '66000000-0000-0000-0000-000000000022', '66000000-0000-0000-0000-000000000012', 'M') AS fiche2 \gset
INSERT INTO public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, type_frais, montant, moyen_paiement, date_paiement)
SELECT '66000000-0000-0000-0000-000000000002', :'fiche2', id, 'scolarite', 900000, 'mobile_money', '2026-09-15'
  FROM public.inscriptions WHERE fiche_eleve_id = :'fiche2';
SELECT public.etat_financier('66000000-0000-0000-0000-000000000002', :'ex2') AS e3 \gset
SELECT is((SELECT (l->>'montant')::numeric FROM jsonb_array_elements(:'e3'::jsonb->'lignes') l WHERE l->>'reference' = 'P3'),
  900000::numeric, 'SYCEBNL : frais scolaires en « ventes et prestations »');
SELECT ok((:'e3'::jsonb->>'provisoire')::boolean AND (:'e3'::jsonb->>'equilibre')::boolean,
  'SYCEBNL : équilibré, signalé comme présentation provisoire');

SELECT pg_temp.en_tant_que(:'dir3_id');
INSERT INTO public.journaux (etablissement_id, code, intitule, type)
VALUES ('66000000-0000-0000-0000-000000000003', 'OD', 'Opérations', 'operations') RETURNING id AS j3 \gset
INSERT INTO public.plans_comptables (etablissement_id, code, intitule, type) VALUES
  ('66000000-0000-0000-0000-000000000003', 'CAISSE', 'Caisse', 'caisse'),
  ('66000000-0000-0000-0000-000000000003', 'SCOL', 'Scolarité', 'produit');
INSERT INTO public.ecritures_comptables (etablissement_id, libelle, compte_debit_id, compte_credit_id, montant, journal_id, date_ecriture)
SELECT '66000000-0000-0000-0000-000000000003', 'Scolarité',
  (SELECT id FROM public.plans_comptables WHERE etablissement_id = '66000000-0000-0000-0000-000000000003' AND code = 'CAISSE'),
  (SELECT id FROM public.plans_comptables WHERE etablissement_id = '66000000-0000-0000-0000-000000000003' AND code = 'SCOL'),
  200000, :'j3', '2026-03-01';
SELECT public.ouvrir_exercice('66000000-0000-0000-0000-000000000003', '2026-01-01', '2026-12-31') AS ex3 \gset
SELECT public.etat_financier('66000000-0000-0000-0000-000000000003', :'ex3') AS e4 \gset
SELECT ok((:'e4'::jsonb->>'equilibre')::boolean AND (:'e4'::jsonb->>'resultat')::numeric = 200000,
  'simplifié : bilan et compte de résultat par nature de compte, équilibrés');

-- ---------------------------------------------------------------------------
-- 5. Droits
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok(format($$SELECT public.etat_financier('66000000-0000-0000-0000-000000000001', %L)$$, :'ex'), '42501', NULL,
  'un parent ne voit pas les états financiers');

SELECT * FROM finish();
ROLLBACK;
