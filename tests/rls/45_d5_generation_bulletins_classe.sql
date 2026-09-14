-- ============================================================================
-- EcoShop — Test RLS 45 : génération des bulletins d'une classe (D5, §12.4)
--
-- Vérifie que :
--   • classer_eleves_classe() calcule un rang exact (tri décroissant de la
--     moyenne déjà éprouvée par calculer_moyenne_eleve, M6), réservé au
--     personnel de l'établissement de la classe ;
--   • generer_bulletins_classe() refuse un appelant sans
--     « scolarite.bulletin.gerer » (y compris quand a_permission() renvoie
--     NULL plutôt que false — un compte sans role_racine choisi) ;
--   • un titulaire de cette permission génère avec succès, contenu conforme
--     au classement (aucun calcul refait dans la RPC d'écriture) ;
--   • RÉGÉNÉRATION après correction d'une note (cahier §12.3 : une note
--     reste modifiable par le responsable jusqu'à la proclamation de fin
--     d'année) met à jour LES MÊMES lignes (mêmes id) avec le nouveau
--     classement, sans jamais créer de doublon — scénario qui a fait
--     échouer la première version de cette fonctionnalité (upsert direct
--     depuis le client sur un index partiel, corrigé par cette RPC) ;
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

SELECT plan(18);

-- ---------------------------------------------------------------------------
-- Établissement B, sans aucun lien avec le personnel testé ci-dessous — sa
-- seule raison d'être est de garantir qu'une fiche d'un AUTRE établissement,
-- présente dans la même table fiches_eleves, ne fait jamais échouer
-- classer_eleves_classe() sur la classe de l'établissement A. Régression
-- réelle trouvée le 2026-09-14 (corrigée migration 20260906001516) :
-- calculer_moyenne_eleve() (durci par l'audit RPC, migration 20260906001513)
-- pouvait être évalué par le planificateur sur CETTE fiche AVANT le filtre
-- de classe, uniquement parce qu'un Seq Scan de fiches_eleves était moins
-- coûteux qu'un index scan sur une petite table — un bug dépendant du plan
-- choisi, pas de l'autorisation de l'appelant, invisible tant qu'aucune
-- fiche étrangère n'existait dans la table pendant le test.
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École B (bruit)', 'ecole-bulletins-d5-b') RETURNING id AS etab_b_id \gset
INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_b_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_b_id \gset
INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_b_id'::uuid, :'annee_b_id'::uuid, '6B', '6e B') RETURNING id AS classe_b_id \gset
INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance)
VALUES (:'etab_b_id'::uuid, 'BRUIT-001', 'ZZZ', 'Etranger', '2011-01-01') RETURNING id AS fiche_b_id \gset
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES (:'etab_b_id'::uuid, :'fiche_b_id'::uuid, :'classe_b_id'::uuid, :'annee_b_id'::uuid, 'active');

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

-- id de la note de fiche2, pour la corriger plus tard (régénération).
SELECT id AS note_fiche2_id FROM public.notes WHERE fiche_eleve_id = :'fiche2_id'::uuid \gset

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

-- 5-6. Un enseignant sans « scolarite.bulletin.gerer » est refusé à la
-- génération (y compris via a_permission() = NULL, pas seulement false —
-- voir docstring de la RPC).
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT * FROM public.generer_bulletins_classe(
       (SELECT id FROM public.classes WHERE code = '5A' AND etablissement_id = (SELECT id FROM public.etablissements WHERE slug = 'ecole-bulletins-d5')),
       (SELECT id FROM public.annees_scolaires WHERE etablissement_id = (SELECT id FROM public.etablissements WHERE slug = 'ecole-bulletins-d5')),
       (SELECT id FROM public.periodes_scolaires WHERE code = 'T1' AND etablissement_id = (SELECT id FROM public.etablissements WHERE slug = 'ecole-bulletins-d5')),
       'trimestriel'
     ) $$,
  '42501', 'PERMISSION_REFUSEE', 'génération : refusée sans scolarite.bulletin.gerer'
);
SELECT is((SELECT count(*) FROM public.bulletins)::int, 0, 'génération : aucun bulletin créé par la tentative refusée');

-- 7-9. La scolarité (permission bulletin.gerer) génère les 2 bulletins —
-- contenu conforme au classement, aucun calcul refait dans la RPC.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'scol_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*)::int FROM public.generer_bulletins_classe(:'classe_id'::uuid, :'annee_id'::uuid, :'periode_id'::uuid, 'trimestriel')),
  2,
  'génération : 2 bulletins créés (un par élève classé)'
);
SELECT is(
  (SELECT contenu FROM public.bulletins WHERE fiche_eleve_id = :'fiche1_id'::uuid),
  jsonb_build_object('moyenne_generale', 18, 'rang', 1, 'effectif_classe', 2),
  'génération : contenu de fiche1 conforme au classement (18/20, rang 1)'
);
SELECT is(
  (SELECT contenu FROM public.bulletins WHERE fiche_eleve_id = :'fiche2_id'::uuid),
  jsonb_build_object('moyenne_generale', 10, 'rang', 2, 'effectif_classe', 2),
  'génération : contenu de fiche2 conforme au classement (10/20, rang 2)'
);

-- id des deux bulletins, pour vérifier après régénération qu'aucun doublon
-- n'a été créé (même ligne mise à jour).
SELECT id AS bulletin1_id FROM public.bulletins WHERE fiche_eleve_id = :'fiche1_id'::uuid \gset
SELECT id AS bulletin2_id FROM public.bulletins WHERE fiche_eleve_id = :'fiche2_id'::uuid \gset

-- ---------------------------------------------------------------------------
-- 10-15. RÉGÉNÉRATION après correction d'une note (cahier §12.3) : le
-- responsable relève la note de fiche2 de 10 à 19 (elle dépasse maintenant
-- fiche1) avant la proclamation de fin d'année, puis régénère.
-- ---------------------------------------------------------------------------
RESET ROLE;
UPDATE public.notes SET valeur = 19 WHERE id = :'note_fiche2_id'::uuid;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'scol_id', 'role', 'authenticated')::text, true);

SELECT is(
  (SELECT count(*)::int FROM public.generer_bulletins_classe(:'classe_id'::uuid, :'annee_id'::uuid, :'periode_id'::uuid, 'trimestriel')),
  2,
  'régénération : renvoie toujours 2 bulletins (mis à jour, pas ajoutés)'
);
SELECT is((SELECT count(*) FROM public.bulletins)::int, 2, 'régénération : toujours 2 lignes en base, aucun doublon créé');
SELECT is((SELECT id FROM public.bulletins WHERE fiche_eleve_id = :'fiche1_id'::uuid), :'bulletin1_id'::uuid, 'régénération : le bulletin de fiche1 garde le même id (mise à jour en place)');
SELECT is((SELECT id FROM public.bulletins WHERE fiche_eleve_id = :'fiche2_id'::uuid), :'bulletin2_id'::uuid, 'régénération : le bulletin de fiche2 garde le même id (mise à jour en place)');
SELECT is(
  (SELECT contenu FROM public.bulletins WHERE fiche_eleve_id = :'fiche2_id'::uuid),
  jsonb_build_object('moyenne_generale', 19, 'rang', 1, 'effectif_classe', 2),
  'régénération : fiche2 (19/20) devient rang 1 — le classement est bien recalculé, pas figé'
);
SELECT is(
  (SELECT contenu FROM public.bulletins WHERE fiche_eleve_id = :'fiche1_id'::uuid),
  jsonb_build_object('moyenne_generale', 18, 'rang', 2, 'effectif_classe', 2),
  'régénération : fiche1 (18/20) redescend rang 2'
);

-- 16-18. Visibilité une fois publié : élève lié, parent confirmé, étranger.
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
