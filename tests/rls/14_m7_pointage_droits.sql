-- ============================================================================
-- EcoShop — Test RLS 14 : droits de pointage et visibilité des alertes (M7)
--
-- Vérifie que :
--   • l'enseignant affecté (ou principal) peut pointer sa classe ;
--   • un enseignant non affecté ne peut pas ;
--   • la scolarité (permission presence.gerer) peut pointer ;
--   • une alerte décrochage n'est visible par l'élève qu'une fois transmise.
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
-- Tenant + année + classe + fiche inscrite
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Pointage M7', 'ecole-pointage-m7') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '5A', '5e A') RETURNING id AS classe_id \gset

-- ---------------------------------------------------------------------------
-- Comptes : élève, enseignant1 (affecté), enseignant2 (non affecté), scolarité
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224600001101', 'eleve')      AS eleve_id \gset
SELECT pg_temp.creer_compte('224600001102', 'enseignant') AS ens1_id \gset
SELECT pg_temp.creer_compte('224600001103', 'enseignant') AS ens2_id \gset
SELECT pg_temp.creer_compte('224600001104', 'enseignant') AS scol_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M7-PNT-001', 'DIALLO', 'Saran', '2011-04-03', :'eleve_id'::uuid, now())
RETURNING id AS fiche_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'ens1_id'::uuid, :'etab_id'::uuid, 'enseignant'),
  (:'ens2_id'::uuid, :'etab_id'::uuid, 'enseignant');

INSERT INTO public.affectations_enseignants (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id, role_affectation)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'ens1_id'::uuid, :'classe_id'::uuid, 'titulaire');

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES (:'etab_id'::uuid, :'fiche_id'::uuid, :'classe_id'::uuid, :'annee_id'::uuid, 'active');

INSERT INTO public.postes (etablissement_id, code, nom)
SELECT :'etab_id'::uuid, 'SCOLARITE', 'Scolarité'
WHERE NOT EXISTS (
  SELECT 1 FROM public.postes WHERE etablissement_id = :'etab_id'::uuid AND code = 'SCOLARITE' AND deleted_at IS NULL
);

SELECT id AS poste_id FROM public.postes
WHERE etablissement_id = :'etab_id'::uuid AND code = 'SCOLARITE' AND deleted_at IS NULL \gset

INSERT INTO public.poste_permissions (poste_id, permission_code)
VALUES (:'poste_id'::uuid, 'scolarite.presence.gerer') ON CONFLICT DO NOTHING;

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement, poste_id)
VALUES (:'scol_id'::uuid, :'etab_id'::uuid, 'personnel', :'poste_id'::uuid);

-- Alerte décrochage (ouverte) pour la fiche.
INSERT INTO public.alertes_decrochage (etablissement_id, fiche_eleve_id, annee_scolaire_id, score, seuil, facteurs, statut)
VALUES (:'etab_id'::uuid, :'fiche_id'::uuid, :'annee_id'::uuid, 0.72, 0.6, '{}'::jsonb, 'ouverte')
RETURNING id AS alerte_id \gset

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

-- 1. L'enseignant affecté peut pointer.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'ens1_id', 'role', 'authenticated')::text, true);
SELECT ok(public.peut_pointer(:'classe_id'), 'pointage : enseignant affecté autorisé');

-- 2. Et l'insertion aboutit réellement.
INSERT INTO public.presences (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, date_presence, type_seance, statut, justifie, saisi_par)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, :'fiche_id'::uuid, date '2026-10-06', 'demi_journee', 'present', false, :'ens1_id'::uuid);
SELECT is((SELECT count(*) FROM public.presences)::int, 1, 'pointage : présence enregistrée');

-- 3. L'enseignant non affecté est bloqué.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'ens2_id', 'role', 'authenticated')::text, true);
SELECT is(public.peut_pointer(:'classe_id'), false, 'pointage : non affecté refusé');

-- 4. La scolarité (permission presence.gerer) peut pointer.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'scol_id', 'role', 'authenticated')::text, true);
SELECT ok(public.peut_pointer(:'classe_id'), 'pointage : scolarité autorisée');

-- 5. Alerte ouverte : invisible pour l'élève.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.alertes_decrochage)::int, 0, 'alerte : invisible tant qu''elle n''est pas transmise');

-- 6. Alerte transmise : visible pour l'élève concerné.
RESET ROLE;
UPDATE public.alertes_decrochage SET statut = 'transmise', transmise_le = now() WHERE id = :'alerte_id'::uuid;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.alertes_decrochage)::int, 1, 'alerte : visible après transmission');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
