-- ============================================================================
-- EcoShop — Test RLS 45 : génération des bulletins d'une classe (D5, §12.4)
--
-- Vérifie que :
--   • classer_eleves_classe() calcule un rang exact (tri décroissant de la
--     moyenne déjà éprouvée par calculer_moyenne_eleve, M6) ;
--   • seul le personnel de l'établissement de la classe peut l'appeler (un
--     étranger n'obtient aucune ligne) ;
--   • un titulaire de « scolarite.bulletin.gerer » peut écrire le bulletin
--     (RLS bulletins_ecriture_scolarite, M6, jamais exercée jusqu'ici) ;
--   • un enseignant sans cette permission est refusé ;
--   • une fois publié, l'élève lié et son parent confirmé voient le
--     bulletin, un élève étranger ne voit rien.
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

SELECT plan(10);

-- ---------------------------------------------------------------------------
-- Tenant + année + période + classe
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Bulletins D5', 'ecole-bulletins-d5') RETURNING id AS etab_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.periodes_scolaires (etablissement_id, annee_scolaire_id, code, libelle, type, ordre, date_debut, date_fin)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, 'T1', '1er trimestre', 'trimestre', 1, '2026-10-01', '2026-12-23')
RETURNING id AS periode_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '5A', '5e A') RETURNING id AS classe_id \gset

-- ---------------------------------------------------------------------------
-- Deux fiches inscrites (moyennes distinctes -> classement vérifiable)
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224600001081', 'eleve') AS eleve1_id \gset
SELECT pg_temp.creer_compte('224600001082', 'eleve') AS eleve2_id \gset
SELECT pg_temp.creer_compte('224600001083', 'parent') AS parent1_id \gset
SELECT pg_temp.creer_compte('224600001084', 'eleve') AS etranger_id \gset
SELECT pg_temp.creer_compte('224600001085', 'enseignant') AS prof_id \gset
SELECT pg_temp.creer_compte('224600001086', 'enseignant') AS scol_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'D5-BUL-001', 'CAMARA', 'Fatoumata', '2011-04-12', :'eleve1_id'::uuid, now())
RETURNING id AS fiche1_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'D5-BUL-002', 'DIALLO', 'Ibrahima', '2011-07-30', :'eleve2_id'::uuid, now())
RETURNING id AS fiche2_id \gset

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES
  (:'etab_id'::uuid, :'fiche1_id'::uuid, :'classe_id'::uuid, :'annee_id'::uuid, 'active'),
  (:'etab_id'::uuid, :'fiche2_id'::uuid, :'classe_id'::uuid, :'annee_id'::uuid, 'active');

INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
VALUES (:'etab_id'::uuid, :'parent1_id'::uuid, :'fiche1_id'::uuid, 'tuteur_legal', 'confirmee', true);

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'prof_id'::uuid, :'etab_id'::uuid, 'enseignant');

INSERT INTO public.postes (etablissement_id, code, nom)
SELECT :'etab_id'::uuid, 'SCOLARITE', 'Scolarité'
WHERE NOT EXISTS (
  SELECT 1 FROM public.postes WHERE etablissement_id = :'etab_id'::uuid AND code = 'SCOLARITE' AND deleted_at IS NULL
);

SELECT id AS poste_id FROM public.postes
WHERE etablissement_id = :'etab_id'::uuid AND code = 'SCOLARITE' AND deleted_at IS NULL \gset

INSERT INTO public.poste_permissions (poste_id, permission_code)
VALUES (:'poste_id'::uuid, 'scolarite.bulletin.gerer') ON CONFLICT DO NOTHING;

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement, poste_id)
VALUES (:'scol_id'::uuid, :'etab_id'::uuid, 'personnel', :'poste_id'::uuid);

-- ---------------------------------------------------------------------------
-- Une évaluation publiée, notes distinctes : 18/20 (fiche1) vs 10/20 (fiche2)
-- ---------------------------------------------------------------------------
INSERT INTO public.evaluations
  (etablissement_id, annee_scolaire_id, periode_id, classe_id, enseignant_profile_id,
   type, libelle, coefficient, bareme, statut, publie_le)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'periode_id'::uuid, :'classe_id'::uuid, :'prof_id'::uuid,
        'composition', 'Composition du 1er trimestre', 1, 20, 'publiee', now())
RETURNING id AS eval_id \gset

INSERT INTO public.notes (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par)
VALUES
  (:'etab_id'::uuid, :'eval_id'::uuid, :'fiche1_id'::uuid, 18, :'prof_id'::uuid),
  (:'etab_id'::uuid, :'eval_id'::uuid, :'fiche2_id'::uuid, 10, :'prof_id'::uuid);

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

-- 1-3. Classement : personnel voit les 2 fiches, rang 1 = meilleure moyenne.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*)::int FROM public.classer_eleves_classe(:'classe_id'::uuid, NULL, :'periode_id'::uuid)),
  2,
  'classement : personnel voit les 2 fiches de la classe'
);
SELECT is(
  (SELECT rang FROM public.classer_eleves_classe(:'classe_id'::uuid, NULL, :'periode_id'::uuid) WHERE fiche_eleve_id = :'fiche1_id'::uuid),
  1,
  'classement : la meilleure moyenne (18/20) est rang 1'
);
SELECT is(
  (SELECT rang FROM public.classer_eleves_classe(:'classe_id'::uuid, NULL, :'periode_id'::uuid) WHERE fiche_eleve_id = :'fiche2_id'::uuid),
  2,
  'classement : la moyenne la plus faible (10/20) est rang 2'
);

-- 4. Un étranger (non membre de l'établissement) n'obtient aucune ligne.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*)::int FROM public.classer_eleves_classe(:'classe_id'::uuid, NULL, :'periode_id'::uuid)),
  0,
  'classement : étranger ne voit aucune ligne (garde personnel)'
);

-- 5. Un enseignant sans « scolarite.bulletin.gerer » est refusé à l'écriture.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ INSERT INTO public.bulletins
       (etablissement_id, annee_scolaire_id, periode_id, classe_id, fiche_eleve_id, type, statut, contenu, genere_le, publie_le)
     SELECT e.id, a.id, p.id, c.id, f.id, 'trimestriel', 'publie',
            jsonb_build_object('moyenne_generale', 18, 'rang', 1, 'effectif_classe', 2), now(), now()
     FROM public.etablissements e
     JOIN public.annees_scolaires a ON a.etablissement_id = e.id
     JOIN public.periodes_scolaires p ON p.etablissement_id = e.id AND p.code = 'T1'
     JOIN public.classes c ON c.etablissement_id = e.id AND c.code = '5A'
     JOIN public.fiches_eleves f ON f.etablissement_id = e.id AND f.matricule = 'D5-BUL-001'
     WHERE e.slug = 'ecole-bulletins-d5' $$,
  '42501', NULL, 'bulletin : écriture refusée sans scolarite.bulletin.gerer'
);
SELECT is((SELECT count(*) FROM public.bulletins)::int, 0, 'bulletin : aucune ligne créée par la tentative refusée');

-- 6. La scolarité (permission bulletin.gerer) écrit le bulletin — valeurs
--    reprises telles quelles du classement déjà calculé côté serveur (étape
--    1-3 ci-dessus), aucun calcul refait ici.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'scol_id', 'role', 'authenticated')::text, true);
INSERT INTO public.bulletins
  (etablissement_id, annee_scolaire_id, periode_id, classe_id, fiche_eleve_id, type, statut, contenu, genere_le, publie_le)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'periode_id'::uuid, :'classe_id'::uuid, :'fiche1_id'::uuid,
        'trimestriel', 'publie', jsonb_build_object('moyenne_generale', 18, 'rang', 1, 'effectif_classe', 2), now(), now())
RETURNING id AS bulletin1_id \gset
SELECT ok(:'bulletin1_id' IS NOT NULL, 'bulletin : la scolarité écrit avec succès (INSERT ... RETURNING réel)');

-- 7-9. Visibilité une fois publié : élève lié, parent confirmé, étranger.
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.bulletins WHERE id = :'bulletin1_id'::uuid)::int, 1, 'bulletin : l''élève lié voit son bulletin publié');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'parent1_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.bulletins WHERE id = :'bulletin1_id'::uuid)::int, 1, 'bulletin : le parent confirmé voit le bulletin de son enfant');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.bulletins WHERE id = :'bulletin1_id'::uuid)::int, 0, 'bulletin : un élève étranger ne voit rien');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
