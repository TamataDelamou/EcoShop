-- ============================================================================
-- EcoShop — Test RLS 40 : M16 — bannière dashboard directeur « élèves à
-- risque » (indicateur 'eleves_a_risque' de consolider_indicateurs_etablissement)
--
-- Ne re-teste PAS calculer_score_decrochage (déjà couvert, M7) ni la
-- matérialisation elle-même (déjà couverte, tests/rls/39) : vérifie
-- uniquement que le nouvel indicateur compte au bon seuil (0.6, identique à
-- generer_alertes_decrochage) sur une population mixte (un élève au-dessus,
-- un en-dessous), qu'il est lisible par le personnel via la RLS déjà en
-- place sur `indicateurs_cles` (aucune policy nouvelle), et qu'il reste
-- absent pour un étranger.
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

SELECT plan(4);

-- ---------------------------------------------------------------------------
-- Tenant + année courante + classe + comptes
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Bannière M16', 'ecole-banniere-m16') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '6A', '6e A') RETURNING id AS classe_id \gset

SELECT pg_temp.creer_compte('224600002191', 'direction')  AS dir_id \gset
SELECT pg_temp.creer_compte('224600002192', 'eleve')      AS eleve_risque_id \gset
SELECT pg_temp.creer_compte('224600002193', 'eleve')      AS eleve_sain_id \gset
SELECT pg_temp.creer_compte('224600002194', 'eleve')      AS etranger_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_id'::uuid, :'etab_id'::uuid, 'direction');

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M16-BAN-001', 'BAH', 'Ibrahima', '2011-05-09', :'eleve_risque_id'::uuid, now())
RETURNING id AS fiche_risque_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M16-BAN-002', 'SYLLA', 'Kadiatou', '2011-06-10', :'eleve_sain_id'::uuid, now())
RETURNING id AS fiche_sain_id \gset

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES
  (:'etab_id'::uuid, :'fiche_risque_id'::uuid, :'classe_id'::uuid, :'annee_id'::uuid, 'active'),
  (:'etab_id'::uuid, :'fiche_sain_id'::uuid, :'classe_id'::uuid, :'annee_id'::uuid, 'active');

-- ---------------------------------------------------------------------------
-- Élève à risque : 3 absences non justifiées (taux_abs = 1) + 10 retards non
-- justifiés (plafond retards) + aucune note → score ≈ 0.5 + 0.2 + 0.045
-- = 0.745, largement au-dessus du seuil 0.6.
-- ---------------------------------------------------------------------------
INSERT INTO public.presences (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, date_presence, type_seance, statut, justifie, saisi_par)
SELECT :'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, :'fiche_risque_id'::uuid,
       (date '2026-10-05' + n::int), 'demi_journee', 'absent', false, :'dir_id'::uuid
FROM generate_series(0, 2) AS n;

INSERT INTO public.retards (etablissement_id, fiche_eleve_id, annee_scolaire_id, date_retard, minutes_retard, justifie, saisi_par)
SELECT :'etab_id'::uuid, :'fiche_risque_id'::uuid, :'annee_id'::uuid,
       (date '2026-10-05' + n::int), 10, false, :'dir_id'::uuid
FROM generate_series(0, 9) AS n;

-- ---------------------------------------------------------------------------
-- Élève sain : présent, bonne note publiée → score bas, sous le seuil.
-- ---------------------------------------------------------------------------
INSERT INTO public.presences (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, date_presence, type_seance, statut, justifie, saisi_par)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, :'fiche_sain_id'::uuid, date '2026-10-05', 'demi_journee', 'present', false, :'dir_id'::uuid);

INSERT INTO public.evaluations (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, type, libelle, coefficient, bareme, statut, publie_le)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, :'dir_id'::uuid, 'controle', 'Contrôle', 1, 20, 'publiee', now())
RETURNING id AS eval_id \gset

INSERT INTO public.notes (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par)
VALUES (:'etab_id'::uuid, :'eval_id'::uuid, :'fiche_sain_id'::uuid, 18, :'dir_id'::uuid);

-- ---------------------------------------------------------------------------
-- Consolidation (personnel, sans poste requis — est_personnel seul) puis
-- lecture de la bannière.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);

SELECT public.consolider_indicateurs_etablissement(:'etab_id'::uuid, :'annee_id'::uuid);

SELECT is(
  (SELECT valeur_numeric FROM public.indicateurs_cles
     WHERE etablissement_id = :'etab_id'::uuid AND annee_scolaire_id = :'annee_id'::uuid
       AND code = 'eleves_a_risque'),
  1::numeric,
  'bannière : exactement 1 élève à risque compté (le sain reste sous le seuil 0.6)'
);

SELECT ok(
  public.calculer_score_decrochage(:'fiche_risque_id'::uuid, :'annee_id'::uuid) >= 0.6,
  'contrôle : le score brut de l''élève compté est bien au-dessus du seuil (pas une coïncidence de comptage)'
);

SELECT ok(
  public.calculer_score_decrochage(:'fiche_sain_id'::uuid, :'annee_id'::uuid) < 0.6,
  'contrôle : le score brut de l''élève sain reste bien sous le seuil (n''est pas compté par erreur)'
);

-- Étranger : aucune ligne indicateurs_cles visible pour cet établissement.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*)::int FROM public.indicateurs_cles WHERE etablissement_id = :'etab_id'::uuid),
  0,
  'étranger : aucun indicateur visible (RLS indicateurs_cles déjà en place, inchangée)'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
