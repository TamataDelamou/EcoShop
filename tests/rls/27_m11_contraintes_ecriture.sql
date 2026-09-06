-- ============================================================================
-- EcoShop — Test RLS 27 : permissions d'écriture de la planification (M11)
--
-- Vérifie que :
--   • la direction (planification.generer) crée des créneaux d'emploi du temps ;
--   • un enseignant sans permission ne peut pas créer de créneau ;
--   • la direction (planification.administrer) gère les contraintes ;
--   • un enseignant sans permission ne peut pas créer de contrainte ;
--   • la direction peut modifier une contrainte existante.
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
-- Tenant + année + classe + salle + comptes (direction administrateur, enseignant)
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Écrit M11', 'ecole-ecrit-m11') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '6A', '6e A') RETURNING id AS classe_id \gset

INSERT INTO public.salles (etablissement_id, code, nom, capacite)
VALUES (:'etab_id'::uuid, 'S1', 'Salle 1', 30) RETURNING id AS salle_id \gset

SELECT pg_temp.creer_compte('224600001421', 'direction')  AS dir_id \gset
SELECT pg_temp.creer_compte('224600001422', 'enseignant') AS ens_id \gset

INSERT INTO public.postes (etablissement_id, code, nom)
VALUES (:'etab_id'::uuid, 'DIRECTION', 'Direction') ON CONFLICT DO NOTHING;

SELECT id AS poste_id FROM public.postes
WHERE etablissement_id = :'etab_id'::uuid AND code = 'DIRECTION' AND deleted_at IS NULL \gset

INSERT INTO public.poste_permissions (poste_id, permission_code)
VALUES
  (:'poste_id'::uuid, 'planification.generer'),
  (:'poste_id'::uuid, 'planification.administrer')
ON CONFLICT DO NOTHING;

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement, poste_id)
VALUES (:'dir_id'::uuid, :'etab_id'::uuid, 'direction', :'poste_id'::uuid);

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'ens_id'::uuid, :'etab_id'::uuid, 'enseignant');

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

-- 1. La direction (generer) crée un créneau d'emploi du temps.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
INSERT INTO public.emplois_du_temps
  (etablissement_id, annee_scolaire_id, classe_id, salle_id, jour_semaine, heure_debut, heure_fin, type)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, :'salle_id'::uuid, 1, '08:00', '09:00', 'cours');
SELECT is((SELECT count(*) FROM public.emplois_du_temps WHERE etablissement_id = :'etab_id'::uuid)::int, 1,
          'direction : crée un créneau d''emploi du temps');

-- 2. L'enseignant (sans permission) ne peut pas créer de créneau.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'ens_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ INSERT INTO public.emplois_du_temps
       (etablissement_id, annee_scolaire_id, classe_id, salle_id, jour_semaine, heure_debut, heure_fin, type)
     SELECT e.id, a.id, c.id, s.id, 2, '09:00', '10:00', 'cours'
     FROM public.etablissements e
     JOIN public.annees_scolaires a ON a.etablissement_id = e.id
     JOIN public.classes c ON c.etablissement_id = e.id
     JOIN public.salles s ON s.etablissement_id = e.id
     WHERE e.slug = 'ecole-ecrit-m11'
     LIMIT 1 $$,
  '42501',
  'enseignant : création de créneau interdite sans permission'
);

-- 3. La direction (administrer) crée une contrainte.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
INSERT INTO public.contraintes_emploi (etablissement_id, annee_scolaire_id, type, raison)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, 'preference', 'à valider');
SELECT is((SELECT count(*) FROM public.contraintes_emploi WHERE etablissement_id = :'etab_id'::uuid)::int, 1,
          'direction : crée une contrainte de planification');

-- 4. L'enseignant ne peut pas créer de contrainte.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'ens_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ INSERT INTO public.contraintes_emploi (etablissement_id, annee_scolaire_id, type, raison)
     SELECT e.id, a.id, 'vacance', 'test'
     FROM public.etablissements e
     JOIN public.annees_scolaires a ON a.etablissement_id = e.id
     WHERE e.slug = 'ecole-ecrit-m11'
     LIMIT 1 $$,
  '42501',
  'enseignant : création de contrainte interdite sans permission'
);

-- 5. La direction modifie une contrainte existante.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
UPDATE public.contraintes_emploi SET raison = 'validée' WHERE etablissement_id = :'etab_id'::uuid;
SELECT is((SELECT raison FROM public.contraintes_emploi WHERE etablissement_id = :'etab_id'::uuid),
          'validée', 'direction : modifie une contrainte');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
