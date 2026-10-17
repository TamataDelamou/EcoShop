-- ============================================================================
-- EcoShop — Test RLS 64 : pièces, validation, contre-passation, exercices et
-- clôtures (REG-03 C2, migration 20260906001535)
--
-- Couvre :
--   • exercices : année civile imposée en OHADA (premier exercice libre),
--     contiguïté, chevauchement, droits ;
--   • pièces : brouillard multi-lignes modifiable, sans numéro ; validation
--     équilibrée ; numérotation continue par journal et exercice (un
--     brouillard supprimé ne crée pas de trou) ; compte non imputable ;
--     lignes invalides ;
--   • irréversibilité : pièce validée ni modifiable ni supprimable, même
--     sans passer par les fonctions ; saisie M14 à deux comptes interdite en
--     OHADA ;
--   • contre-passation en négatif (art. 20) : liée, unique, motivée ;
--   • documents : journal, grand livre et balance intègrent les pièces ;
--   • clôture de période : brouillards en attente refusés, dates figées pour
--     les pièces comme pour les écritures M14 ;
--   • clôture d'exercice : Direction seule, résultat, à-nouveaux validés
--     dans l'exercice suivant (créé au besoin), balance d'ouverture exacte ;
--     exercice clôturé intouchable ; plan simplifié (compte 13 créé) ;
--   • isolation : fonctions internes inaccessibles, pièces d'un autre
--     établissement invisibles.
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

SELECT plan(49);

-- Établissement OHADA (SYCEBNL) et établissement simplifié.
INSERT INTO public.etablissements (nom, slug, pays_code, ville, devise_code, langue_code, fuseau_horaire, statut)
VALUES ('École Bambino C2', 'bambino-c2-64', 'GN', 'Conakry', 'GNF', 'fr', 'Africa/Conakry', 'actif')
RETURNING id AS etab \gset
INSERT INTO public.etablissements (nom, slug, pays_code, ville, devise_code, langue_code, fuseau_horaire, statut)
VALUES ('École Simple C2', 'simple-c2-64', 'GN', 'Labé', 'GNF', 'fr', 'Africa/Conakry', 'actif')
RETURNING id AS etab3 \gset

SELECT pg_temp.creer_compte('224664000001', 'direction') AS dir_id \gset
SELECT pg_temp.creer_compte('224664000002', 'parent') AS parent_id \gset
SELECT pg_temp.creer_compte('224664000003', 'direction') AS dir3_id \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement, actif) VALUES
  (:'dir_id', :'etab', 'direction', true),
  (:'parent_id', :'etab', 'parent', true),
  (:'dir3_id', :'etab3', 'direction', true);

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.choisir_referentiel_comptable(:'etab', 'sycebnl', 'confessionnelle');
INSERT INTO public.journaux (etablissement_id, code, intitule, type) VALUES (:'etab', 'CAI', 'Caisse', 'caisse')
RETURNING id AS jcai \gset

CREATE TEMP TABLE c AS
  SELECT code, id FROM public.plans_comptables WHERE etablissement_id = :'etab' AND deleted_at IS NULL;
GRANT SELECT ON c TO authenticated;
SELECT id AS c571 FROM c WHERE code = '571' \gset
SELECT id AS c57 FROM c WHERE code = '57' \gset
SELECT id AS c70521 FROM c WHERE code = '70521' \gset
SELECT id AS c70522 FROM c WHERE code = '70522' \gset
SELECT id AS c70523 FROM c WHERE code = '70523' \gset

-- ---------------------------------------------------------------------------
-- 1. Exercices
-- ---------------------------------------------------------------------------
SELECT throws_ok(format($$SELECT public.ouvrir_exercice(%L, '2026-09-01', '2027-08-31')$$, :'etab'),
  'EXERCICE_NON_CONFORME', 'OHADA : un exercice doit finir le 31 décembre');
SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok(format($$SELECT public.ouvrir_exercice(%L, '2026-09-01', '2026-12-31')$$, :'etab'),
  '42501', NULL, 'un parent ne peut pas ouvrir d''exercice');
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.ouvrir_exercice(:'etab', '2026-09-01', '2026-12-31') AS ex2026 \gset
SELECT is((SELECT libelle FROM public.exercices_comptables WHERE id = :'ex2026'), 'Exercice 2026',
  'premier exercice en cours d''année accepté, libellé automatique');
SELECT throws_ok(format($$SELECT public.ouvrir_exercice(%L, '2026-12-01', '2027-12-31')$$, :'etab'),
  'EXERCICE_CHEVAUCHEMENT', 'deux exercices ne se chevauchent pas');
SELECT throws_ok(format($$SELECT public.ouvrir_exercice(%L, '2027-02-01', '2027-12-31')$$, :'etab'),
  'EXERCICE_NON_CONTIGU', 'les exercices se suivent sans trou');

-- ---------------------------------------------------------------------------
-- 2. Pièces : contrôles de saisie
-- ---------------------------------------------------------------------------
SELECT throws_ok(format($$SELECT public.enregistrer_piece(%L, %L, '2025-05-01', 'Hors exercice',
  jsonb_build_array(jsonb_build_object('compte_id', %L, 'debit', 1000), jsonb_build_object('compte_id', %L, 'credit', 1000)))$$,
  :'etab', :'jcai', :'c571', :'c70521'), 'AUCUN_EXERCICE_OUVERT', 'pas de pièce hors exercice ouvert');
SELECT throws_ok(format($$SELECT public.enregistrer_piece(%L, %L, '2026-10-01', 'Compte de regroupement',
  jsonb_build_array(jsonb_build_object('compte_id', %L, 'debit', 1000), jsonb_build_object('compte_id', %L, 'credit', 1000)))$$,
  :'etab', :'jcai', :'c57', :'c70521'), 'COMPTE_NON_IMPUTABLE', 'OHADA : imputation sur un compte de détail seulement');
SELECT throws_ok(format($$SELECT public.enregistrer_piece(%L, %L, '2026-10-01', 'Deux sens',
  jsonb_build_array(jsonb_build_object('compte_id', %L, 'debit', 1000, 'credit', 1000)))$$,
  :'etab', :'jcai', :'c571'), 'LIGNE_INVALIDE', 'une ligne porte un débit OU un crédit');
SELECT throws_ok(format($$SELECT public.enregistrer_piece(%L, %L, '2026-10-01', 'Négatif',
  jsonb_build_array(jsonb_build_object('compte_id', %L, 'debit', -1000)))$$,
  :'etab', :'jcai', :'c571'), 'LIGNE_INVALIDE', 'montant négatif refusé en saisie (réservé à la contre-passation)');
SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok(format($$SELECT public.enregistrer_piece(%L, %L, '2026-10-01', 'Intrus',
  jsonb_build_array(jsonb_build_object('compte_id', %L, 'debit', 1000)))$$,
  :'etab', :'jcai', :'c571'), '42501', NULL, 'un parent ne saisit pas de pièce');
SELECT pg_temp.en_tant_que(:'dir_id');

-- ---------------------------------------------------------------------------
-- 3. Brouillard multi-lignes, validation, numérotation continue
-- ---------------------------------------------------------------------------
SELECT public.enregistrer_piece(:'etab', :'jcai', '2026-10-05', 'Encaissements du 5 octobre',
  jsonb_build_array(
    jsonb_build_object('compte_id', :'c571', 'debit', 600000),
    jsonb_build_object('compte_id', :'c70521', 'credit', 500000, 'libelle', 'Scolarité'),
    jsonb_build_object('compte_id', :'c70523', 'credit', 50000, 'libelle', 'Cantine')),
  'Reçus 001 à 012') AS pa \gset
SELECT is((SELECT statut || '|' || coalesce(numero::text, 'sans numéro') FROM public.pieces_comptables WHERE id = :'pa'),
  'brouillard|sans numéro', 'un brouillard n''a pas de numéro');
SELECT throws_ok(format($$SELECT public.valider_piece(%L)$$, :'pa'), 'PIECE_DESEQUILIBREE',
  'pièce déséquilibrée : validation refusée');
SELECT public.enregistrer_piece(:'etab', :'jcai', '2026-10-05', 'Encaissements du 5 octobre',
  jsonb_build_array(
    jsonb_build_object('compte_id', :'c571', 'debit', 600000),
    jsonb_build_object('compte_id', :'c70521', 'credit', 500000, 'libelle', 'Scolarité'),
    jsonb_build_object('compte_id', :'c70523', 'credit', 100000, 'libelle', 'Cantine')),
  'Reçus 001 à 012', :'pa');
SELECT is((SELECT count(*)::int FROM public.lignes_pieces_comptables WHERE piece_id = :'pa'), 3,
  'brouillard corrigé : lignes remplacées, pas ajoutées');
SELECT is(public.valider_piece(:'pa'), 'CAI-2026-000001', 'validée : référence journal-année-numéro');

SELECT public.enregistrer_piece(:'etab', :'jcai', '2026-10-08', 'Brouillard abandonné',
  jsonb_build_array(jsonb_build_object('compte_id', :'c571', 'debit', 1), jsonb_build_object('compte_id', :'c70521', 'credit', 1))) AS pdraft \gset
SELECT lives_ok(format($$SELECT public.supprimer_brouillard(%L)$$, :'pdraft'), 'un brouillard se supprime');
SELECT public.enregistrer_piece(:'etab', :'jcai', '2026-10-10', 'Inscriptions',
  jsonb_build_array(jsonb_build_object('compte_id', :'c571', 'debit', 200000), jsonb_build_object('compte_id', :'c70522', 'credit', 200000))) AS pb \gset
SELECT is(public.valider_piece(:'pb'), 'CAI-2026-000002', 'numérotation continue : pas de trou après un brouillard supprimé');

-- ---------------------------------------------------------------------------
-- 4. Irréversibilité
-- ---------------------------------------------------------------------------
SELECT throws_ok(format($$SELECT public.enregistrer_piece(%L, %L, '2026-10-10', 'Retouche',
  jsonb_build_array(jsonb_build_object('compte_id', %L, 'debit', 1), jsonb_build_object('compte_id', %L, 'credit', 1)), NULL, %L)$$,
  :'etab', :'jcai', :'c571', :'c70522', :'pb'), 'PIECE_VALIDEE_IMMUABLE', 'une pièce validée ne se ressaisit pas');
SELECT throws_ok(format($$SELECT public.supprimer_brouillard(%L)$$, :'pb'), 'PIECE_VALIDEE_IMMUABLE',
  'ni ne se supprime');
SELECT throws_ok(format($$UPDATE public.pieces_comptables SET libelle = 'X' WHERE id = %L$$, :'pb'), '42501', NULL,
  'aucune écriture directe sur les pièces');
SELECT throws_ok(format($$INSERT INTO public.ecritures_comptables (etablissement_id, libelle, compte_debit_id, compte_credit_id, montant, journal_id)
  VALUES (%L, 'Ancienne saisie', %L, %L, 1000, %L)$$, :'etab', :'c571', :'c70521', :'jcai'),
  'SAISIE_PAR_PIECES_OBLIGATOIRE', 'OHADA : la saisie à deux comptes M14 est fermée');
RESET ROLE;
SELECT throws_ok(format($$UPDATE public.pieces_comptables SET libelle = 'X' WHERE id = %L$$, :'pb'),
  'PIECE_VALIDEE_IMMUABLE', 'même sans passer par les fonctions, une pièce validée est figée');
SELECT throws_ok(format($$UPDATE public.lignes_pieces_comptables SET debit = 1 WHERE piece_id = %L AND debit > 0$$, :'pb'),
  'PIECE_VALIDEE_IMMUABLE', 'ses lignes aussi');
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');

-- ---------------------------------------------------------------------------
-- 5. Contre-passation (art. 20)
-- ---------------------------------------------------------------------------
SELECT throws_ok(format($$SELECT public.contrepasser_piece(%L, '  ', '2026-10-12')$$, :'pb'), 'MOTIF_REQUIS',
  'contre-passation motivée');
SELECT public.contrepasser_piece(:'pb', 'Double saisie', '2026-10-12') AS pc \gset
SELECT is((SELECT reference || '|' || origine || '|' || statut FROM public.pieces_comptables WHERE id = :'pc'),
  'CAI-2026-000003|contrepassation|validee', 'contre-passation numérotée et validée');
SELECT is((SELECT sum(debit)::numeric FROM public.lignes_pieces_comptables WHERE piece_id = :'pc'), -200000::numeric,
  'inscription en négatif');
SELECT is((SELECT annulee_par_piece_id FROM public.pieces_comptables WHERE id = :'pb'), :'pc'::uuid,
  'la pièce d''origine pointe vers sa contre-passation');
SELECT throws_ok(format($$SELECT public.contrepasser_piece(%L, 'Encore', '2026-10-12')$$, :'pb'), 'PIECE_DEJA_CONTREPASSEE',
  'une pièce ne se contre-passe qu''une fois');
SELECT throws_ok(format($$SELECT public.contrepasser_piece(%L, 'Annuler l''annulation', '2026-10-12')$$, :'pc'), 'PIECE_NON_CONTREPASSABLE',
  'une contre-passation ne se contre-passe pas');

-- ---------------------------------------------------------------------------
-- 6. Documents
-- ---------------------------------------------------------------------------
SELECT is((SELECT solde_debit FROM public.balance_comptable(:'etab', '2026-12-31') WHERE code = '571'), 600000::numeric,
  'balance : caisse = 600 000 après contre-passation');
SELECT is((SELECT count(*)::int FROM public.grand_livre(:'etab', :'c571', '2026-01-01', '2026-12-31')), 3,
  'grand livre de la caisse : trois mouvements, contre-passation comprise');
SELECT ok((SELECT bool_or(libelle LIKE '[CAI-2026-000001]%') FROM public.journal_comptable(:'etab', :'jcai', '2026-01-01', '2026-12-31')),
  'journal : chaque ligne porte la référence de sa pièce');
SELECT throws_ok(format($$SELECT * FROM public.mouvements_comptables(%L, NULL, NULL)$$, :'etab'), '42501', NULL,
  'fonction interne des mouvements inaccessible aux clients');

-- ---------------------------------------------------------------------------
-- 7. Clôture de période (art. 22 3°)
-- ---------------------------------------------------------------------------
SELECT public.enregistrer_piece(:'etab', :'jcai', '2026-10-20', 'En attente',
  jsonb_build_array(jsonb_build_object('compte_id', :'c571', 'debit', 1), jsonb_build_object('compte_id', :'c70521', 'credit', 1))) AS pattente \gset
SELECT throws_ok(format($$SELECT public.cloturer_periode(%L, '2026-10-31')$$, :'etab'), 'BROUILLARDS_EN_ATTENTE',
  'pas de clôture de période avec des brouillards en attente');
SELECT public.supprimer_brouillard(:'pattente');
SELECT is(public.cloturer_periode(:'etab', '2026-10-31'), '2026-10-31'::date, 'octobre clôturé');
SELECT throws_ok(format($$SELECT public.enregistrer_piece(%L, %L, '2026-10-15', 'Trop tard',
  jsonb_build_array(jsonb_build_object('compte_id', %L, 'debit', 1), jsonb_build_object('compte_id', %L, 'credit', 1)))$$,
  :'etab', :'jcai', :'c571', :'c70521'), 'PERIODE_CLOTUREE', 'plus aucune pièce dans une période clôturée');

-- ---------------------------------------------------------------------------
-- 8. Clôture d'exercice
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok(format($$SELECT public.cloturer_exercice(%L)$$, :'ex2026'), '42501', NULL,
  'seule la Direction clôture un exercice');
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.cloturer_exercice(:'ex2026') AS cloture \gset
SELECT is((:'cloture'::jsonb->>'resultat')::numeric, 600000::numeric, 'résultat 2026 : 600 000 d''excédent');
SELECT is((SELECT reference FROM public.pieces_comptables WHERE id = (:'cloture'::jsonb->>'piece_a_nouveaux_id')::uuid),
  'AN-2027-000001', 'à-nouveaux validés dans le journal AN de l''exercice suivant');
SELECT is((SELECT date_debut || '|' || date_fin FROM public.exercices_comptables WHERE id = (:'cloture'::jsonb->>'exercice_suivant_id')::uuid),
  '2027-01-01|2027-12-31', 'exercice 2027 ouvert automatiquement (année civile)');
SELECT is((SELECT solde_debit FROM public.balance_comptable(:'etab', '2027-01-01') WHERE code = '571'), 600000::numeric,
  'balance d''ouverture 2027 : caisse reportée');
SELECT is((SELECT solde_credit FROM public.balance_comptable(:'etab', '2027-01-01') WHERE code = '131'), 600000::numeric,
  'excédent porté au compte 131');
SELECT is((SELECT total_credit FROM public.balance_comptable(:'etab', '2027-01-01') WHERE code = '70521'), 0::numeric,
  'les comptes de produits repartent de zéro');
SELECT throws_ok(format($$SELECT public.contrepasser_piece(%L, 'Erreur découverte', '2027-01-15')$$, :'pa'), 'PIECE_EXERCICE_CLOTURE',
  'une pièce d''un exercice clôturé ne se contre-passe plus (report à nouveau)');
SELECT throws_ok(format($$SELECT public.cloturer_exercice(%L)$$, :'ex2026'), 'EXERCICE_DEJA_CLOTURE',
  'un exercice ne se clôture qu''une fois');

-- ---------------------------------------------------------------------------
-- 9. Plan simplifié : écritures M14, période et exercice clôturés
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir3_id');
INSERT INTO public.journaux (etablissement_id, code, intitule, type) VALUES (:'etab3', 'OD', 'Opérations', 'operations')
RETURNING id AS j3 \gset
INSERT INTO public.plans_comptables (etablissement_id, code, intitule, type) VALUES
  (:'etab3', 'CAISSE', 'Caisse', 'caisse'), (:'etab3', 'SCOL', 'Scolarité', 'produit');
INSERT INTO public.ecritures_comptables (etablissement_id, libelle, compte_debit_id, compte_credit_id, montant, journal_id, date_ecriture)
SELECT :'etab3', 'Scolarité mars',
  (SELECT id FROM public.plans_comptables WHERE etablissement_id = :'etab3' AND code = 'CAISSE'),
  (SELECT id FROM public.plans_comptables WHERE etablissement_id = :'etab3' AND code = 'SCOL'), 100000, :'j3', '2026-03-01';
SELECT public.ouvrir_exercice(:'etab3', '2025-09-01', '2026-08-31') AS ex3 \gset
SELECT public.cloturer_periode(:'etab3', '2026-06-30');
SELECT throws_ok(format($$INSERT INTO public.ecritures_comptables (etablissement_id, libelle, compte_debit_id, compte_credit_id, montant, journal_id, date_ecriture)
  VALUES (%L, 'Rétroactive', (SELECT id FROM public.plans_comptables WHERE etablissement_id = %L AND code = 'CAISSE'),
          (SELECT id FROM public.plans_comptables WHERE etablissement_id = %L AND code = 'SCOL'), 5000, %L, '2026-05-01')$$,
  :'etab3', :'etab3', :'etab3', :'j3'), 'PERIODE_CLOTUREE', 'simplifié : écriture M14 refusée en période clôturée');
SELECT throws_ok(format($$UPDATE public.ecritures_comptables SET montant = 1 WHERE etablissement_id = %L$$, :'etab3'),
  'PERIODE_CLOTUREE', 'et une écriture d''une période clôturée ne se modifie plus');
INSERT INTO public.ecritures_comptables (etablissement_id, libelle, compte_debit_id, compte_credit_id, montant, journal_id, date_ecriture)
SELECT :'etab3', 'Scolarité juillet',
  (SELECT id FROM public.plans_comptables WHERE etablissement_id = :'etab3' AND code = 'CAISSE'),
  (SELECT id FROM public.plans_comptables WHERE etablissement_id = :'etab3' AND code = 'SCOL'), 50000, :'j3', '2026-07-01';
SELECT is((public.cloturer_exercice(:'ex3')->>'resultat')::numeric, 150000::numeric,
  'simplifié : exercice scolaire clôturé, résultat calculé sur les écritures M14');
SELECT is((SELECT solde_credit FROM public.balance_comptable(:'etab3', '2026-09-01') WHERE code = '13'), 150000::numeric,
  'simplifié : compte 13 créé et crédité du résultat');

-- ---------------------------------------------------------------------------
-- 10. Isolation
-- ---------------------------------------------------------------------------
SELECT is((SELECT count(*)::int FROM public.pieces_comptables WHERE etablissement_id = :'etab'), 0,
  'la Direction d''un autre établissement ne voit pas ces pièces');

SELECT * FROM finish();
ROLLBACK;
