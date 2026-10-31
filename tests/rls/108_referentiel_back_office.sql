-- ============================================================================
-- EcoShop — Test RLS 108 : back-office du référentiel, pays de la
-- sous-région en brouillon (REG-38 lot E2b, migration 20260906001592)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.sur(p_uid uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  UPDATE public.profiles SET role_racine = p_role::public.role_racine, prenom = 'Test', nom = 'Test' WHERE id = v_id;
  RETURN v_id;
END $$;

SELECT plan(20);

SELECT pg_temp.compte('contenu.108@exemple.org', 'admin_contenu') AS contenu \gset
SELECT pg_temp.compte('parent.108@exemple.org', 'parent') AS parent \gset
SELECT pg_temp.compte('dir.108@exemple.org', 'direction') AS dir \gset

-- ---------------------------------------------------------------------------
-- 1. Pays de la sous-région livrés en brouillon
-- ---------------------------------------------------------------------------
SELECT is((SELECT count(*)::int FROM public.pays_pedagogiques
            WHERE code_iso IN ('CI', 'BJ', 'TG', 'NG', 'SL', 'LR', 'GM', 'CV', 'GW', 'ML', 'BF', 'NE')
              AND statut_deploiement = 'brouillon'), 12, 'douze pays ajoutés, tous en brouillon');
SELECT is((SELECT string_agg(code_iso, ',' ORDER BY code_iso) FROM public.pays_pedagogiques WHERE zone = 'aes'),
  'BF,ML,NE', 'Mali, Burkina Faso, Niger : zone AES');
SELECT is((SELECT count(*)::int FROM public.niveaux_educatifs WHERE pays_code = 'CI'), 13, 'Côte d''Ivoire : CP1 → Terminale');
SELECT is((SELECT string_agg(code, ',' ORDER BY code) FROM public.examens_nationaux WHERE pays_code = 'TG'),
  'BAC1,BAC2,BEPC,CEPD', 'Togo : BAC I et BAC II');
SELECT is((SELECT count(*)::int FROM public.niveaux_educatifs WHERE pays_code IN ('CV', 'GW')), 0,
  'pays lusophones : aucun niveau inventé');
SELECT is((SELECT max(grade_level_normalise) - min(grade_level_normalise) + 1 FROM public.niveaux_educatifs WHERE pays_code = 'ML'),
  (SELECT count(*)::int FROM public.niveaux_educatifs WHERE pays_code = 'ML'), 'Mali : grille contiguë');

SET LOCAL ROLE authenticated;

SELECT pg_temp.sur(:'parent');
SELECT is((SELECT count(*)::int FROM public.pays_pedagogiques WHERE code_iso = 'CI'), 0,
  'un pays en brouillon reste invisible des familles');
SELECT throws_ok($$ SELECT public.pays_back_office() $$, '42501', NULL, 'back-office fermé aux parents');

SELECT pg_temp.sur(:'dir');
SELECT throws_ok($$ SELECT public.enregistrer_pays_referentiel('ZZ', 'Essai', 'francophone_cfa', 'fr') $$,
  '42501', NULL, 'une direction ne modifie pas le référentiel');

-- ---------------------------------------------------------------------------
-- 2. Contrôle et publication
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'contenu');
SELECT ok(public.pays_back_office() @> '[{"code": "CI", "statut": "brouillon", "a_verifier": true}]',
  'l''Administrateur de contenu voit les brouillons');
SELECT throws_ok($$ SELECT public.publier_pays_referentiel('CI') $$, '22023', 'REFERENTIEL_INCOMPLET',
  'publication refusée tant que des points restent à vérifier');
SELECT public.enregistrer_pays_referentiel('CI', 'Côte d''Ivoire', 'francophone_cfa', 'fr', 'DECO', 'XOF', 'cedeao', 'Arrêtés vérifiés', NULL);
SELECT is((public.publier_pays_referentiel('CI') ->> 'niveaux')::int, 13, 'points levés : les 13 niveaux sont publiés');

SELECT pg_temp.sur(:'parent');
SELECT is((SELECT count(*)::int FROM public.niveaux_educatifs WHERE pays_code = 'CI'), 13,
  'publié : visible de tous (demande d''ouverture d''école, révisions)');

-- Un pays décrit de toutes pièces, avec un trou dans la grille.
SELECT pg_temp.sur(:'contenu');
SELECT public.enregistrer_pays_referentiel('ZZ', 'Pays d''essai', 'francophone_cfa', 'fr');
SELECT public.enregistrer_cycle_referentiel('a8100000-0000-0000-0000-000000000001', 'ZZ', 'primaire', 'Primaire', 1, 1, 1);
SELECT public.enregistrer_niveau_referentiel('a8200000-0000-0000-0000-000000000001', 'a8100000-0000-0000-0000-000000000001',
  'N1', 'Niveau 1', 1, 1, 1);
SELECT public.enregistrer_niveau_referentiel('a8200000-0000-0000-0000-000000000003', 'a8100000-0000-0000-0000-000000000001',
  'N3', 'Niveau 3', 3, 1, 3);
SELECT public.enregistrer_examen_referentiel('a8300000-0000-0000-0000-000000000001', 'ZZ',
  'a8100000-0000-0000-0000-000000000001', 'CEP', 'Certificat', NULL, 6);
SELECT ok(EXISTS (SELECT 1 FROM jsonb_array_elements(public.controle_referentiel('ZZ')) x
                   WHERE x ->> 'message' LIKE 'Les rangs des niveaux ne se suivent pas%'), 'trou dans la grille repéré');
SELECT ok(EXISTS (SELECT 1 FROM jsonb_array_elements(public.controle_referentiel('ZZ')) x
                   WHERE x ->> 'message' LIKE 'CEP : aucune classe d''examen%'), 'examen sans classe d''examen repéré');
SELECT throws_ok($$ SELECT public.enregistrer_niveau_referentiel(gen_random_uuid(), 'a8100000-0000-0000-0000-000000000001',
  'N1', 'Doublon', 2, 1, 2) $$, '22023', 'CODE_OU_RANG_DEJA_UTILISE', 'un code par pays');

-- Un niveau qui a des classes ne change plus de rang et ne se supprime pas.
RESET ROLE;
INSERT INTO public.etablissements (id, nom, slug, devise_code, pays_code)
VALUES ('a8000000-0000-0000-0000-00000000000a', 'École 108', 'ecole-108', 'XOF', 'GN');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('a8000000-0000-0000-0000-0000000000a1', 'a8000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom, niveau_id)
VALUES ('a8000000-0000-0000-0000-00000000000a', 'a8000000-0000-0000-0000-0000000000a1', 'N3A', 'N3 A',
        'a8200000-0000-0000-0000-000000000003');
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'contenu');
SELECT throws_ok($$ SELECT public.enregistrer_niveau_referentiel('a8200000-0000-0000-0000-000000000003',
  'a8100000-0000-0000-0000-000000000001', 'N3', 'Niveau 3', 2, 1, 3) $$, '22023', 'NIVEAU_UTILISE',
  'le rang d''un niveau utilisé ne bouge plus');
SELECT throws_ok($$ SELECT public.supprimer_element_referentiel('niveau', 'a8200000-0000-0000-0000-000000000003') $$,
  '22023', 'ELEMENT_UTILISE', 'un niveau utilisé ne se supprime pas');

-- ---------------------------------------------------------------------------
-- 3. Programme national de la Guinée, base de la banque de questions
-- ---------------------------------------------------------------------------
SELECT id AS gn10 FROM public.niveaux_educatifs WHERE pays_code = 'GN' AND code = '10e' \gset
SELECT public.enregistrer_programme_national('a8400000-0000-0000-0000-000000000001', :'gn10');
SELECT public.enregistrer_matiere_nationale('a8500000-0000-0000-0000-000000000001', 'a8400000-0000-0000-0000-000000000001',
  'math', 'Mathématiques', 1);
SELECT public.publier_programme_national('a8400000-0000-0000-0000-000000000001');

SELECT pg_temp.sur(:'parent');
SELECT is((SELECT code || '/' || coalesce(coefficient::text, 'aucun') FROM public.programmes_matieres
            WHERE id = 'a8500000-0000-0000-0000-000000000001'), 'MATH/aucun',
  'matière publiée, sans coefficient (chaque école fixe les siens)');

-- Une question de la banque sur cette matière.
RESET ROLE;
INSERT INTO public.questions (id, matiere_id, statut, version_travail)
VALUES ('a8600000-0000-0000-0000-000000000001', 'a8500000-0000-0000-0000-000000000001', 'brouillon', 1);
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'contenu');
SELECT throws_ok($$ SELECT public.supprimer_element_referentiel('matiere', 'a8500000-0000-0000-0000-000000000001') $$,
  '22023', 'QUESTIONS_EXISTANTES', 'une matière qui a des questions ne se supprime pas');

SELECT * FROM finish();
ROLLBACK;
