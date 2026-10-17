-- ============================================================================
-- EcoShop — Test RLS 67 : la paie passe en comptabilité
-- (REG-03 C5, migration 20260906001538)
--
-- Couvre :
--   • bulletin brouillon : rien ; validé → constatation (661 / 422 / 447),
--     datée de la fin de période, journal PAIE ; payé → règlement (422 / 571) ;
--   • idempotence : une resynchronisation ne crée rien ;
--   • bulletin modifié après validation → contre-passation puis nouvelle
--     constatation au bon montant ; ramené en brouillon → tout est annulé ;
--   • archivage et suppression définitive → contre-passation ;
--   • sans exercice ouvert : la paie passe, un incident est consigné, le
--     rattrapage le résout ;
--   • SYCEBNL : comptes 66 / 422 / 44 ; état « paies à synchroniser » ;
--   • droits : fonctions internes inaccessibles, pièce non annulable à la main ;
--   • comptabilité simplifiée sans règles : rien d'automatique.
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

-- Écritures d'une pièce sous la forme « code:débit/crédit ».
CREATE OR REPLACE FUNCTION pg_temp.lignes(p_piece uuid) RETURNS text
LANGUAGE sql AS $$
  SELECT string_agg(c.code || ':' || l.debit::bigint || '/' || l.credit::bigint, ' ' ORDER BY l.ordre)
    FROM public.lignes_pieces_comptables l JOIN public.plans_comptables c ON c.id = l.compte_id
   WHERE l.piece_id = p_piece;
$$;

-- Pièce automatique active d'un bulletin.
CREATE OR REPLACE FUNCTION pg_temp.piece(p_bulletin uuid, p_type text) RETURNS uuid
LANGUAGE sql AS $$
  SELECT id FROM public.pieces_comptables
   WHERE source_id = p_bulletin AND source_type = p_type AND origine = 'automatique'
     AND annulee_par_piece_id IS NULL;
$$;

SELECT plan(31);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('67000000-0000-0000-0000-000000000001', 'Lycée Paie C5', 'lycee-paie-67', 'GNF'),
  ('67000000-0000-0000-0000-000000000002', 'École Bambino Paie', 'bambino-paie-67', 'GNF'),
  ('67000000-0000-0000-0000-000000000003', 'École Simple Paie', 'simple-paie-67', 'GNF');

SELECT pg_temp.creer_compte('224667000001', 'direction') AS dir_id \gset
SELECT pg_temp.creer_compte('224667000002', 'enseignant') AS ens_id \gset
SELECT pg_temp.creer_compte('224667000003', 'direction') AS dir2_id \gset
SELECT pg_temp.creer_compte('224667000004', 'enseignant') AS ens2_id \gset
SELECT pg_temp.creer_compte('224667000005', 'direction') AS dir3_id \gset
SELECT pg_temp.creer_compte('224667000006', 'enseignant') AS ens3_id \gset
UPDATE public.profiles SET nom = 'SYLLA', prenom = 'Aïssata' WHERE id = :'ens_id';
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_id', '67000000-0000-0000-0000-000000000001', 'direction'),
  (:'ens_id', '67000000-0000-0000-0000-000000000001', 'enseignant'),
  (:'dir2_id', '67000000-0000-0000-0000-000000000002', 'direction'),
  (:'ens2_id', '67000000-0000-0000-0000-000000000002', 'enseignant'),
  (:'dir3_id', '67000000-0000-0000-0000-000000000003', 'direction'),
  (:'ens3_id', '67000000-0000-0000-0000-000000000003', 'enseignant');

INSERT INTO public.employes (etablissement_id, profile_id, matricule, categorie, date_embauche) VALUES
  ('67000000-0000-0000-0000-000000000001', :'ens_id', 'P-01', 'enseignant', '2024-09-01'),
  ('67000000-0000-0000-0000-000000000002', :'ens2_id', 'P-02', 'enseignant', '2024-09-01'),
  ('67000000-0000-0000-0000-000000000003', :'ens3_id', 'P-03', 'enseignant', '2024-09-01');
INSERT INTO public.contrats (etablissement_id, employe_id, type, date_debut, salaire_base)
SELECT etablissement_id, id, 'cdi', '2026-01-01', 2000000 FROM public.employes
 WHERE etablissement_id::text LIKE '67000000-%';

CREATE OR REPLACE FUNCTION pg_temp.bulletin(p_etab uuid, p_mois int, p_base numeric, p_primes numeric, p_retenues numeric)
RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.paie_bulletins
    (etablissement_id, employe_id, contrat_id, periode_debut, periode_fin, salaire_base, primes, retenues, net)
  SELECT p_etab, e.id, c.id, make_date(2026, p_mois, 1),
         (make_date(2026, p_mois, 1) + interval '1 month - 1 day')::date, p_base, p_primes, p_retenues, 0
    FROM public.employes e JOIN public.contrats c ON c.employe_id = e.id
   WHERE e.etablissement_id = p_etab
  RETURNING id;
$$;

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.choisir_referentiel_comptable('67000000-0000-0000-0000-000000000001', 'syscohada_normal', 'societe');
SELECT public.ouvrir_exercice('67000000-0000-0000-0000-000000000001', '2026-01-01', '2026-12-31');

-- ---------------------------------------------------------------------------
-- 1. Brouillon → validé → payé (SYSCOHADA)
-- ---------------------------------------------------------------------------
SELECT pg_temp.bulletin('67000000-0000-0000-0000-000000000001', 9, 2000000, 300000, 230000) AS b1 \gset
SELECT is((SELECT count(*)::int FROM public.pieces_comptables WHERE source_id = :'b1'::uuid), 0,
  'bulletin brouillon : aucune pièce');

UPDATE public.paie_bulletins SET statut = 'valide' WHERE id = :'b1';
SELECT pg_temp.piece(:'b1', 'paie_constatation') AS c1 \gset
SELECT is(pg_temp.lignes(:'c1'), '661:2300000/0 422:0/2070000 447:0/230000',
  'validé → constatation : D 661 brut, C 422 net, C 447 retenues');
SELECT is((SELECT left(reference, 9) || '|' || statut || '|' || date_piece FROM public.pieces_comptables WHERE id = :'c1'),
  'PAIE-2026|validee|2026-09-30', 'pièce validée, numérotée dans le journal PAIE, datée de la fin de période');
SELECT ok((SELECT libelle = 'Salaire 09/2026 — SYLLA Aïssata' FROM public.pieces_comptables WHERE id = :'c1'),
  'libellé : mois et nom du salarié');

UPDATE public.paie_bulletins SET statut = 'paye' WHERE id = :'b1';
SELECT pg_temp.piece(:'b1', 'paie_reglement') AS r1 \gset
SELECT is(pg_temp.lignes(:'r1'), '422:2070000/0 571:0/2070000', 'payé → règlement : D 422, C 571');
SELECT is((SELECT date_piece FROM public.pieces_comptables WHERE id = :'r1'), greatest(current_date, '2026-09-30'::date),
  'règlement daté du jour du paiement');
SELECT is((SELECT solde_credit FROM public.balance_comptable('67000000-0000-0000-0000-000000000001', '2026-12-31') WHERE code = '422'),
  0::numeric, 'la dette envers le salarié est soldée');

RESET ROLE;
SELECT is(public.synchroniser_paie(:'b1'), 'a_jour', 'idempotent : resynchroniser ne crée rien');
SELECT is((SELECT count(*)::int FROM public.pieces_comptables WHERE source_id = :'b1'::uuid), 2, 'toujours deux pièces');
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');

-- ---------------------------------------------------------------------------
-- 2. Modification après coup
-- ---------------------------------------------------------------------------
UPDATE public.paie_bulletins SET primes = 500000 WHERE id = :'b1';
SELECT is((SELECT origine FROM public.pieces_comptables WHERE piece_annulee_id = :'c1'), 'contrepassation',
  'prime corrigée → l''ancienne constatation est contre-passée');
SELECT is((SELECT origine FROM public.pieces_comptables WHERE piece_annulee_id = :'r1'), 'contrepassation',
  '… ainsi que l''ancien règlement');
SELECT is(pg_temp.lignes(pg_temp.piece(:'b1', 'paie_constatation')), '661:2500000/0 422:0/2270000 447:0/230000',
  'nouvelle constatation au bon montant');
SELECT is(pg_temp.lignes(pg_temp.piece(:'b1', 'paie_reglement')), '422:2270000/0 571:0/2270000',
  'nouveau règlement au bon montant');
SELECT is((SELECT source_type FROM public.pieces_comptables WHERE id = :'c1'), 'paie_constatation_annulee',
  'l''ancienne pièce reste au journal, marquée comme remplacée');
SELECT is((SELECT solde_debit FROM public.balance_comptable('67000000-0000-0000-0000-000000000001', '2026-12-31') WHERE code = '661'),
  2500000::numeric, 'charges de personnel = le bulletin corrigé, une seule fois');

UPDATE public.paie_bulletins SET statut = 'brouillon' WHERE id = :'b1';
SELECT ok(pg_temp.piece(:'b1', 'paie_constatation') IS NULL AND pg_temp.piece(:'b1', 'paie_reglement') IS NULL,
  'ramené en brouillon → plus aucune pièce active');
SELECT is((SELECT coalesce(sum(solde_debit + solde_credit), 0) FROM public.balance_comptable('67000000-0000-0000-0000-000000000001', '2026-12-31')
            WHERE code IN ('661', '422', '447', '571')), 0::numeric, 'tous les comptes de paie reviennent à zéro');

-- ---------------------------------------------------------------------------
-- 3. Archivage et suppression définitive
-- ---------------------------------------------------------------------------
SELECT pg_temp.bulletin('67000000-0000-0000-0000-000000000001', 10, 2000000, 0, 0) AS b2 \gset
UPDATE public.paie_bulletins SET statut = 'valide' WHERE id = :'b2';
SELECT pg_temp.piece(:'b2', 'paie_constatation') AS c2 \gset
UPDATE public.paie_bulletins SET deleted_at = now() WHERE id = :'b2';
SELECT ok(pg_temp.piece(:'b2', 'paie_constatation') IS NULL AND EXISTS (SELECT 1 FROM public.pieces_comptables WHERE piece_annulee_id = :'c2'),
  'bulletin archivé → constatation contre-passée');

SELECT pg_temp.bulletin('67000000-0000-0000-0000-000000000001', 11, 2000000, 0, 0) AS b3 \gset
UPDATE public.paie_bulletins SET statut = 'paye' WHERE id = :'b3';
SELECT is((SELECT count(*)::int FROM public.pieces_comptables WHERE source_id = :'b3'::uuid), 2,
  'validé et payé d''un coup : constatation et règlement');
DELETE FROM public.paie_bulletins WHERE id = :'b3';
SELECT is((SELECT count(*)::int FROM public.pieces_comptables p
            WHERE p.source_id = :'b3'::uuid AND p.origine = 'automatique' AND p.annulee_par_piece_id IS NOT NULL), 2,
  'suppression définitive → les deux pièces sont contre-passées');

-- ---------------------------------------------------------------------------
-- 4. Droits
-- ---------------------------------------------------------------------------
SELECT throws_ok(format($$SELECT public.synchroniser_paie(%L)$$, :'b1'), '42501', NULL,
  'fonction interne de synchronisation inaccessible');

-- ---------------------------------------------------------------------------
-- 5. SYCEBNL, sans exercice puis rattrapage
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir2_id');
SELECT public.choisir_referentiel_comptable('67000000-0000-0000-0000-000000000002', 'sycebnl', 'confessionnelle');
SELECT pg_temp.bulletin('67000000-0000-0000-0000-000000000002', 9, 1500000, 0, 100000) AS b4 \gset
UPDATE public.paie_bulletins SET statut = 'valide' WHERE id = :'b4';
SELECT is((SELECT count(*)::int FROM public.paie_bulletins WHERE id = :'b4' AND statut = 'valide'), 1,
  'la comptabilité ne bloque jamais la paie');
SELECT is((SELECT code FROM public.incidents_comptabilisation WHERE source_id = :'b4' AND NOT resolu), 'AUCUN_EXERCICE_OUVERT',
  'incident consigné : aucun exercice ouvert');
SELECT is((public.etat_comptabilisation_automatique('67000000-0000-0000-0000-000000000002')->>'paies_a_synchroniser')::int, 1,
  'état : une paie à synchroniser');
SELECT is((SELECT r->>'compte_code' FROM jsonb_array_elements(
             public.etat_comptabilisation_automatique('67000000-0000-0000-0000-000000000002')->'regles') r
            WHERE r->>'cle' = 'paie:retenues'), '44', 'comptes de paie affichés (retenues → 44 en SYCEBNL)');

SELECT public.ouvrir_exercice('67000000-0000-0000-0000-000000000002', '2026-01-01', '2026-12-31');
SELECT is(public.comptabiliser_en_attente('67000000-0000-0000-0000-000000000002')->>'comptabilises', '1',
  'rattrapage : la paie en attente est comptabilisée');
SELECT is(pg_temp.lignes(pg_temp.piece(:'b4', 'paie_constatation')), '66:1500000/0 422:0/1400000 44:0/100000',
  'SYCEBNL : D 66, C 422, C 44');
SELECT is((SELECT count(*)::int FROM public.incidents_comptabilisation WHERE source_id = :'b4' AND NOT resolu), 0,
  'et l''incident est résolu');
SELECT throws_ok(format($$SELECT public.contrepasser_piece(%L, 'À la main', '2026-12-01')$$, pg_temp.piece(:'b4', 'paie_constatation')),
  'PIECE_AUTOMATIQUE', 'une pièce de paie ne s''annule pas à la main : on corrige le bulletin');

-- ---------------------------------------------------------------------------
-- 6. Comptabilité simplifiée sans règles « paie »
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir3_id');
SELECT pg_temp.bulletin('67000000-0000-0000-0000-000000000003', 9, 1000000, 0, 0) AS b5 \gset
UPDATE public.paie_bulletins SET statut = 'paye' WHERE id = :'b5';
SELECT is((SELECT count(*)::int FROM public.pieces_comptables WHERE source_id = :'b5'::uuid)
        + (SELECT count(*)::int FROM public.incidents_comptabilisation WHERE source_id = :'b5'::uuid), 0,
  'simplifié sans règles : ni pièce ni incident');
SELECT is((public.etat_comptabilisation_automatique('67000000-0000-0000-0000-000000000003')->>'paies_a_synchroniser')::int, 0,
  'et rien à synchroniser');

SELECT * FROM finish();
ROLLBACK;
