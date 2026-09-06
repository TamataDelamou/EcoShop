-- ============================================================================
-- EcoShop — Test RLS 24 : validation des anomalies et recommandations (M10)
--
-- Vérifie que :
--   • la direction (permission rapports.administrer) valide une anomalie ;
--   • la direction valide une recommandation stratégique ;
--   • un enseignant sans la permission ne peut ni valider une anomalie ni une
--     recommandation (écriture d'administration réservée) ;
--   • le personnel (y compris enseignant) peut lire les anomalies.
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

SELECT plan(5);

-- ---------------------------------------------------------------------------
-- Tenant + année + comptes (direction administrateur, enseignant simple)
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Admin M10', 'ecole-admin-m10') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

SELECT pg_temp.creer_compte('224600001321', 'direction')  AS dir_id \gset
SELECT pg_temp.creer_compte('224600001322', 'enseignant') AS ens_id \gset

-- Poste « Direction » avec la permission d'administration des rapports.
INSERT INTO public.postes (etablissement_id, code, nom)
VALUES (:'etab_id'::uuid, 'DIRECTION', 'Direction')
ON CONFLICT DO NOTHING;

SELECT id AS poste_id FROM public.postes
WHERE etablissement_id = :'etab_id'::uuid AND code = 'DIRECTION' AND deleted_at IS NULL \gset

INSERT INTO public.poste_permissions (poste_id, permission_code)
VALUES (:'poste_id'::uuid, 'rapports.administrer') ON CONFLICT DO NOTHING;

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement, poste_id)
VALUES (:'dir_id'::uuid, :'etab_id'::uuid, 'direction', :'poste_id'::uuid);

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'ens_id'::uuid, :'etab_id'::uuid, 'enseignant');

-- ---------------------------------------------------------------------------
-- Une anomalie et une recommandation en attente de validation humaine
-- ---------------------------------------------------------------------------
INSERT INTO public.anomalies_statistiques
  (etablissement_id, annee_scolaire_id, type, severite, description, signature, statut)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, 'note', 'moyenne',
        'Note aberrante à valider', 'sig-anomalie-test', 'ouverte')
RETURNING id AS anomalie_id \gset

INSERT INTO public.recommandations_strategiques
  (etablissement_id, annee_scolaire_id, type, titre, description, justification, priorite, statut)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, 'tutorat',
        'Plan de tutorat', 'Classe à risque', '{"score_risque": 0.65}'::jsonb, 'haute', 'proposee')
RETURNING id AS reco_id \gset

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

-- 1. La direction lit les anomalies (personnel).
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.anomalies_statistiques)::int, 1,
          'direction : lit les anomalies');

-- 2. La direction valide l'anomalie (permission d'administration).
UPDATE public.anomalies_statistiques
   SET statut = 'confirmee', traitee_le = now()
 WHERE id = :'anomalie_id'::uuid;
SELECT is((SELECT statut FROM public.anomalies_statistiques WHERE id = :'anomalie_id'::uuid),
          'confirmee', 'direction : valide une anomalie');

-- 3. La direction valide la recommandation.
UPDATE public.recommandations_strategiques
   SET statut = 'validee', validee_le = now()
 WHERE id = :'reco_id'::uuid;
SELECT is((SELECT statut FROM public.recommandations_strategiques WHERE id = :'reco_id'::uuid),
          'validee', 'direction : valide une recommandation');

-- 4. L'enseignant (personnel sans permission) ne peut pas valider une anomalie.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'ens_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ UPDATE public.anomalies_statistiques SET statut = 'traitee' WHERE signature = 'sig-anomalie-test' $$,
  '42501',
  'enseignant : validation d''anomalie interdite sans permission'
);

-- 5. L'enseignant ne peut pas valider une recommandation.
SELECT throws_ok(
  $$ UPDATE public.recommandations_strategiques SET statut = 'mise_en_oeuvre' WHERE type = 'tutorat' $$,
  '42501',
  'enseignant : validation de recommandation interdite sans permission'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
