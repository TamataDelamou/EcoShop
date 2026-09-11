-- ============================================================================
-- EcoShop — Test RLS 41 : M16 — infrastructure Edge Functions IA
-- (déterminer_role_ia, ai_conversations/ai_messages, preparer_analyse_
-- risque_echec, obtenir_detail_risque_echec_interne)
--
-- Ne re-teste PAS calculer_score_decrochage/materialiser_risque_reussite
-- (déjà couverts, tests 39/40) : vérifie le rôle IA réel (jamais celui du
-- client), l'isolation stricte par auteur (une conversation n'est JAMAIS
-- partagée, même entre deux comptes direction du même établissement), le
-- correctif de sécurité construit DÈS LA CONCEPTION (le client ne peut
-- jamais poser lui-même grounding=true/cible sur une conversation), la
-- portée correcte de l'agrégat groundé (établissement vs classe), la
-- ré-vérification systématique côté détail nominatif, et l'immutabilité
-- des deux tables.
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

SELECT plan(30);

-- ---------------------------------------------------------------------------
-- Tenant + année courante + 2 classes (+ 1 étranger, pour les tests de
-- cloisonnement)
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École IA M16', 'ecole-ia-m16') RETURNING id AS etab_id \gset
INSERT INTO public.etablissements (nom, slug) VALUES ('École Étrangère M16', 'ecole-etrangere-ia-m16') RETURNING id AS etab_etranger_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_etranger_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_etranger_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '6A', '6e A') RETURNING id AS classe_a_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, '6B', '6e B') RETURNING id AS classe_b_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, code, nom)
VALUES (:'etab_etranger_id'::uuid, :'annee_etranger_id'::uuid, '6X', '6e X') RETURNING id AS classe_etrangere_id \gset

-- ---------------------------------------------------------------------------
-- Comptes
-- ---------------------------------------------------------------------------
-- eleve1 : classe A, à risque. eleve2 : classe A, sain. eleve3 : classe B,
-- à risque. etranger : aucun lien avec l'établissement.
SELECT pg_temp.creer_compte('224600002291', 'eleve')      AS eleve1_id \gset
SELECT pg_temp.creer_compte('224600002292', 'eleve')      AS eleve2_id \gset
SELECT pg_temp.creer_compte('224600002293', 'eleve')      AS eleve3_id \gset
SELECT pg_temp.creer_compte('224600002294', 'direction')  AS dir_id \gset
SELECT pg_temp.creer_compte('224600002295', 'direction')  AS dir2_id \gset
SELECT pg_temp.creer_compte('224600002296', 'enseignant') AS prof_id \gset
SELECT pg_temp.creer_compte('224600002297', 'eleve')      AS etranger_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'dir_id'::uuid, :'etab_id'::uuid, 'direction'),
  (:'dir2_id'::uuid, :'etab_id'::uuid, 'direction'),
  (:'prof_id'::uuid, :'etab_id'::uuid, 'enseignant');

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M16-IA-001', 'CAMARA', 'Alpha', '2011-02-01', :'eleve1_id'::uuid, now())
RETURNING id AS fiche1_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M16-IA-002', 'DIALLO', 'Beta', '2011-03-02', :'eleve2_id'::uuid, now())
RETURNING id AS fiche2_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M16-IA-003', 'BAH', 'Gamma', '2011-04-03', :'eleve3_id'::uuid, now())
RETURNING id AS fiche3_id \gset

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES
  (:'etab_id'::uuid, :'fiche1_id'::uuid, :'classe_a_id'::uuid, :'annee_id'::uuid, 'active'),
  (:'etab_id'::uuid, :'fiche2_id'::uuid, :'classe_a_id'::uuid, :'annee_id'::uuid, 'active'),
  (:'etab_id'::uuid, :'fiche3_id'::uuid, :'classe_b_id'::uuid, :'annee_id'::uuid, 'active');

-- ---------------------------------------------------------------------------
-- eleve1 (classe A) et eleve3 (classe B) à risque ; eleve2 (classe A) sain
-- — même fixture que tests 39/40 (absences/retards non justifiés vs note
-- publiée correcte).
-- ---------------------------------------------------------------------------
INSERT INTO public.presences (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, date_presence, type_seance, statut, justifie, saisi_par)
SELECT :'etab_id'::uuid, :'annee_id'::uuid, :'classe_a_id'::uuid, :'fiche1_id'::uuid,
       (date '2026-10-05' + n::int), 'demi_journee', 'absent', false, :'dir_id'::uuid
FROM generate_series(0, 2) AS n;
INSERT INTO public.retards (etablissement_id, fiche_eleve_id, annee_scolaire_id, date_retard, minutes_retard, justifie, saisi_par)
SELECT :'etab_id'::uuid, :'fiche1_id'::uuid, :'annee_id'::uuid, (date '2026-10-05' + n::int), 10, false, :'dir_id'::uuid
FROM generate_series(0, 9) AS n;

INSERT INTO public.presences (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, date_presence, type_seance, statut, justifie, saisi_par)
SELECT :'etab_id'::uuid, :'annee_id'::uuid, :'classe_b_id'::uuid, :'fiche3_id'::uuid,
       (date '2026-10-05' + n::int), 'demi_journee', 'absent', false, :'dir_id'::uuid
FROM generate_series(0, 2) AS n;
INSERT INTO public.retards (etablissement_id, fiche_eleve_id, annee_scolaire_id, date_retard, minutes_retard, justifie, saisi_par)
SELECT :'etab_id'::uuid, :'fiche3_id'::uuid, :'annee_id'::uuid, (date '2026-10-05' + n::int), 10, false, :'dir_id'::uuid
FROM generate_series(0, 9) AS n;

INSERT INTO public.presences (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, date_presence, type_seance, statut, justifie, saisi_par)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_a_id'::uuid, :'fiche2_id'::uuid, date '2026-10-05', 'demi_journee', 'present', false, :'dir_id'::uuid);

INSERT INTO public.evaluations (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, type, libelle, coefficient, bareme, statut, publie_le)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_a_id'::uuid, :'dir_id'::uuid, 'controle', 'Contrôle', 1, 20, 'publiee', now())
RETURNING id AS eval_id \gset
INSERT INTO public.notes (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par)
VALUES (:'etab_id'::uuid, :'eval_id'::uuid, :'fiche2_id'::uuid, 18, :'dir_id'::uuid);

-- ---------------------------------------------------------------------------
-- 1) determiner_role_ia — rôle réel par établissement, jamais celui envoyé
--    par le client.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);

SELECT is(public.determiner_role_ia(:'etab_id'::uuid)::text, 'direction', 'direction : rôle IA réel = direction');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);
SELECT is(public.determiner_role_ia(:'etab_id'::uuid)::text, 'enseignant', 'enseignant : rôle IA réel = enseignant');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);
SELECT is(public.determiner_role_ia(:'etab_id'::uuid)::text, 'eleve', 'élève : rôle IA réel = eleve');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT is(public.determiner_role_ia(:'etab_id'::uuid), NULL, 'étranger : aucun rôle IA (chat fermé, même comportement que PROMPTS[role] absent côté source)');

-- ---------------------------------------------------------------------------
-- 2) ai_conversations — écriture cliente restreinte au « libre », jamais
--    de grounding/cible posé directement (correctif de sécurité dès la
--    conception).
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);

INSERT INTO public.ai_conversations (etablissement_id, profile_id)
VALUES (:'etab_id'::uuid, :'dir_id'::uuid)
RETURNING id AS conv_libre_dir_id \gset
SELECT ok(:'conv_libre_dir_id' IS NOT NULL,
  'non-régression : INSERT...RETURNING fonctionne sur ai_conversations (policy select non auto-référentielle)');

-- ★ Utilise dir_id/etab_id RÉELS (rôle IA valide) — sinon le garde-fou
-- tenant (PROFILE_SANS_ROLE_IA, 23514) masquerait le rejet RLS visé ici.
SELECT throws_ok(
  format($$ INSERT INTO public.ai_conversations (etablissement_id, profile_id, grounding, cible_type)
     VALUES ('%s', '%s', true, 'etablissement') $$, :'etab_id', :'dir_id'),
  '42501',
  NULL
);

SELECT throws_ok(
  format($$ INSERT INTO public.ai_conversations (etablissement_id, profile_id, type, cible_type, cible_id)
     VALUES ('%s', '%s', 'risque_echec', 'etablissement', NULL) $$, :'etab_id', :'dir_id'),
  '42501',
  NULL
);

-- Isolation stricte par auteur : dir2 crée sa PROPRE conversation libre,
-- ne voit jamais celle de dir_id (même établissement, même rôle direction).
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir2_id', 'role', 'authenticated')::text, true);
INSERT INTO public.ai_conversations (etablissement_id, profile_id) VALUES (:'etab_id'::uuid, :'dir2_id'::uuid);
SELECT is(
  (SELECT count(*)::int FROM public.ai_conversations WHERE profile_id = :'dir_id'::uuid),
  0,
  'dir2 ne voit AUCUNE conversation de dir_id, même établissement, même rôle direction'
);
SELECT is(
  (SELECT count(*)::int FROM public.ai_conversations WHERE profile_id = :'dir2_id'::uuid),
  1,
  'dir2 voit exactement sa propre conversation'
);

-- Immutabilité : ni update ni delete, même par l'auteur. ★ Aucune policy
-- update/delete définie ⇒ RLS ne « lève » rien, elle rend simplement 0
-- ligne visible pour la commande (comportement RLS standard : policy
-- absente = USING effectif « false », jamais une exception) — testé donc
-- par un rowcount à 0 et une valeur inchangée, pas par un throws_ok.
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
WITH tentative AS (
  UPDATE public.ai_conversations SET type = 'risque_echec' WHERE profile_id = auth.uid() RETURNING 1
)
SELECT is(
  (SELECT count(*)::int FROM tentative),
  0,
  'update ai_conversations : 0 ligne affectée (aucune policy update, immuable)'
);

WITH tentative AS (
  DELETE FROM public.ai_conversations WHERE profile_id = auth.uid() RETURNING 1
)
SELECT is(
  (SELECT count(*)::int FROM tentative),
  0,
  'delete ai_conversations : 0 ligne affectée (aucune policy delete, immuable)'
);

-- ---------------------------------------------------------------------------
-- 3) ai_messages — écriture/lecture scoping par conversation, immutable.
-- ---------------------------------------------------------------------------
INSERT INTO public.ai_messages (conversation_id, sender, content)
VALUES (:'conv_libre_dir_id'::uuid, 'user', 'Bonjour Directeur-Adviser')
RETURNING id AS msg_id \gset
SELECT ok(:'msg_id' IS NOT NULL,
  'non-régression : INSERT...RETURNING fonctionne sur ai_messages');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir2_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ INSERT INTO public.ai_messages (conversation_id, sender, content) VALUES ('%s', 'user', 'intrusion') $$, :'conv_libre_dir_id'),
  '42501',
  NULL
);
SELECT is(
  (SELECT count(*)::int FROM public.ai_messages WHERE conversation_id = :'conv_libre_dir_id'::uuid),
  0,
  'dir2 ne voit AUCUN message de la conversation de dir_id'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
WITH tentative AS (
  UPDATE public.ai_messages SET content = 'modifié'
    WHERE conversation_id IN (SELECT id FROM public.ai_conversations WHERE profile_id = auth.uid())
  RETURNING 1
)
SELECT is(
  (SELECT count(*)::int FROM tentative),
  0,
  'update ai_messages : 0 ligne affectée (aucune policy update, immuable)'
);

-- ---------------------------------------------------------------------------
-- 4) preparer_analyse_risque_echec — portée établissement vs classe, garde
--    directeur stricte, cibles invalides rejetées.
-- ---------------------------------------------------------------------------
SELECT (r->>'conversation_id')::uuid AS conv_etab_id,
       (r->>'effectif')::int AS effectif_etab,
       (r->>'eleves_a_risque')::int AS risque_etab
FROM (SELECT public.preparer_analyse_risque_echec(:'etab_id'::uuid, 'etablissement') AS r) s \gset

SELECT is(:'effectif_etab'::int, 3, 'établissement : effectif total = 3 (classe A + classe B)');
SELECT is(:'risque_etab'::int, 2, 'établissement : 2 élèves à risque (eleve1 + eleve3)');

SELECT (r->>'conversation_id')::uuid AS conv_classe_a_id,
       (r->>'effectif')::int AS effectif_classe_a,
       (r->>'eleves_a_risque')::int AS risque_classe_a
FROM (SELECT public.preparer_analyse_risque_echec(:'etab_id'::uuid, 'classe', :'classe_a_id'::uuid) AS r) s \gset

SELECT is(:'effectif_classe_a'::int, 2, 'classe A : effectif = 2 (eleve1 + eleve2, jamais eleve3 de la classe B)');
SELECT is(:'risque_classe_a'::int, 1, 'classe A : 1 seul élève à risque (eleve1) — la portée exclut bien la classe B');

SELECT (r->>'eleves_a_risque')::int AS risque_classe_b
FROM (SELECT public.preparer_analyse_risque_echec(:'etab_id'::uuid, 'classe', :'classe_b_id'::uuid) AS r) s \gset

SELECT is(:'risque_classe_b'::int, 1, 'classe B : 1 élève à risque (eleve3) — comptée séparément de la classe A');

-- Garde stricte : ni enseignant ni élève ne peuvent déclencher l'analyse,
-- même s'ils sont personnel/concernés par l'établissement.
SELECT set_config('request.jwt.claims', json_build_object('sub', :'prof_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.preparer_analyse_risque_echec('%s', 'etablissement') $$, :'etab_id'),
  '42501',
  NULL
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.preparer_analyse_risque_echec('%s', 'etablissement') $$, :'etab_id'),
  '42501',
  NULL
);

-- Cibles invalides.
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.preparer_analyse_risque_echec('%s', 'eleve') $$, :'etab_id'),
  '22023',
  NULL
);
SELECT throws_ok(
  format($$ SELECT public.preparer_analyse_risque_echec('%s', 'classe') $$, :'etab_id'),
  '22023',
  NULL
);
SELECT throws_ok(
  format($$ SELECT public.preparer_analyse_risque_echec('%s', 'classe', '%s') $$, :'etab_id', :'classe_etrangere_id'),
  '23514',
  NULL
);

-- ---------------------------------------------------------------------------
-- 5) obtenir_detail_risque_echec_interne — détail nominatif (couche 3) :
--    ré-vérifie propriété + grounding + type + rôle à CHAQUE appel.
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM public.obtenir_detail_risque_echec_interne(:'conv_etab_id'::uuid)),
  2,
  'détail nominatif (établissement) : exactement 2 élèves à risque renvoyés'
);

SELECT is(
  (SELECT array_agg(matricule ORDER BY matricule) FROM public.obtenir_detail_risque_echec_interne(:'conv_etab_id'::uuid)),
  ARRAY['M16-IA-001', 'M16-IA-003'],
  'détail nominatif : matricules exacts (eleve1 + eleve3), jamais eleve2 (sain)'
);

SELECT is(
  (SELECT count(*)::int FROM public.obtenir_detail_risque_echec_interne(:'conv_classe_a_id'::uuid)),
  1,
  'détail nominatif (classe A) : portée respectée, 1 seul élève'
);

-- dir2 n'est PAS propriétaire de la conversation de dir_id : refusé même
-- si dir2 est aussi direction du même établissement.
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir2_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.obtenir_detail_risque_echec_interne('%s') $$, :'conv_etab_id'),
  '42501',
  NULL
);

-- Une conversation libre (non groundée) n'expose jamais cet outil, même
-- pour son propre auteur.
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.obtenir_detail_risque_echec_interne('%s') $$, :'conv_libre_dir_id'),
  '42501',
  NULL
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;

