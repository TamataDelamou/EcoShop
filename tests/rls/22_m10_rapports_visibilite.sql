-- ============================================================================
-- EcoShop — Test RLS 22 : visibilité des rapports et indicateurs (M10)
--
-- Vérifie que :
--   • le personnel voit tous les rapports (individuels et de classe) et les KPI ;
--   • le parent confirmé ne voit que le rapport individuel de son enfant ;
--   • l'élève ne voit que son propre rapport individuel ;
--   • un compte étranger ne voit aucun rapport ;
--   • les indicateurs clés restent réservés au personnel (pas aux parents).
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

SELECT plan(6);

-- ---------------------------------------------------------------------------
-- Tenant + année + classe + comptes
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Rapports M10', 'ecole-rap-m10') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '6A', '6e A') RETURNING id AS classe_id \gset

SELECT pg_temp.creer_compte('224600001301', 'enseignant') AS prof_id \gset
SELECT pg_temp.creer_compte('224600001302', 'parent')     AS parent_id \gset
SELECT pg_temp.creer_compte('224600001303', 'eleve')      AS eleve_id \gset
SELECT pg_temp.creer_compte('224600001304', 'eleve')      AS etranger_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M10-VIS-001', 'DIALLO', 'Aminata', '2010-03-08', :'eleve_id'::uuid, now())
RETURNING id AS fiche_id \gset

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES (:'etab_id'::uuid, :'fiche_id'::uuid, :'classe_id'::uuid, :'annee_id'::uuid, 'active');

INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
VALUES (:'etab_id'::uuid, :'parent_id'::uuid, :'fiche_id'::uuid, 'tuteur_legal', 'confirmee', true);

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'prof_id'::uuid, :'etab_id'::uuid, 'enseignant');

-- ---------------------------------------------------------------------------
-- Un rapport individuel (bulletin élève) + un rapport de classe (relevé) + un KPI
-- ---------------------------------------------------------------------------
INSERT INTO public.rapports
  (etablissement_id, annee_scolaire_id, fiche_eleve_id, type, format, statut)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'fiche_id'::uuid, 'bulletin', 'pdf', 'genere');

INSERT INTO public.rapports
  (etablissement_id, annee_scolaire_id, classe_id, type, format, statut)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, 'releve_notes', 'excel', 'demande');

INSERT INTO public.indicateurs_cles (etablissement_id, annee_scolaire_id, code, valeur_numeric)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, 'effectifs', 15);

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.rapports)::int, 2, 'personnel : voit tous les rapports');
SELECT is((SELECT count(*) FROM public.indicateurs_cles)::int, 1, 'personnel : voit les KPI');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'parent_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.rapports)::int, 1, 'parent : voit le rapport individuel de son enfant');
SELECT is((SELECT count(*) FROM public.indicateurs_cles)::int, 0, 'parent : aucun KPI (réservé personnel)');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.rapports)::int, 1, 'élève : voit son propre rapport');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.rapports)::int, 0, 'étranger : aucun rapport visible');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
