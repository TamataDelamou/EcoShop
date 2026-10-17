-- ============================================================================
-- EcoShop — Test RLS 65 : comptabilisation automatique des encaissements
-- (REG-03 C3, migration 20260906001536)
--
-- Couvre :
--   • sans exercice ouvert : l'encaissement passe, un incident est consigné ;
--     le rattrapage le comptabilise ensuite et résout l'incident ;
--   • pièce automatique validée : bon journal (CAI / OM), bons comptes
--     (571 / 5521 ; 70521 / 70522 en SYCEBNL), numérotée, liée à l'encaissement ;
--   • idempotence : une seule pièce par encaissement ;
--   • annulation de l'encaissement → contre-passation automatique ; une
--     pièce automatique ne s'annule pas à la main ;
--   • période clôturée : encaissement accepté, incident consigné ;
--   • état : non comptabilisés, incidents, comptes effectifs ;
--   • règles de l'école : compte de regroupement refusé, sous-compte accepté
--     et utilisé ensuite ;
--   • droits : parent refusé, fonctions internes inaccessibles ;
--   • comptabilité simplifiée sans règles : rien d'automatique, aucun incident.
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

SELECT plan(29);

INSERT INTO public.etablissements (id, nom, slug, devise_code)
VALUES ('65000000-0000-0000-0000-000000000001', 'École Bambino C3', 'bambino-c3-65', 'GNF'),
       ('65000000-0000-0000-0000-000000000099', 'École Simple C3', 'simple-c3-65', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('65000000-0000-0000-0000-000000000002', '65000000-0000-0000-0000-000000000001', '2026-2027', '2026-09-01', '2027-06-30', true),
  ('65000000-0000-0000-0000-000000000092', '65000000-0000-0000-0000-000000000099', '2026-2027', '2026-09-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('65000000-0000-0000-0000-000000000003', '65000000-0000-0000-0000-000000000001', '65000000-0000-0000-0000-000000000002', '6A', '6e A'),
  ('65000000-0000-0000-0000-000000000093', '65000000-0000-0000-0000-000000000099', '65000000-0000-0000-0000-000000000092', '6A', '6e A');

SELECT pg_temp.creer_compte('224665000001', 'direction') AS dir_id \gset
SELECT pg_temp.creer_compte('224665000002', 'parent') AS parent_id \gset
SELECT pg_temp.creer_compte('224665000003', 'direction') AS dir2_id \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_id', '65000000-0000-0000-0000-000000000001', 'direction'),
  (:'parent_id', '65000000-0000-0000-0000-000000000001', 'parent'),
  (:'dir2_id', '65000000-0000-0000-0000-000000000099', 'direction');

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.choisir_referentiel_comptable('65000000-0000-0000-0000-000000000001', 'sycebnl', 'confessionnelle');
SELECT public.creer_inscription_nouvel_eleve(
  '65000000-0000-0000-0000-000000000001', 'BAH', 'Mariama', '2014-02-03',
  '65000000-0000-0000-0000-000000000003', '65000000-0000-0000-0000-000000000002', 'F') AS fiche \gset
SELECT id AS insc FROM public.inscriptions WHERE fiche_eleve_id = :'fiche' \gset

CREATE OR REPLACE FUNCTION pg_temp.encaisser(p_fiche uuid, p_insc uuid, p_type text, p_montant numeric, p_moyen text, p_date date)
RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.encaissements_scolarite
    (etablissement_id, fiche_eleve_id, inscription_id, type_frais, montant, moyen_paiement, date_paiement)
  VALUES ('65000000-0000-0000-0000-000000000001', p_fiche, p_insc, p_type::public.type_frais_scolaire,
          p_montant, p_moyen::public.moyen_paiement, p_date)
  RETURNING id;
$$;

-- ---------------------------------------------------------------------------
-- 1. Sans exercice : l'encaissement passe, l'incident est consigné
-- ---------------------------------------------------------------------------
SELECT pg_temp.encaisser(:'fiche', :'insc', 'scolarite', 500000, 'especes', '2026-10-05') AS enc1 \gset
SELECT is((SELECT count(*)::int FROM public.encaissements_scolarite WHERE id = :'enc1'), 1,
  'la comptabilité ne bloque jamais l''encaissement');
SELECT is((SELECT code FROM public.incidents_comptabilisation WHERE source_id = :'enc1' AND NOT resolu), 'AUCUN_EXERCICE_OUVERT',
  'incident consigné : aucun exercice ouvert');

SELECT public.ouvrir_exercice('65000000-0000-0000-0000-000000000001', '2026-01-01', '2026-12-31');
SELECT is(public.comptabiliser_en_attente('65000000-0000-0000-0000-000000000001')->>'comptabilises', '1',
  'rattrapage : l''encaissement en attente est comptabilisé');
SELECT is((SELECT count(*)::int FROM public.incidents_comptabilisation WHERE source_id = :'enc1' AND NOT resolu), 0,
  'et l''incident est résolu');

CREATE TEMP TABLE p1 AS
  SELECT p.* FROM public.pieces_comptables p WHERE p.source_id = :'enc1'::uuid AND p.origine = 'automatique';
GRANT SELECT ON p1 TO authenticated;
SELECT is((SELECT reference || '|' || statut FROM p1), 'CAI-2026-000001|validee', 'pièce automatique validée dans le journal Caisse');
SELECT is((SELECT string_agg(c.code || ':' || l.debit::bigint || '/' || l.credit::bigint, ' ' ORDER BY l.ordre)
             FROM public.lignes_pieces_comptables l JOIN public.plans_comptables c ON c.id = l.compte_id
            WHERE l.piece_id = (SELECT id FROM p1)),
  '571:500000/0 70521:0/500000', 'Débit caisse 571, crédit scolarité 70521 (SYCEBNL)');
SELECT is((SELECT date_piece FROM p1), '2026-10-05'::date, 'pièce datée du jour de l''encaissement');

-- ---------------------------------------------------------------------------
-- 2. Orange Money, idempotence
-- ---------------------------------------------------------------------------
SELECT pg_temp.encaisser(:'fiche', :'insc', 'inscription', 150000, 'mobile_money', '2026-10-06') AS enc2 \gset
SELECT is((SELECT p.reference FROM public.pieces_comptables p WHERE p.source_id = :'enc2'::uuid), 'OM-2026-000001',
  'paiement Orange Money : pièce immédiate dans le journal OM');
SELECT is((SELECT string_agg(c.code, '/' ORDER BY l.ordre)
             FROM public.lignes_pieces_comptables l JOIN public.plans_comptables c ON c.id = l.compte_id
             JOIN public.pieces_comptables p ON p.id = l.piece_id WHERE p.source_id = :'enc2'::uuid),
  '5521/70522', 'Débit Orange Money 5521, crédit inscriptions 70522');
RESET ROLE;
SELECT is(public.comptabiliser_encaissement(:'enc2'), 'deja_comptabilise', 'idempotent : un second appel ne crée rien');
SELECT throws_ok(format($$INSERT INTO public.pieces_comptables (etablissement_id, exercice_id, journal_id, date_piece, libelle, origine, source_type, source_id)
  SELECT etablissement_id, exercice_id, journal_id, date_piece, 'doublon', 'automatique', source_type, source_id
    FROM public.pieces_comptables WHERE source_id = %L$$, :'enc2'), '23505', NULL,
  'index unique : jamais deux pièces automatiques pour un encaissement');
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');

-- ---------------------------------------------------------------------------
-- 3. Annulation
-- ---------------------------------------------------------------------------
SELECT throws_ok(format($$SELECT public.contrepasser_piece(%L, 'À la main', '2026-10-07')$$, (SELECT id FROM p1)),
  'PIECE_AUTOMATIQUE', 'une pièce automatique ne s''annule pas à la main');
UPDATE public.encaissements_scolarite SET statut = 'annule', motif_annulation = 'Reçu établi en double' WHERE id = :'enc1';
SELECT is((SELECT p.origine || '|' || p.statut FROM public.pieces_comptables p
            WHERE p.piece_annulee_id = (SELECT id FROM p1)), 'contrepassation|validee',
  'annulation de l''encaissement → contre-passation automatique');
SELECT ok((SELECT libelle LIKE '%Reçu établi en double%' FROM public.pieces_comptables WHERE piece_annulee_id = (SELECT id FROM p1)),
  'le motif de l''annulation figure sur la contre-passation');
SELECT is((SELECT solde_debit + solde_credit FROM public.balance_comptable('65000000-0000-0000-0000-000000000001', '2026-12-31') WHERE code = '571'),
  0::numeric, 'la caisse revient à zéro');

-- ---------------------------------------------------------------------------
-- 4. Période clôturée
-- ---------------------------------------------------------------------------
SELECT public.cloturer_periode('65000000-0000-0000-0000-000000000001', '2026-10-31');
SELECT pg_temp.encaisser(:'fiche', :'insc', 'cantine', 30000, 'especes', '2026-10-20') AS enc3 \gset
SELECT is((SELECT count(*)::int FROM public.encaissements_scolarite WHERE id = :'enc3'), 1,
  'encaissement daté d''une période clôturée : accepté…');
SELECT is((SELECT code FROM public.incidents_comptabilisation WHERE source_id = :'enc3' AND NOT resolu), 'PERIODE_CLOTUREE',
  '… et signalé à la comptabilité');

-- ---------------------------------------------------------------------------
-- 5. État de la comptabilisation automatique
-- ---------------------------------------------------------------------------
SELECT public.etat_comptabilisation_automatique('65000000-0000-0000-0000-000000000001') AS etat \gset
SELECT ok((:'etat'::jsonb->>'active')::boolean, 'comptabilisation automatique active en SYCEBNL');
SELECT is((:'etat'::jsonb->>'non_comptabilises')::int, 1, 'un encaissement reste à comptabiliser');
SELECT is(jsonb_array_length(:'etat'::jsonb->'incidents'), 1, 'un incident ouvert');
SELECT is((SELECT r->>'compte_code' FROM jsonb_array_elements(:'etat'::jsonb->'regles') r WHERE r->>'cle' = 'tresorerie:mobile_money'),
  '5521', 'comptes effectifs affichés (Orange Money → 5521)');

-- ---------------------------------------------------------------------------
-- 6. Règles propres à l'école
-- ---------------------------------------------------------------------------
SELECT throws_ok($$SELECT public.definir_regle_comptabilisation('65000000-0000-0000-0000-000000000001', 'tresorerie:especes',
  (SELECT id FROM public.plans_comptables WHERE etablissement_id = '65000000-0000-0000-0000-000000000001' AND code = '57'))$$,
  'COMPTE_NON_IMPUTABLE', 'règle vers un compte de regroupement refusée');
INSERT INTO public.plans_comptables (etablissement_id, code, intitule, type)
VALUES ('65000000-0000-0000-0000-000000000001', '5711', 'Caisse secrétariat', 'caisse');
SELECT lives_ok($$SELECT public.definir_regle_comptabilisation('65000000-0000-0000-0000-000000000001', 'tresorerie:especes',
  (SELECT id FROM public.plans_comptables WHERE etablissement_id = '65000000-0000-0000-0000-000000000001' AND code = '5711'))$$,
  'règle vers un sous-compte acceptée');
SELECT pg_temp.encaisser(:'fiche', :'insc', 'scolarite', 250000, 'especes', '2026-11-03') AS enc4 \gset
SELECT is((SELECT c.code FROM public.lignes_pieces_comptables l JOIN public.plans_comptables c ON c.id = l.compte_id
             JOIN public.pieces_comptables p ON p.id = l.piece_id WHERE p.source_id = :'enc4'::uuid AND l.debit > 0),
  '5711', 'les encaissements suivants utilisent le compte choisi par l''école');

-- ---------------------------------------------------------------------------
-- 7. Droits
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok($$SELECT public.comptabiliser_en_attente('65000000-0000-0000-0000-000000000001')$$, '42501', NULL,
  'un parent ne lance pas le rattrapage');
SELECT throws_ok(format($$SELECT public.comptabiliser_encaissement(%L)$$, :'enc3'), '42501', NULL,
  'fonction interne de comptabilisation inaccessible');
SELECT is((SELECT count(*)::int FROM public.incidents_comptabilisation), 0, 'un parent ne voit pas les incidents comptables');

-- ---------------------------------------------------------------------------
-- 8. Comptabilité simplifiée sans règles : rien d'automatique
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir2_id');
SELECT public.creer_inscription_nouvel_eleve(
  '65000000-0000-0000-0000-000000000099', 'CAMARA', 'Fodé', '2013-05-01',
  '65000000-0000-0000-0000-000000000093', '65000000-0000-0000-0000-000000000092', 'M') AS fiche2 \gset
INSERT INTO public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, type_frais, montant, moyen_paiement)
SELECT '65000000-0000-0000-0000-000000000099', :'fiche2', id, 'scolarite', 400000, 'especes'
  FROM public.inscriptions WHERE fiche_eleve_id = :'fiche2'
RETURNING id AS enc5 \gset
SELECT is((SELECT count(*)::int FROM public.pieces_comptables WHERE source_id = :'enc5'::uuid), 0,
  'simplifié sans règles : aucune pièce automatique');
SELECT is((SELECT count(*)::int FROM public.incidents_comptabilisation WHERE source_id = :'enc5'::uuid), 0,
  'et aucun incident (ce n''est pas une erreur)');

SELECT * FROM finish();
ROLLBACK;
