-- ============================================================================
-- EcoShop — Test 15 : fonctions IA de la vie scolaire (M7)
--
-- Vérifie les trois niveaux d'IA (descriptif, prédictif, prescriptif) :
--   • analyse_comportement : comptage des absences non justifiées ;
--   • calculer_score_decrochage : score pondéré exact ;
--   • recommander_sanction_educative : recommandation non punitive ;
--   • predire_presence : taux attendu ajusté des événements.
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
INSERT INTO public.etablissements (nom, slug) VALUES ('École IA M7', 'ecole-ia-m7') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '4A', '4e A') RETURNING id AS classe_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance)
VALUES (:'etab_id'::uuid, 'M7-IA-001', 'BARRY', 'Mamadou', '2012-05-11') RETURNING id AS fiche_id \gset

SELECT pg_temp.creer_compte('224600001111', 'enseignant') AS prof_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'prof_id'::uuid, :'etab_id'::uuid, 'enseignant');

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES (:'etab_id'::uuid, :'fiche_id'::uuid, :'classe_id'::uuid, :'annee_id'::uuid, 'active');

-- ---------------------------------------------------------------------------
-- Données : 8 pointages (5 absences non justifiées, 3 présences),
-- 3 retards non justifiés, un événement impactant la présence.
-- ---------------------------------------------------------------------------
INSERT INTO public.presences (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, date_presence, type_seance, statut, justifie, saisi_par)
SELECT :'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, :'fiche_id'::uuid,
       (date '2026-10-05' + n::int), 'demi_journee',
       (case when n < 5 then 'absent' else 'present' end)::public.statut_presence,
       false, :'prof_id'::uuid
FROM generate_series(0, 7) AS n;

INSERT INTO public.retards (etablissement_id, fiche_eleve_id, annee_scolaire_id, date_retard, minutes_retard, justifie, saisi_par)
SELECT :'etab_id'::uuid, :'fiche_id'::uuid, :'annee_id'::uuid, d, m, false, :'prof_id'::uuid
FROM (VALUES
  (date '2026-10-05', 10),
  (date '2026-10-07', 15),
  (date '2026-10-09', 20)
) AS v(d, m);

INSERT INTO public.evenements_scolaires (etablissement_id, annee_scolaire_id, type, libelle, date_debut, date_fin, impact_presence)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, 'greve', 'Grève', date '2026-10-10', date '2026-10-10', 0.1);

-- ---------------------------------------------------------------------------
-- Assertions (sous authenticated pour vérifier les grants)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);

-- Score : 0.5 * (5/8) + 0.2 * min(3/10,1) + 0.15 (moyenne nulle) = 0.5225.
SELECT is(
  public.calculer_score_decrochage(:'fiche_id'::uuid, :'annee_id'::uuid)::numeric,
  0.5225::numeric,
  'IA prédictive : score de décrochage pondéré exact'
);

SELECT is(
  (public.analyse_comportement(:'fiche_id'::uuid, :'annee_id'::uuid)->>'absences_non_justifiees')::int,
  5,
  'IA descriptive : comptage des absences non justifiées'
);

SELECT is(
  public.recommander_sanction_educative(:'fiche_id'::uuid, :'annee_id'::uuid)->>'type_recommande',
  'entretien_famille_et_tutorat',
  'IA prescriptive : recommandation éducative adaptée'
);

SELECT is(
  public.recommander_sanction_educative(:'fiche_id'::uuid, :'annee_id'::uuid)->>'non_punitif',
  'true',
  'IA prescriptive : caractère non punitif garanti'
);

-- Taux attendu : 3/8 présents (0.375) - impact grève 0.1 = 0.275.
SELECT is(
  public.predire_presence(:'etab_id'::uuid, date '2026-10-10')::numeric,
  0.275::numeric,
  'IA prédictive : présence attendue ajustée des événements'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
