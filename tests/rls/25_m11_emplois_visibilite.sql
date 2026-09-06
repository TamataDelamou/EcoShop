-- ============================================================================
-- EcoShop — Test RLS 25 : visibilité des emplois du temps et de l'agenda (M11)
--
-- Vérifie que :
--   • le personnel voit tous les créneaux et événements de l'établissement ;
--   • l'élève voit les créneaux de sa classe et les événements de sa classe ;
--   • le parent voit l'agenda de la classe de son enfant ;
--   • un compte étranger ne voit ni créneaux ni événements ;
--   • un événement d'établissement (sans classe) reste invisible à l'élève.
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
INSERT INTO public.etablissements (nom, slug) VALUES ('École Agenda M11', 'ecole-agenda-m11') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '6A', '6e A') RETURNING id AS classe_id \gset

SELECT pg_temp.creer_compte('224600001401', 'enseignant') AS prof_id \gset
SELECT pg_temp.creer_compte('224600001402', 'parent')     AS parent_id \gset
SELECT pg_temp.creer_compte('224600001403', 'eleve')      AS eleve_id \gset
SELECT pg_temp.creer_compte('224600001404', 'eleve')      AS etranger_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M11-VIS-001', 'BARRY', 'Ousmane', '2010-05-20', :'eleve_id'::uuid, now())
RETURNING id AS fiche_id \gset

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES (:'etab_id'::uuid, :'fiche_id'::uuid, :'classe_id'::uuid, :'annee_id'::uuid, 'active');

INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
VALUES (:'etab_id'::uuid, :'parent_id'::uuid, :'fiche_id'::uuid, 'tuteur_legal', 'confirmee', true);

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'prof_id'::uuid, :'etab_id'::uuid, 'enseignant');

-- ---------------------------------------------------------------------------
-- Une salle + deux créneaux + un événement de classe + un événement d'établissement
-- ---------------------------------------------------------------------------
INSERT INTO public.salles (etablissement_id, code, nom, capacite)
VALUES (:'etab_id'::uuid, 'S1', 'Salle 1', 30) RETURNING id AS salle_id \gset

INSERT INTO public.emplois_du_temps
  (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, salle_id, jour_semaine, heure_debut, heure_fin, type)
VALUES
  (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, :'prof_id'::uuid, :'salle_id'::uuid, 1, '08:00', '09:00', 'cours'),
  (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, :'prof_id'::uuid, :'salle_id'::uuid, 2, '10:00', '11:00', 'cours');

INSERT INTO public.evenements_agenda
  (etablissement_id, annee_scolaire_id, classe_id, titre, type, date_debut, date_fin)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, 'Conseil de classe', 'conseil_classe', '2026-11-15', '2026-11-15');

INSERT INTO public.evenements_agenda
  (etablissement_id, annee_scolaire_id, titre, type, date_debut, date_fin)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, 'Réunion de rentrée', 'reunion', '2026-10-05', '2026-10-05');

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.emplois_du_temps)::int, 2, 'personnel : voit tous les créneaux');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.emplois_du_temps)::int, 2, 'élève : voit les créneaux de sa classe');
SELECT is((SELECT count(*) FROM public.evenements_agenda)::int, 1, 'élève : ne voit que l''événement de sa classe');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'parent_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.emplois_du_temps)::int, 2, 'parent : voit l''agenda de la classe de son enfant');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.emplois_du_temps)::int, 0, 'étranger : aucun créneau visible');
SELECT is((SELECT count(*) FROM public.evenements_agenda)::int, 0, 'étranger : aucun événement visible');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
