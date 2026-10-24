-- ============================================================================
-- EcoShop — Test RLS 87 : données de référence livrées par migration
-- (migration 20260906001560)
--
-- Couvre :
--   • Guinée complète : 4 cycles, 16 niveaux contigus de la Petite section
--     à la Terminale, Grande section → CP1, examens CEE/BEPC/Bac, niveaux
--     d'examen CM2, 10e, Terminale ;
--   • Sénégal et Ghana publiés ; langue en code ISO (recopiée dans
--     etablissements.langue_code) ;
--   • liste des pays lisible sans compte (écran de demande d'ouverture) ;
--   • demande d'ouverture acceptée pour la Guinée ;
--   • paramètres globaux présents ; grade < -3 refusé ;
--   • contrôle de préparation : lignes vertes, puis rouges quand un
--     paramètre manque, qu'un pays n'a pas d'examen ou qu'aucun pays n'est
--     ouvert.
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

CREATE OR REPLACE FUNCTION pg_temp.controle(p_etat jsonb, p_nom text) RETURNS jsonb
LANGUAGE sql AS $$
  SELECT c FROM jsonb_array_elements(p_etat -> 'controles') c WHERE c ->> 'controle' = p_nom;
$$;

SELECT plan(24);

-- ---------------------------------------------------------------------------
-- Guinée
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT string_agg(code, ',' ORDER BY ordre) FROM public.cycles_educatifs WHERE pays_code = 'GN' AND statut = 'publie'),
  'prescolaire,primaire,college,lycee',
  'Guinée : préscolaire, primaire, collège, lycée');

SELECT is(
  (SELECT string_agg(code, ',' ORDER BY grade_level_normalise) FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND statut = 'publie'),
  'PS,MS,GS,CP1,CP2,CE1,CE2,CM1,CM2,7e,8e,9e,10e,11e,12e,Terminale',
  'Guinée : 16 niveaux, de la Petite section à la Terminale');

SELECT is(
  (SELECT max(grade_level_normalise) - min(grade_level_normalise) + 1 FROM public.niveaux_educatifs WHERE pays_code = 'GN'),
  16, 'grille contiguë, sans trou');

SELECT is(
  (SELECT n2.code FROM public.niveaux_educatifs n2
   WHERE n2.id = public.niveau_suivant((SELECT id FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND code = 'GS'))),
  'CP1', 'après la Grande section vient le CP1');

SELECT is(
  (SELECT n2.code FROM public.niveaux_educatifs n2
   WHERE n2.id = public.niveau_suivant((SELECT id FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND code = '12e'))),
  'Terminale', 'après la 12e vient la Terminale');

SELECT is(
  (SELECT string_agg(x.code || '@' || c.code, ',' ORDER BY c.ordre)
   FROM public.examens_nationaux x JOIN public.cycles_educatifs c ON c.id = x.cycle_id
   WHERE x.pays_code = 'GN' AND x.statut = 'publie'),
  'CEE@primaire,BEPC@college,BAC@lycee',
  'Guinée : CEE, BEPC et Bac rattachés à leur cycle');

SELECT is(
  (SELECT string_agg(code, ',' ORDER BY grade_level_normalise) FROM public.niveaux_educatifs
   WHERE pays_code = 'GN' AND est_niveau_examinateur),
  'CM2,10e,Terminale', 'Guinée : classes d''examen en CM2, 10e et Terminale');

SELECT is(
  (SELECT langue_enseignement_principale || '/' || devise_code || '/' || statut_deploiement
   FROM public.pays_pedagogiques WHERE code_iso = 'GN'),
  'fr/GNF/deploye', 'Guinée ouverte, langue en code, devise GNF');

-- ---------------------------------------------------------------------------
-- Sénégal et Ghana
-- ---------------------------------------------------------------------------
SELECT is((SELECT count(*)::int FROM public.niveaux_educatifs WHERE pays_code = 'SN' AND statut = 'publie'), 13,
  'Sénégal : 13 niveaux (CI → Terminale)');
SELECT is((SELECT string_agg(code, ',' ORDER BY code) FROM public.examens_nationaux WHERE pays_code = 'SN'), 'BAC,BFEM,CFEE',
  'Sénégal : CFEE, BFEM, Bac');
SELECT is((SELECT count(*)::int FROM public.niveaux_educatifs WHERE pays_code = 'GH' AND statut = 'publie'), 12,
  'Ghana : 12 niveaux (P1 → SHS3)');
SELECT is((SELECT string_agg(code, ',' ORDER BY code) FROM public.examens_nationaux WHERE pays_code = 'GH'), 'BECE,WASSCE',
  'Ghana : BECE, WASSCE');

-- ---------------------------------------------------------------------------
-- Lecture sans compte (écran de demande d'ouverture)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SELECT ok((SELECT array_agg(code_iso ORDER BY code_iso) FROM public.pays_pedagogiques) @> ARRAY['GH', 'GN', 'SN'],
  'la liste des pays se lit sans compte');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- Demande d'ouverture pour la Guinée, puis acceptation
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224687000001') AS fondateur \gset
SELECT pg_temp.creer_compte('224687000002', 'admin_gsg') AS admin \gset

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'fondateur');
SELECT public.soumettre_demande_etablissement('École Référentiel 87', 'GN', 'Kindia', '+224 620 87 00 01') AS demande \gset
SELECT ok(:'demande' IS NOT NULL, 'demande d''ouverture enregistrée pour la Guinée');

SELECT pg_temp.en_tant_que(:'admin');
SELECT public.traiter_demande_etablissement(:'demande'::uuid, 'acceptee') AS decision \gset
RESET ROLE;
SELECT is(
  (SELECT pays_code || '/' || devise_code || '/' || langue_code FROM public.etablissements
   WHERE id = (:'decision'::jsonb ->> 'etablissement_id')::uuid),
  'GN/GNF/fr', 'école créée avec la devise et la langue de la Guinée');

-- ---------------------------------------------------------------------------
-- Paramètres globaux et garde de la grille
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM public.parametres_globaux_attendus() a(cle)
   WHERE NOT EXISTS (SELECT 1 FROM public.parametres_globaux g WHERE g.cle = a.cle)),
  0, 'tous les paramètres globaux attendus sont présents');
SELECT is((SELECT (valeur ->> 'valeur')::int FROM public.parametres_globaux WHERE cle = 'seuil_effectif_gratuit'), 100,
  'seuil de gratuité livré (facturation)');

SELECT throws_ok(
  $$ INSERT INTO public.niveaux_educatifs (cycle_id, pays_code, code, nom, grade_level_normalise, isced, ordre)
     SELECT id, 'GN', 'TROP_TOT', 'Trop tôt', -4, 0, 9 FROM public.cycles_educatifs WHERE pays_code = 'GN' AND code = 'prescolaire' $$,
  '23514', NULL, 'grade inférieur à -3 refusé');

-- ---------------------------------------------------------------------------
-- Contrôle de préparation
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'admin');
SELECT public.etat_mise_en_service() AS etat \gset
RESET ROLE;
SELECT is((pg_temp.controle(:'etat', 'Référentiel : pays ouverts') ->> 'ok')::boolean, true, 'pays ouverts : vert');
SELECT is((pg_temp.controle(:'etat', 'Référentiel : cycles, niveaux, examens') ->> 'ok')::boolean, true, 'référentiel complet : vert');
SELECT is((pg_temp.controle(:'etat', 'Paramètres globaux') ->> 'ok')::boolean, true, 'paramètres globaux : vert');

-- Un paramètre manque, le Sénégal perd ses examens.
DELETE FROM public.parametres_globaux WHERE cle = 'devise_defaut';
UPDATE public.examens_nationaux SET statut = 'brouillon' WHERE pays_code = 'SN';
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'admin');
SELECT public.etat_mise_en_service() AS etat \gset
RESET ROLE;
SELECT is(pg_temp.controle(:'etat', 'Paramètres globaux') ->> 'detail', 'manquants : devise_defaut',
  'paramètre manquant nommé');
SELECT is(pg_temp.controle(:'etat', 'Référentiel : cycles, niveaux, examens') ->> 'detail', 'incomplet : SN (aucun examen)',
  'pays sans examen nommé');

-- Aucun pays ouvert : la demande d'ouverture n'aurait rien à proposer.
UPDATE public.pays_pedagogiques SET statut_deploiement = 'brouillon';
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'admin');
SELECT public.etat_mise_en_service() AS etat \gset
RESET ROLE;
SELECT is((pg_temp.controle(:'etat', 'Référentiel : pays ouverts') ->> 'ok')::boolean, false, 'aucun pays ouvert : rouge');

SELECT * FROM finish();
ROLLBACK;
