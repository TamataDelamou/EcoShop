-- ============================================================================
-- EcoShop — Test RLS 70 : changement de plan de comptes avec historique
-- (REG-03 C6, migration 20260906001542)
--
-- Scénario : une école tenue en SYSCOHADA en 2026 passe en SYCEBNL au
-- 1er janvier 2027.
-- Couvre :
--   • choix direct toujours refusé dès qu'il y a des écritures ; exercice
--     vierge exigé (effet au premier jour d'un exercice) ;
--   • table de correspondance proposée : table connue (70611 → 70521,
--     661 → 66), même numéro et intitulé, même numéro à vérifier,
--     rattachement (sous-compte de l'école → compte parent) ;
--   • corrections : sous-compte conservé, cible non imputable ou inconnue
--     refusée ; droits (parent, enseignant) ;
--   • application : archives des états 2026 tels que publiés, anciens
--     comptes retirés et renumérotés, pièces intactes, saisie refusée sur
--     un ancien compte, règles réorientées, note sur le changement ;
--   • lecture de l'historique dans le nouveau plan : états 2026 retraités
--     (résultat identique, équilibre, aucun compte hors rubrique), balance,
--     à-nouveaux 2027, tableau des flux ; nouvelles écritures automatiques
--     sur les comptes SYCEBNL ; double application refusée.
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

CREATE OR REPLACE FUNCTION pg_temp.compte(p_code text) RETURNS uuid
LANGUAGE sql AS $$
  SELECT id FROM public.plans_comptables
   WHERE etablissement_id = '70000000-0000-0000-0000-000000000001' AND code = p_code AND deleted_at IS NULL;
$$;

CREATE OR REPLACE FUNCTION pg_temp.piece(p_journal uuid, p_date date, p_libelle text, p_d text, p_c text, p_montant numeric)
RETURNS text LANGUAGE sql AS $$
  SELECT public.valider_piece(public.enregistrer_piece('70000000-0000-0000-0000-000000000001', p_journal, p_date, p_libelle,
    jsonb_build_array(jsonb_build_object('compte_id', pg_temp.compte(p_d), 'debit', p_montant),
                      jsonb_build_object('compte_id', pg_temp.compte(p_c), 'credit', p_montant))));
$$;

CREATE OR REPLACE FUNCTION pg_temp.ligne(p_etat jsonb, p_ref text) RETURNS numeric
LANGUAGE sql AS $$
  SELECT (l->>'montant')::numeric FROM jsonb_array_elements(p_etat->'lignes') l WHERE l->>'reference' = p_ref LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION pg_temp.corresp(p_detail jsonb, p_code text, p_champ text) RETURNS text
LANGUAGE sql AS $$
  SELECT l->>p_champ FROM jsonb_array_elements(p_detail->'lignes') l WHERE l->>'ancien_code' = p_code;
$$;

SELECT plan(36);

INSERT INTO public.etablissements (id, nom, slug, devise_code)
VALUES ('70000000-0000-0000-0000-000000000001', 'École Changement de plan', 'changement-plan-70', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('70000000-0000-0000-0000-000000000011', '70000000-0000-0000-0000-000000000001', '2026-2027', '2026-09-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('70000000-0000-0000-0000-000000000012', '70000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000011', 'CM2', 'CM2');

SELECT pg_temp.creer_compte('224670000001', 'direction') AS dir_id \gset
SELECT pg_temp.creer_compte('224670000002', 'parent') AS parent_id \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_id', '70000000-0000-0000-0000-000000000001', 'direction'),
  (:'parent_id', '70000000-0000-0000-0000-000000000001', 'parent');

-- ---------------------------------------------------------------------------
-- 1. Année 2026 en SYSCOHADA
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.choisir_referentiel_comptable('70000000-0000-0000-0000-000000000001', 'syscohada_normal', 'societe');
SELECT public.ouvrir_exercice('70000000-0000-0000-0000-000000000001', '2026-01-01', '2026-12-31') AS ex2026 \gset
INSERT INTO public.journaux (etablissement_id, code, intitule, type)
VALUES ('70000000-0000-0000-0000-000000000001', 'OP', 'Opérations', 'operations') RETURNING id AS jop \gset

SELECT pg_temp.piece(:'jop', '2026-01-05', 'Apport en capital', '521', '101', 1000000);
SELECT pg_temp.piece(:'jop', '2026-01-10', 'Ordinateurs', '2442', '521', 600000);
SELECT pg_temp.piece(:'jop', '2026-09-30', 'Salaires', '661', '422', 400000);
SELECT pg_temp.piece(:'jop', '2026-09-30', 'Paiement salaires', '422', '571', 400000);
SELECT public.creer_inscription_nouvel_eleve('70000000-0000-0000-0000-000000000001', 'KOUROUMA', 'Awa', '2015-03-02',
  '70000000-0000-0000-0000-000000000012', '70000000-0000-0000-0000-000000000011', 'F') AS fiche \gset
INSERT INTO public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, type_frais, montant, moyen_paiement, date_paiement)
SELECT '70000000-0000-0000-0000-000000000001', :'fiche', id, 'scolarite', 3030000, 'especes', '2026-09-10'
  FROM public.inscriptions WHERE fiche_eleve_id = :'fiche';
INSERT INTO public.plans_comptables (etablissement_id, code, intitule, type)
VALUES ('70000000-0000-0000-0000-000000000001', '5711', 'Caisse secrétariat', 'caisse');
SELECT pg_temp.piece(:'jop', '2026-10-01', 'Inscriptions au secrétariat', '5711', '70612', 100000);
SELECT public.definir_regle_comptabilisation('70000000-0000-0000-0000-000000000001', 'tresorerie:especes', pg_temp.compte('5711'));

SELECT public.etat_financier('70000000-0000-0000-0000-000000000001', :'ex2026') AS avant \gset
SELECT is(pg_temp.ligne(:'avant', 'XI'), 2730000::numeric, '2026 en SYSCOHADA : résultat 2 730 000');

-- ---------------------------------------------------------------------------
-- 2. Conditions
-- ---------------------------------------------------------------------------
SELECT throws_ok($$SELECT public.choisir_referentiel_comptable('70000000-0000-0000-0000-000000000001', 'sycebnl', 'confessionnelle')$$,
  'ECRITURES_EXISTANTES', 'le choix direct reste refusé dès qu''il y a des écritures');
SELECT throws_ok($$SELECT public.proposer_changement_plan('70000000-0000-0000-0000-000000000001', 'sycebnl')$$,
  'EXERCICE_VIERGE_REQUIS', 'jamais en cours d''exercice : il faut un exercice sans écriture');
SELECT public.cloturer_exercice(:'ex2026');
SELECT id AS ex2027 FROM public.exercices_comptables
 WHERE etablissement_id = '70000000-0000-0000-0000-000000000001' AND date_debut = '2027-01-01' \gset
SELECT throws_ok($$SELECT public.proposer_changement_plan('70000000-0000-0000-0000-000000000001', 'syscohada_smt')$$,
  'MEME_PLAN', 'SMT ↔ normal : même plan, pas de changement à préparer');

SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok($$SELECT public.proposer_changement_plan('70000000-0000-0000-0000-000000000001', 'sycebnl')$$,
  '42501', NULL, 'un parent ne prépare pas de changement de plan');
SELECT pg_temp.en_tant_que(:'dir_id');

-- ---------------------------------------------------------------------------
-- 3. Proposition
-- ---------------------------------------------------------------------------
SELECT public.proposer_changement_plan('70000000-0000-0000-0000-000000000001', 'sycebnl', 'confessionnelle') AS p \gset
SELECT id AS ch FROM public.changements_plan WHERE etablissement_id = '70000000-0000-0000-0000-000000000001' AND statut = 'brouillon' \gset
SELECT is(:'p'::jsonb->>'date_effet', '2027-01-01', 'effet au premier jour de l''exercice 2027 (vierge hors à-nouveaux)');
SELECT is(pg_temp.corresp(:'p', '70611', 'code_cible') || '/' || pg_temp.corresp(:'p', '70611', 'origine'), '70521/table',
  'frais de scolarité : 70611 → 70521 (table connue)');
SELECT is(pg_temp.corresp(:'p', '661', 'code_cible') || '/' || pg_temp.corresp(:'p', '661', 'origine'), '66/table',
  'salaires : 661 → 66');
SELECT is(pg_temp.corresp(:'p', '422', 'origine') || '/' || pg_temp.corresp(:'p', '422', 'a_verifier'), 'identique/false',
  '422 : même numéro, même intitulé, rien à vérifier');
SELECT is(pg_temp.corresp(:'p', '101', 'origine') || '/' || pg_temp.corresp(:'p', '101', 'a_verifier'), 'meme_numero/true',
  '101 capital social → 101 dotation : même numéro, signalé à vérifier');
SELECT is(pg_temp.corresp(:'p', '2442', 'code_cible') || '/' || pg_temp.corresp(:'p', '2442', 'origine'), '244/rattachement',
  'matériel informatique 2442 → 244 (compte de rattachement)');
SELECT is(pg_temp.corresp(:'p', '5711', 'code_cible'), '571', 'sous-compte de l''école : rattaché par défaut au compte parent');
SELECT is(pg_temp.corresp(:'p', '521', 'solde')::numeric, 400000::numeric,
  'solde à reporter de la banque affiché (400 000)');
SELECT is((:'p'::jsonb->>'a_completer')::int, 0, 'chaque compte utilisé a une proposition');

-- Corrections
SELECT public.definir_correspondance(:'ch', pg_temp.compte('5711'), '5711') AS p2 \gset
SELECT is(pg_temp.corresp(:'p2', '5711', 'code_cible') || '/' || pg_temp.corresp(:'p2', '5711', 'origine'), '5711/manuel',
  'l''école garde son sous-compte 5711 sous 571');
SELECT throws_ok(format($$SELECT public.definir_correspondance(%L, %L, '57')$$, :'ch', pg_temp.compte('571')),
  'COMPTE_CIBLE_INVALIDE', 'cible non imputable (57 a des sous-comptes) refusée');
SELECT throws_ok(format($$SELECT public.definir_correspondance(%L, %L, '9999')$$, :'ch', pg_temp.compte('571')),
  'COMPTE_CIBLE_INVALIDE', 'cible hors plan refusée');
SELECT throws_ok(format($$SELECT public.definir_correspondance(%L, %L, '571')$$, :'ch', pg_temp.compte('604')),
  'COMPTE_HORS_CHANGEMENT', 'compte non concerné par le changement');

-- ---------------------------------------------------------------------------
-- 4. Application
-- ---------------------------------------------------------------------------
SELECT (SELECT count(*) FROM public.lignes_pieces_comptables l JOIN public.pieces_comptables p ON p.id = l.piece_id
         WHERE p.etablissement_id = '70000000-0000-0000-0000-000000000001') AS nb_lignes \gset
SELECT pg_temp.compte('70611') AS ancien_70611 \gset
SELECT public.appliquer_changement_plan(:'ch') AS res \gset
SELECT is(:'res'::jsonb->>'referentiel' || '/' || (:'res'::jsonb->>'exercices_archives'), 'sycebnl/1',
  'référentiel SYCEBNL ; exercice 2026 archivé');
SELECT is((SELECT referentiel || '|' || (etat->'lignes' @> '[{"reference":"XI"}]')::text
             FROM public.etats_financiers_archives WHERE exercice_id = :'ex2026'),
  'syscohada_normal|true', 'archives : états 2026 tels que publiés en SYSCOHADA');
SELECT is((public.etat_financier_archive(:'ex2026')->'etat'->>'resultat')::numeric, 2730000::numeric,
  'archive consultable : résultat publié 2 730 000');
SELECT is((SELECT count(*) FROM public.lignes_pieces_comptables l JOIN public.pieces_comptables p ON p.id = l.piece_id
            WHERE p.etablissement_id = '70000000-0000-0000-0000-000000000001'), :'nb_lignes'::bigint,
  'aucune pièce modifiée');
SELECT is((SELECT code || '|' || (deleted_at IS NOT NULL)::text || '|' || intitule FROM public.plans_comptables WHERE id = :'ancien_70611'),
  '70611*|true|Frais de scolarité (ancien plan)', 'ancien compte retiré et renuméroté');
SELECT throws_ok(format($$SELECT public.enregistrer_piece('70000000-0000-0000-0000-000000000001', %L, '2027-02-01', 'Test',
  jsonb_build_array(jsonb_build_object('compte_id', %L, 'debit', 1), jsonb_build_object('compte_id', %L, 'credit', 1)))$$,
  :'jop', pg_temp.compte('5521'), :'ancien_70611'), 'COMPTE_INVALIDE', 'plus de saisie sur un compte de l''ancien plan');
SELECT is((SELECT intitule || '|' || reglementaire::text FROM public.plans_comptables WHERE id = pg_temp.compte('5711')),
  'Caisse secrétariat|false', 'sous-compte 5711 recréé sous 571 du nouveau plan');
SELECT is((SELECT c.code FROM public.regles_comptabilisation g JOIN public.plans_comptables c ON c.id = g.compte_id
            WHERE g.etablissement_id = '70000000-0000-0000-0000-000000000001' AND g.cle = 'tresorerie:especes'),
  '5711', 'règle des espèces réorientée vers le 5711 du nouveau plan');
SELECT ok((SELECT texte LIKE 'Changement de référentiel comptable au 01/01/2027%' FROM public.notes_annexes_redigees
            WHERE exercice_id = :'ex2027' AND cle = 'methodes'), 'note annexe 1 : changement de méthode expliqué');

-- ---------------------------------------------------------------------------
-- 5. Historique lu dans le nouveau plan
-- ---------------------------------------------------------------------------
SELECT public.etat_financier('70000000-0000-0000-0000-000000000001', :'ex2026') AS apres \gset
SELECT is(pg_temp.ligne(:'apres', 'P3') || '/' || pg_temp.ligne(:'apres', 'C4'), '3130000.00/2730000.00',
  '2026 retraité en SYCEBNL : frais scolaires en P3, résultat inchangé');
SELECT is((:'apres'::jsonb->>'equilibre') || '/' || jsonb_array_length(:'apres'::jsonb->'non_classes'), 'true/0',
  'retraitement équilibré, aucun compte hors rubrique');
SELECT is((SELECT solde_credit FROM public.balance_comptable('70000000-0000-0000-0000-000000000001', '2026-12-31') WHERE code = '70521'),
  3030000::numeric, 'balance : l''historique du 70611 apparaît sous 70521');
SELECT public.etat_financier('70000000-0000-0000-0000-000000000001', :'ex2027') AS e27 \gset
SELECT is(pg_temp.ligne(:'e27', 'C1') || '/' || (:'e27'::jsonb->>'equilibre'), '1000000.00/true',
  '2027 : à-nouveaux lus dans le nouveau plan (dotation 1 000 000), bilan équilibré');
SELECT is(pg_temp.ligne(:'e27', 'P3') IS NULL OR pg_temp.ligne(:'e27', 'P3') = 0, true, '2027 : aucun produit fictif');
SELECT is((SELECT (l->>'montant_n1')::numeric FROM jsonb_array_elements(:'e27'::jsonb->'lignes') l WHERE l->>'reference' = 'P3'),
  3130000::numeric, 'colonne N-1 comparable : 2026 présenté dans le plan SYCEBNL');
SELECT is((SELECT (l->>'montant')::numeric FROM jsonb_array_elements(
             public.tableau_flux_tresorerie('70000000-0000-0000-0000-000000000001', :'ex2027')->'lignes') l
            WHERE l->>'reference' = 'ZA'), 3130000::numeric, 'tableau des flux 2027 : trésorerie d''ouverture');

INSERT INTO public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, type_frais, montant, moyen_paiement, date_paiement)
SELECT '70000000-0000-0000-0000-000000000001', :'fiche', id, 'cantine', 50000, 'mobile_money', '2027-01-15'
  FROM public.inscriptions WHERE fiche_eleve_id = :'fiche'
RETURNING id AS enc27 \gset
SELECT is((SELECT string_agg(c.code, '/' ORDER BY l.ordre) FROM public.lignes_pieces_comptables l
             JOIN public.plans_comptables c ON c.id = l.compte_id JOIN public.pieces_comptables p ON p.id = l.piece_id
            WHERE p.source_id = :'enc27'::uuid), '5521/70523', 'écritures automatiques : comptes SYCEBNL');
SELECT throws_ok(format($$SELECT public.appliquer_changement_plan(%L)$$, :'ch'), 'CHANGEMENT_DEJA_APPLIQUE',
  'un changement ne s''applique qu''une fois');

SELECT * FROM finish();
ROLLBACK;
