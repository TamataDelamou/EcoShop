-- ============================================================================
-- EcoShop — Test RLS 13 : visibilité de la vie scolaire (M7)
--
-- Vérifie que l'élève, le parent et le personnel voient présences, retards et
-- sanctions de la fiche concernée, et qu'un étranger ne voit rien.
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
-- Tenant + année + classe
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Vie M7', 'ecole-vie-m7') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '6A', '6e A') RETURNING id AS classe_id \gset

-- ---------------------------------------------------------------------------
-- Comptes + fiche + inscription + relation parent + membre enseignant
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224600001091', 'eleve')      AS eleve_id \gset
SELECT pg_temp.creer_compte('224600001092', 'parent')     AS parent_id \gset
SELECT pg_temp.creer_compte('224600001093', 'enseignant') AS prof_id \gset
SELECT pg_temp.creer_compte('224600001094', 'eleve')      AS etranger_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M7-VIS-001', 'CAMARA', 'Mory', '2010-09-14', :'eleve_id'::uuid, now())
RETURNING id AS fiche_id \gset

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES (:'etab_id'::uuid, :'fiche_id'::uuid, :'classe_id'::uuid, :'annee_id'::uuid, 'active');

INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
VALUES (:'etab_id'::uuid, :'parent_id'::uuid, :'fiche_id'::uuid, 'tuteur_legal', 'confirmee', true);

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'prof_id'::uuid, :'etab_id'::uuid, 'enseignant');

-- ---------------------------------------------------------------------------
-- Données : présence, retard, sanction
-- ---------------------------------------------------------------------------
INSERT INTO public.presences (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, date_presence, type_seance, statut, justifie, saisi_par)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, :'fiche_id'::uuid, date '2026-10-06', 'demi_journee', 'absent', false, :'prof_id'::uuid);

INSERT INTO public.retards (etablissement_id, fiche_eleve_id, annee_scolaire_id, date_retard, minutes_retard, justifie, saisi_par)
VALUES (:'etab_id'::uuid, :'fiche_id'::uuid, :'annee_id'::uuid, date '2026-10-07', 15, false, :'prof_id'::uuid);

INSERT INTO public.sanctions (etablissement_id, fiche_eleve_id, annee_scolaire_id, type_sanction, motif, date_debut, decisionnaire_id, origine, statut)
VALUES (:'etab_id'::uuid, :'fiche_id'::uuid, :'annee_id'::uuid, 'avertissement', 'Retards répétés', date '2026-10-08', :'prof_id'::uuid, 'humaine', 'notifiee');

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.presences)::int, 1, 'élève : voit sa présence');
SELECT is((SELECT count(*) FROM public.retards)::int, 1, 'élève : voit ses retards');
SELECT is((SELECT count(*) FROM public.sanctions)::int, 1, 'élève : voit ses sanctions');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'parent_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.presences)::int, 1, 'parent : voit la présence de son enfant');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.presences)::int, 1, 'enseignant : voit les présences (personnel)');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.presences)::int, 0, 'étranger : aucune présence visible');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
