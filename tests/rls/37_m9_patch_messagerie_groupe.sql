-- ============================================================================
-- EcoShop — Test RLS 37 : messagerie de groupe scolaire (patch de sécurité M9)
--
-- Vérifie les 7 règles absolues de protection des mineurs (voir migration
-- 20260906000901_m9_patch_securite_messagerie_groupe.sql) :
--   • le créateur (enseignant) et un élève inscrit voient le groupe/messages ;
--   • un parent de l'élève NE voit RIEN (règle absolue #4 — zéro accès parent) ;
--   • un compte étranger (autre classe, non-membre) ne voit rien et ne peut
--     ni lire ni écrire dans le groupe ;
--   • un élève ne peut ni créer un groupe, ni modérer (soft-supprimer) un
--     message, ni lire un signalement (règle absolue #1/#6) ;
--   • la modération (enseignant créateur) peut soft-supprimer un message et
--     lire les signalements.
--
-- Identifiants fixes (comme le reste de la suite, ex. test 19) pour pouvoir
-- les référencer littéralement dans les blocs $$...$$ passés à throws_ok :
-- l'interpolation de variable psql (:'var') n'est pas fiable à l'intérieur
-- d'un bloc dollar-quoté.
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
-- Établissement (id fixe), année, deux classes (A = celle du groupe,
-- B = étrangère), groupe (id fixe).
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('41000000-0000-0000-0000-000000000001', 'École Messagerie M9', 'ecole-messagerie-m9');

INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('41000000-0000-0000-0000-000000000002', '41000000-0000-0000-0000-000000000001',
        '2026-2027', '2026-10-01', '2027-06-30', true);

INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom)
VALUES ('41000000-0000-0000-0000-000000000003', '41000000-0000-0000-0000-000000000001',
        '41000000-0000-0000-0000-000000000002', '6A-MSG', '6e A');

INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom)
VALUES ('41000000-0000-0000-0000-000000000004', '41000000-0000-0000-0000-000000000001',
        '41000000-0000-0000-0000-000000000002', '6B-MSG', '6e B');

-- Classe C : dédiée au test de non-régression ci-dessous (INSERT ...
-- RETURNING), pour ne pas entrer en conflit avec l'unique groupe actif
-- classe+année déjà créé sur la classe A.
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom)
VALUES ('41000000-0000-0000-0000-000000000008', '41000000-0000-0000-0000-000000000001',
        '41000000-0000-0000-0000-000000000002', '6C-MSG', '6e C');

-- ---------------------------------------------------------------------------
-- Comptes : enseignant créateur (affecté classe A), élève membre (inscrit
-- classe A), parent du membre, élève étranger (inscrit classe B seulement).
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224600002001', 'enseignant') AS prof_id      \gset
SELECT pg_temp.creer_compte('224600002002', 'eleve')      AS eleve_id     \gset
SELECT pg_temp.creer_compte('224600002003', 'parent')     AS parent_id    \gset
SELECT pg_temp.creer_compte('224600002004', 'eleve')      AS etranger_id  \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'prof_id'::uuid, '41000000-0000-0000-0000-000000000001', 'enseignant'),
  (:'eleve_id'::uuid, '41000000-0000-0000-0000-000000000001', 'eleve'),
  (:'etranger_id'::uuid, '41000000-0000-0000-0000-000000000001', 'eleve');

INSERT INTO public.affectations_enseignants
  (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id, role_affectation)
VALUES ('41000000-0000-0000-0000-000000000001', '41000000-0000-0000-0000-000000000002',
        :'prof_id'::uuid, '41000000-0000-0000-0000-000000000003', 'titulaire');

-- Affectation sur la classe C, uniquement pour le test de non-régression.
INSERT INTO public.affectations_enseignants
  (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id, role_affectation)
VALUES ('41000000-0000-0000-0000-000000000001', '41000000-0000-0000-0000-000000000002',
        :'prof_id'::uuid, '41000000-0000-0000-0000-000000000008', 'titulaire');

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES ('41000000-0000-0000-0000-000000000001', 'M9-MSG-001', 'DIALLO', 'Fatoumata', '2013-03-02', :'eleve_id'::uuid, now())
RETURNING id AS fiche_eleve_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES ('41000000-0000-0000-0000-000000000001', 'M9-MSG-002', 'BAH', 'Ousmane', '2013-05-19', :'etranger_id'::uuid, now())
RETURNING id AS fiche_etranger_id \gset

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES ('41000000-0000-0000-0000-000000000001', :'fiche_eleve_id'::uuid,
        '41000000-0000-0000-0000-000000000003', '41000000-0000-0000-0000-000000000002', 'active');

-- L'étranger est inscrit dans l'AUTRE classe : jamais membre du groupe de A.
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES ('41000000-0000-0000-0000-000000000001', :'fiche_etranger_id'::uuid,
        '41000000-0000-0000-0000-000000000004', '41000000-0000-0000-0000-000000000002', 'active');

-- Le parent a une relation confirmée et autorisée avec l'élève membre — ce
-- qui, pour la fiche/scolarité, lui donnerait accès. Le groupe de classe ne
-- doit JAMAIS le considérer comme membre (règle absolue #4).
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
VALUES ('41000000-0000-0000-0000-000000000001', :'parent_id'::uuid, :'fiche_eleve_id'::uuid, 'parent', 'confirmee', true);

-- ---------------------------------------------------------------------------
-- Groupe de classe A (id fixe) + 2 messages (créés hors RLS, comme le reste
-- des fixtures de cette suite).
-- ---------------------------------------------------------------------------
INSERT INTO public.groupes_discussion (id, etablissement_id, classe_id, annee_scolaire_id, nom, enseignant_createur_id)
VALUES ('41000000-0000-0000-0000-000000000005', '41000000-0000-0000-0000-000000000001',
        '41000000-0000-0000-0000-000000000003', '41000000-0000-0000-0000-000000000002',
        'Classe 6e A', :'prof_id'::uuid);

INSERT INTO public.messages_groupe (id, etablissement_id, groupe_id, auteur_id, contenu)
VALUES ('41000000-0000-0000-0000-000000000006', '41000000-0000-0000-0000-000000000001',
        '41000000-0000-0000-0000-000000000005', :'prof_id'::uuid, 'Bienvenue dans le groupe de la classe.');

INSERT INTO public.messages_groupe (id, etablissement_id, groupe_id, auteur_id, contenu)
VALUES ('41000000-0000-0000-0000-000000000007', '41000000-0000-0000-0000-000000000001',
        '41000000-0000-0000-0000-000000000005', :'eleve_id'::uuid, 'Merci monsieur !');

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

-- 1-2. Le créateur (enseignant) voit le groupe et les deux messages.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.groupes_discussion
           WHERE id = '41000000-0000-0000-0000-000000000005')::int, 1,
  'enseignant créateur : voit le groupe');
SELECT is((SELECT count(*) FROM public.messages_groupe
           WHERE groupe_id = '41000000-0000-0000-0000-000000000005')::int, 2,
  'enseignant créateur : voit les 2 messages');

-- 2bis. Non-régression (patch 20260906001503) : INSERT ... RETURNING réussit
-- pour l'enseignant créateur — la policy SELECT s'appuyait auparavant sur
-- membre_groupe(id), auto-référentielle (re-interroge groupes_discussion
-- par id), qui ne voyait pas la ligne tout juste insérée au moment où
-- Postgres vérifie implicitement la policy SELECT pour construire le
-- résultat de RETURNING (INSERT seul réussissait, RETURNING échouait en
-- 42501 pour tout le monde). Classe C dédiée + savepoint pour ne pas
-- perturber les comptages des assertions suivantes.
SAVEPOINT avant_regression_returning;
INSERT INTO public.groupes_discussion
  (etablissement_id, classe_id, annee_scolaire_id, nom, enseignant_createur_id)
VALUES ('41000000-0000-0000-0000-000000000001', '41000000-0000-0000-0000-000000000008',
        '41000000-0000-0000-0000-000000000002', 'Classe 6e C (non-régression)', :'prof_id'::uuid)
RETURNING id AS groupe_regression_id \gset
SELECT ok(
  :'groupe_regression_id' IS NOT NULL,
  'non-régression : INSERT ... RETURNING réussit pour le créateur (policy SELECT non auto-référentielle)'
);
ROLLBACK TO SAVEPOINT avant_regression_returning;

-- 3-4. L'élève membre (inscrit dans la classe) voit le groupe et les messages.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.groupes_discussion
           WHERE id = '41000000-0000-0000-0000-000000000005')::int, 1,
  'élève membre : voit le groupe');
SELECT is((SELECT count(*) FROM public.messages_groupe
           WHERE groupe_id = '41000000-0000-0000-0000-000000000005')::int, 2,
  'élève membre : voit les 2 messages');

-- 5-6. Le parent de l'élève membre NE voit RIEN (règle absolue #4).
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'parent_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.groupes_discussion
           WHERE id = '41000000-0000-0000-0000-000000000005')::int, 0,
  'parent : zéro accès au groupe (règle absolue #4)');
SELECT is((SELECT count(*) FROM public.messages_groupe
           WHERE groupe_id = '41000000-0000-0000-0000-000000000005')::int, 0,
  'parent : zéro accès aux messages (règle absolue #4)');

-- 7-9. Un compte non-membre (étranger, autre classe) ne voit rien et ne peut
-- pas écrire dans le groupe.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.groupes_discussion
           WHERE id = '41000000-0000-0000-0000-000000000005')::int, 0,
  'non-membre : ne voit pas le groupe d''une autre classe');
SELECT is((SELECT count(*) FROM public.messages_groupe
           WHERE groupe_id = '41000000-0000-0000-0000-000000000005')::int, 0,
  'non-membre : ne voit aucun message d''une autre classe');

SELECT throws_ok(
  $$ INSERT INTO public.messages_groupe (etablissement_id, groupe_id, auteur_id, contenu)
     VALUES ('41000000-0000-0000-0000-000000000001', '41000000-0000-0000-0000-000000000005',
             auth.uid(), 'Je m''incruste') $$,
  '42501',
  NULL
);

-- 10. Un élève (jamais un adulte) ne peut pas créer de groupe.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ INSERT INTO public.groupes_discussion
     (etablissement_id, classe_id, annee_scolaire_id, nom, enseignant_createur_id)
     VALUES ('41000000-0000-0000-0000-000000000001', '41000000-0000-0000-0000-000000000003',
             '41000000-0000-0000-0000-000000000002', 'Groupe pirate', auth.uid()) $$,
  '42501',
  NULL
);

-- 11. Un élève membre (non modérateur) ne peut pas soft-supprimer un message
-- : la policy UPDATE le filtre silencieusement (0 ligne affectée).
WITH tentative AS (
  UPDATE public.messages_groupe
     SET supprime = true, supprime_par_id = :'eleve_id'::uuid
   WHERE id = '41000000-0000-0000-0000-000000000007'
  RETURNING id
)
SELECT is((SELECT count(*) FROM tentative)::int, 0,
  'élève membre : ne peut pas modérer un message (règle absolue #6)');

-- 12. L'enseignant créateur (modérateur) peut soft-supprimer un message.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);
WITH moderation AS (
  UPDATE public.messages_groupe
     SET supprime = true, supprime_par_id = :'prof_id'::uuid, date_suppression = now()
   WHERE id = '41000000-0000-0000-0000-000000000007'
  RETURNING id
)
SELECT is((SELECT count(*) FROM moderation)::int, 1,
  'modérateur : peut soft-supprimer un message');

-- 13-14. Signalement : un élève membre peut signaler un message qu'il voit,
-- mais ne peut pas lire les signalements (réservé à la modération) — seule
-- la modération le peut.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT lives_ok(
  $$ INSERT INTO public.signalements_message (etablissement_id, message_id, signale_par_id, motif)
     VALUES ('41000000-0000-0000-0000-000000000001', '41000000-0000-0000-0000-000000000006',
             auth.uid(), 'Contenu inapproprié') $$,
  'élève membre : peut signaler un message du groupe'
);
SELECT is((SELECT count(*) FROM public.signalements_message)::int, 0,
  'élève membre : ne peut pas lire les signalements (réservé personnel)');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.signalements_message)::int, 1,
  'modérateur : peut lire le signalement');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
