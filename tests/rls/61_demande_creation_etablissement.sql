-- ============================================================================
-- EcoShop — Test RLS 61 : demande de création d'établissement (REG-04,
-- migration 20260906001532 ; cahier §5.3 et §30.1)
--
-- Couvre :
--   • soumission par un compte neuf (rôle non choisi) ; refus d'un compte
--     élève/parent ; une seule demande en cours ; pays inconnu refusé ;
--     téléphone mal formé refusé ;
--   • aucune écriture directe ; le demandeur ne voit que ses demandes ;
--   • traitement réservé à l'admin GSG ; refus motivé obligatoire ;
--   • acceptation : établissement créé avec la devise et la langue du pays,
--     demandeur devenu Direction, rattaché, établissement actif ; demande
--     non traitable deux fois ;
--   • après un refus, une nouvelle demande est possible.
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

SELECT plan(20);

INSERT INTO public.systemes_educatifs (code, nom)
SELECT 'francophone_cfa', 'Francophone CFA'
WHERE NOT EXISTS (SELECT 1 FROM public.systemes_educatifs WHERE code = 'francophone_cfa');
INSERT INTO public.pays_pedagogiques (code_iso, nom, type_systeme, langue_enseignement_principale, devise_code, statut_deploiement)
VALUES ('GN', 'Guinée', 'francophone_cfa', 'fr', 'GNF', 'deploye')
ON CONFLICT (code_iso) DO NOTHING;

SELECT pg_temp.creer_compte('224661000001')              AS fondateur_id \gset
SELECT pg_temp.creer_compte('224661000002', 'parent')    AS parent_id    \gset
SELECT pg_temp.creer_compte('224661000003', 'admin_gsg') AS admin_id     \gset
SELECT pg_temp.creer_compte('224661000004')              AS autre_id     \gset

SET LOCAL ROLE authenticated;

-- ---------------------------------------------------------------------------
-- 1. Soumission
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok(
  $$ SELECT public.soumettre_demande_etablissement('École X', 'GN', 'Conakry', '+224 620 00 00 00') $$,
  '42501', 'ROLE_INCOMPATIBLE', 'un compte parent ne peut pas demander la création d''une école');

SELECT pg_temp.en_tant_que(:'fondateur_id');
SELECT throws_ok(
  $$ SELECT public.soumettre_demande_etablissement('École X', 'ZZ', 'Conakry', '+224 620 00 00 00') $$,
  '22023', 'PAYS_INCONNU', 'pays absent du référentiel refusé');
SELECT throws_ok(
  $$ SELECT public.soumettre_demande_etablissement('École X', 'GN', 'Conakry', 'abc') $$,
  '22023', 'DEMANDE_INVALIDE', 'téléphone mal formé refusé');

SELECT public.soumettre_demande_etablissement(
  'Groupe Scolaire Bambino Emmaüs', 'gn', 'Conakry', '+224 620 11 22 33',
  'Ratoma, Kipé', 'Direction@Bambino.gn', 650, 'AUT-2026-001', 'Ouverture prévue en novembre'
) AS demande1 \gset
SELECT isnt(:'demande1'::uuid, NULL::uuid, 'compte neuf : demande soumise');

SELECT results_eq(
  format($$ SELECT pays_code, email, statut FROM public.demandes_etablissement WHERE id = %L $$, :'demande1'),
  $$ VALUES ('GN', 'direction@bambino.gn', 'en_attente') $$,
  'données normalisées (pays en majuscules, courriel en minuscules), statut en attente');

SELECT throws_ok(
  $$ SELECT public.soumettre_demande_etablissement('Autre école', 'GN', 'Kindia', '+224 620 11 22 34') $$,
  '55000', 'DEMANDE_DEJA_EN_COURS', 'une seule demande en cours par compte');

SELECT throws_ok(
  format($$ UPDATE public.demandes_etablissement SET statut = 'acceptee' WHERE id = %L $$, :'demande1'),
  '42501', NULL, 'aucune écriture directe sur les demandes');

SELECT throws_ok(
  format($$ SELECT public.traiter_demande_etablissement(%L, 'acceptee') $$, :'demande1'),
  '42501', 'ACCES_REFUSE', 'le demandeur ne valide pas sa propre demande');

SELECT pg_temp.en_tant_que(:'autre_id');
SELECT is((SELECT count(*) FROM public.demandes_etablissement), 0::bigint,
  'un autre compte ne voit pas la demande');
SELECT public.soumettre_demande_etablissement('École Lumière', 'GN', 'Kindia', '+224 621 00 00 01') AS demande2 \gset

-- ---------------------------------------------------------------------------
-- 2. Traitement par l'admin GSG
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'admin_id');
SELECT is(jsonb_array_length(public.demandes_etablissement_a_traiter()), 2, 'file du backoffice : 2 demandes');

SELECT throws_ok(
  format($$ SELECT public.traiter_demande_etablissement(%L, 'refusee', '  ') $$, :'demande2'),
  '22023', 'MOTIF_REQUIS', 'un refus doit être motivé');
SELECT is(
  public.traiter_demande_etablissement(:'demande2'::uuid, 'refusee', 'Numéro d''autorisation manquant') ->> 'statut',
  'refusee', 'refus motivé enregistré');

SELECT public.traiter_demande_etablissement(:'demande1'::uuid, 'acceptee') ->> 'etablissement_id' AS etab_id \gset
SELECT isnt(:'etab_id'::uuid, NULL::uuid, 'acceptation : établissement créé');
SELECT throws_ok(
  format($$ SELECT public.traiter_demande_etablissement(%L, 'acceptee') $$, :'demande1'),
  '55000', 'DEMANDE_DEJA_TRAITEE', 'une demande ne se traite qu''une fois');
RESET ROLE;

SELECT results_eq(
  format($$ SELECT nom, pays_code, ville, devise_code, langue_code, fuseau_horaire, statut FROM public.etablissements WHERE id = %L $$, :'etab_id'),
  $$ VALUES ('Groupe Scolaire Bambino Emmaüs', 'GN', 'Conakry', 'GNF', 'fr', 'Africa/Conakry', 'actif') $$,
  'établissement créé avec la devise, la langue et le fuseau du pays');
SELECT matches((SELECT slug FROM public.etablissements WHERE id = :'etab_id'::uuid),
  '^groupe-scolaire-bambino-emmaus-[0-9a-f]{6}$', 'identifiant lisible et unique (accents retirés)');
SELECT results_eq(
  format($$ SELECT role_racine::text, etablissement_actif_id FROM public.profiles WHERE id = %L $$, :'fondateur_id'),
  format($$ VALUES ('direction', %L::uuid) $$, :'etab_id'),
  'le fondateur devient Direction et l''établissement devient son établissement actif');
SELECT is(
  (SELECT role_dans_etablissement FROM public.etablissements_membres
    WHERE profile_id = :'fondateur_id'::uuid AND etablissement_id = :'etab_id'::uuid AND actif),
  'direction', 'le fondateur est rattaché comme Direction');

-- ---------------------------------------------------------------------------
-- 3. Après un refus : nouvelle demande possible, motif visible
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'autre_id');
SELECT is((SELECT motif_refus FROM public.demandes_etablissement WHERE id = :'demande2'::uuid),
  'Numéro d''autorisation manquant', 'le demandeur lit le motif du refus');
SELECT lives_ok(
  $$ SELECT public.soumettre_demande_etablissement('École Lumière', 'GN', 'Kindia', '+224 621 00 00 01',
       NULL, NULL, NULL, 'AUT-2026-777') $$,
  'nouvelle demande corrigée possible après un refus');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
