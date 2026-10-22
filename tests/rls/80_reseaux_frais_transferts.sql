-- ============================================================================
-- EcoShop — Test RLS 80 : réseaux, politique de frais et transferts
-- (migration 20260906001553)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email) VALUES (v_id, p_email);
  UPDATE public.profiles SET role_racine = p_role::public.role_racine WHERE id = v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

SELECT plan(40);

INSERT INTO public.etablissements (id, nom, slug, ville, devise_code) VALUES
  ('80000000-0000-0000-0000-00000000000a', 'École Emmaüs', 'emmaus-80', 'Conakry', 'GNF'),
  ('80000000-0000-0000-0000-00000000000b', 'École Kindia', 'kindia-80', 'Kindia', 'GNF'),
  ('80000000-0000-0000-0000-00000000000c', 'École Hors Réseau', 'hors-80', 'Labé', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('80000000-0000-0000-0000-0000000000a1', '80000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true),
  ('80000000-0000-0000-0000-0000000000b1', '80000000-0000-0000-0000-00000000000b', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('80000000-0000-0000-0000-0000000000ca', '80000000-0000-0000-0000-00000000000a', '80000000-0000-0000-0000-0000000000a1', '6A', '6e A'),
  ('80000000-0000-0000-0000-0000000000cb', '80000000-0000-0000-0000-00000000000b', '80000000-0000-0000-0000-0000000000b1', '6B', '6e B');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, nom_pere) VALUES
  ('80000000-0000-0000-0000-0000000000e1', '80000000-0000-0000-0000-00000000000a', 'A-1', 'BAH', 'Awa', '2014-01-01', 'Ibrahima BAH'),
  ('80000000-0000-0000-0000-0000000000e2', '80000000-0000-0000-0000-00000000000a', 'A-2', 'CAMARA', 'Mory', '2014-02-01', null);
INSERT INTO public.inscriptions (id, etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('80000000-0000-0000-0000-0000000000f1', '80000000-0000-0000-0000-00000000000a', '80000000-0000-0000-0000-0000000000e1', '80000000-0000-0000-0000-0000000000ca', '80000000-0000-0000-0000-0000000000a1'),
  ('80000000-0000-0000-0000-0000000000f2', '80000000-0000-0000-0000-00000000000a', '80000000-0000-0000-0000-0000000000e2', '80000000-0000-0000-0000-0000000000ca', '80000000-0000-0000-0000-0000000000a1');
INSERT INTO public.frais_scolarite_config (etablissement_id, annee_scolaire_id, montant_annuel) VALUES
  ('80000000-0000-0000-0000-00000000000a', '80000000-0000-0000-0000-0000000000a1', 1000000),
  ('80000000-0000-0000-0000-00000000000b', '80000000-0000-0000-0000-0000000000b1', 800000);

SELECT pg_temp.compte('dg@epn.org', 'parent') AS dg \gset
SELECT pg_temp.compte('dir.a@epn.org', 'direction') AS dira \gset
SELECT pg_temp.compte('dir.b@epn.org', 'direction') AS dirb \gset
SELECT pg_temp.compte('dir.c@hors.org', 'direction') AS dirc \gset
SELECT pg_temp.compte('parent.awa@gmail.com', 'parent') AS parent \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dira', '80000000-0000-0000-0000-00000000000a', 'direction'),
  (:'dirb', '80000000-0000-0000-0000-00000000000b', 'direction'),
  (:'dirc', '80000000-0000-0000-0000-00000000000c', 'direction');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id) VALUES
  ('80000000-0000-0000-0000-00000000000a', :'parent', '80000000-0000-0000-0000-0000000000e1');

-- Awa a tout payé, Mory non.
SELECT pg_temp.en_tant_que(:'dira');
INSERT INTO public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, montant, saisi_par)
VALUES ('80000000-0000-0000-0000-00000000000a', '80000000-0000-0000-0000-0000000000e1', '80000000-0000-0000-0000-0000000000f1', 1200000, :'dira');

INSERT INTO public.reseaux (id, nom, denomination, type_reseau, pays_code, devise_code) VALUES
  ('80000000-0000-0000-0000-0000000000d0', 'Réseau EPN', 'Église Protestante Nationale', 'confessionnel', 'GN', 'GNF');
INSERT INTO public.reseaux_responsables (reseau_id, profile_id, role) VALUES
  ('80000000-0000-0000-0000-0000000000d0', :'dg', 'direction_generale');
INSERT INTO public.reseaux_etablissements (reseau_id, etablissement_id, statut) VALUES
  ('80000000-0000-0000-0000-0000000000d0', '80000000-0000-0000-0000-00000000000a', 'membre'),
  ('80000000-0000-0000-0000-0000000000d0', '80000000-0000-0000-0000-00000000000b', 'membre');

\set reseau '80000000-0000-0000-0000-0000000000d0'

-- ---------------------------------------------------------------------------
-- 1. Politique de frais
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dira');
SELECT is(public.regles_reseau(:'reseau') ->> 'politique_frais', 'autonome', 'par défaut chaque école fixe ses frais');
SELECT throws_ok($$ SELECT public.parametrer_reseau('80000000-0000-0000-0000-0000000000d0', 'commune', true, true, false, true, true) $$,
  '42501', NULL, 'seule la Direction Générale règle le réseau');
SELECT throws_ok($$ SELECT public.enregistrer_grille_reseau('80000000-0000-0000-0000-0000000000d0', '[]') $$,
  '42501', NULL, 'une école ne modifie pas la grille du réseau');

SELECT pg_temp.en_tant_que(:'dg');
SELECT throws_ok($$ SELECT public.parametrer_reseau('80000000-0000-0000-0000-0000000000d0', 'commune', true, true, false, true, true) $$,
  '23514', 'GRILLE_VIDE', 'pas de grille commune sans grille');
SELECT throws_ok($$ SELECT public.enregistrer_grille_reseau('80000000-0000-0000-0000-0000000000d0',
  '[{"niveau_id":"80000000-0000-0000-0000-000000000999","montant_annuel":1}]') $$,
  '22023', 'NIVEAU_INCONNU', 'niveau inconnu refusé');
SELECT is((public.enregistrer_grille_reseau(:'reseau', '[{"niveau_id":null,"montant_annuel":1200000,"frais_inscription":50000}]') ->> 'lignes')::int,
  1, 'grille enregistrée');
SELECT is(public.parametrer_reseau(:'reseau', 'commune', true, true, false, true, true) -> 'grille_appliquee' ->> 'ecoles', '2',
  'grille commune appliquée aux deux écoles');
RESET ROLE;
SELECT is((SELECT montant_annuel::int FROM public.frais_scolarite_config
           WHERE etablissement_id = '80000000-0000-0000-0000-00000000000b' AND deleted_at IS NULL), 1200000,
  'tarif de l''école remplacé par la grille');
SELECT is((SELECT count(*)::int FROM public.frais_scolarite_config WHERE fixe_par_reseau_id = :'reseau'), 2, 'origine réseau tracée');

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dira');
SELECT throws_ok($$ UPDATE public.frais_scolarite_config SET montant_annuel = 900000
                    WHERE etablissement_id = '80000000-0000-0000-0000-00000000000a' $$,
  '42501', 'FRAIS_FIXES_PAR_RESEAU', 'en grille commune, l''école ne change plus ses frais');
SELECT is((public.regles_reseau(:'reseau', '80000000-0000-0000-0000-00000000000a') -> 'grille' -> 0 ->> 'tarif_ecole')::numeric::int,
  1200000, 'l''école voit la grille et son tarif en regard');

SELECT pg_temp.en_tant_que(:'dg');
SELECT is(public.parametrer_reseau(:'reseau', 'indicative', true, true, true, true, true) ->> 'politique_frais', 'indicative',
  'grille rendue indicative, validation des transferts par le réseau');
SELECT pg_temp.en_tant_que(:'dira');
SELECT lives_ok($$ UPDATE public.frais_scolarite_config SET montant_annuel = 1100000
                   WHERE etablissement_id = '80000000-0000-0000-0000-00000000000a' $$,
  'grille indicative : l''école adapte son tarif');
SELECT is((public.appliquer_grille_reseau(:'reseau', '80000000-0000-0000-0000-00000000000a') ->> 'ecoles')::int, 1,
  'une école peut adopter la grille de référence');

-- ---------------------------------------------------------------------------
-- 2. Transferts
-- ---------------------------------------------------------------------------
SELECT is(jsonb_array_length(public.eleves_transferables('80000000-0000-0000-0000-00000000000a', 'camara')), 1,
  'recherche d''élève sans accents ni casse');
SELECT ok((SELECT (x ->> 'solde')::numeric > 0 FROM jsonb_array_elements(public.eleves_transferables('80000000-0000-0000-0000-00000000000a')) x
           WHERE x ->> 'prenom' = 'Mory'), 'le solde dû se voit avant de demander');
SELECT throws_ok($$ SELECT public.demander_transfert_reseau('80000000-0000-0000-0000-000000000101',
  '80000000-0000-0000-0000-0000000000e1', '80000000-0000-0000-0000-00000000000c', 'Déménagement') $$,
  '23514', 'ECOLES_HORS_MEME_RESEAU', 'transfert hors réseau refusé');
SELECT throws_ok($$ SELECT public.demander_transfert_reseau('80000000-0000-0000-0000-000000000102',
  '80000000-0000-0000-0000-0000000000e2', '80000000-0000-0000-0000-00000000000b', 'Déménagement') $$,
  '23514', 'SOLDE_IMPAYE', 'frais non soldés : transfert bloqué (règle du réseau)');
SELECT is(public.demander_transfert_reseau('80000000-0000-0000-0000-000000000103',
  '80000000-0000-0000-0000-0000000000e1', '80000000-0000-0000-0000-00000000000b', 'Déménagement à Kindia') ->> 'statut',
  'a_valider_reseau', 'transfert demandé, en attente du réseau');
SELECT is((public.demander_transfert_reseau('80000000-0000-0000-0000-000000000103',
  '80000000-0000-0000-0000-0000000000e1', '80000000-0000-0000-0000-00000000000b', 'Déménagement à Kindia') ->> 'deja_recue')::boolean,
  true, 'renvoi hors connexion : déjà reçue');
SELECT throws_ok($$ SELECT public.demander_transfert_reseau('80000000-0000-0000-0000-000000000104',
  '80000000-0000-0000-0000-0000000000e1', '80000000-0000-0000-0000-00000000000b', 'Encore') $$,
  '23505', 'TRANSFERT_DEJA_EN_COURS', 'un seul transfert en cours par élève');
SELECT is((SELECT d ->> 'nom' FROM jsonb_array_elements(public.destinations_transfert('80000000-0000-0000-0000-00000000000a')) d),
  'École Kindia', 'destinations : les autres écoles du réseau');

SELECT pg_temp.en_tant_que(:'dirb');
SELECT throws_ok($$ SELECT public.repondre_transfert_reseau('80000000-0000-0000-0000-000000000103', true,
  '80000000-0000-0000-0000-0000000000cb') $$, '23514', 'TRANSFERT_DEJA_TRAITE', 'l''accueil attend la validation du réseau');

SELECT pg_temp.en_tant_que(:'dg');
SELECT is(public.valider_transfert_reseau('80000000-0000-0000-0000-000000000103', true), 'en_attente_accueil',
  'validé par la Direction Générale');

SELECT pg_temp.en_tant_que(:'dira');
SELECT throws_ok($$ SELECT public.repondre_transfert_reseau('80000000-0000-0000-0000-000000000103', true,
  '80000000-0000-0000-0000-0000000000cb') $$, '42501', NULL, 'l''école de départ ne répond pas à la place de l''accueil');

SELECT pg_temp.en_tant_que(:'dirb');
SELECT is(jsonb_array_length(public.classes_accueil_transfert('80000000-0000-0000-0000-000000000103')), 1, 'classes proposées à l''accueil');
SELECT is((SELECT t -> 'dossier' ->> 'nom_pere' FROM jsonb_array_elements(
             public.transferts_reseau_liste(null, '80000000-0000-0000-0000-00000000000b')) t),
  'Ibrahima BAH', 'dossier transmis à l''école d''accueil');
SELECT throws_ok($$ SELECT public.repondre_transfert_reseau('80000000-0000-0000-0000-000000000103', true,
  '80000000-0000-0000-0000-0000000000ca') $$, '22023', 'CLASSE_INVALIDE', 'classe d''une autre école refusée');
SELECT is(public.repondre_transfert_reseau('80000000-0000-0000-0000-000000000103', true,
  '80000000-0000-0000-0000-0000000000cb') ->> 'statut', 'transfere', 'accepté : transfert fait');
SELECT is((public.repondre_transfert_reseau('80000000-0000-0000-0000-000000000103', true,
  '80000000-0000-0000-0000-0000000000cb') ->> 'deja_recue')::boolean, true, 'renvoi : déjà fait');
RESET ROLE;

SELECT is((SELECT f.prenom || '|' || f.nom_pere || '|' || (f.fiche_origine_id = '80000000-0000-0000-0000-0000000000e1')::text
           FROM public.fiches_eleves f WHERE f.etablissement_id = '80000000-0000-0000-0000-00000000000b'),
  'Awa|Ibrahima BAH|true', 'fiche créée à l''arrivée, famille reprise');
SELECT is((SELECT count(*)::int FROM public.inscriptions WHERE etablissement_id = '80000000-0000-0000-0000-00000000000b'
           AND statut = 'active'), 1, 'inscrite à l''arrivée');
SELECT is((SELECT statut::text FROM public.inscriptions WHERE id = '80000000-0000-0000-0000-0000000000f1'), 'retiree',
  'retirée au départ');
SELECT is((SELECT count(*)::int FROM public.relations_parent_eleve WHERE parent_profile_id = :'parent'), 2,
  'le parent suit son enfant dans la nouvelle école');

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dira');
SELECT throws_ok($$ SELECT public.annuler_transfert_reseau('80000000-0000-0000-0000-000000000103') $$,
  '23514', 'TRANSFERT_DEJA_TRAITE', 'un transfert fait ne s''annule pas');

-- Sans quitus ni validation : Mory part directement vers l'accueil, qui refuse.
SELECT pg_temp.en_tant_que(:'dg');
SELECT public.parametrer_reseau(:'reseau', 'autonome', true, false, false, false, false);
SELECT pg_temp.en_tant_que(:'dira');
SELECT is(public.demander_transfert_reseau('80000000-0000-0000-0000-000000000105',
  '80000000-0000-0000-0000-0000000000e2', '80000000-0000-0000-0000-00000000000b', 'Rapprochement familial') ->> 'statut',
  'en_attente_accueil', 'sans validation du réseau : directement à l''accueil');
SELECT pg_temp.en_tant_que(:'dirb');
SELECT throws_ok($$ SELECT public.repondre_transfert_reseau('80000000-0000-0000-0000-000000000105', false) $$,
  '23514', 'MOTIF_REQUIS', 'un refus est motivé');
SELECT is(public.repondre_transfert_reseau('80000000-0000-0000-0000-000000000105', false, null, 'Classe complète') ->> 'statut',
  'refuse', 'refusé par l''accueil');

SELECT pg_temp.en_tant_que(:'dirc');
SELECT throws_ok($$ SELECT public.transferts_reseau_liste(null, '80000000-0000-0000-0000-00000000000a') $$,
  '42501', NULL, 'une autre école ne voit pas les transferts');
SELECT pg_temp.en_tant_que(:'dg');
SELECT is(jsonb_array_length(public.transferts_reseau_liste('80000000-0000-0000-0000-0000000000d0')), 2,
  'la Direction Générale suit les transferts du réseau');

SELECT * FROM finish();
ROLLBACK;
