-- ============================================================================
-- EcoShop — Test RLS 44 : M16, sous-livrable 5/7 — Scan et résolution
-- d'exercice (cahier §21.5)
--
-- Vérifie, dans cet ordre : création réussie par l'élève propriétaire ;
-- REJET par rôle (enseignant/direction — outil élève uniquement) ; refus
-- sans consentement ; refus texte vide ; REJET pour une fiche d'autrui
-- (tiers) ; aucune policy d'écriture cliente directe sur `ai_conversations`
-- (type scan_exercice) ni sur `scan_exercices` (INSERT rejeté, UPDATE sans
-- effet) ; REJET de `renseigner_identification_scan_exercice` par un tiers ;
-- succès de cette même fonction pour le propriétaire légitime ; visibilité
-- stricte à l'auteur (ni un autre élève, ni la direction) ; garde-fou tenant
-- du trigger `scan_exercices_verifie_tenant` (SECURITY DEFINER dès la
-- conception, cf. leçon du test 43) exercé directement ; refus sans
-- authentification.
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

SELECT plan(26);

-- ---------------------------------------------------------------------------
-- Tenant + comptes
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Scan Exercice M16', 'ecole-scan-exercice-m16')
RETURNING id AS etab_id \gset

SELECT pg_temp.creer_compte('224600002581', 'eleve')      AS eleve1_id \gset
SELECT pg_temp.creer_compte('224600002582', 'eleve')      AS eleve2_id \gset
SELECT pg_temp.creer_compte('224600002583', 'enseignant') AS prof_id \gset
SELECT pg_temp.creer_compte('224600002584', 'direction')  AS dir_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'prof_id'::uuid, :'etab_id'::uuid, 'enseignant'),
  (:'dir_id'::uuid, :'etab_id'::uuid, 'direction');

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M16-SCAN-001', 'SYLLA', 'Aissatou', '2012-05-01', :'eleve1_id'::uuid, now())
RETURNING id AS fiche1_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M16-SCAN-002', 'BARRY', 'Ibrahima', '2012-06-02', :'eleve2_id'::uuid, now())
RETURNING id AS fiche2_id \gset

-- Second établissement, totalement distinct — isolation inter-établissement
-- réelle (même méthode que le test 38, M15quater) : un élève réel, mais
-- sans aucun lien avec le premier établissement.
INSERT INTO public.etablissements (nom, slug) VALUES ('École Scan Exercice M16 Bis', 'ecole-scan-exercice-m16-bis')
RETURNING id AS etab2_id \gset

SELECT pg_temp.creer_compte('224600002585', 'eleve') AS eleve3_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab2_id'::uuid, 'M16-SCAN-BIS-001', 'CAMARA', 'Fatoumata', '2012-07-03', :'eleve3_id'::uuid, now())
RETURNING id AS fiche3_id \gset

SET LOCAL ROLE authenticated;

-- ---------------------------------------------------------------------------
-- 1) Création réussie par l'élève propriétaire.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);

SELECT public.preparer_scan_exercice(
  :'etab_id'::uuid, :'fiche1_id'::uuid,
  'Résoudre : 2x + 3 = 11', true
) AS preparation_json \gset

SELECT ok((:'preparation_json'::jsonb) ->> 'conversation_id' IS NOT NULL, 'préparation réussie : conversation_id renvoyé');
SELECT ok((:'preparation_json'::jsonb) ->> 'scan_id' IS NOT NULL, 'préparation réussie : scan_id renvoyé');

SELECT (:'preparation_json'::jsonb) ->> 'conversation_id' AS conv1_id \gset
SELECT (:'preparation_json'::jsonb) ->> 'scan_id' AS scan1_id \gset

SELECT is(
  (SELECT type::text FROM public.ai_conversations WHERE id = :'conv1_id'::uuid),
  'scan_exercice',
  'la conversation créée est bien de type scan_exercice'
);
SELECT is(
  (SELECT texte_extrait FROM public.scan_exercices WHERE id = :'scan1_id'::uuid),
  'Résoudre : 2x + 3 = 11',
  'le texte reconnu est bien celui transmis (jamais une photo)'
);

-- ---------------------------------------------------------------------------
-- 2) Rejet par rôle — outil élève uniquement, ni enseignant ni direction.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.preparer_scan_exercice('%s', '%s', 'texte', true) $$, :'etab_id', :'fiche1_id'),
  '42501',
  NULL
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.preparer_scan_exercice('%s', '%s', 'texte', true) $$, :'etab_id', :'fiche1_id'),
  '42501',
  NULL
);

-- ---------------------------------------------------------------------------
-- 3) Refus sans consentement / texte vide.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);

SELECT throws_ok(
  format($$ SELECT public.preparer_scan_exercice('%s', '%s', 'texte', false) $$, :'etab_id', :'fiche1_id'),
  '22023',
  NULL
);
SELECT throws_ok(
  format($$ SELECT public.preparer_scan_exercice('%s', '%s', '   ', true) $$, :'etab_id', :'fiche1_id'),
  '22023',
  NULL
);

-- ---------------------------------------------------------------------------
-- 4) Tiers ciblant la fiche d'autrui — eleve2 (rôle élève réel, mais sur la
--    fiche d'eleve1) doit être rejeté exactement comme un attaquant.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve2_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.preparer_scan_exercice('%s', '%s', 'texte forgé', true) $$, :'etab_id', :'fiche1_id'),
  '42501',
  NULL
);

-- ---------------------------------------------------------------------------
-- 4bis) Élève d'un AUTRE établissement (eleve3, rôle élève réel, aucun lien
--       avec le premier établissement) — trois angles distincts, même
--       méthode que l'isolation inter-établissement du test 38 (M15quater) :
--       a) usurpe l'établissement de la victime (etab_id) avec sa propre
--          fiche (fiche3, réellement dans etab2) : `determiner_role_ia
--          (etab_id)` doit renvoyer null pour eleve3 (aucune fiche à lui
--          dans cet établissement) → ACCES_REFUSE avant même la
--          vérification de propriété de la fiche.
--       b) rôle élève bien réel et valide dans SON PROPRE établissement
--          (etab2_id), mais cible la fiche de la victime (fiche1, réellement
--          dans etab_id) : le rôle passe, mais le rattachement
--          établissement/fiche/auteur échoue (fiche1 n'appartient pas à
--          etab2_id) → FICHE_INTROUVABLE, toujours 42501.
--       c) tente de renseigner l'identification d'un scan qui n'est pas le
--          sien (celui d'eleve1, établissement 1) → rejeté par la
--          vérification de propriété (auth.uid()), tenant-agnostique par
--          construction.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve3_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.preparer_scan_exercice('%s', '%s', 'texte forgé inter-établissement', true) $$, :'etab_id', :'fiche3_id'),
  '42501',
  NULL
);
SELECT throws_ok(
  format($$ SELECT public.preparer_scan_exercice('%s', '%s', 'texte forgé inter-établissement', true) $$, :'etab2_id', :'fiche1_id'),
  '42501',
  NULL
);
SELECT throws_ok(
  format($$ SELECT public.renseigner_identification_scan_exercice('%s', 'Matière forgée', 'Chapitre forgé') $$, :'scan1_id'),
  '42501',
  NULL
);

-- ---------------------------------------------------------------------------
-- 5) Aucune policy d'écriture cliente directe.
-- ---------------------------------------------------------------------------
-- 5a) ai_conversations : type scan_exercice toujours refusé en INSERT direct
--     (policy ai_conversations_insert_libre — non-régression 3/7/5/7).
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ INSERT INTO public.ai_conversations (etablissement_id, profile_id, type)
     VALUES ('%s', '%s', 'scan_exercice') $$, :'etab_id', :'eleve1_id'),
  '42501',
  NULL
);

-- 5b) scan_exercices : INSERT direct refusé même pour sa propre conversation.
SELECT throws_ok(
  format($$ INSERT INTO public.scan_exercices (conversation_id, fiche_eleve_id, texte_extrait, consentement)
     VALUES ('%s', '%s', 'intrusion', true) $$, :'conv1_id', :'fiche1_id'),
  '42501',
  NULL
);

-- 5c) UPDATE direct sans effet (aucune policy update).
UPDATE public.scan_exercices SET matiere_libelle = 'Falsifié' WHERE id = :'scan1_id'::uuid;
SELECT is(
  (SELECT matiere_libelle FROM public.scan_exercices WHERE id = :'scan1_id'::uuid),
  NULL,
  'UPDATE client direct sans effet (aucune policy update) — matiere_libelle reste NULL'
);

-- ---------------------------------------------------------------------------
-- 6) renseigner_identification_scan_exercice — rejet par un tiers, succès
--    pour le propriétaire légitime.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve2_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.renseigner_identification_scan_exercice('%s', 'Mathématiques', 'Équations du premier degré') $$, :'scan1_id'),
  '42501',
  NULL
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.renseigner_identification_scan_exercice('%s', 'Mathématiques', 'Équations du premier degré') $$, :'scan1_id'),
  '42501',
  NULL
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);
SELECT lives_ok(
  format($$ SELECT public.renseigner_identification_scan_exercice('%s', 'Mathématiques', 'Équations du premier degré') $$, :'scan1_id'),
  'le propriétaire légitime (via l''Edge Function, JWT forwardé) peut renseigner l''identification'
);
SELECT is(
  (SELECT matiere_libelle FROM public.scan_exercices WHERE id = :'scan1_id'::uuid),
  'Mathématiques',
  'matiere_libelle bien enregistrée (texte libre, jamais un FK)'
);
SELECT is(
  (SELECT chapitre_libelle FROM public.scan_exercices WHERE id = :'scan1_id'::uuid),
  'Équations du premier degré',
  'chapitre_libelle bien enregistré (inférence IA, jamais persistée dans un référentiel)'
);

-- ---------------------------------------------------------------------------
-- 7) Visibilité stricte à l'auteur.
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM public.scan_exercices WHERE id = :'scan1_id'::uuid),
  1,
  'eleve1 (auteur) voit son propre scan'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve2_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*)::int FROM public.scan_exercices WHERE id = :'scan1_id'::uuid),
  0,
  'eleve2 (aucun lien) ne voit rien du scan d''eleve1'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*)::int FROM public.scan_exercices WHERE id = :'scan1_id'::uuid),
  0,
  'la direction ne voit rien — travail personnel de l''élève, jamais partagé au personnel'
);

-- ---------------------------------------------------------------------------
-- 8) Garde-fou tenant du trigger `scan_exercices_verifie_tenant` — exercé
--    directement (rôle postgres, contourne RLS mais jamais les triggers) :
--    ★ même leçon que le test 43 (trigger SECURITY DEFINER dès la
--    conception ici, jamais après coup).
-- ---------------------------------------------------------------------------
RESET ROLE;

-- 8a) fiche incohérente avec le profil de la conversation.
INSERT INTO public.ai_conversations (etablissement_id, profile_id, type)
VALUES (:'etab_id'::uuid, :'eleve1_id'::uuid, 'scan_exercice')
RETURNING id AS conv_pour_trigger_id \gset

SELECT throws_ok(
  format($$ INSERT INTO public.scan_exercices (conversation_id, fiche_eleve_id, texte_extrait, consentement)
     VALUES ('%s', '%s', 'texte', true) $$, :'conv_pour_trigger_id', :'fiche2_id'),
  '23514',
  NULL
);

-- 8b) conversation d'un mauvais type (libre, pas scan_exercice).
INSERT INTO public.ai_conversations (etablissement_id, profile_id, type)
VALUES (:'etab_id'::uuid, :'eleve1_id'::uuid, 'libre')
RETURNING id AS conv_libre_id \gset

SELECT throws_ok(
  format($$ INSERT INTO public.scan_exercices (conversation_id, fiche_eleve_id, texte_extrait, consentement)
     VALUES ('%s', '%s', 'texte', true) $$, :'conv_libre_id', :'fiche1_id'),
  '23514',
  NULL
);

-- ---------------------------------------------------------------------------
-- 9) Sans authentification.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', NULL, true);

SELECT throws_ok(
  format($$ SELECT public.preparer_scan_exercice('%s', '%s', 'texte', true) $$, :'etab_id', :'fiche1_id'),
  '28000',
  NULL
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
