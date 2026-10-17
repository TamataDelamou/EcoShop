-- ============================================================================
-- EcoShop — Test RLS 69 : tableau des flux de trésorerie et notes annexes
-- (REG-03 C5, migration 20260906001541)
--
-- Couvre :
--   • SYSCOHADA (méthode indirecte) : CAFG, variation des créances et du
--     passif circulant, investissement, capitaux propres, emprunts et
--     remboursements, variation et trésorerie de clôture = bilan ;
--     rapprochement avec les flux constatés pièce par pièce (écart nul) ;
--   • exercice suivant : trésorerie d'ouverture (à-nouveaux), colonne N-1 ;
--   • SYCEBNL (méthode directe) : générosité, autres revenus, fournisseurs,
--     personnel, acquisitions, fonds affectés en fonds propres ;
--   • simplifié : encaissements, décaissements, clôture ;
--   • notes annexes : immobilisations, créances, trésorerie, produits,
--     personnel ; SYCEBNL : générosité, fonds affectés ; notes rédigées,
--     figées après clôture ; droits.
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

CREATE OR REPLACE FUNCTION pg_temp.piece(p_etab uuid, p_journal uuid, p_date date, p_libelle text, p_d text, p_c text, p_montant numeric)
RETURNS text LANGUAGE sql AS $$
  SELECT public.valider_piece(public.enregistrer_piece(p_etab, p_journal, p_date, p_libelle, jsonb_build_array(
    jsonb_build_object('compte_id', (SELECT id FROM public.plans_comptables WHERE etablissement_id = p_etab AND code = p_d AND deleted_at IS NULL), 'debit', p_montant),
    jsonb_build_object('compte_id', (SELECT id FROM public.plans_comptables WHERE etablissement_id = p_etab AND code = p_c AND deleted_at IS NULL), 'credit', p_montant))));
$$;

CREATE OR REPLACE FUNCTION pg_temp.flux(p_tft jsonb, p_ref text, p_champ text DEFAULT 'montant') RETURNS numeric
LANGUAGE sql AS $$
  SELECT (l->>p_champ)::numeric FROM jsonb_array_elements(p_tft->'lignes') l WHERE l->>'reference' = p_ref;
$$;

-- Ligne d'une note : la première dont la 1re colonne commence par p_libelle.
CREATE OR REPLACE FUNCTION pg_temp.note(p_notes jsonb, p_code text, p_libelle text, p_col int) RETURNS text
LANGUAGE sql AS $$
  SELECT l->>p_col FROM jsonb_array_elements(p_notes->'notes') n, jsonb_array_elements(n->'lignes') l
   WHERE n->>'code' = p_code AND l->>0 LIKE p_libelle || '%' LIMIT 1;
$$;

SELECT plan(38);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('69000000-0000-0000-0000-000000000001', 'Lycée Flux', 'lycee-flux-69', 'GNF'),
  ('69000000-0000-0000-0000-000000000002', 'École Bambino Flux', 'bambino-flux-69', 'GNF'),
  ('69000000-0000-0000-0000-000000000003', 'École Simple Flux', 'simple-flux-69', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('69000000-0000-0000-0000-000000000011', '69000000-0000-0000-0000-000000000001', '2026-2027', '2026-09-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('69000000-0000-0000-0000-000000000012', '69000000-0000-0000-0000-000000000001', '69000000-0000-0000-0000-000000000011', 'TS', 'Terminale');

SELECT pg_temp.creer_compte('224669000001', 'direction') AS dir_id \gset
SELECT pg_temp.creer_compte('224669000002', 'parent') AS parent_id \gset
SELECT pg_temp.creer_compte('224669000003', 'direction') AS dir2_id \gset
SELECT pg_temp.creer_compte('224669000004', 'direction') AS dir3_id \gset
SELECT pg_temp.creer_compte('224669000005', 'enseignant') AS ens_id \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_id', '69000000-0000-0000-0000-000000000001', 'direction'),
  (:'parent_id', '69000000-0000-0000-0000-000000000001', 'parent'),
  (:'ens_id', '69000000-0000-0000-0000-000000000001', 'enseignant'),
  (:'dir2_id', '69000000-0000-0000-0000-000000000002', 'direction'),
  (:'dir3_id', '69000000-0000-0000-0000-000000000003', 'direction');
INSERT INTO public.employes (etablissement_id, profile_id, matricule, categorie, date_embauche)
VALUES ('69000000-0000-0000-0000-000000000001', :'ens_id', 'E-01', 'enseignant', '2025-09-01');

-- ---------------------------------------------------------------------------
-- 1. SYSCOHADA 2026
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.choisir_referentiel_comptable('69000000-0000-0000-0000-000000000001', 'syscohada_normal', 'societe');
SELECT public.ouvrir_exercice('69000000-0000-0000-0000-000000000001', '2026-01-01', '2026-12-31') AS ex \gset
INSERT INTO public.journaux (etablissement_id, code, intitule, type)
VALUES ('69000000-0000-0000-0000-000000000001', 'OP', 'Opérations', 'operations') RETURNING id AS jop \gset

SELECT pg_temp.piece('69000000-0000-0000-0000-000000000001', :'jop', '2026-01-05', 'Apport en capital', '521', '101', 1000000);
SELECT pg_temp.piece('69000000-0000-0000-0000-000000000001', :'jop', '2026-01-10', 'Ordinateurs', '2442', '521', 600000);
SELECT pg_temp.piece('69000000-0000-0000-0000-000000000001', :'jop', '2026-02-01', 'Emprunt bancaire', '521', '162', 500000);
SELECT pg_temp.piece('69000000-0000-0000-0000-000000000001', :'jop', '2026-08-01', 'Remboursement emprunt', '162', '521', 100000);
SELECT pg_temp.piece('69000000-0000-0000-0000-000000000001', :'jop', '2026-09-30', 'Amortissement', '681', '284', 50000);
SELECT pg_temp.piece('69000000-0000-0000-0000-000000000001', :'jop', '2026-09-30', 'Salaires dus', '661', '422', 400000);
SELECT pg_temp.piece('69000000-0000-0000-0000-000000000001', :'jop', '2026-09-30', 'Salaires payés', '422', '571', 350000);
SELECT pg_temp.piece('69000000-0000-0000-0000-000000000001', :'jop', '2026-10-02', 'Fournitures', '6055', '571', 25000);
SELECT pg_temp.piece('69000000-0000-0000-0000-000000000001', :'jop', '2026-10-05', 'Frais facturés non payés', '41111', '70611', 200000);
SELECT public.creer_inscription_nouvel_eleve('69000000-0000-0000-0000-000000000001', 'BAH', 'Oumar', '2008-04-02',
  '69000000-0000-0000-0000-000000000012', '69000000-0000-0000-0000-000000000011', 'M') AS fiche \gset
INSERT INTO public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, type_frais, montant, moyen_paiement, date_paiement)
SELECT '69000000-0000-0000-0000-000000000001', :'fiche', id, 'scolarite', 3030000, 'especes', '2026-09-10'
  FROM public.inscriptions WHERE fiche_eleve_id = :'fiche';

SELECT public.tableau_flux_tresorerie('69000000-0000-0000-0000-000000000001', :'ex') AS t1 \gset
SELECT is(:'t1'::jsonb->>'methode', 'indirecte', 'SYSCOHADA : méthode indirecte');
SELECT is(pg_temp.flux(:'t1', 'FA'), 2805000::numeric, 'FA — CAFG = résultat 2 755 000 + dotation 50 000');
SELECT is(pg_temp.flux(:'t1', 'FD'), -200000::numeric, 'FD — créance famille non encaissée');
SELECT is(pg_temp.flux(:'t1', 'FE'), 50000::numeric, 'FE — salaires restant dus');
SELECT is(pg_temp.flux(:'t1', 'ZB'), 2655000::numeric, 'ZB — flux opérationnels');
SELECT is((:'t1'::jsonb->>'operationnel_direct')::numeric, 2655000::numeric,
  'rapprochement : identique aux encaissements et décaissements constatés pièce par pièce');
SELECT is(pg_temp.flux(:'t1', 'FG'), -600000::numeric, 'FG — acquisition de matériel');
SELECT is(pg_temp.flux(:'t1', 'FK'), 1000000::numeric, 'FK — apport en capital');
SELECT is(pg_temp.flux(:'t1', 'FO') || '/' || pg_temp.flux(:'t1', 'FQ'), '500000.00/-100000.00', 'FO emprunt, FQ remboursement');
SELECT is(pg_temp.flux(:'t1', 'ZG'), 3455000::numeric, 'ZG — variation de trésorerie');
SELECT is(pg_temp.flux(:'t1', 'ZH') || '/' || (:'t1'::jsonb->>'tresorerie_bilan') || '/' || (:'t1'::jsonb->>'ecart_cloture'),
  '3455000.00/3455000.00/0.00', 'ZH — trésorerie de clôture = trésorerie du bilan, écart nul');
SELECT ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(:'t1'::jsonb->'lignes') l WHERE l->>'reference' = 'OPD'),
  'la ligne de contrôle n''est pas affichée dans le modèle');

-- Notes annexes 2026
SELECT public.notes_annexes('69000000-0000-0000-0000-000000000001', :'ex') AS n1 \gset
SELECT is(pg_temp.note(:'n1', '2', 'Matériel', 4)::numeric::bigint || '/' || pg_temp.note(:'n1', '2', 'Matériel', 5)::numeric::bigint
          || '/' || pg_temp.note(:'n1', '2', 'Matériel', 6)::numeric::bigint,
  '600000/50000/550000', 'note 2 : matériel brut, amortissements, net');
SELECT is(pg_temp.note(:'n1', '3', 'Familles', 3)::numeric, 200000::numeric, 'note 3 : créances des familles à la clôture');
SELECT is((SELECT count(*)::int FROM jsonb_array_elements(:'n1'::jsonb->'notes') n, jsonb_array_elements(n->'lignes') l
            WHERE n->>'code' = '4'), 2, 'note 4 : banque et caisse, compte par compte');
SELECT is(pg_temp.note(:'n1', '6', '70611', 1)::numeric, 3230000::numeric, 'note 6 : frais de scolarité de l''exercice');
SELECT is(pg_temp.note(:'n1', '8', 'Effectif — enseignants', 1)::int || '/' || pg_temp.note(:'n1', '8', 'Charges de personnel', 1)::numeric::bigint,
  '1/400000', 'note 8 : effectif et charges de personnel');
SELECT ok((SELECT n->>'texte' LIKE '%SYSCOHADA révisé (système normal)%' FROM jsonb_array_elements(:'n1'::jsonb->'notes') n WHERE n->>'code' = '1'),
  'note 1 : référentiel et méthodes rédigés automatiquement');

SELECT public.enregistrer_note_annexe(:'ex', 'faits_marquants', 'Ouverture d''une classe de Terminale.');
SELECT is((SELECT n->>'texte' FROM jsonb_array_elements(public.notes_annexes('69000000-0000-0000-0000-000000000001', :'ex')->'notes') n
            WHERE n->>'modifiable' = 'faits_marquants'), 'Ouverture d''une classe de Terminale.', 'note rédigée par l''école');
SELECT throws_ok(format($$SELECT public.enregistrer_note_annexe(%L, 'poeme', 'x')$$, :'ex'), 'NOTE_INVALIDE',
  'seules les rubriques prévues sont acceptées');

-- ---------------------------------------------------------------------------
-- 2. Exercice suivant : ouverture, N-1, notes figées
-- ---------------------------------------------------------------------------
SELECT public.cloturer_exercice(:'ex');
SELECT throws_ok(format($$SELECT public.enregistrer_note_annexe(%L, 'faits_marquants', 'Après coup')$$, :'ex'),
  'EXERCICE_DEJA_CLOTURE', 'notes figées après la clôture de l''exercice');
SELECT id AS ex2027 FROM public.exercices_comptables
 WHERE etablissement_id = '69000000-0000-0000-0000-000000000001' AND date_debut = '2027-01-01' \gset
-- Les écritures de 2027 sont datées « aujourd'hui » au plus tard : on teste
-- l'ouverture sans mouvement.
SELECT public.tableau_flux_tresorerie('69000000-0000-0000-0000-000000000001', :'ex2027') AS t2 \gset
SELECT is(pg_temp.flux(:'t2', 'ZA'), 3455000::numeric, '2027 : ouverture = clôture 2026 (à-nouveaux, pas un flux)');
SELECT is(pg_temp.flux(:'t2', 'ZB') || '/' || pg_temp.flux(:'t2', 'ZH'), '0.00/3455000.00', 'aucun flux fictif né des à-nouveaux');
SELECT is(pg_temp.flux(:'t2', 'ZB', 'montant_n1'), 2655000::numeric, 'colonne N-1 = flux 2026');

-- ---------------------------------------------------------------------------
-- 3. SYCEBNL (méthode directe)
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir2_id');
SELECT public.choisir_referentiel_comptable('69000000-0000-0000-0000-000000000002', 'sycebnl', 'confessionnelle');
SELECT public.ouvrir_exercice('69000000-0000-0000-0000-000000000002', '2026-01-01', '2026-12-31') AS exb \gset
INSERT INTO public.journaux (etablissement_id, code, intitule, type)
VALUES ('69000000-0000-0000-0000-000000000002', 'OP', 'Opérations', 'operations') RETURNING id AS jopb \gset
INSERT INTO public.affectations_dons (id, etablissement_id, libelle, type) VALUES
  ('69000000-0000-0000-0000-0000000000a1', '69000000-0000-0000-0000-000000000002', 'Nouveau toit', 'projet');
SELECT public.enregistrer_don('69000000-0000-0000-0000-000000000002', 500000, 'don', 'especes', '2026-02-01');
SELECT public.enregistrer_don('69000000-0000-0000-0000-000000000002', 2000000, 'mecenat', 'virement', '2026-03-01',
  NULL, '69000000-0000-0000-0000-0000000000a1');
SELECT public.constater_emploi_fonds('69000000-0000-0000-0000-0000000000a1', 1500000, 'Tôles et charpente', '2026-04-01');
SELECT pg_temp.piece('69000000-0000-0000-0000-000000000002', :'jopb', '2026-09-15', 'Frais scolaires', '571', '70521', 800000);
SELECT pg_temp.piece('69000000-0000-0000-0000-000000000002', :'jopb', '2026-09-30', 'Salaires', '66', '571', 300000);
SELECT pg_temp.piece('69000000-0000-0000-0000-000000000002', :'jopb', '2026-10-01', 'Craies et cahiers', '605', '571', 100000);
SELECT pg_temp.piece('69000000-0000-0000-0000-000000000002', :'jopb', '2026-10-02', 'Tables-bancs', '244', '521', 400000);

SELECT public.tableau_flux_tresorerie('69000000-0000-0000-0000-000000000002', :'exb') AS t3 \gset
SELECT is(:'t3'::jsonb->>'methode', 'directe', 'SYCEBNL : méthode directe');
SELECT is(pg_temp.flux(:'t3', 'FC'), 500000::numeric, 'FC — revenus liés à la générosité');
SELECT is(pg_temp.flux(:'t3', 'FE'), 800000::numeric, 'FE — autres revenus (frais scolaires)');
SELECT is(pg_temp.flux(:'t3', 'FF') || '/' || pg_temp.flux(:'t3', 'FG'), '-100000.00/-300000.00', 'FF fournisseurs, FG personnel');
SELECT is(pg_temp.flux(:'t3', 'FI'), -400000::numeric, 'FI — acquisition de matériel');
SELECT is(pg_temp.flux(:'t3', 'FM'), 2000000::numeric, 'FM — don affecté au projet, en fonds propres');
SELECT is(pg_temp.flux(:'t3', 'ZG') || '/' || (:'t3'::jsonb->>'ecart_cloture'), '2500000.00/0.00',
  'trésorerie de clôture = bilan (l''emploi des fonds n''est pas un flux)');

SELECT public.notes_annexes('69000000-0000-0000-0000-000000000002', :'exb') AS n2 \gset
SELECT is(pg_temp.note(:'n2', '10', 'Mécénat', 2)::numeric, 2000000::numeric, 'note 10 : générosité par nature');
SELECT is(pg_temp.note(:'n2', '11', 'Nouveau toit', 2)::numeric::bigint || '/' || pg_temp.note(:'n2', '11', 'Nouveau toit', 3)::numeric::bigint
          || '/' || pg_temp.note(:'n2', '11', 'Nouveau toit', 4)::numeric::bigint,
  '2000000/1500000/500000', 'note 11 : fonds affectés reçus, employés, à reporter');
SELECT ok((SELECT n->>'titre' FROM jsonb_array_elements(:'n2'::jsonb->'notes') n WHERE n->>'code' = '5') LIKE 'Fonds propres, fonds affectés%',
  'note 5 : intitulés propres aux entités à but non lucratif');

-- ---------------------------------------------------------------------------
-- 4. Simplifié
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir3_id');
SELECT public.ouvrir_exercice('69000000-0000-0000-0000-000000000003', '2026-01-01', '2026-12-31') AS exs \gset
INSERT INTO public.plans_comptables (etablissement_id, code, intitule, type) VALUES
  ('69000000-0000-0000-0000-000000000003', 'C1', 'Caisse', 'caisse'),
  ('69000000-0000-0000-0000-000000000003', 'P1', 'Frais scolaires', 'produit'),
  ('69000000-0000-0000-0000-000000000003', 'D1', 'Achats', 'charge');
INSERT INTO public.journaux (etablissement_id, code, intitule, type)
VALUES ('69000000-0000-0000-0000-000000000003', 'OP', 'Opérations', 'operations') RETURNING id AS jops \gset
SELECT pg_temp.piece('69000000-0000-0000-0000-000000000003', :'jops', '2026-09-01', 'Frais', 'C1', 'P1', 1000);
SELECT pg_temp.piece('69000000-0000-0000-0000-000000000003', :'jops', '2026-09-02', 'Achats', 'D1', 'C1', 300);
SELECT public.tableau_flux_tresorerie('69000000-0000-0000-0000-000000000003', :'exs') AS t4 \gset
SELECT is(pg_temp.flux(:'t4', 'T1') || '/' || pg_temp.flux(:'t4', 'T2') || '/' || pg_temp.flux(:'t4', 'T5'),
  '1000.00/-300.00/700.00', 'simplifié : encaissements, décaissements, trésorerie de fin');

-- ---------------------------------------------------------------------------
-- 5. Droits
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok(format($$SELECT public.tableau_flux_tresorerie('69000000-0000-0000-0000-000000000001', %L)$$, :'ex'),
  '42501', NULL, 'un parent ne voit pas le tableau des flux');
SELECT throws_ok(format($$SELECT public.notes_annexes('69000000-0000-0000-0000-000000000001', %L)$$, :'ex'),
  '42501', NULL, 'ni les notes annexes');
SELECT throws_ok($$SELECT public.calculer_flux_tresorerie('69000000-0000-0000-0000-000000000001', 'syscohada', '2026-01-01', '2026-12-31')$$,
  '42501', NULL, 'calcul interne inaccessible');

SELECT * FROM finish();
ROLLBACK;
