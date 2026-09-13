-- ============================================================================
-- EcoShop — Test RLS 46 : complément de contenu réglementaire du bulletin (D5)
--
-- Vérifie que :
--   • classe_isced() renvoie le palier ISCED normalisé (1/primaire,
--     2/collège, 3/lycée) — PAS un code de cycle littéral, qui varie par
--     pays (§6.4 du cahier) — et NULL si la classe n'a pas de niveau
--     renseigné ou si l'appelant n'est pas personnel ;
--   • detail_bulletin_matieres() ne renvoie rien pour un cycle primaire
--     (ISCED 1) même si des affectations existent — le tableau par matière
--     est réservé au secondaire (collège + lycée) ;
--   • pour un cycle secondaire, il renvoie matière/coefficient/moyenne
--     (moyenne déléguée à calculer_moyenne_eleve, aucun nouveau calcul) et
--     nom/EMAIL de l'enseignant (jamais le téléphone, usage interne
--     uniquement), résilient (email NULL) si l'enseignant n'a pas de
--     dossier RH (employes) ;
--   • un appelant non personnel n'obtient rien ;
--   • pays_pedagogiques.ministere_tutelle est résilient (NULL par défaut,
--     jamais une contrainte bloquante) et signatures_bulletin porte les
--     libellés par défaut attendus par cycle.
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

SELECT plan(16);

-- ---------------------------------------------------------------------------
-- Référentiel pays de test (isolé du GN/SN/GH, qui ne sont peuplés que par
-- un seed optionnel non rejoué par `supabase db reset`) : 3 cycles ISCED
-- 1/2/3, un niveau par cycle.
-- ---------------------------------------------------------------------------
INSERT INTO public.systemes_educatifs (code, nom) VALUES ('francophone_cfa', 'Francophone (CFA)')
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.pays_pedagogiques (code_iso, nom, type_systeme, langue_enseignement_principale, statut_deploiement)
VALUES ('ZZ', 'Pays Test D5', 'francophone_cfa', 'français', 'deploye')
ON CONFLICT (code_iso) DO NOTHING;

INSERT INTO public.cycles_educatifs (pays_code, code, nom, ordre, duree_annees, isced_min, isced_max, statut)
VALUES
  ('ZZ', 'primaire_test', 'Primaire', 1, 6, 1, 1, 'publie'),
  ('ZZ', 'college_test',  'Collège',  2, 4, 2, 2, 'publie'),
  ('ZZ', 'lycee_test',    'Lycée',    3, 3, 3, 3, 'publie')
ON CONFLICT (pays_code, code) DO NOTHING;

INSERT INTO public.niveaux_educatifs (cycle_id, pays_code, code, nom, grade_level_normalise, isced, ordre, statut)
SELECT c.id, 'ZZ', v.code, v.nom, v.grade, v.isced, 1, 'publie'
FROM (VALUES ('primaire_test', 'CM2_TEST', 'CM2 Test', 6, 1), ('college_test', '3E_TEST', '3e Test', 9, 2), ('lycee_test', 'TLE_TEST', 'Terminale Test', 13, 3)) AS v(cycle_code, code, nom, grade, isced)
JOIN public.cycles_educatifs c ON c.pays_code = 'ZZ' AND c.code = v.cycle_code
ON CONFLICT (pays_code, code) DO NOTHING;

SELECT id AS niveau_primaire_id FROM public.niveaux_educatifs WHERE pays_code = 'ZZ' AND code = 'CM2_TEST' \gset
SELECT id AS niveau_college_id FROM public.niveaux_educatifs WHERE pays_code = 'ZZ' AND code = '3E_TEST' \gset
SELECT id AS niveau_lycee_id FROM public.niveaux_educatifs WHERE pays_code = 'ZZ' AND code = 'TLE_TEST' \gset

-- ---------------------------------------------------------------------------
-- Tenant + année + classes (primaire, collège) + programme/matière
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Contenu Bulletin D5', 'ecole-contenu-bulletin-d5') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, niveau_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'niveau_primaire_id'::uuid, 'CM2', 'CM2') RETURNING id AS classe_primaire_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, niveau_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'niveau_college_id'::uuid, '3E', '3e') RETURNING id AS classe_college_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, 'SANS_NIVEAU', 'Classe sans niveau') RETURNING id AS classe_sans_niveau_id \gset

INSERT INTO public.programmes_officiels (pays_code, niveau_id, code, nom, annee_scolaire, version, statut)
VALUES ('ZZ', :'niveau_college_id'::uuid, 'PROG_ZZ_COLLEGE', 'Programme Collège Test', '2026-2027', 1, 'publie')
RETURNING id AS programme_id \gset

INSERT INTO public.programmes_matieres (programme_id, code, nom, coefficient, ordre, statut)
VALUES (:'programme_id'::uuid, 'MATH', 'Mathématiques', 4, 1, 'publie') RETURNING id AS matiere_id \gset

-- ---------------------------------------------------------------------------
-- Comptes : personnel (scolarité), étranger, deux enseignants (l'un avec
-- dossier RH + téléphone, l'autre sans dossier RH — résilience du LEFT JOIN)
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224600001091', 'enseignant') AS scol_id \gset
SELECT pg_temp.creer_compte('224600001092', 'eleve') AS etranger_id \gset
SELECT pg_temp.creer_compte('224600001093', 'enseignant') AS prof_avec_rh_id \gset
SELECT pg_temp.creer_compte('224600001094', 'enseignant') AS prof_sans_rh_id \gset

UPDATE public.profiles SET prenom = 'Mory', nom = 'CAMARA' WHERE id = :'prof_avec_rh_id'::uuid;
UPDATE public.profiles SET prenom = 'Aissatou', nom = 'BARRY' WHERE id = :'prof_sans_rh_id'::uuid;

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'prof_avec_rh_id'::uuid, :'etab_id'::uuid, 'enseignant'),
  (:'prof_sans_rh_id'::uuid, :'etab_id'::uuid, 'enseignant');

INSERT INTO public.postes (etablissement_id, code, nom) VALUES (:'etab_id'::uuid, 'SCOLARITE', 'Scolarité')
ON CONFLICT DO NOTHING;
SELECT id AS poste_id FROM public.postes WHERE etablissement_id = :'etab_id'::uuid AND code = 'SCOLARITE' \gset
INSERT INTO public.poste_permissions (poste_id, permission_code) VALUES (:'poste_id'::uuid, 'scolarite.bulletin.gerer') ON CONFLICT DO NOTHING;
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement, poste_id)
VALUES (:'scol_id'::uuid, :'etab_id'::uuid, 'personnel', :'poste_id'::uuid);

INSERT INTO public.employes (etablissement_id, profile_id, matricule, categorie, telephone, email)
VALUES (:'etab_id'::uuid, :'prof_avec_rh_id'::uuid, 'D5-TEL-001', 'enseignant', '+224600001093', 'mory.camara@ecole-test.gn');

INSERT INTO public.affectations_enseignants (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id, programme_matiere_id, role_affectation)
VALUES
  (:'etab_id'::uuid, :'annee_id'::uuid, :'prof_avec_rh_id'::uuid, :'classe_college_id'::uuid, :'matiere_id'::uuid, 'titulaire'),
  (:'etab_id'::uuid, :'annee_id'::uuid, :'prof_sans_rh_id'::uuid, :'classe_primaire_id'::uuid, :'matiere_id'::uuid, 'titulaire');

-- Une fiche + une note en collège, pour une moyenne de matière réelle.
INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance)
VALUES (:'etab_id'::uuid, 'D5-TEL-ELV-001', 'DIALLO', 'Sekou', '2012-01-01') RETURNING id AS fiche_id \gset

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES (:'etab_id'::uuid, :'fiche_id'::uuid, :'classe_college_id'::uuid, :'annee_id'::uuid, 'active');

INSERT INTO public.evaluations (etablissement_id, annee_scolaire_id, classe_id, programme_matiere_id, enseignant_profile_id, type, libelle, coefficient, bareme, statut, publie_le)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_college_id'::uuid, :'matiere_id'::uuid, :'prof_avec_rh_id'::uuid, 'devoir', 'Devoir Maths', 1, 20, 'publiee', now())
RETURNING id AS eval_id \gset

INSERT INTO public.notes (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par)
VALUES (:'etab_id'::uuid, :'eval_id'::uuid, :'fiche_id'::uuid, 16, :'prof_avec_rh_id'::uuid);

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'scol_id', 'role', 'authenticated')::text, true);

-- 1-4. classe_isced : primaire=1, collège=2, sans niveau=NULL.
SELECT is(public.classe_isced(:'classe_primaire_id'::uuid), 1, 'classe_isced : primaire -> ISCED 1');
SELECT is(public.classe_isced(:'classe_college_id'::uuid), 2, 'classe_isced : collège -> ISCED 2');
SELECT is(public.classe_isced(:'classe_sans_niveau_id'::uuid), NULL, 'classe_isced : classe sans niveau -> NULL (résilient)');

-- 5. classe_isced : étranger (non personnel) -> NULL.
SELECT set_config('request.jwt.claims', json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT is(public.classe_isced(:'classe_college_id'::uuid), NULL, 'classe_isced : étranger -> NULL (garde personnel)');

-- 6. detail_bulletin_matieres : primaire -> aucune ligne malgré une affectation existante.
SELECT set_config('request.jwt.claims', json_build_object('sub', :'scol_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*)::int FROM public.detail_bulletin_matieres(:'fiche_id'::uuid, :'classe_primaire_id'::uuid, NULL)),
  0,
  'detail_bulletin_matieres : primaire -> table vide (pas de tableau par matière)'
);

-- 7-8. detail_bulletin_matieres : collège -> une ligne, contenu conforme.
SELECT is(
  (SELECT count(*)::int FROM public.detail_bulletin_matieres(:'fiche_id'::uuid, :'classe_college_id'::uuid, NULL)),
  1,
  'detail_bulletin_matieres : collège -> une ligne (une matière affectée)'
);
SELECT is((SELECT matiere FROM public.detail_bulletin_matieres(:'fiche_id'::uuid, :'classe_college_id'::uuid, NULL)), 'Mathématiques', 'detail_bulletin_matieres : nom de la matière conforme');
SELECT is((SELECT coefficient FROM public.detail_bulletin_matieres(:'fiche_id'::uuid, :'classe_college_id'::uuid, NULL)), 4, 'detail_bulletin_matieres : coefficient officiel du programme conforme');
SELECT is((SELECT moyenne FROM public.detail_bulletin_matieres(:'fiche_id'::uuid, :'classe_college_id'::uuid, NULL)), 16.00, 'detail_bulletin_matieres : moyenne de la matière déléguée à calculer_moyenne_eleve');
SELECT is((SELECT enseignant_email FROM public.detail_bulletin_matieres(:'fiche_id'::uuid, :'classe_college_id'::uuid, NULL)), 'mory.camara@ecole-test.gn', 'detail_bulletin_matieres : email de l''enseignant (jamais le téléphone)');

-- 9. Résilience : enseignant sans dossier RH -> email NULL, pas d'erreur.
-- (réaffecte temporairement la matière au prof sans dossier RH ; RESET ROLE
-- nécessaire, la scolarité n'a pas la permission rh.enseignant.affecter)
RESET ROLE;
UPDATE public.affectations_enseignants SET enseignant_profile_id = :'prof_sans_rh_id'::uuid
WHERE classe_id = :'classe_college_id'::uuid AND programme_matiere_id = :'matiere_id'::uuid;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'scol_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT enseignant_email FROM public.detail_bulletin_matieres(:'fiche_id'::uuid, :'classe_college_id'::uuid, NULL)),
  NULL,
  'detail_bulletin_matieres : enseignant sans dossier RH -> email NULL, pas d''erreur'
);
SELECT is(
  (SELECT enseignant_nom FROM public.detail_bulletin_matieres(:'fiche_id'::uuid, :'classe_college_id'::uuid, NULL)),
  'Aissatou BARRY',
  'detail_bulletin_matieres : nom de l''enseignant toujours résolu via profiles'
);

-- 10. Un étranger n'obtient rien.
SELECT set_config('request.jwt.claims', json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*)::int FROM public.detail_bulletin_matieres(:'fiche_id'::uuid, :'classe_college_id'::uuid, NULL)),
  0,
  'detail_bulletin_matieres : étranger -> aucune ligne'
);

-- 11-13. pays_pedagogiques : ministere_tutelle résilient (NULL par défaut),
-- signatures_bulletin porte les libellés par défaut attendus.
SELECT is(
  (SELECT ministere_tutelle FROM public.pays_pedagogiques WHERE code_iso = 'ZZ'),
  NULL,
  'pays_pedagogiques : ministere_tutelle est NULL par défaut, jamais bloquant'
);
SELECT is(
  (SELECT signatures_bulletin -> 'college' ->> 'signataire2' FROM public.pays_pedagogiques WHERE code_iso = 'ZZ'),
  'Directeur des Études',
  'pays_pedagogiques : libellé par défaut du 2e signataire collège'
);
SELECT is(
  (SELECT signatures_bulletin -> 'lycee' ->> 'signataire2' FROM public.pays_pedagogiques WHERE code_iso = 'ZZ'),
  'Censeur',
  'pays_pedagogiques : libellé par défaut du 2e signataire lycée'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
