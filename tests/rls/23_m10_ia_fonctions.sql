-- ============================================================================
-- EcoShop — Test 23 : fonctions IA des rapports & statistiques (M10)
--
-- Vérifie les fonctions :
--   • consolider_indicateurs_etablissement : 7 KPI calculés (dont
--     'eleves_a_risque', M16 sous-livrable 2/7 — consomme
--     statistiques_agregats.risque_reussite, pas un second calcul) ;
--   • detecter_anomalies : détection d'absentéisme excessif (> 30 %) ;
--   • risque_classe : score prédictif pondéré (niveau « faible » ici) ;
--   • recommander_actions : aucune action pour une classe saine ;
--   • generer_resume_executif : résumé NLG traçable ;
--   • contrôle d'accès : un élève ne peut pas appeler risque_classe.
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
-- Tenant + année + classe + comptes + 3 fiches inscrites
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École IA M10', 'ecole-ia-m10') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '6A', '6e A') RETURNING id AS classe_id \gset

SELECT pg_temp.creer_compte('224600001311', 'enseignant') AS prof_id \gset
SELECT pg_temp.creer_compte('224600001312', 'eleve')      AS eleve_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'prof_id'::uuid, :'etab_id'::uuid, 'enseignant');

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M10-IA-001', 'CONDÉ', 'Fatou', '2010-01-11', :'eleve_id'::uuid, now())
RETURNING id AS fiche1_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance)
VALUES (:'etab_id'::uuid, 'M10-IA-002', 'TRAORÉ', 'Sékou', '2010-02-12') RETURNING id AS fiche2_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance)
VALUES (:'etab_id'::uuid, 'M10-IA-003', 'SOW', 'Mariama', '2010-03-13') RETURNING id AS fiche3_id \gset

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES
  (:'etab_id'::uuid, :'fiche1_id'::uuid, :'classe_id'::uuid, :'annee_id'::uuid, 'active'),
  (:'etab_id'::uuid, :'fiche2_id'::uuid, :'classe_id'::uuid, :'annee_id'::uuid, 'active'),
  (:'etab_id'::uuid, :'fiche3_id'::uuid, :'classe_id'::uuid, :'annee_id'::uuid, 'active');

-- ---------------------------------------------------------------------------
-- Une évaluation + 3 notes (toutes au-dessus du seuil : classe saine)
-- ---------------------------------------------------------------------------
INSERT INTO public.evaluations
  (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id,
   type, libelle, coefficient, bareme, statut, publie_le)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, :'prof_id'::uuid,
        'controle', 'Contrôle n°1', 1, 20, 'publiee', now())
RETURNING id AS eval_id \gset

INSERT INTO public.notes (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par)
VALUES
  (:'etab_id'::uuid, :'eval_id'::uuid, :'fiche1_id'::uuid, 15, :'prof_id'::uuid),
  (:'etab_id'::uuid, :'eval_id'::uuid, :'fiche2_id'::uuid, 15, :'prof_id'::uuid),
  (:'etab_id'::uuid, :'eval_id'::uuid, :'fiche3_id'::uuid, 15, :'prof_id'::uuid);

-- ---------------------------------------------------------------------------
-- 6 pointages : 4 présences + 2 absences (33 % → anomalie d'absentéisme)
-- ---------------------------------------------------------------------------
INSERT INTO public.presences
  (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, date_presence,
   type_seance, statut, justifie, saisi_par)
SELECT :'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, :'fiche1_id'::uuid,
       (date '2026-10-05' + n::int), 'demi_journee',
       (case when n < 2 then 'absent' else 'present' end)::public.statut_presence,
       false, :'prof_id'::uuid
FROM generate_series(0, 5) AS n;

-- ---------------------------------------------------------------------------
-- Assertions (sous authenticated pour vérifier les grants)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);

SELECT is(
  public.consolider_indicateurs_etablissement(:'etab_id'::uuid, :'annee_id'::uuid),
  7,
  'IA descriptive : 7 indicateurs clés consolidés (dont eleves_a_risque, M16)'
);

-- M16 sous-livrable 2/7 : classe saine (tous sous le seuil 0.6 de
-- calculer_score_decrochage) → 0 élève à risque compté.
SELECT is(
  (SELECT valeur_numeric FROM public.indicateurs_cles
     WHERE etablissement_id = :'etab_id'::uuid AND annee_scolaire_id = :'annee_id'::uuid
       AND code = 'eleves_a_risque'),
  0::numeric,
  'M16 : bannière eleves_a_risque à 0 pour une classe saine'
);

SELECT is(
  public.detecter_anomalies(:'etab_id'::uuid, :'annee_id'::uuid),
  1,
  'IA prédictive : absentéisme excessif détecté (anomalie)'
);

SELECT is(
  public.risque_classe(:'classe_id'::uuid)->>'niveau_risque',
  'faible',
  'IA prédictive : classe saine → niveau de risque faible'
);

SELECT is(
  public.recommander_actions(:'etab_id'::uuid, :'annee_id'::uuid),
  0,
  'IA prescriptive : aucune recommandation pour une classe saine'
);

SELECT ok(
  public.generer_resume_executif(:'etab_id'::uuid, :'annee_id'::uuid) LIKE '%Résumé exécutif%',
  'IA prescriptive : résumé exécutif NLG généré'
);

-- Contrôle d'accès : un élève (non personnel) ne peut pas évaluer le risque.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.risque_classe((SELECT id FROM public.classes WHERE code = '6A')) $$,
  '42501',
  NULL
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
