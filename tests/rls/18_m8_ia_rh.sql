-- ============================================================================
-- EcoShop — Test 18 : fonctions IA RH (M8)
--
-- Vérifie les trois niveaux d'IA RH :
--   • prédictif : calculer_score_turnover (score pondéré exact) ;
--   • descriptif : analyser_effectifs (effectifs par catégorie) ;
--   • prescriptif : recommander_formation (matière M4 non couverte) et
--     optimiser_remplacements (remplaçant le moins chargé).
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
-- Référentiel M4 minimal (pays GN + deux matières)
-- ---------------------------------------------------------------------------
INSERT INTO public.systemes_educatifs (code, nom) VALUES ('francophone_cfa', 'Francophone CFA');

INSERT INTO public.pays_pedagogiques (code_iso, nom, type_systeme, langue_enseignement_principale, organisme_examinateur, devise_code, statut_deploiement)
VALUES ('GN', 'Guinée', 'francophone_cfa', 'fr', 'Ministère', 'GNF', 'deploye');

INSERT INTO public.cycles_educatifs (pays_code, code, nom, ordre, isced_min, isced_max, statut)
VALUES ('GN', 'SEC', 'Secondaire', 2, 2, 3, 'publie') RETURNING id AS cycle_id \gset

INSERT INTO public.niveaux_educatifs (cycle_id, pays_code, code, nom, grade_level_normalise, isced, ordre, statut)
VALUES (:'cycle_id'::uuid, 'GN', '10e', '10e', 10, 2, 1, 'publie') RETURNING id AS niveau_id \gset

INSERT INTO public.programmes_officiels (pays_code, niveau_id, code, nom, version, statut)
VALUES ('GN', :'niveau_id'::uuid, 'PROG-GN-10E', 'Programme 10e', 1, 'publie') RETURNING id AS prog_id \gset

INSERT INTO public.programmes_matieres (programme_id, code, nom, statut)
VALUES (:'prog_id'::uuid, 'MATH', 'Mathématiques', 'publie') RETURNING id AS matiere_math \gset

INSERT INTO public.programmes_matieres (programme_id, code, nom, statut)
VALUES (:'prog_id'::uuid, 'PC-M8', 'Physique-Chimie', 'publie') RETURNING id AS matiere_pc \gset

-- ---------------------------------------------------------------------------
-- Tenant + année + classes
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug, pays_code) VALUES ('École IA M8', 'ecole-ia-m8', 'GN') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, 'IA-A', 'Classe A') RETURNING id AS classe_a \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, 'IA-B', 'Classe B') RETURNING id AS classe_b \gset

-- ---------------------------------------------------------------------------
-- Comptes + membres + dossiers employés + contrats
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224600001221', 'direction')  AS dir_id \gset
SELECT pg_temp.creer_compte('224600001222', 'enseignant') AS ens1_id \gset
SELECT pg_temp.creer_compte('224600001223', 'enseignant') AS ens2_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'dir_id'::uuid,  :'etab_id'::uuid, 'direction'),
  (:'ens1_id'::uuid, :'etab_id'::uuid, 'enseignant'),
  (:'ens2_id'::uuid, :'etab_id'::uuid, 'enseignant');

INSERT INTO public.employes (etablissement_id, profile_id, matricule, categorie, date_embauche)
VALUES
  (:'etab_id'::uuid, :'dir_id'::uuid,  'IA-DIR',  'direction',  current_date - 1095),
  (:'etab_id'::uuid, :'ens1_id'::uuid, 'IA-ENS1', 'enseignant', current_date - 730),
  (:'etab_id'::uuid, :'ens2_id'::uuid, 'IA-ENS2', 'enseignant', current_date);

INSERT INTO public.contrats (etablissement_id, employe_id, type, date_debut, date_fin, salaire_base)
SELECT :'etab_id'::uuid, e.id, v.type::public.type_contrat, current_date - 30, v.fin, v.salaire
FROM public.employes e
JOIN (VALUES
  ('IA-DIR',  'cdi', NULL,                 6000000),
  ('IA-ENS1', 'cdi', NULL,                 3500000),
  ('IA-ENS2', 'cdd', current_date + 30,    2800000)
) AS v(matricule, type, fin, salaire) ON v.matricule = e.matricule
WHERE e.etablissement_id = :'etab_id'::uuid;

-- ---------------------------------------------------------------------------
-- Affectations : ens1 = 10 h sur MATH, ens2 = 35 h (surcharge) sur MATH
-- ---------------------------------------------------------------------------
INSERT INTO public.affectations_enseignants
  (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id, programme_matiere_id, role_affectation, volume_horaire_hebdo)
VALUES
  (:'etab_id'::uuid, :'annee_id'::uuid, :'ens1_id'::uuid, :'classe_a'::uuid, :'matiere_math'::uuid, 'enseignant', 10),
  (:'etab_id'::uuid, :'annee_id'::uuid, :'ens2_id'::uuid, :'classe_b'::uuid, :'matiere_math'::uuid, 'enseignant', 35);

-- ---------------------------------------------------------------------------
-- Données RH : absences (3 injustifiées) + arrêt maladie validé pour ens2
-- ---------------------------------------------------------------------------
INSERT INTO public.absences_personnel (etablissement_id, employe_id, date_absence, type, justifie)
SELECT :'etab_id'::uuid, e.id, current_date - n, 'injustifiee', false
FROM public.employes e, (VALUES (10), (20), (30)) AS d(n)
WHERE e.matricule = 'IA-ENS2';

INSERT INTO public.conges (etablissement_id, employe_id, type, date_debut, date_fin, nb_jours, statut)
SELECT :'etab_id'::uuid, e.id, 'maladie', current_date - 15, current_date - 14, 2, 'valide'
FROM public.employes e WHERE e.matricule = 'IA-ENS2';

-- ---------------------------------------------------------------------------
-- Assertions (sous authenticated direction)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);

-- Score ens2 : 0.4*(3*2+1)/10 + 0.2*1 (ancienneté) + 0.2*1 (surcharge) + 0.2*1 (CDD fin imminente) = 0.88.
SELECT is(
  public.calculer_score_turnover((SELECT id FROM public.employes WHERE matricule = 'IA-ENS2'))::numeric,
  0.88::numeric,
  'IA prédictive : score de turn-over élevé (0.88)'
);

-- Score direction : 0 + 0.2*0.2 (ancienneté) + 0.2*0.3 (pas d''affectation) + 0.2*0.1 (CDI) = 0.12.
SELECT is(
  public.calculer_score_turnover((SELECT id FROM public.employes WHERE matricule = 'IA-DIR'))::numeric,
  0.12::numeric,
  'IA prédictive : score de turn-over faible (0.12)'
);

-- Descriptif : deux enseignants dans l'établissement.
SELECT is(
  (SELECT effectif::int FROM public.analyser_effectifs(:'etab_id'::uuid) WHERE categorie = 'enseignant'),
  2,
  'IA descriptive : effectif enseignant correct'
);

-- Prescriptif : seule la matière PC-M8 (non enseignée) est recommandée.
SELECT is(
  (SELECT string_agg(code, ',' ORDER BY code) FROM public.recommander_formation(
     (SELECT id FROM public.employes WHERE matricule = 'IA-ENS1'), :'annee_id'::uuid)),
  'PC-M8',
  'IA prescriptive : formation sur la matière non couverte'
);

-- Prescriptif : remplacement de ens2 (absent) par ens1 (disponible, moins chargé).
SELECT is(
  (SELECT remplacant_matricule FROM public.optimiser_remplacements(:'etab_id'::uuid, current_date - 10) LIMIT 1),
  'IA-ENS1',
  'IA prescriptive : remplaçant proposé = enseignant disponible le moins chargé'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
