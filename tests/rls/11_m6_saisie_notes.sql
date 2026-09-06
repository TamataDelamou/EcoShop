-- ============================================================================
-- EcoShop — Test RLS 11 : saisie des notes (M6)
--
-- Vérifie que :
--   • l'enseignant auteur d'une évaluation peut saisir des notes ;
--   • un enseignant non-auteur sans permission ne peut pas ;
--   • un membre titulaire de la permission « scolarite.note.gerer » peut ;
--   • une évaluation clôturée verrouille la saisie.
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
-- Tenant + année + classe + fiche inscrite
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Saisie M6', 'ecole-saisie-m6') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '5A', '5e A') RETURNING id AS classe_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance)
VALUES (:'etab_id'::uuid, 'M6-SAI-001', 'KOUROUMA', 'Sékou', '2011-06-20') RETURNING id AS fiche_id \gset

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES (:'etab_id'::uuid, :'fiche_id'::uuid, :'classe_id'::uuid, :'annee_id'::uuid, 'active');

-- ---------------------------------------------------------------------------
-- Comptes : enseignant1 (auteur, affecté), enseignant2 (non affecté),
-- scolarité (poste avec permission note.gerer)
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224600001071', 'enseignant') AS ens1_id \gset
SELECT pg_temp.creer_compte('224600001072', 'enseignant') AS ens2_id \gset
SELECT pg_temp.creer_compte('224600001073', 'enseignant') AS scol_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'ens1_id'::uuid, :'etab_id'::uuid, 'enseignant'),
  (:'ens2_id'::uuid, :'etab_id'::uuid, 'enseignant');

INSERT INTO public.affectations_enseignants (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id, role_affectation)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'ens1_id'::uuid, :'classe_id'::uuid, 'titulaire');

INSERT INTO public.postes (etablissement_id, code, nom)
SELECT :'etab_id'::uuid, 'SCOLARITE', 'Scolarité'
WHERE NOT EXISTS (
  SELECT 1 FROM public.postes WHERE etablissement_id = :'etab_id'::uuid AND code = 'SCOLARITE' AND deleted_at IS NULL
);

SELECT id AS poste_id FROM public.postes
WHERE etablissement_id = :'etab_id'::uuid AND code = 'SCOLARITE' AND deleted_at IS NULL \gset

INSERT INTO public.poste_permissions (poste_id, permission_code)
VALUES (:'poste_id'::uuid, 'scolarite.note.gerer') ON CONFLICT DO NOTHING;

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement, poste_id)
VALUES (:'scol_id'::uuid, :'etab_id'::uuid, 'personnel', :'poste_id'::uuid);

-- ---------------------------------------------------------------------------
-- Évaluation (brouillon, auteur = enseignant1)
-- ---------------------------------------------------------------------------
INSERT INTO public.evaluations
  (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, type, libelle, coefficient, bareme, statut)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, :'ens1_id'::uuid,
        'controle', 'Contrôle de mathématiques', 2, 20, 'brouillon')
RETURNING id AS eval_id \gset

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

-- 1. L'auteur peut saisir.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'ens1_id', 'role', 'authenticated')::text, true);
SELECT ok(public.peut_saisir_notes(:'eval_id'), 'saisie : l''auteur est autorisé');

-- 2. Et l'insertion aboutit réellement.
INSERT INTO public.notes (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par)
VALUES (:'etab_id'::uuid, :'eval_id'::uuid, :'fiche_id'::uuid, 13, :'ens1_id'::uuid);
SELECT is((SELECT count(*) FROM public.notes)::int, 1, 'saisie : la note est enregistrée');

-- 3. Un enseignant non-auteur sans permission est refusé.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'ens2_id', 'role', 'authenticated')::text, true);
SELECT is(public.peut_saisir_notes(:'eval_id'), false, 'saisie : non-auteur refusé');

-- 4. La scolarité (permission note.gerer) peut saisir.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'scol_id', 'role', 'authenticated')::text, true);
SELECT ok(public.peut_saisir_notes(:'eval_id'), 'saisie : scolarité autorisée');

-- 5. La clôture verrouille la saisie, même pour l'auteur.
RESET ROLE;
UPDATE public.evaluations SET statut = 'cloturee', cloture_le = now() WHERE id = :'eval_id'::uuid;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'ens1_id', 'role', 'authenticated')::text, true);
SELECT is(public.peut_saisir_notes(:'eval_id'), false, 'saisie : clôture = verrou');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
