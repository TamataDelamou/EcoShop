-- ============================================================================
-- EcoShop — Test RLS 78 : M17 bibliothèque physique (migration 1551)
-- Catalogue, exemplaires numérotés, prêt et retour, limite, renouvellement,
-- statuts automatiques retard/perdu, réservation, relances, pertes
-- répétées, inventaire.
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

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

SELECT plan(30);

\set E '78000000-0000-0000-0000-000000000001'
\set L1 '78000000-0000-0000-0000-0000000000b1'
\set L2 '78000000-0000-0000-0000-0000000000b2'
\set FA '78000000-0000-0000-0000-0000000000e1'
\set FB '78000000-0000-0000-0000-0000000000e2'
\set FC '78000000-0000-0000-0000-0000000000e3'

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES (:'E', 'École Livres', 'livres-78', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('78000000-0000-0000-0000-0000000000d1', :'E', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('78000000-0000-0000-0000-0000000000f1', :'E', '78000000-0000-0000-0000-0000000000d1', '6A', '6e A');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance) VALUES
  (:'FA', :'E', 'L-1', 'BAH', 'Awa', '2014-01-01'),
  (:'FB', :'E', 'L-2', 'SOW', 'Ibrahima', '2014-01-01'),
  (:'FC', :'E', 'L-3', 'DIALLO', 'Mariama', '2014-01-01');

SELECT pg_temp.creer_compte('224678000001', 'direction') AS dir \gset
SELECT pg_temp.creer_compte('224678000002', 'enseignant') AS prof \gset
SELECT pg_temp.creer_compte('224678000003', 'parent') AS parent_a \gset
SELECT pg_temp.creer_compte('224678000004', 'parent') AS parent_b \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir', :'E', 'direction'), (:'prof', :'E', 'enseignant'), (:'parent_a', :'E', 'parent'), (:'parent_b', :'E', 'parent');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id) VALUES
  (:'E', :'parent_a', :'FA'), (:'E', :'parent_b', :'FB');

SET LOCAL ROLE authenticated;

-- ---------------------------------------------------------------------------
-- 1. Catalogue et exemplaires
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'prof');
SELECT throws_ok(format($$ SELECT public.enregistrer_livre(%L, %L, 'Une si longue lettre') $$, :'L1', :'E'),
  '42501', NULL, 'un enseignant sans habilitation ne gère pas la bibliothèque');

SELECT pg_temp.en_tant_que(:'dir');
SELECT is(public.enregistrer_livre(:'L1', :'E', 'Une si longue lettre', 'Mariama Bâ', '978-2-84261-027-1', 'Le Serpent à Plumes',
  1979, 'Roman', '3e', 'R BA', null, 2) -> 'nouveaux_codes', '["LIV-000001", "LIV-000002"]'::jsonb, 'deux exemplaires numérotés');
SELECT is(public.enregistrer_livre(:'L2', :'E', 'L''Enfant noir', 'Camara Laye', null, null, 1953, 'Roman', null, 'R CAM', null, 1)
  -> 'nouveaux_codes' ->> 0, 'LIV-000003', 'numérotation continue de l''école');
RESET ROLE;
SELECT is((SELECT isbn FROM public.livres WHERE id = :'L1'), '9782842610271', 'ISBN normalisé');
SET LOCAL ROLE authenticated;

SELECT pg_temp.en_tant_que(:'parent_a');
SELECT is((SELECT (x ->> 'disponibles')::int FROM jsonb_array_elements(public.catalogue_bibliotheque(:'E', 'longue')) x), 2,
  'catalogue consultable par une famille, avec la disponibilité');
SELECT throws_ok(format($$ SELECT public.preter_exemplaire(gen_random_uuid(), %L, %L, 'LIV-000001') $$, :'E', :'FA'),
  '42501', NULL, 'une famille ne prête pas de livre');

-- ---------------------------------------------------------------------------
-- 2. Prêt, limite, renouvellement
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir');
SELECT is((public.preter_exemplaire('78000000-0000-0000-0000-00000000aa01', :'E', :'FA', 'liv-000001') ->> 'echeance')::date,
  current_date + 14, 'prêt : échéance à 14 jours (par défaut)');
SELECT is((public.preter_exemplaire('78000000-0000-0000-0000-00000000aa01', :'E', :'FA', 'LIV-000001') ->> 'deja_recu')::boolean,
  true, 'prêt renvoyé hors connexion : sans doublon');
SELECT throws_ok(format($$ SELECT public.preter_exemplaire(gen_random_uuid(), %L, %L, 'LIV-000001') $$, :'E', :'FB'),
  '23514', 'EXEMPLAIRE_DEJA_PRETE', 'un exemplaire déjà prêté ne l''est pas une seconde fois');
SELECT public.enregistrer_parametres_bibliotheque(:'E', 14, 1, 1, 30, true);
SELECT throws_ok(format($$ SELECT public.preter_exemplaire(gen_random_uuid(), %L, %L, 'LIV-000002') $$, :'E', :'FA'),
  '23514', 'LIMITE_EMPRUNTS', 'limite d''emprunts par élève');
SELECT is(public.renouveler_emprunt('78000000-0000-0000-0000-00000000aa01'), current_date + 28, 'renouvellement : 14 jours de plus');
SELECT throws_ok($$ SELECT public.renouveler_emprunt('78000000-0000-0000-0000-00000000aa01') $$,
  '23514', 'RENOUVELLEMENTS_EPUISES', 'renouvellements limités');

-- ---------------------------------------------------------------------------
-- 3. Statuts automatiques (25.3)
-- ---------------------------------------------------------------------------
RESET ROLE;
UPDATE public.emprunts SET echeance = current_date - 1 WHERE id = '78000000-0000-0000-0000-00000000aa01';
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'parent_a');
SELECT is(public.emprunts_eleve(:'FA') -> 'emprunts' -> 0 ->> 'statut', 'en_retard', 'en retard dès le lendemain de l''échéance, sans action');
RESET ROLE;
UPDATE public.emprunts SET echeance = current_date - 31 WHERE id = '78000000-0000-0000-0000-00000000aa01';
SET LOCAL ROLE authenticated;
SELECT is(public.emprunts_eleve(:'FA') -> 'emprunts' -> 0 ->> 'statut', 'perdu', 'perdu après le délai de perte (30 jours)');
SELECT throws_ok(format($$ SELECT public.emprunts_eleve(%L) $$, :'FB'), '42501', NULL, 'les emprunts d''un autre enfant restent privés');

-- ---------------------------------------------------------------------------
-- 4. Réservation et retour
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir');
SELECT public.enregistrer_parametres_bibliotheque(:'E', 14, 3, 1, 30, true);
SELECT public.preter_exemplaire('78000000-0000-0000-0000-00000000aa02', :'E', :'FB', 'LIV-000003');
SELECT pg_temp.en_tant_que(:'parent_a');
SELECT lives_ok(format($$ SELECT public.reserver_livre(%L, %L) $$, :'L2', :'FA'), 'la famille réserve un livre sorti');
SELECT throws_ok(format($$ SELECT public.reserver_livre(%L, %L) $$, :'L2', :'FC'), '42501', NULL,
  'pas de réservation au nom d''un enfant qui n''est pas le sien');
SELECT pg_temp.en_tant_que(:'dir');
SELECT is((public.rendre_exemplaire(:'E', 'LIV-000003') ->> 'reserve')::boolean, true, 'retour : le livre réservé est gardé');
SELECT throws_ok(format($$ SELECT public.preter_exemplaire(gen_random_uuid(), %L, %L, 'LIV-000003') $$, :'E', :'FC'),
  '23514', 'EXEMPLAIRE_RESERVE', 'l''exemplaire gardé ne part pas chez un autre élève');
SELECT lives_ok(format($$ SELECT public.preter_exemplaire(gen_random_uuid(), %L, %L, 'LIV-000003') $$, :'E', :'FA'),
  'l''élève qui l''a réservé peut l''emprunter');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications WHERE destinataire = :'parent_a' AND type = 'bibliotheque_reservation'), 1,
  'la famille est prévenue que le livre l''attend');
SELECT ok((SELECT close_le IS NOT NULL FROM public.reservations_livres WHERE livre_id = :'L2' AND fiche_eleve_id = :'FA'),
  'réservation close à l''emprunt');

-- ---------------------------------------------------------------------------
-- 5. Relances, pertes répétées, inventaire
-- ---------------------------------------------------------------------------
UPDATE public.emprunts SET echeance = current_date + 1 WHERE fiche_eleve_id = :'FA' AND rendu_le IS NULL
  AND exemplaire_id = (SELECT id FROM public.exemplaires WHERE code = 'LIV-000003' AND etablissement_id = :'E');
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT ok((public.executer_taches_quotidiennes() ->> 'relances_bibliotheque')::int >= 1, 'la tâche de nuit relance la bibliothèque');
SELECT public.relancer_emprunts_bibliotheque();
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications WHERE destinataire = :'parent_a' AND type = 'bibliotheque_relance'
           AND contenu LIKE '%à rendre demain%'), 1, 'rappel la veille de l''échéance, une seule fois');

INSERT INTO public.emprunts (id, etablissement_id, exemplaire_id, fiche_eleve_id, emprunte_le, echeance)
SELECT gen_random_uuid(), :'E', id, :'FC', now() - interval '60 days', current_date - 40
FROM public.exemplaires WHERE etablissement_id = :'E' AND code = 'LIV-000002';
INSERT INTO public.emprunts (id, etablissement_id, exemplaire_id, fiche_eleve_id, emprunte_le, echeance, rendu_le)
SELECT gen_random_uuid(), :'E', id, :'FC', now() - interval '90 days', current_date - 70, null
FROM public.exemplaires WHERE etablissement_id = :'E' AND code = 'LIV-000001'
ON CONFLICT DO NOTHING;
UPDATE public.emprunts SET rendu_le = now() WHERE id = '78000000-0000-0000-0000-00000000aa01';
INSERT INTO public.emprunts (id, etablissement_id, exemplaire_id, fiche_eleve_id, emprunte_le, echeance)
SELECT gen_random_uuid(), :'E', id, :'FC', now() - interval '90 days', current_date - 70
FROM public.exemplaires WHERE etablissement_id = :'E' AND code = 'LIV-000001';

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir');
SELECT public.tableau_bibliotheque(:'E') AS tb \gset
SELECT is(:'tb'::jsonb -> 'pertes_repetees' -> 0 ->> 'eleve', 'Mariama DIALLO', 'pertes répétées signalées (sans sanction automatique)');
SELECT ok(jsonb_array_length(:'tb'::jsonb -> 'retards') >= 2, 'retards et pertes listés');

SELECT public.commencer_inventaire_bibliotheque(:'E');
SELECT is(public.inventorier_exemplaire(:'E', 'LIV-000003') ->> 'statut', 'vu', 'exemplaire scanné à l''inventaire');
SELECT is(public.inventorier_exemplaire(:'E', 'LIV-999999') ->> 'statut', 'inconnu', 'étiquette inconnue signalée');
SELECT is(jsonb_array_length(public.tableau_bibliotheque(:'E') -> 'inventaire' -> 'introuvables'), 0,
  'les exemplaires prêtés ne sont pas comptés introuvables');

SELECT throws_ok($$ SELECT * FROM public.emprunts $$, '42501', NULL, 'aucune lecture directe des emprunts');

SELECT * FROM finish();
ROLLBACK;
