-- ============================================================================
-- EcoShop — Test RLS 10 : visibilité des notes et évaluations (M6)
--
-- Vérifie que :
--   • l'élève lié voit son évaluation publiée et sa note ;
--   • le parent confirmé voit la note de son enfant ;
--   • le personnel voit les notes de l'établissement ;
--   • un compte étranger (élève sans fiche) ne voit rien.
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
-- Tenant + année + période + classe
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Notes M6', 'ecole-notes-m6') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.periodes_scolaires (etablissement_id, annee_scolaire_id, code, libelle, type, ordre, date_debut, date_fin)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, 'T1', '1er trimestre', 'trimestre', 1, '2026-10-01', '2026-12-23');

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '6A', '6e A') RETURNING id AS classe_id \gset

-- ---------------------------------------------------------------------------
-- Comptes + fiche liée + inscription + relation parent + affectation
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224600001061', 'eleve')      AS eleve_id \gset
SELECT pg_temp.creer_compte('224600001062', 'parent')     AS parent_id \gset
SELECT pg_temp.creer_compte('224600001063', 'enseignant') AS prof_id \gset
SELECT pg_temp.creer_compte('224600001064', 'eleve')      AS etranger_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M6-VIS-001', 'SOUMAH', 'Kadiatou', '2010-03-08', :'eleve_id'::uuid, now())
RETURNING id AS fiche_id \gset

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES (:'etab_id'::uuid, :'fiche_id'::uuid, :'classe_id'::uuid, :'annee_id'::uuid, 'active');

INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
VALUES (:'etab_id'::uuid, :'parent_id'::uuid, :'fiche_id'::uuid, 'tuteur_legal', 'confirmee', true);

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'prof_id'::uuid, :'etab_id'::uuid, 'enseignant');

INSERT INTO public.affectations_enseignants (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id, role_affectation)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'prof_id'::uuid, :'classe_id'::uuid, 'titulaire');

-- ---------------------------------------------------------------------------
-- Évaluation publiée + note
-- ---------------------------------------------------------------------------
INSERT INTO public.evaluations
  (etablissement_id, annee_scolaire_id, periode_id, classe_id, enseignant_profile_id,
   type, libelle, coefficient, bareme, statut, publie_le)
SELECT :'etab_id'::uuid, :'annee_id'::uuid, p.id, :'classe_id'::uuid, :'prof_id'::uuid,
       'controle', 'Contrôle n°1', 1, 20, 'publiee', now()
FROM public.periodes_scolaires p
WHERE p.code = 'T1' AND p.annee_scolaire_id = :'annee_id'::uuid
RETURNING id AS eval_id \gset

INSERT INTO public.notes (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par)
VALUES (:'etab_id'::uuid, :'eval_id'::uuid, :'fiche_id'::uuid, 15, :'prof_id'::uuid);

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.evaluations)::int, 1, 'élève : voit son évaluation publiée');
SELECT is((SELECT count(*) FROM public.notes)::int, 1, 'élève : voit sa note');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'parent_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.notes)::int, 1, 'parent : voit la note de son enfant');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.notes)::int, 1, 'enseignant : voit les notes (personnel)');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.evaluations)::int, 0, 'étranger : aucune évaluation visible');
SELECT is((SELECT count(*) FROM public.notes)::int, 0, 'étranger : aucune note visible');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
