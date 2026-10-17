-- ============================================================================
-- EcoShop — Test RLS 63 : référentiel comptable par établissement (REG-03 C1,
-- migration 20260906001534)
--
-- Couvre :
--   • recommandation : association/confessionnelle → SYCEBNL ; société sous
--     le seuil SMT → SMT ; au-dessus → normal ; refus de comptabilité
--     réglementaire respecté mais signalé ; seuil GNF marqué « à confirmer » ;
--   • choix réservé à la Direction ; plan de référence chargé (comptes
--     réglementaires, sous-comptes EcoShop, arborescence) ; anciens comptes
--     libres retirés ;
--   • comptes réglementaires ni modifiables ni supprimables ;
--   • sous-compte : doit prolonger un compte réglementaire, hérite de sa
--     nature et de son parent ; code libre refusé ;
--   • SMT ↔ normal possible même avec écritures ; changement de plan refusé
--     dès qu'une écriture existe ;
--   • plan simplifié (M14) inchangé : codes libres acceptés ;
--   • historique des choix ; aucune écriture directe des paramètres.
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

SELECT plan(30);

-- Deux établissements, une Direction chacun, un parent.
INSERT INTO public.etablissements (nom, slug, pays_code, ville, devise_code, langue_code, fuseau_horaire, statut)
VALUES ('École Bambino Test', 'bambino-test-63', 'GN', 'Conakry', 'GNF', 'fr', 'Africa/Conakry', 'actif')
RETURNING id AS etab \gset
INSERT INTO public.etablissements (nom, slug, pays_code, ville, devise_code, langue_code, fuseau_horaire, statut)
VALUES ('Lycée Privé Test', 'lycee-test-63', 'GN', 'Kindia', 'GNF', 'fr', 'Africa/Conakry', 'actif')
RETURNING id AS etab2 \gset

SELECT pg_temp.creer_compte('224663000001', 'direction') AS dir_id \gset
SELECT pg_temp.creer_compte('224663000002', 'direction') AS dir2_id \gset
SELECT pg_temp.creer_compte('224663000003', 'parent') AS parent_id \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement, actif) VALUES
  (:'dir_id', :'etab', 'direction', true),
  (:'dir2_id', :'etab2', 'direction', true),
  (:'parent_id', :'etab', 'parent', true);

-- Comptes libres hérités de la comptabilité simplifiée (sans écriture).
INSERT INTO public.plans_comptables (etablissement_id, code, intitule, type) VALUES
  (:'etab', '520', 'Banque', 'banque'),
  (:'etab', '701', 'Scolarité', 'produit');

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');

-- ---------------------------------------------------------------------------
-- 1. Recommandation
-- ---------------------------------------------------------------------------
SELECT is(public.recommander_referentiel_comptable('confessionnelle', NULL, 'GNF', true)->>'referentiel', 'sycebnl',
  'école confessionnelle → SYCEBNL');
SELECT is(public.recommander_referentiel_comptable('association', 1000000000, 'GNF', true)->>'referentiel', 'sycebnl',
  'association → SYCEBNL, quel que soit le chiffre d''affaires');
SELECT is(public.recommander_referentiel_comptable('societe', 300000000, 'GNF', true)->>'referentiel', 'syscohada_smt',
  'société sous le seuil SMT → Système minimal de trésorerie');
SELECT is(public.recommander_referentiel_comptable('societe', 900000000, 'GNF', true)->>'referentiel', 'syscohada_normal',
  'société au-dessus du seuil → Système normal');
SELECT is(public.recommander_referentiel_comptable('societe', 20000000, 'XOF', true)->>'referentiel', 'syscohada_smt',
  'seuil en FCFA (30 M) appliqué pour le XOF');
SELECT ok((public.recommander_referentiel_comptable('societe', 1, 'GNF', true)->>'seuil_a_confirmer')::boolean,
  'le seuil en GNF est signalé « à confirmer »');
SELECT is(public.recommander_referentiel_comptable('societe', 900000000, 'GNF', false)->>'referentiel', 'simplifie',
  'refus de comptabilité réglementaire respecté…');
SELECT ok(public.recommander_referentiel_comptable('societe', 900000000, 'GNF', false)->'alternatives' ? 'syscohada_normal',
  '… mais le référentiel légal reste proposé en alternative');

-- ---------------------------------------------------------------------------
-- 2. Choix : droits
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok(format($$SELECT public.choisir_referentiel_comptable(%L, 'sycebnl')$$, :'etab'), '42501', NULL,
  'un parent ne peut pas choisir le référentiel');
SELECT pg_temp.en_tant_que(:'dir2_id');
SELECT throws_ok(format($$SELECT public.choisir_referentiel_comptable(%L, 'sycebnl')$$, :'etab'), '42501', NULL,
  'la Direction d''un autre établissement non plus');
SELECT throws_ok(format($$INSERT INTO public.parametres_comptables (etablissement_id, referentiel) VALUES (%L, 'sycebnl')$$, :'etab2'),
  '42501', NULL, 'aucune écriture directe des paramètres');

-- ---------------------------------------------------------------------------
-- 3. Choix SYCEBNL par la Direction : chargement du plan
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT is((public.choisir_referentiel_comptable(:'etab', 'sycebnl', 'confessionnelle', 300000000)->>'comptes_charges')::int,
  (SELECT count(*)::int FROM public.plans_comptables_reference WHERE plan = 'sycebnl'),
  'tout le plan de référence SYCEBNL est chargé');
SELECT is(public.referentiel_comptable_de(:'etab'), 'sycebnl', 'référentiel enregistré');
SELECT is((SELECT intitule FROM public.plans_comptables WHERE etablissement_id = :'etab' AND code = '701' AND deleted_at IS NULL),
  'Cotisations des adhérents', 'le compte 701 prend l''intitulé réglementaire (l''ancien compte libre est remplacé)');
SELECT is((SELECT count(*)::int FROM public.plans_comptables WHERE etablissement_id = :'etab' AND code = '520' AND deleted_at IS NULL),
  0, 'l''ancien compte libre 520 est retiré');
SELECT is((SELECT p.code FROM public.plans_comptables c JOIN public.plans_comptables p ON p.id = c.parent_id
            WHERE c.etablissement_id = :'etab' AND c.code = '70521'), '7052',
  'arborescence : 70521 (scolarité) rattaché à 7052');
SELECT ok((SELECT extension_ecoshop FROM public.plans_comptables WHERE etablissement_id = :'etab' AND code = '5521'),
  'Orange Money (5521) identifié comme sous-compte EcoShop');

-- ---------------------------------------------------------------------------
-- 4. Comptes réglementaires protégés, sous-comptes encadrés
-- ---------------------------------------------------------------------------
SELECT throws_ok(format($$UPDATE public.plans_comptables SET intitule = 'X' WHERE etablissement_id = %L AND code = '571'$$, :'etab'),
  'COMPTE_REGLEMENTAIRE_PROTEGE', 'un compte réglementaire ne se renomme pas');
SELECT throws_ok(format($$UPDATE public.plans_comptables SET deleted_at = now() WHERE etablissement_id = %L AND code = '571'$$, :'etab'),
  'COMPTE_REGLEMENTAIRE_PROTEGE', 'ni ne se supprime');
SELECT throws_ok(format($$INSERT INTO public.plans_comptables (etablissement_id, code, intitule, type, reglementaire) VALUES (%L, '999', 'Faux', 'autre', true)$$, :'etab'),
  'COMPTE_REGLEMENTAIRE_PROTEGE', 'un utilisateur ne fabrique pas de compte réglementaire');
SELECT throws_ok(format($$INSERT INTO public.plans_comptables (etablissement_id, code, intitule, type) VALUES (%L, 'BANQUE2', 'Banque 2', 'banque')$$, :'etab'),
  'SOUS_COMPTE_INVALIDE', 'code libre refusé en référentiel OHADA');
SELECT throws_ok(format($$INSERT INTO public.plans_comptables (etablissement_id, code, intitule, type) VALUES (%L, '999', 'Hors plan', 'charge')$$, :'etab'),
  'SOUS_COMPTE_INVALIDE', 'un compte qui ne prolonge aucun compte réglementaire est refusé');
INSERT INTO public.plans_comptables (etablissement_id, code, intitule, type)
VALUES (:'etab', '52101', 'Ecobank — compte courant', 'autre');
SELECT is((SELECT c.type || '|' || p.code FROM public.plans_comptables c JOIN public.plans_comptables p ON p.id = c.parent_id
            WHERE c.etablissement_id = :'etab' AND c.code = '52101'), 'banque|521',
  'le sous-compte bancaire hérite de la nature « banque » et du parent 521');

-- ---------------------------------------------------------------------------
-- 5. Changement de référentiel et écritures existantes
-- ---------------------------------------------------------------------------
INSERT INTO public.journaux (etablissement_id, code, intitule, type) VALUES (:'etab', 'CAI', 'Caisse', 'caisse')
RETURNING id AS journal \gset
INSERT INTO public.ecritures_comptables (etablissement_id, libelle, compte_debit_id, compte_credit_id, montant, journal_id)
SELECT :'etab', 'Scolarité octobre',
  (SELECT id FROM public.plans_comptables WHERE etablissement_id = :'etab' AND code = '571'),
  (SELECT id FROM public.plans_comptables WHERE etablissement_id = :'etab' AND code = '70521'),
  500000, :'journal';

SELECT throws_ok(format($$SELECT public.choisir_referentiel_comptable(%L, 'syscohada_normal', 'societe')$$, :'etab'),
  'ECRITURES_EXISTANTES', 'changer de plan avec des écritures est refusé (réservé à l''ouverture d''exercice)');

-- Société : SYSCOHADA SMT puis passage au normal malgré des écritures.
SELECT pg_temp.en_tant_que(:'dir2_id');
SELECT public.choisir_referentiel_comptable(:'etab2', 'syscohada_smt', 'societe', 300000000);
SELECT is((SELECT intitule FROM public.plans_comptables WHERE etablissement_id = :'etab2' AND code = '70611'),
  'Frais de scolarité', 'plan SYSCOHADA chargé avec le sous-compte scolarité 70611');
INSERT INTO public.journaux (etablissement_id, code, intitule, type) VALUES (:'etab2', 'BQ', 'Banque', 'banque')
RETURNING id AS journal2 \gset
INSERT INTO public.ecritures_comptables (etablissement_id, libelle, compte_debit_id, compte_credit_id, montant, journal_id)
SELECT :'etab2', 'Scolarité',
  (SELECT id FROM public.plans_comptables WHERE etablissement_id = :'etab2' AND code = '521'),
  (SELECT id FROM public.plans_comptables WHERE etablissement_id = :'etab2' AND code = '70611'),
  750000, :'journal2';
SELECT is(public.choisir_referentiel_comptable(:'etab2', 'syscohada_normal')->>'comptes_charges', '0',
  'SMT → normal : même plan, aucun rechargement, autorisé malgré les écritures');
SELECT is(public.referentiel_comptable_de(:'etab2'), 'syscohada_normal', 'passage au Système normal enregistré');
SELECT is((SELECT forme_juridique FROM public.parametres_comptables WHERE etablissement_id = :'etab2'), 'societe',
  'la forme juridique déjà connue est conservée');

-- Retour au simplifié : le plan redevient ouvert.
SELECT public.choisir_referentiel_comptable(:'etab2', 'simplifie');
INSERT INTO public.plans_comptables (etablissement_id, code, intitule, type)
VALUES (:'etab2', 'DIVERS', 'Compte libre', 'autre');
SELECT is((SELECT count(*)::int FROM public.plans_comptables WHERE etablissement_id = :'etab2' AND reglementaire),
  0, 'retour au simplifié : plus aucun compte verrouillé, codes libres acceptés');

SELECT is((SELECT count(*)::int FROM public.historique_referentiels_comptables WHERE etablissement_id = :'etab2'),
  3, 'chaque choix est historisé');

SELECT * FROM finish();
ROLLBACK;
