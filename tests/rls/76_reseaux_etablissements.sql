-- ============================================================================
-- EcoShop — Test RLS 76 : M19 réseaux d'établissements (migration 1549)
-- Demande validée par GSG, annuaire sans accents, invitation, tableau de
-- bord agrégé, circulaires, calendrier commun, retrait soumis à GSG,
-- dissolution confirmée par le nom.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.creer_compte(p_phone text, p_role text DEFAULT NULL, p_email text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public, auth, pg_catalog
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, phone, email) VALUES (v_id, p_phone, p_email);
  IF p_role IS NOT NULL THEN
    UPDATE public.profiles SET role_racine = p_role::public.role_racine WHERE id = v_id;
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

SELECT plan(37);

INSERT INTO public.systemes_educatifs (code, nom) VALUES ('francophone_cfa', 'Francophone CFA') ON CONFLICT DO NOTHING;
INSERT INTO public.pays_pedagogiques (code_iso, nom, type_systeme, langue_enseignement_principale, statut_deploiement)
VALUES ('GN', 'Guinée', 'francophone_cfa', 'fr', 'deploye') ON CONFLICT (code_iso) DO NOTHING;

INSERT INTO public.etablissements (id, nom, slug, ville, devise_code) VALUES
  ('76000000-0000-0000-0000-000000000001', 'École Bambino Emmaüs', 'bambino-76', 'Conakry', 'GNF'),
  ('76000000-0000-0000-0000-000000000002', 'Collège Évangélique de Kindia', 'kindia-76', 'Kindia', 'GNF'),
  ('76000000-0000-0000-0000-000000000003', 'École Hors Réseau', 'hors-76', 'Labé', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('76000000-0000-0000-0000-0000000000a1', '76000000-0000-0000-0000-000000000001', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('76000000-0000-0000-0000-0000000000c1', '76000000-0000-0000-0000-000000000001', '76000000-0000-0000-0000-0000000000a1', 'CP', 'CP A');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance) VALUES
  ('76000000-0000-0000-0000-0000000000e1', '76000000-0000-0000-0000-000000000001', 'B-1', 'SECRETNOM', 'Awa', '2019-01-01'),
  ('76000000-0000-0000-0000-0000000000e2', '76000000-0000-0000-0000-000000000001', 'B-2', 'CAMARA', 'Mory', '2019-02-01');
INSERT INTO public.inscriptions (id, etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('76000000-0000-0000-0000-0000000000f1', '76000000-0000-0000-0000-000000000001', '76000000-0000-0000-0000-0000000000e1', '76000000-0000-0000-0000-0000000000c1', '76000000-0000-0000-0000-0000000000a1'),
  ('76000000-0000-0000-0000-0000000000f2', '76000000-0000-0000-0000-000000000001', '76000000-0000-0000-0000-0000000000e2', '76000000-0000-0000-0000-0000000000c1', '76000000-0000-0000-0000-0000000000a1');
INSERT INTO public.frais_scolarite_config (etablissement_id, annee_scolaire_id, montant_annuel)
VALUES ('76000000-0000-0000-0000-000000000001', '76000000-0000-0000-0000-0000000000a1', 1000000);

SELECT pg_temp.creer_compte('224676000001', 'parent', 'fondateur@epn.org') AS fondateur \gset
SELECT pg_temp.creer_compte('224676000002', 'direction') AS dir1 \gset
SELECT pg_temp.creer_compte('224676000003', 'direction') AS dir2 \gset
SELECT pg_temp.creer_compte('224676000004', 'admin_gsg') AS admin \gset
SELECT pg_temp.creer_compte('224676000005', 'parent', 'adjoint@epn.org') AS adjoint \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir1', '76000000-0000-0000-0000-000000000001', 'direction'),
  (:'dir2', '76000000-0000-0000-0000-000000000002', 'direction');

SELECT pg_temp.en_tant_que(:'dir1');
INSERT INTO public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, montant, saisi_par)
VALUES ('76000000-0000-0000-0000-000000000001', '76000000-0000-0000-0000-0000000000e1', '76000000-0000-0000-0000-0000000000f1', 500000, :'dir1');
INSERT INTO public.presences (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, date_presence, statut, saisi_par)
SELECT '76000000-0000-0000-0000-000000000001', '76000000-0000-0000-0000-0000000000a1', '76000000-0000-0000-0000-0000000000c1',
       '76000000-0000-0000-0000-0000000000e1', current_date - g, s::public.statut_presence, :'dir1'
FROM (VALUES (1, 'present'), (2, 'present'), (3, 'retard'), (4, 'absent')) AS t(g, s);

-- ---------------------------------------------------------------------------
-- 1. Demande de création
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'fondateur');
SELECT is((public.soumettre_demande_reseau('76000000-0000-0000-0000-00000000d001', 'Réseau EPN', 'Église Protestante Nationale — Éducation',
  'confessionnel', 'gn', 'GNF', 'contact@epn.org', '+224 620 00 00 00', 'Conakry, Kaloum', 'Pasteur Diallo') ->> 'deja_recue')::boolean,
  false, 'demande de réseau enregistrée');
SELECT is((public.soumettre_demande_reseau('76000000-0000-0000-0000-00000000d001', 'Réseau EPN', 'Église Protestante Nationale — Éducation',
  'confessionnel', 'GN', 'GNF', 'contact@epn.org', '+224 620 00 00 00', 'Conakry, Kaloum', 'Pasteur Diallo') ->> 'deja_recue')::boolean,
  true, 'renvoi hors connexion : déjà reçue');
SELECT throws_ok($$ SELECT public.soumettre_demande_reseau('76000000-0000-0000-0000-00000000d002', 'Autre', 'Autre réseau',
  'autre', 'GN', 'GNF', 'x@y.org', '+224 620 00 00 01', 'Conakry', 'Moi') $$,
  '23505', 'DEMANDE_DEJA_EN_COURS', 'une seule demande en cours par compte');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications_sortantes WHERE modele IN ('demande_reseau_recue', 'demande_reseau_a_traiter')), 2,
  'courriels : accusé de réception et alerte GSG');

SET LOCAL ROLE authenticated;
SELECT throws_ok($$ SELECT public.traiter_demande_reseau('76000000-0000-0000-0000-00000000d001', true, null, true) $$,
  '42501', NULL, 'seul GSG valide une demande');
SELECT pg_temp.en_tant_que(:'admin');
SELECT throws_ok($$ SELECT public.traiter_demande_reseau('76000000-0000-0000-0000-00000000d001', true) $$,
  '23514', 'FRAIS_CREATION_NON_REGLES', 'frais de création exigés');
SELECT public.traiter_demande_reseau('76000000-0000-0000-0000-00000000d001', true, null, true) ->> 'reseau_id' AS reseau \gset
SELECT ok(:'reseau' IS NOT NULL, 'réseau créé à l''acceptation');
RESET ROLE;
SELECT is((SELECT role_racine::text FROM public.profiles WHERE id = :'fondateur'), 'parent', 'le rôle du compte n''est pas modifié');
SET LOCAL ROLE authenticated;

SELECT pg_temp.en_tant_que(:'fondateur');
SELECT is(public.role_reseau(:'reseau'), 'direction_generale', 'le demandeur devient Direction Générale');
SELECT is(public.nommer_responsable_reseau(:'reseau', 'ADJOINT@epn.org', 'adjoint'), :'adjoint'::uuid, 'adjoint nommé par son adresse');

-- ---------------------------------------------------------------------------
-- 2. Annuaire et invitation
-- ---------------------------------------------------------------------------
SELECT is((SELECT nom FROM public.rechercher_etablissements_reseau(:'reseau', 'EMMAUS')), 'École Bambino Emmaüs',
  'recherche insensible à la casse et aux accents');
SELECT is((SELECT count(*)::int FROM public.rechercher_etablissements_reseau(:'reseau', 'kindia')), 1, 'recherche par ville');
SELECT is(public.inviter_etablissement_reseau(:'reseau', '76000000-0000-0000-0000-000000000001'), 'invite', 'invitation envoyée');
SELECT is(public.inviter_etablissement_reseau(:'reseau', '76000000-0000-0000-0000-000000000001'), 'invite', 'invitation répétée sans doublon');
SELECT public.inviter_etablissement_reseau(:'reseau', '76000000-0000-0000-0000-000000000002');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications WHERE destinataire = :'dir1' AND type = 'reseau_invitation'), 1,
  'la direction invitée est prévenue une fois');
SET LOCAL ROLE authenticated;

SELECT pg_temp.en_tant_que(:'dir2');
SELECT throws_ok(format($$ SELECT public.repondre_invitation_reseau(%L, '76000000-0000-0000-0000-000000000001', true) $$, :'reseau'),
  '42501', NULL, 'une autre école ne répond pas à la place de l''école invitée');
SELECT pg_temp.en_tant_que(:'dir1');
SELECT is(public.repondre_invitation_reseau(:'reseau', '76000000-0000-0000-0000-000000000001', true), 'membre', 'invitation acceptée');
SELECT is(public.repondre_invitation_reseau(:'reseau', '76000000-0000-0000-0000-000000000001', true), 'membre', 'même réponse renvoyée : sans effet');
SELECT pg_temp.en_tant_que(:'dir2');
SELECT is(public.repondre_invitation_reseau(:'reseau', '76000000-0000-0000-0000-000000000002', false), 'refuse', 'invitation refusée');

-- ---------------------------------------------------------------------------
-- 3. Tableau de bord consolidé
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir1');
SELECT throws_ok(format($$ SELECT public.tableau_bord_reseau(%L) $$, :'reseau'), '42501', NULL,
  'une direction membre ne voit pas le tableau consolidé du réseau');
SELECT pg_temp.en_tant_que(:'adjoint');
SELECT public.tableau_bord_reseau(:'reseau') AS tb \gset
SELECT is((:'tb'::jsonb -> 'totaux' ->> 'ecoles')::int, 1, 'une école membre (l''école qui a refusé n''y est pas)');
SELECT is((:'tb'::jsonb -> 'totaux' ->> 'effectif')::int, 2, 'effectif de l''année courante');
SELECT is((:'tb'::jsonb -> 'totaux' ->> 'taux_recouvrement')::numeric, 25.0, 'recouvrement : 500 000 encaissés sur 2 000 000 dus');
SELECT is((:'tb'::jsonb -> 'ecoles' -> 0 ->> 'taux_presence')::numeric, 75.0, 'présence sur 30 jours (retard compté présent)');
SELECT ok(position('SECRETNOM' in :'tb') = 0 AND position('Awa' in :'tb') = 0, 'aucun nom d''élève dans le tableau du réseau');

-- ---------------------------------------------------------------------------
-- 4. Circulaires et calendrier commun
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'fondateur');
SELECT is((public.publier_circulaire_reseau('76000000-0000-0000-0000-00000000c101', :'reseau', 'Examens blancs',
  'Les examens blancs auront lieu la semaine du 8 mars.', true) ->> 'destinataires')::int, 1, 'circulaire envoyée aux directions membres');
SELECT is((public.publier_circulaire_reseau('76000000-0000-0000-0000-00000000c101', :'reseau', 'Examens blancs',
  'Les examens blancs auront lieu la semaine du 8 mars.', true) ->> 'deja_recue')::boolean, true, 'renvoi : pas de second envoi');
SELECT public.enregistrer_evenement_reseau('76000000-0000-0000-0000-00000000e101', :'reseau', 'Rentrée des classes', 'rentree',
  '2026-10-05', '2026-10-05');

SELECT pg_temp.en_tant_que(:'dir1');
SELECT is((public.circulaires_reseau_liste(:'reseau') -> 0 ->> 'lue')::boolean, false, 'circulaire non lue');
SELECT public.marquer_circulaire_lue('76000000-0000-0000-0000-00000000c101');
SELECT public.importer_evenement_reseau('76000000-0000-0000-0000-00000000e101', '76000000-0000-0000-0000-000000000001') AS agenda \gset
SELECT is(public.importer_evenement_reseau('76000000-0000-0000-0000-00000000e101', '76000000-0000-0000-0000-000000000001'), :'agenda'::uuid,
  'événement commun importé une seule fois dans l''agenda de l''école');

SELECT pg_temp.en_tant_que(:'fondateur');
SELECT is(public.circulaires_reseau_liste(:'reseau') -> 0 ->> 'lectures', '1', 'accusé de lecture visible par le réseau');

-- ---------------------------------------------------------------------------
-- 5. Retrait (GSG) et dissolution
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir1');
SELECT is(public.demander_retrait_reseau(:'reseau', '76000000-0000-0000-0000-000000000001', 'Changement de tutelle'), 'retrait_demande',
  'retrait demandé par l''école');
SELECT pg_temp.en_tant_que(:'fondateur');
SELECT throws_ok(format($$ SELECT public.decider_retrait_reseau(%L, '76000000-0000-0000-0000-000000000001', true) $$, :'reseau'),
  '42501', NULL, 'la Direction Générale ne finalise pas un retrait (règle 28.4)');
SELECT pg_temp.en_tant_que(:'admin');
SELECT is(public.decider_retrait_reseau(:'reseau', '76000000-0000-0000-0000-000000000001', true), 'retire', 'retrait finalisé par GSG');

SELECT pg_temp.en_tant_que(:'fondateur');
SELECT throws_ok(format($$ SELECT public.dissoudre_reseau(%L, 'Reseau') $$, :'reseau'),
  '23514', 'CONFIRMATION_INCORRECTE', 'dissolution refusée sans le nom exact');
SELECT lives_ok(format($$ SELECT public.dissoudre_reseau(%L, 'réseau epn') $$, :'reseau'), 'dissolution confirmée par le nom');
SELECT is(jsonb_array_length(public.mes_reseaux()), 0, 'réseau dissous : plus affiché');

SELECT throws_ok($$ INSERT INTO public.reseaux (nom, denomination, type_reseau, pays_code, devise_code) VALUES ('x', 'x', 'autre', 'GN', 'GNF') $$,
  '42501', NULL, 'aucune écriture directe dans les tables du réseau');

SELECT * FROM finish();
ROLLBACK;
