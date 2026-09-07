-- ============================================================================
-- EcoShop — Test RLS 12 : création d'évaluations et moyenne (M6)
--
-- Vérifie que :
--   • seul un enseignant affecté à la classe crée une évaluation ;
--   • un enseignant non affecté ne peut pas ;
--   • la moyenne pondérée (calculer_moyenne_eleve) est exacte ;
--   • l'élève ne voit que les évaluations publiées.
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

SELECT plan(7);

-- ---------------------------------------------------------------------------
-- Tenant + année + classe
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Évaluations M6', 'ecole-eval-m6') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '4A', '4e A') RETURNING id AS classe_id \gset

-- ---------------------------------------------------------------------------
-- Comptes : élève (fiche liée), enseignant1 (affecté), enseignant2 (non affecté)
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224600001081', 'eleve')      AS eleve_id \gset
SELECT pg_temp.creer_compte('224600001082', 'enseignant') AS ens1_id \gset
SELECT pg_temp.creer_compte('224600001083', 'enseignant') AS ens2_id \gset

-- ---------------------------------------------------------------------------
-- Fiche élève liée + inscription
-- ---------------------------------------------------------------------------
INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M6-EVA-001', 'TOUNKARA', 'Mariam', '2012-01-12', :'eleve_id'::uuid, now())
RETURNING id AS fiche_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'ens1_id'::uuid, :'etab_id'::uuid, 'enseignant'),
  (:'ens2_id'::uuid, :'etab_id'::uuid, 'enseignant');

INSERT INTO public.affectations_enseignants (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id, role_affectation)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'ens1_id'::uuid, :'classe_id'::uuid, 'titulaire');

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES (:'etab_id'::uuid, :'fiche_id'::uuid, :'classe_id'::uuid, :'annee_id'::uuid, 'active');

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

-- 1. L'enseignant affecté est reconnu.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'ens1_id', 'role', 'authenticated')::text, true);
SELECT ok(public.est_enseignant_affecte(:'classe_id'), 'évaluation : enseignant affecté reconnu');

-- 2. Il crée une évaluation.
INSERT INTO public.evaluations
  (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, type, libelle, coefficient, bareme, statut, publie_le)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, :'ens1_id'::uuid,
        'controle', 'Contrôle n°1', 2, 20, 'publiee', now());
SELECT is((SELECT count(*) FROM public.evaluations)::int, 1, 'évaluation : créée par l''affecté');

-- 3. L'enseignant non affecté est bloqué.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'ens2_id', 'role', 'authenticated')::text, true);
SELECT is(public.est_enseignant_affecte(:'classe_id'), false, 'évaluation : non affecté détecté');
SELECT throws_ok(
  $$ INSERT INTO public.evaluations
       (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, type, libelle, coefficient, bareme, statut)
     SELECT e.id, a.id, c.id, auth.uid(), 'devoir', 'Devoir pirate', 1, 20, 'brouillon'
     FROM public.etablissements e
     JOIN public.annees_scolaires a ON a.etablissement_id = e.id
     JOIN public.classes c ON c.etablissement_id = e.id
     WHERE e.slug = 'ecole-eval-m6' AND c.code = '4A' $$,
  '42501', NULL, 'evaluation : creation bloquee pour non affecte'
);
SELECT is((SELECT count(*) FROM public.evaluations)::int, 1, 'évaluation : création bloquée pour non affecté');

-- 4. Moyenne pondérée exacte : (16/20*2 + 12/20*1)/3 * 20 = 14.67.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'ens1_id', 'role', 'authenticated')::text, true);

INSERT INTO public.evaluations
  (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, type, libelle, coefficient, bareme, statut, publie_le)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, :'ens1_id'::uuid,
        'devoir', 'Devoir maison', 1, 20, 'publiee', now());

INSERT INTO public.evaluations
  (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, type, libelle, coefficient, bareme, statut)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, :'ens1_id'::uuid,
        'controle', 'Contrôle brouillon (invisible)', 1, 20, 'brouillon');

INSERT INTO public.notes (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par)
SELECT :'etab_id'::uuid, e.id, :'fiche_id'::uuid, v.valeur, :'ens1_id'::uuid
FROM (VALUES
  ('Contrôle n°1', 16::numeric),
  ('Devoir maison', 12::numeric)
) AS v(libelle, valeur)
JOIN public.evaluations e ON e.libelle = v.libelle AND e.classe_id = :'classe_id'::uuid;

SELECT is(
  public.calculer_moyenne_eleve(:'fiche_id'::uuid, NULL, NULL)::numeric,
  14.67::numeric,
  'moyenne : pondération par coefficient exacte'
);

-- 5. L'élève ne voit que les évaluations publiées.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.evaluations)::int, 2, 'élève : seules les évaluations publiées');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
