-- ============================================================================
-- EcoShop — Test 26 : fonctions IA de la planification (M11)
--
-- Vérifie :
--   • suggerer_placement_seance : premier créneau libre (CSP glouton) ;
--   • charger_travail_enseignant : heures hebdo calculées ;
--   • charger_travail_eleve : charge de la classe ;
--   • detecter_conflits_emploi : chevauchement de salle détecté ;
--   • recommander_seances : séance de rattrapage proposée (réussite faible) ;
--   • contrôle d'accès : un non-personnel ne peut pas lancer l'optimisation.
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
-- Tenant + année + 2 classes + 2 enseignants membres + 1 salle
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École IA M11', 'ecole-ia-m11') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

SELECT pg_temp.creer_compte('224600001411', 'enseignant') AS prof1_id \gset
SELECT pg_temp.creer_compte('224600001412', 'enseignant') AS prof2_id \gset
SELECT pg_temp.creer_compte('224600001413', 'eleve')      AS eleve_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'prof1_id'::uuid, :'etab_id'::uuid, 'enseignant'),
  (:'prof2_id'::uuid, :'etab_id'::uuid, 'enseignant');

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom, enseignant_principal_id)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '6A', '6e A', :'prof1_id'::uuid) RETURNING id AS classe_a_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '5A', '5e A') RETURNING id AS classe_b_id \gset

INSERT INTO public.salles (etablissement_id, code, nom, capacite)
VALUES (:'etab_id'::uuid, 'S1', 'Salle 1', 30) RETURNING id AS salle_id \gset

-- ---------------------------------------------------------------------------
-- Un créneau existant (classe A, prof1, salle S1 — lundi 08:00-09:00)
-- ---------------------------------------------------------------------------
INSERT INTO public.emplois_du_temps
  (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, salle_id, jour_semaine, heure_debut, heure_fin, type)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_a_id'::uuid, :'prof1_id'::uuid, :'salle_id'::uuid, 1, '08:00', '09:00', 'cours');

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'prof1_id', 'role', 'authenticated')::text, true);

-- 1. Le premier créneau libre après 08:00-09:00 est lundi 09:00-10:00.
SELECT is(
  public.suggerer_placement_seance(:'etab_id'::uuid, :'annee_id'::uuid, :'prof1_id'::uuid, :'classe_a_id'::uuid, :'salle_id'::uuid)->>'heure_debut',
  '09:00:00',
  'IA optimisation : premier créneau libre proposé'
);

-- 2. Charge enseignant : 1 h hebdo, pas de surcharge.
SELECT is(
  public.charger_travail_enseignant(:'etab_id'::uuid, :'annee_id'::uuid, :'prof1_id'::uuid)->>'heures_hebdo',
  '1.00',
  'IA prédiction : charge enseignant calculée'
);

-- 3. Charge élève/classe : 1 h hebdo.
SELECT is(
  public.charger_travail_eleve(:'classe_a_id'::uuid)->>'heures_hebdo',
  '1.00',
  'IA prédiction : charge de la classe calculée'
);

-- 4. Ajout d'un chevauchement de salle (classe B, prof2, même salle, 08:30-09:30)
--    puis détection d'un conflit.
RESET ROLE;
INSERT INTO public.emplois_du_temps
  (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, salle_id, jour_semaine, heure_debut, heure_fin, type)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_b_id'::uuid, :'prof2_id'::uuid, :'salle_id'::uuid, 1, '08:30', '09:30', 'cours');
SET LOCAL ROLE authenticated;

SELECT is(
  (SELECT count(*) FROM public.detecter_conflits_emploi(:'etab_id'::uuid, :'annee_id'::uuid))::int,
  1,
  'IA détection : chevauchement de salle signalé'
);

-- 5. Recommandation de séance : aucune note → réussite 0 < 0.6 → rattrapage proposé.
SELECT is(
  public.recommander_seances(:'etab_id'::uuid, :'annee_id'::uuid),
  1,
  'IA recommandation : séance de rattrapage proposée'
);

-- 6. Contrôle d'accès : un élève (non personnel) ne peut pas lancer l'optimisation.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.suggerer_placement_seance(NULL, NULL, NULL, NULL, NULL) $$,
  '42501',
  NULL
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
