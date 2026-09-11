-- ============================================================================
-- EcoShop — Test RLS 39 : M16 — matérialisation & exposition du score de
-- risque par élève (`materialiser_risque_reussite`/`risque_reussite_actuel`)
--
-- Ne re-teste PAS la formule de `calculer_score_decrochage` (déjà couverte
-- ailleurs, M7) : vérifie que la matérialisation reproduit EXACTEMENT sa
-- valeur (pas de drift), que la ligne est unique par (fiche, année) et mise
-- à jour (pas dupliquée) à chaque appel, que l'échelle reste 0-1 (pas de
-- conversion 0-100 stockée), que la lecture respecte la visibilité déjà en
-- place (`statistiques_select`), et que la matérialisation est réservée au
-- service_role (jamais appelable par un client authentifié, même direction).
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

SELECT plan(11);

-- ---------------------------------------------------------------------------
-- Tenant + année courante + classe
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Risque M16', 'ecole-risque-m16') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '6A', '6e A') RETURNING id AS classe_id \gset

-- ---------------------------------------------------------------------------
-- Comptes + fiche + inscription + relation parent + membre enseignant/direction
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224600002091', 'eleve')      AS eleve_id \gset
SELECT pg_temp.creer_compte('224600002092', 'parent')     AS parent_id \gset
SELECT pg_temp.creer_compte('224600002093', 'enseignant') AS prof_id \gset
SELECT pg_temp.creer_compte('224600002094', 'eleve')      AS etranger_id \gset
SELECT pg_temp.creer_compte('224600002095', 'direction')  AS dir_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M16-RISQ-001', 'KEITA', 'Aissatou', '2011-03-02', :'eleve_id'::uuid, now())
RETURNING id AS fiche_id \gset

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES (:'etab_id'::uuid, :'fiche_id'::uuid, :'classe_id'::uuid, :'annee_id'::uuid, 'active');

INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
VALUES (:'etab_id'::uuid, :'parent_id'::uuid, :'fiche_id'::uuid, 'tuteur_legal', 'confirmee', true);

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'prof_id'::uuid, :'etab_id'::uuid, 'enseignant'),
  (:'dir_id'::uuid, :'etab_id'::uuid, 'direction');

-- ---------------------------------------------------------------------------
-- Une absence non justifiée (seule donnée d'entrée nécessaire pour un score
-- non nul et déterministe : taux_abs = 1, retards = 0, moyenne absente).
-- ---------------------------------------------------------------------------
INSERT INTO public.presences (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, date_presence, type_seance, statut, justifie, saisi_par)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_id'::uuid, :'fiche_id'::uuid, date '2026-10-06', 'demi_journee', 'absent', false, :'prof_id'::uuid);

-- ---------------------------------------------------------------------------
-- 1) La matérialisation reproduit EXACTEMENT calculer_score_decrochage
-- ---------------------------------------------------------------------------
SELECT public.calculer_score_decrochage(:'fiche_id'::uuid, :'annee_id'::uuid) AS score_attendu \gset

SELECT public.materialiser_risque_reussite(:'etab_id'::uuid, :'annee_id'::uuid);

SELECT is(
  (SELECT valeur_numeric FROM public.statistiques_agregats
     WHERE fiche_eleve_id = :'fiche_id'::uuid AND type_agregat = 'risque_reussite'),
  :'score_attendu'::numeric,
  'la valeur persistée est EXACTEMENT calculer_score_decrochage, aucune formule parallèle'
);

-- ---------------------------------------------------------------------------
-- 2) Échelle : jamais 0-100, toujours 0-1 (conversion = affichage seulement)
-- ---------------------------------------------------------------------------
SELECT ok(
  (SELECT valeur_numeric FROM public.statistiques_agregats
     WHERE fiche_eleve_id = :'fiche_id'::uuid AND type_agregat = 'risque_reussite') BETWEEN 0 AND 1,
  'la valeur stockée reste sur l''échelle 0-1, jamais convertie en 0-100'
);

-- ---------------------------------------------------------------------------
-- 3) Une seule ligne par (fiche, année) : ré-appeler ne duplique pas
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM public.statistiques_agregats
     WHERE fiche_eleve_id = :'fiche_id'::uuid AND type_agregat = 'risque_reussite'),
  1,
  'une seule ligne risque_reussite pour cette fiche après le premier calcul'
);

SELECT public.materialiser_risque_reussite(:'etab_id'::uuid, :'annee_id'::uuid);

SELECT is(
  (SELECT count(*)::int FROM public.statistiques_agregats
     WHERE fiche_eleve_id = :'fiche_id'::uuid AND type_agregat = 'risque_reussite'),
  1,
  'un second appel met à jour la ligne existante (upsert), ne la duplique pas'
);

SELECT is(
  (SELECT version FROM public.statistiques_agregats
     WHERE fiche_eleve_id = :'fiche_id'::uuid AND type_agregat = 'risque_reussite'),
  2,
  'la version s''incrémente à chaque recalcul (traçabilité)'
);

-- ---------------------------------------------------------------------------
-- 4) Exposition + visibilité : risque_reussite_actuel() est SECURITY DEFINER
--    (la RLS de la table ne s'applique PAS à l'intérieur — visibilité
--    revérifiée explicitement dans la fonction, voir migration). Testé sous
--    un contexte authentifié réel : personnel voit et retrouve exactement
--    la valeur persistée, étranger ne voit rien, élève/parent voient leur
--    propre score.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);
SELECT is(
  public.risque_reussite_actuel(:'fiche_id'::uuid),
  :'score_attendu'::numeric,
  'enseignant (personnel) : voit le score de risque, valeur exacte (même source, un seul chemin de lecture)'
);

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*)::int FROM public.statistiques_agregats
     WHERE fiche_eleve_id = :'fiche_id'::uuid AND type_agregat = 'risque_reussite'),
  0,
  'étranger : aucune ligne de risque visible pour un élève hors de son établissement'
);

-- ★ risque_reussite_actuel() est SECURITY DEFINER : la RLS de la table ne
-- s'applique pas à l'intérieur, donc revérifiée explicitement dans la
-- fonction (voir migration) — testé ICI en appelant la fonction elle-même,
-- pas seulement la table brute, pour ne pas laisser une fuite passer
-- inaperçue si la fonction oubliait un jour ce filtre.
SELECT is(
  public.risque_reussite_actuel(:'fiche_id'::uuid),
  NULL,
  'étranger : risque_reussite_actuel() ne fuite pas le score d''un élève hors de son établissement'
);

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT is(
  public.risque_reussite_actuel(:'fiche_id'::uuid),
  :'score_attendu'::numeric,
  'élève : voit son propre score de risque, valeur exacte'
);

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'parent_id', 'role', 'authenticated')::text, true);
SELECT is(
  public.risque_reussite_actuel(:'fiche_id'::uuid),
  :'score_attendu'::numeric,
  'parent : voit le score de risque de son enfant, valeur exacte'
);

-- ---------------------------------------------------------------------------
-- 6) La matérialisation reste réservée au service_role, même pour une
--    direction sans poste (jamais un raccourci "personnel = autorisé").
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.materialiser_risque_reussite('42000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000002') $$,
  '42501',
  NULL
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
