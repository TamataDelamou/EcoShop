-- ============================================================================
-- EcoShop — Test RLS 85 : annonces de l'école (REG-19 lot 1, migration 1558)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

-- Compte avec numéro de téléphone (SMS) ou adresse.
CREATE OR REPLACE FUNCTION pg_temp.compte(p_ident text, p_role text)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  IF p_ident LIKE '%@%' THEN
    INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_ident, now());
  ELSE
    INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (v_id, p_ident, now());
  END IF;
  UPDATE public.profiles SET role_racine = p_role::public.role_racine, prenom = 'Test', nom = 'Compte' WHERE id = v_id;
  RETURN v_id;
END $$;

SELECT plan(37);

-- Référentiel minimal : deux niveaux.
INSERT INTO public.systemes_educatifs (code, nom) VALUES ('francophone_cfa', 'Francophone (CFA)') ON CONFLICT (code) DO NOTHING;
INSERT INTO public.pays_pedagogiques (code_iso, nom, type_systeme, langue_enseignement_principale, statut_deploiement)
VALUES ('Z5', 'Pays Test 85', 'francophone_cfa', 'français', 'deploye') ON CONFLICT (code_iso) DO NOTHING;
INSERT INTO public.cycles_educatifs (pays_code, code, nom, ordre, duree_annees, isced_min, isced_max, statut)
VALUES ('Z5', 'prim85', 'Primaire', 1, 6, 1, 1, 'publie');
INSERT INTO public.niveaux_educatifs (cycle_id, pays_code, code, nom, grade_level_normalise, isced, ordre, statut)
SELECT c.id, 'Z5', v.code, v.nom, v.g, 1, v.g, 'publie'
FROM (VALUES ('CM1_85', 'CM1', 5), ('CM2_85', 'CM2', 6)) AS v(code, nom, g)
JOIN public.cycles_educatifs c ON c.pays_code = 'Z5' AND c.code = 'prim85';
SELECT id AS n_cm1 FROM public.niveaux_educatifs WHERE code = 'CM1_85' \gset
SELECT id AS n_cm2 FROM public.niveaux_educatifs WHERE code = 'CM2_85' \gset

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('85000000-0000-0000-0000-00000000000a', 'École A', 'ecole-a-85', 'GNF'),
  ('85000000-0000-0000-0000-00000000000b', 'École B', 'ecole-b-85', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('85000000-0000-0000-0000-0000000000a1', '85000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true),
  ('85000000-0000-0000-0000-0000000000b1', '85000000-0000-0000-0000-00000000000b', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, niveau_id, code, nom) VALUES
  ('85000000-0000-0000-0000-0000000000c1', '85000000-0000-0000-0000-00000000000a', '85000000-0000-0000-0000-0000000000a1', :'n_cm1', 'CM1', 'CM1'),
  ('85000000-0000-0000-0000-0000000000c2', '85000000-0000-0000-0000-00000000000a', '85000000-0000-0000-0000-0000000000a1', :'n_cm2', 'CM2', 'CM2'),
  ('85000000-0000-0000-0000-0000000000c3', '85000000-0000-0000-0000-00000000000a', '85000000-0000-0000-0000-0000000000a1', :'n_cm2', 'CM2B', 'CM2 B (vide)'),
  ('85000000-0000-0000-0000-0000000000cb', '85000000-0000-0000-0000-00000000000b', '85000000-0000-0000-0000-0000000000b1', :'n_cm1', 'CM1', 'CM1');

SELECT pg_temp.compte('dir.a@exemple.org', 'direction') AS dir_a \gset
SELECT pg_temp.compte('dir.b@exemple.org', 'direction') AS dir_b \gset
SELECT pg_temp.compte('prof.a@exemple.org', 'enseignant') AS prof_a \gset
SELECT pg_temp.compte('224620850001', 'parent') AS p1 \gset
SELECT pg_temp.compte('224620850002', 'parent') AS p2 \gset
SELECT pg_temp.compte('attente@exemple.org', 'parent') AS p_attente \gset
SELECT pg_temp.compte('inconnu@exemple.org', 'parent') AS p_x \gset
SELECT pg_temp.compte('parent.b@exemple.org', 'parent') AS p_b \gset
SELECT pg_temp.compte('eleve1@exemple.org', 'eleve') AS el1 \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_a', '85000000-0000-0000-0000-00000000000a', 'direction'),
  (:'dir_b', '85000000-0000-0000-0000-00000000000b', 'direction'),
  (:'prof_a', '85000000-0000-0000-0000-00000000000a', 'enseignant');

INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id) VALUES
  ('85000000-0000-0000-0000-0000000000e1', '85000000-0000-0000-0000-00000000000a', 'A85-1', 'BAH', 'Awa', '2015-01-01', :'el1'),
  ('85000000-0000-0000-0000-0000000000e2', '85000000-0000-0000-0000-00000000000a', 'A85-2', 'DIALLO', 'Ousmane', '2014-01-01', NULL),
  ('85000000-0000-0000-0000-0000000000eb', '85000000-0000-0000-0000-00000000000b', 'B85-1', 'SOW', 'Binta', '2015-01-01', NULL);
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('85000000-0000-0000-0000-00000000000a', '85000000-0000-0000-0000-0000000000e1', '85000000-0000-0000-0000-0000000000c1', '85000000-0000-0000-0000-0000000000a1'),
  ('85000000-0000-0000-0000-00000000000a', '85000000-0000-0000-0000-0000000000e2', '85000000-0000-0000-0000-0000000000c2', '85000000-0000-0000-0000-0000000000a1'),
  ('85000000-0000-0000-0000-00000000000b', '85000000-0000-0000-0000-0000000000eb', '85000000-0000-0000-0000-0000000000cb', '85000000-0000-0000-0000-0000000000b1');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise) VALUES
  ('85000000-0000-0000-0000-00000000000a', :'p1', '85000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true),
  ('85000000-0000-0000-0000-00000000000a', :'p2', '85000000-0000-0000-0000-0000000000e2', 'parent', 'confirmee', true),
  ('85000000-0000-0000-0000-00000000000a', :'p_attente', '85000000-0000-0000-0000-0000000000e1', 'parent', 'en_attente', true),
  ('85000000-0000-0000-0000-00000000000b', :'p_b', '85000000-0000-0000-0000-0000000000eb', 'parent', 'confirmee', true);

-- ---------------------------------------------------------------------------
-- 1. Publication : direction de l'école seulement
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'p1');
SELECT throws_ok($$ SELECT public.publier_annonce(gen_random_uuid(), '85000000-0000-0000-0000-00000000000a', 'ecole', NULL, 'Réunion', 'Réunion des parents samedi.') $$,
  '42501', 'PERMISSION_REFUSEE', 'un parent ne publie pas');
SELECT pg_temp.en_tant_que(:'prof_a');
SELECT throws_ok($$ SELECT public.publier_annonce(gen_random_uuid(), '85000000-0000-0000-0000-00000000000a', 'ecole', NULL, 'Réunion', 'Réunion des parents samedi.') $$,
  '42501', 'PERMISSION_REFUSEE', 'un enseignant ne publie pas d''annonce');
SELECT pg_temp.en_tant_que(:'dir_b');
SELECT throws_ok($$ SELECT public.publier_annonce(gen_random_uuid(), '85000000-0000-0000-0000-00000000000a', 'ecole', NULL, 'Réunion', 'Réunion des parents samedi.') $$,
  '42501', 'PERMISSION_REFUSEE', 'une autre école ne publie pas pour l''école A');
SELECT throws_ok($$ INSERT INTO public.annonces_ecole (id, etablissement_id, portee, titre, corps, publiee_par)
  VALUES (gen_random_uuid(), '85000000-0000-0000-0000-00000000000a', 'ecole', 'Faux', 'Fausse annonce', auth.uid()) $$,
  '42501', NULL, 'aucune écriture directe');

SELECT pg_temp.en_tant_que(:'dir_a');
SELECT public.publier_annonce('85000000-0000-0000-0000-0000000000f1', '85000000-0000-0000-0000-00000000000a', 'ecole', NULL,
  'Réunion des parents', 'Réunion samedi à 9 h dans la cour.', true) AS r1 \gset
SELECT is((:'r1'::jsonb ->> 'familles')::int, 2, 'école : deux familles (deux élèves inscrits)');
SELECT is((:'r1'::jsonb ->> 'notifications')::int, 3, 'école : parents confirmés et compte élève prévenus (3)');
SELECT is((public.publier_annonce('85000000-0000-0000-0000-0000000000f1', '85000000-0000-0000-0000-00000000000a', 'ecole', NULL,
  'Réunion des parents', 'Réunion samedi à 9 h dans la cour.', true) ->> 'deja_recue')::boolean, true,
  'renvoi après une coupure : reconnu, rien ne repart');
SELECT public.publier_annonce('85000000-0000-0000-0000-0000000000f2', '85000000-0000-0000-0000-00000000000a', 'classe',
  '85000000-0000-0000-0000-0000000000c1', 'Sortie CM1', 'Sortie au musée jeudi.') AS r2 \gset
SELECT is((:'r2'::jsonb ->> 'familles')::int, 1, 'classe CM1 : une famille');
SELECT public.publier_annonce('85000000-0000-0000-0000-0000000000f3', '85000000-0000-0000-0000-00000000000a', 'niveau',
  :'n_cm2', 'Examen CM2', 'Examen blanc lundi.') AS r3 \gset
SELECT is((:'r3'::jsonb ->> 'familles')::int, 1, 'niveau CM2 : une famille');
SELECT throws_ok($$ SELECT public.publier_annonce(gen_random_uuid(), '85000000-0000-0000-0000-00000000000a', 'classe',
  '85000000-0000-0000-0000-0000000000c3', 'Classe vide', 'Personne ne lira.') $$, '22023', 'AUCUN_DESTINATAIRE',
  'classe sans élève : refusé');
SELECT throws_ok($$ SELECT public.publier_annonce(gen_random_uuid(), '85000000-0000-0000-0000-00000000000a', 'classe',
  '85000000-0000-0000-0000-0000000000cb', 'Autre école', 'Classe de l''école B.') $$, '22023', 'PORTEE_INVALIDE',
  'classe d''une autre école : refusé');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications WHERE type = 'annonce_ecole'), 6,
  'push : 3 (école) + 2 (CM1 : parent et élève) + 1 (CM2), aucun en double au renvoi');

-- ---------------------------------------------------------------------------
-- 2. Qui lit
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'p1');
SELECT is(jsonb_array_length(public.mes_annonces()), 2, 'parent CM1 : école et classe CM1');
SELECT is((SELECT count(*)::int FROM public.annonces_ecole), 2, 'lecture directe : ses deux annonces seulement (RLS)');
SELECT pg_temp.en_tant_que(:'el1');
SELECT is(jsonb_array_length(public.mes_annonces()), 2, 'élève concerné : les mêmes annonces');
SELECT pg_temp.en_tant_que(:'p2');
SELECT is(jsonb_array_length(public.mes_annonces()), 2, 'parent CM2 : école et niveau CM2, pas la sortie CM1');
SELECT pg_temp.en_tant_que(:'p_attente');
SELECT is(jsonb_array_length(public.mes_annonces()), 0, 'parent en attente de l''école : rien');
SELECT pg_temp.en_tant_que(:'p_x');
SELECT is(jsonb_array_length(public.mes_annonces()), 0, 'parent non lié : rien');
SELECT is_empty($$ SELECT id FROM public.annonces_ecole $$, 'parent non lié : table illisible');
SELECT throws_ok($$ SELECT public.marquer_annonce_lue('85000000-0000-0000-0000-0000000000f1') $$, '42501', 'PERMISSION_REFUSEE',
  'parent non lié : ne confirme pas de lecture');
SELECT pg_temp.en_tant_que(:'p_b');
SELECT is(jsonb_array_length(public.mes_annonces()), 0, 'parent de l''école B : rien de l''école A');
SELECT pg_temp.en_tant_que(:'dir_b');
SELECT throws_ok($$ SELECT public.annonces_etablissement('85000000-0000-0000-0000-00000000000a') $$, '42501', 'PERMISSION_REFUSEE',
  'direction B : ne voit pas les annonces de l''école A');
SELECT is_empty($$ SELECT annonce_id FROM public.annonces_destinataires $$, 'direction B : destinataires illisibles');

-- ---------------------------------------------------------------------------
-- 3. Lectures : combien de familles ont lu
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'p1');
SELECT public.marquer_annonce_lue('85000000-0000-0000-0000-0000000000f1');
SELECT pg_temp.en_tant_que(:'el1');
SELECT public.marquer_annonce_lue('85000000-0000-0000-0000-0000000000f1');
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT is((SELECT (a ->> 'familles_lues')::int FROM jsonb_array_elements(public.annonces_etablissement('85000000-0000-0000-0000-00000000000a')) a
           WHERE a ->> 'id' = '85000000-0000-0000-0000-0000000000f1'), 1, 'parent et élève d''une même famille : une famille');
SELECT pg_temp.en_tant_que(:'p2');
SELECT public.marquer_annonce_lue('85000000-0000-0000-0000-0000000000f1');
SELECT public.marquer_annonce_lue('85000000-0000-0000-0000-0000000000f1');
SELECT ok((SELECT (a ->> 'lue')::boolean FROM jsonb_array_elements(public.mes_annonces()) a
           WHERE a ->> 'id' = '85000000-0000-0000-0000-0000000000f1'), 'lecture confirmée (une seule fois)');
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT is((SELECT (a ->> 'familles_lues')::int || '/' || (a ->> 'familles') FROM jsonb_array_elements(public.annonces_etablissement('85000000-0000-0000-0000-00000000000a')) a
           WHERE a ->> 'id' = '85000000-0000-0000-0000-0000000000f1'), '2/2', 'direction : 2 familles sur 2 ont lu');

-- ---------------------------------------------------------------------------
-- 4. Modération : masquer, journalisé
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'p1');
SELECT throws_ok($$ SELECT public.masquer_annonce('85000000-0000-0000-0000-0000000000f2', 'Erreur de date') $$, '42501', 'PERMISSION_REFUSEE',
  'un parent ne masque pas');
SELECT pg_temp.en_tant_que(:'dir_b');
SELECT throws_ok($$ SELECT public.masquer_annonce('85000000-0000-0000-0000-0000000000f2', 'Erreur de date') $$, '42501', 'PERMISSION_REFUSEE',
  'une autre école ne masque pas');
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT throws_ok($$ SELECT public.masquer_annonce('85000000-0000-0000-0000-0000000000f2', '') $$, '22023', 'MOTIF_REQUIS',
  'motif obligatoire');
SELECT lives_ok($$ SELECT public.masquer_annonce('85000000-0000-0000-0000-0000000000f2', 'Erreur de date') $$, 'direction : masque');
SELECT ok((SELECT a ->> 'masquee_le' IS NOT NULL FROM jsonb_array_elements(public.annonces_etablissement('85000000-0000-0000-0000-00000000000a')) a
           WHERE a ->> 'id' = '85000000-0000-0000-0000-0000000000f2'), 'direction : toujours visible, marquée masquée (jamais supprimée)');
SELECT is((SELECT count(*)::int FROM public.journal_audit WHERE entite = 'annonce'
           AND entite_id = '85000000-0000-0000-0000-0000000000f2' AND auteur_id = :'dir_a'
           AND nouvelle_valeur ->> 'motif' = 'Erreur de date'), 1, 'journal d''audit : qui, quand, motif (visible par la direction)');
SELECT pg_temp.en_tant_que(:'p1');
SELECT is(jsonb_array_length(public.mes_annonces()), 1, 'masquée : disparaît pour la famille');
SELECT throws_ok($$ SELECT public.marquer_annonce_lue('85000000-0000-0000-0000-0000000000f2') $$, '42501', 'PERMISSION_REFUSEE',
  'masquée : plus de confirmation de lecture');
SELECT is_empty($$ SELECT id FROM public.journal_audit WHERE entite = 'annonce' $$, 'journal illisible pour un parent');

-- ---------------------------------------------------------------------------
-- 5. SMS : seulement si l'école a des crédits
-- ---------------------------------------------------------------------------
RESET ROLE;
INSERT INTO public.credits_sms (etablissement_id, solde) VALUES ('85000000-0000-0000-0000-00000000000a', 1)
ON CONFLICT (etablissement_id) DO UPDATE SET solde = 1;
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT public.publier_annonce('85000000-0000-0000-0000-0000000000f4', '85000000-0000-0000-0000-00000000000a', 'ecole', NULL,
  'École fermée', 'École fermée demain.', true, true) AS r4 \gset
SELECT is((:'r4'::jsonb ->> 'sms')::int || '+' || (:'r4'::jsonb ->> 'sms_non_envoyes'), '1+1',
  'un crédit : un SMS parti, le second non envoyé (parents seulement)');
RESET ROLE;
SELECT is((SELECT solde FROM public.credits_sms WHERE etablissement_id = '85000000-0000-0000-0000-00000000000a'), 0, 'crédit consommé');

SELECT * FROM finish();
ROLLBACK;
