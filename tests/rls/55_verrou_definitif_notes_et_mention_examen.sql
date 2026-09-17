-- ============================================================================
-- EcoShop — Test RLS 55 : verrou définitif des notes après proclamation +
-- mention admis(e)/recalé(e) pour les classes d'examen (cahier §12.3, §12.4,
-- §7.3 ; migration 20260906001522).
--
-- Couvre : classe_est_examen() (héritage niveau, coalesce sur niveau_id
-- null) ; definir_mention_finale() réservée à la Direction, refusée sur une
-- classe non-examen ; proclamer_classe() réservée à la Direction, bloquée
-- tant qu'une mention manque (classe d'examen), idempotence refusée
-- (déjà proclamée) ; verrou TOTAL après proclamation -- y compris pour la
-- Direction elle-même, qui pouvait pourtant écrire juste avant (mention,
-- notes via peut_saisir_notes, régénération de bulletins) ; isolation
-- inter-établissement réelle sur la proclamation (pas seulement un tiers,
-- une VRAIE direction d'un AUTRE établissement) ; visibilité de
-- proclamations_classes (personnel + admin_gsg, jamais un étranger).
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

SELECT plan(22);

-- ---------------------------------------------------------------------------
-- Référentiel pédagogique auto-contenu (pas de dépendance au seed) : un
-- niveau "examen" et un niveau "normal" sous le même pays/cycle test.
-- ---------------------------------------------------------------------------
INSERT INTO public.systemes_educatifs (code, nom) VALUES ('systeme_test_55', 'Système test 55') ON CONFLICT DO NOTHING;
INSERT INTO public.pays_pedagogiques (code_iso, nom, type_systeme, langue_enseignement_principale, statut_deploiement)
VALUES ('Q5', 'Pays Test 55', 'systeme_test_55', 'fr', 'deploye');
INSERT INTO public.cycles_educatifs (pays_code, code, nom, ordre, isced_min, isced_max, statut)
VALUES ('Q5', 'CYCLE55', 'Cycle Test 55', 1, 2, 3, 'publie') RETURNING id AS cycle_id \gset
INSERT INTO public.niveaux_educatifs (cycle_id, pays_code, code, nom, grade_level_normalise, isced, ordre, statut, est_niveau_examinateur)
VALUES (:'cycle_id'::uuid, 'Q5', 'NIVEXAMEN', 'Niveau Examen Test', 12, 3, 1, 'publie', true) RETURNING id AS niveau_examen_id \gset
INSERT INTO public.niveaux_educatifs (cycle_id, pays_code, code, nom, grade_level_normalise, isced, ordre, statut, est_niveau_examinateur)
VALUES (:'cycle_id'::uuid, 'Q5', 'NIVNORMAL', 'Niveau Normal Test', 6, 2, 2, 'publie', false) RETURNING id AS niveau_normal_id \gset

-- ---------------------------------------------------------------------------
-- Établissement A (cible) + établissement B (isolation, direction distincte).
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Verrou 55', 'ecole-verrou-55') RETURNING id AS etab_id \gset
INSERT INTO public.etablissements (nom, slug) VALUES ('École Verrou 55 B (isolation)', 'ecole-verrou-55-b') RETURNING id AS etab_b_id \gset

INSERT INTO public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
VALUES (:'etab_id'::uuid, '2026-2027', '2026-10-01', '2027-06-30', true) RETURNING id AS annee_id \gset

INSERT INTO public.classes (etablissement_id, annee_scolaire_id, niveau_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'niveau_examen_id'::uuid, 'TermA', 'Terminale A') RETURNING id AS classe_examen_id \gset
INSERT INTO public.classes (etablissement_id, annee_scolaire_id, niveau_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'niveau_normal_id'::uuid, '6A', '6e A') RETURNING id AS classe_normale_id \gset
INSERT INTO public.classes (etablissement_id, annee_scolaire_id, niveau_id, code, nom)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, null, 'SN', 'Sans niveau') RETURNING id AS classe_sans_niveau_id \gset

SELECT pg_temp.creer_compte('224620001001', 'eleve')      AS eleve_e1_id     \gset
SELECT pg_temp.creer_compte('224620001002', 'eleve')      AS eleve_e2_id     \gset
SELECT pg_temp.creer_compte('224620001003', 'eleve')      AS eleve_n1_id     \gset
SELECT pg_temp.creer_compte('224620001004', 'enseignant') AS enseignant_id   \gset
SELECT pg_temp.creer_compte('224620001005', 'direction')  AS direction_a_id  \gset
SELECT pg_temp.creer_compte('224620001006', 'direction')  AS direction_b_id  \gset
SELECT pg_temp.creer_compte('224620001007', 'admin_gsg')  AS admin_gsg_id    \gset
SELECT pg_temp.creer_compte('224620001008', 'eleve')      AS etranger_id     \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'V55-E1', 'BAH', 'Alpha', '2008-01-01', :'eleve_e1_id'::uuid, now()) RETURNING id AS fiche_e1_id \gset
INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'V55-E2', 'SOW', 'Mamadou', '2008-02-01', :'eleve_e2_id'::uuid, now()) RETURNING id AS fiche_e2_id \gset
INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'V55-N1', 'DIA', 'Kadiatou', '2014-01-01', :'eleve_n1_id'::uuid, now()) RETURNING id AS fiche_n1_id \gset

INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES
  (:'etab_id'::uuid, :'fiche_e1_id'::uuid, :'classe_examen_id'::uuid, :'annee_id'::uuid, 'active'),
  (:'etab_id'::uuid, :'fiche_e2_id'::uuid, :'classe_examen_id'::uuid, :'annee_id'::uuid, 'active'),
  (:'etab_id'::uuid, :'fiche_n1_id'::uuid, :'classe_normale_id'::uuid, :'annee_id'::uuid, 'active');
SELECT id AS inscription_e1_id FROM public.inscriptions WHERE fiche_eleve_id = :'fiche_e1_id'::uuid \gset
SELECT id AS inscription_e2_id FROM public.inscriptions WHERE fiche_eleve_id = :'fiche_e2_id'::uuid \gset
SELECT id AS inscription_n1_id FROM public.inscriptions WHERE fiche_eleve_id = :'fiche_n1_id'::uuid \gset

-- direction_a : membre "direction" (est_direction) + poste porteur des
-- permissions note/bulletin (pour driver aussi les tests 15-17 avec le même
-- compte, réaliste : un poste Direction porte usuellement ces droits).
INSERT INTO public.postes (etablissement_id, code, nom) VALUES (:'etab_id'::uuid, 'DIRECTION', 'Direction') RETURNING id AS poste_direction_id \gset
INSERT INTO public.poste_permissions (poste_id, permission_code)
VALUES (:'poste_direction_id'::uuid, 'scolarite.note.gerer'), (:'poste_direction_id'::uuid, 'scolarite.bulletin.gerer');
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement, poste_id)
VALUES (:'direction_a_id'::uuid, :'etab_id'::uuid, 'direction', :'poste_direction_id'::uuid);
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'direction_b_id'::uuid, :'etab_b_id'::uuid, 'direction');
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'enseignant_id'::uuid, :'etab_id'::uuid, 'enseignant');

-- Une évaluation (brouillon, non clôturée) sur la classe d'examen, portée par
-- l'enseignant -- pour prouver que peut_saisir_notes() se verrouille aussi
-- pour SON auteur légitime après proclamation, pas seulement pour un tiers.
INSERT INTO public.evaluations
  (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, type, libelle, statut)
VALUES (:'etab_id'::uuid, :'annee_id'::uuid, :'classe_examen_id'::uuid, :'enseignant_id'::uuid, 'composition', 'Bac blanc', 'brouillon')
RETURNING id AS eval_id \gset

-- ===========================================================================
-- 1-3. classe_est_examen() -- héritage du niveau, coalesce sur niveau_id null.
-- ===========================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);

SELECT is(public.classe_est_examen(:'classe_examen_id'::uuid), true, 'classe_est_examen : classe TermA (niveau examen) -> true');
SELECT is(public.classe_est_examen(:'classe_normale_id'::uuid), false, 'classe_est_examen : classe 6A (niveau normal) -> false');
SELECT is(public.classe_est_examen(:'classe_sans_niveau_id'::uuid), false, 'classe_est_examen : classe sans niveau (niveau_id null) -> false (coalesce)');

-- ===========================================================================
-- 4-6. definir_mention_finale : réservée Direction, refusée hors classe
-- d'examen, succès légitime en classe d'examen.
-- ===========================================================================
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'enseignant_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.definir_mention_finale('%s', 'admis') $$, :'inscription_e1_id'),
  '42501', 'PERMISSION_REFUSEE',
  'definir_mention_finale : refusée à l''enseignant (poste non-Direction, même établissement)'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.definir_mention_finale('%s', 'admis') $$, :'inscription_n1_id'),
  '23514', 'CLASSE_NON_EXAMEN',
  'definir_mention_finale : refusée par la Direction elle-même sur une classe NON examen (6A)'
);
SELECT lives_ok(
  format($$ SELECT public.definir_mention_finale('%s', 'admis') $$, :'inscription_e1_id'),
  'definir_mention_finale : succès Direction sur fiche_e1 (classe d''examen) -- mention "admis"'
);

-- ===========================================================================
-- 7-9. proclamer_classe : réservée Direction, bloquée tant qu'une mention
-- manque (fiche_e2), succès une fois complétée.
-- ===========================================================================
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'enseignant_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.proclamer_classe('%s', '%s') $$, :'classe_examen_id', :'annee_id'),
  '42501', 'PERMISSION_REFUSEE',
  'proclamer_classe : refusée à l''enseignant (poste non-Direction)'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.proclamer_classe('%s', '%s') $$, :'classe_examen_id', :'annee_id'),
  '23514', 'MENTION_MANQUANTE',
  'proclamer_classe : refusée -- fiche_e2 n''a pas encore de mention finale'
);

SELECT lives_ok(
  format($$ SELECT public.definir_mention_finale('%s', 'recale') $$, :'inscription_e2_id'),
  'definir_mention_finale : succès Direction sur fiche_e2 -- mention "recale" (complète la classe)'
);
SELECT lives_ok(
  format($$ SELECT public.proclamer_classe('%s', '%s') $$, :'classe_examen_id', :'annee_id'),
  'proclamer_classe : succès Direction -- toutes les mentions sont maintenant présentes'
);

-- ===========================================================================
-- 10-13. Idempotence, isolation par classe, isolation inter-établissement
-- (une VRAIE direction d'un AUTRE établissement, pas un tiers générique).
-- ===========================================================================
SELECT throws_ok(
  format($$ SELECT public.proclamer_classe('%s', '%s') $$, :'classe_examen_id', :'annee_id'),
  '42501', 'CLASSE_DEJA_PROCLAMEE',
  'proclamer_classe : refusée -- déjà proclamée (idempotence refusée, pas un no-op silencieux)'
);
SELECT is(public.classe_est_proclamee(:'classe_examen_id'::uuid, :'annee_id'::uuid), true, 'classe_est_proclamee : TermA -> true après proclamation');
SELECT is(public.classe_est_proclamee(:'classe_normale_id'::uuid, :'annee_id'::uuid), false, 'classe_est_proclamee : 6A -> false (isolation par classe, pas par établissement)');

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_b_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.proclamer_classe('%s', '%s') $$, :'classe_normale_id', :'annee_id'),
  '42501', 'PERMISSION_REFUSEE',
  'proclamer_classe : la direction d''un AUTRE établissement (B) est refusée sur une classe de l''établissement A'
);

-- ===========================================================================
-- 14. Verrou TOTAL : la Direction elle-même, qui pouvait écrire juste avant,
-- est bloquée après proclamation -- pas d'exception, y compris pour elle.
-- ===========================================================================
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.definir_mention_finale('%s', 'recale') $$, :'inscription_e1_id'),
  '42501', 'CLASSE_DEJA_PROCLAMEE',
  'definir_mention_finale : la Direction ne peut plus changer une mention après proclamation -- verrou total'
);

-- ===========================================================================
-- 15-16. peut_saisir_notes() se verrouille aussi, y compris pour l'auteur
-- légitime de l'évaluation (pas seulement un tiers) -- + refus RLS réel sur
-- un INSERT direct dans notes.
-- ===========================================================================
SELECT is(
  public.peut_saisir_notes(:'eval_id'::uuid),
  false,
  'peut_saisir_notes : classe proclamée -> false pour la Direction (a_permission scolarite.note.gerer)'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'enseignant_id', 'role', 'authenticated')::text, true);
SELECT is(
  public.peut_saisir_notes(:'eval_id'::uuid),
  false,
  'peut_saisir_notes : classe proclamée -> false même pour l''enseignant AUTEUR de l''évaluation'
);
SELECT throws_ok(
  format(
    $$ insert into public.notes (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par) values ('%s', '%s', '%s', 15, '%s') $$,
    :'etab_id', :'eval_id', :'fiche_e1_id', :'enseignant_id'
  ),
  '42501', NULL,
  'notes (INSERT direct) : refusé par la RLS pour l''auteur légitime -- classe proclamée, verrou total'
);

-- ===========================================================================
-- 17. generer_bulletins_classe() refuse aussi après proclamation.
-- ===========================================================================
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT * FROM public.generer_bulletins_classe('%s', '%s', null, 'trimestriel') $$, :'classe_examen_id', :'annee_id'),
  '42501', 'CLASSE_DEJA_PROCLAMEE',
  'generer_bulletins_classe : refusée après proclamation, même pour la Direction titulaire du droit bulletin.gerer'
);

-- ===========================================================================
-- 18-20. Visibilité de proclamations_classes : personnel + admin_gsg, jamais
-- un étranger sans lien avec l'établissement.
-- ===========================================================================
SELECT is(
  (SELECT count(*) FROM public.proclamations_classes WHERE classe_id = :'classe_examen_id'::uuid),
  1::bigint,
  'proclamations_classes : la Direction de l''établissement voit la proclamation'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.proclamations_classes WHERE classe_id = :'classe_examen_id'::uuid),
  0::bigint,
  'proclamations_classes : un étranger sans lien avec l''établissement ne voit rien'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.proclamations_classes WHERE classe_id = :'classe_examen_id'::uuid),
  1::bigint,
  'proclamations_classes : admin_gsg voit la proclamation (visibilité seule -- jamais de droit de la défaire)'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
