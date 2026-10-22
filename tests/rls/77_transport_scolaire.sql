-- ============================================================================
-- EcoShop — Test RLS 77 : M18 transport scolaire (migration 1550)
-- Circuits et arrêts, affectation, chauffeur à l'accès restreint, trajet,
-- avis aux familles (approche, montée, descente), rejeu tardif sans avis,
-- enfants restés à bord, position effacée en fin de trajet, facturation.
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

CREATE OR REPLACE FUNCTION pg_temp.avis(p_dest uuid, p_type text) RETURNS integer
LANGUAGE sql AS $$
  SELECT count(*)::int FROM public.notifications WHERE destinataire = p_dest AND type = p_type;
$$;

SELECT plan(37);

\set E '77000000-0000-0000-0000-000000000001'
\set E2 '77000000-0000-0000-0000-000000000002'
\set C '77000000-0000-0000-0000-0000000000c1'
\set A1 '77000000-0000-0000-0000-0000000000a1'
\set A2 '77000000-0000-0000-0000-0000000000a2'
\set A3 '77000000-0000-0000-0000-0000000000a3'
\set T '77000000-0000-0000-0000-0000000000b1'
\set FA '77000000-0000-0000-0000-0000000000e1'
\set FB '77000000-0000-0000-0000-0000000000e2'
\set FC '77000000-0000-0000-0000-0000000000e3'

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  (:'E', 'École Transport', 'transport-77', 'GNF'), (:'E2', 'Autre', 'autre-77', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('77000000-0000-0000-0000-0000000000d1', :'E', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('77000000-0000-0000-0000-0000000000f1', :'E', '77000000-0000-0000-0000-0000000000d1', 'CM1', 'CM1 A');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance) VALUES
  (:'FA', :'E', 'T-1', 'BAH', 'Awa', '2016-01-01'),
  (:'FB', :'E', 'T-2', 'SOW', 'Ibrahima', '2016-01-01'),
  (:'FC', :'E', 'T-3', 'DIALLO', 'Mariama', '2016-01-01');
INSERT INTO public.inscriptions (id, etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id)
SELECT gen_random_uuid(), :'E', f, '77000000-0000-0000-0000-0000000000f1', '77000000-0000-0000-0000-0000000000d1'
FROM unnest(array[:'FA', :'FB', :'FC']::uuid[]) f;
INSERT INTO public.cartes_eleves (fiche_eleve_id, etablissement_id, jeton) VALUES
  (:'FA', :'E', 'CARTE-AWA-77'), (:'FB', :'E', 'CARTE-IBRAHIMA-77'), (:'FC', :'E', 'CARTE-MARIAMA-77');

SELECT pg_temp.creer_compte('224677000001', 'direction') AS dir \gset
SELECT pg_temp.creer_compte('224677000002', 'direction') AS dir2 \gset
SELECT pg_temp.creer_compte('224677000003', 'parent') AS chauffeur \gset
SELECT pg_temp.creer_compte('224677000004', 'parent') AS parent_a \gset
SELECT pg_temp.creer_compte('224677000005', 'parent') AS parent_b \gset
SELECT pg_temp.creer_compte('224677000006', 'parent') AS inconnu \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir', :'E', 'direction'), (:'dir2', :'E2', 'direction');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id) VALUES
  (:'E', :'parent_a', :'FA'), (:'E', :'parent_b', :'FB');

SET LOCAL ROLE authenticated;

-- ---------------------------------------------------------------------------
-- 1. Circuit, arrêts, affectations (direction)
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir2');
SELECT throws_ok(format($$ SELECT public.enregistrer_circuit_transport(%L, %L, 'Circuit 1', 'RC-1234', 2, 600000, '620 77 00 03') $$, :'C', :'E'),
  '42501', NULL, 'la direction d''une autre école ne crée pas de circuit ici');
SELECT pg_temp.en_tant_que(:'dir');
SELECT is(public.enregistrer_circuit_transport(:'C', :'E', 'Circuit 1', 'RC-1234', 2, 600000, '+224 677 00 00 03') ->> 'chauffeur_profile_id',
  :'chauffeur', 'chauffeur reconnu par son numéro');
SELECT is(public.enregistrer_arrets_transport(:'C', jsonb_build_array(
  jsonb_build_object('id', :'A1', 'nom', 'Kaloum', 'heure_matin', '06:45', 'latitude', 9.51, 'longitude', -13.71),
  jsonb_build_object('id', :'A2', 'nom', 'Dixinn', 'heure_matin', '07:00'),
  jsonb_build_object('id', :'A3', 'nom', 'Ratoma', 'heure_matin', '07:15'))), 3, 'trois arrêts ordonnés');
SELECT lives_ok(format($$ SELECT public.affecter_eleve_transport(%L, %L, %L) $$, :'FA', :'C', :'A2'), 'Awa affectée à Dixinn');
SELECT lives_ok(format($$ SELECT public.affecter_eleve_transport(%L, %L, %L) $$, :'FB', :'C', :'A3'), 'Ibrahima affecté à Ratoma');
SELECT throws_ok(format($$ SELECT public.affecter_eleve_transport(%L, %L, %L) $$, :'FC', :'C', :'A3'),
  '23514', 'CIRCUIT_COMPLET', 'capacité du véhicule respectée');
SELECT throws_ok(format($$ SELECT public.enregistrer_arrets_transport(%L, jsonb_build_array(jsonb_build_object('id', %L, 'nom', 'Kaloum'))) $$, :'C', :'A1'),
  '23514', 'ARRET_AVEC_ELEVES', 'un arrêt où des élèves sont affectés ne disparaît pas');

-- ---------------------------------------------------------------------------
-- 2. Chauffeur : accès restreint (règle 24.3)
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'chauffeur');
SELECT is(jsonb_array_length(public.mes_circuits_chauffeur() -> 0 -> 'eleves'), 2, 'le chauffeur reçoit ses deux élèves');
SELECT is(public.mes_circuits_chauffeur() -> 0 -> 'eleves' -> 0 ->> 'jeton', 'CARTE-AWA-77', 'avec leurs cartes, pour scanner sans réseau');
SELECT is((SELECT count(*)::int FROM public.fiches_eleves), 0, 'aucun accès aux fiches des élèves');
SELECT throws_ok(format($$ SELECT public.transport_etablissement(%L) $$, :'E'), '42501', NULL, 'ni à la gestion du transport');

SELECT pg_temp.en_tant_que(:'inconnu');
SELECT throws_ok(format($$ SELECT public.demarrer_trajet(%L, %L, 'aller') $$, :'T', :'C'), '42501', NULL,
  'seul le chauffeur du circuit démarre un trajet');

-- ---------------------------------------------------------------------------
-- 3. Trajet et avis aux familles
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'chauffeur');
SELECT is((public.demarrer_trajet(:'T', :'C', 'aller') ->> 'deja_recu')::boolean, false, 'trajet démarré');
SELECT is((public.demarrer_trajet(:'T', :'C', 'aller') ->> 'deja_recu')::boolean, true, 'renvoi hors connexion : déjà reçu');

SELECT public.passer_arret(:'T', :'A1');
SELECT public.passer_arret(:'T', :'A1');
RESET ROLE;
SELECT is(pg_temp.avis(:'parent_a', 'transport_approche'), 1, 'arrêt Kaloum passé : la famille de Dixinn prévenue, une fois');
SELECT is(pg_temp.avis(:'parent_b', 'transport_approche'), 0, 'pas encore la famille de Ratoma');
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'chauffeur');

SELECT is(public.enregistrer_montee('77000000-0000-0000-0000-0000000001a1', :'T', 'CARTE-AWA-77', 'montee', :'A2', now() - interval '5 minutes') ->> 'statut',
  'enregistre', 'Awa monte à Dixinn');
SELECT is(public.enregistrer_montee('77000000-0000-0000-0000-0000000001a1', :'T', 'CARTE-AWA-77', 'montee', :'A2') ->> 'statut',
  'deja_recu', 'scan renvoyé : sans doublon');
SELECT is(public.enregistrer_montee('77000000-0000-0000-0000-0000000001a2', :'T', 'CARTE-INCONNUE', 'montee') ->> 'statut',
  'carte_inconnue', 'carte inconnue signalée');
-- Scan fait sans réseau il y a une heure, transmis maintenant : enregistré, sans avis.
SELECT is((public.enregistrer_montee('77000000-0000-0000-0000-0000000001b1', :'T', 'CARTE-IBRAHIMA-77', 'montee', :'A3',
  now() - interval '1 hour') ->> 'a_bord')::int, 2, 'Ibrahima enregistré à bord');
SELECT public.signaler_position_trajet(:'T', 9.53, -13.68);
SELECT public.signaler_position_trajet(:'T', 1.0, 1.0, now() - interval '10 minutes');
RESET ROLE;
SELECT is(pg_temp.avis(:'parent_a', 'transport_montee'), 1, 'la famille d''Awa avertie de la montée');
SELECT is(pg_temp.avis(:'parent_b', 'transport_montee'), 0, 'avis devenu inutile (scan d''il y a une heure) : pas envoyé');
SET LOCAL ROLE authenticated;

SELECT pg_temp.en_tant_que(:'parent_a');
SELECT public.suivi_transport_enfant(:'FA') AS suivi \gset
SELECT is(:'suivi'::jsonb -> 'trajet_en_cours' ->> 'a_bord', 'true', 'le parent voit son enfant à bord');
SELECT is((:'suivi'::jsonb -> 'trajet_en_cours' ->> 'latitude')::numeric, 9.53, 'position la plus récente (l''ancienne renvoyée après est ignorée)');
SELECT is(:'suivi'::jsonb -> 'trajet_en_cours' ->> 'dernier_arret_ordre', '1', 'dernier arrêt passé');
SELECT throws_ok(format($$ SELECT public.suivi_transport_enfant(%L) $$, :'FB'), '42501', NULL,
  'un parent ne suit pas l''enfant d''une autre famille');

-- ---------------------------------------------------------------------------
-- 4. Fin de trajet : enfants restés à bord, position effacée
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'chauffeur');
SELECT public.enregistrer_montee('77000000-0000-0000-0000-0000000001a3', :'T', 'CARTE-AWA-77', 'descente', null);
SELECT public.terminer_trajet(:'T') AS fin \gset
SELECT is(jsonb_array_length(:'fin'::jsonb -> 'restes_a_bord'), 1, 'un enfant encore enregistré à bord');
SELECT is(:'fin'::jsonb -> 'restes_a_bord' -> 0 ->> 'prenom', 'Ibrahima', 'son nom est rendu au chauffeur');
SELECT lives_ok(format($$ SELECT public.signaler_position_trajet(%L, 9.6, -13.6) $$, :'T'), 'position après la fin : ignorée');
RESET ROLE;
SELECT is(pg_temp.avis(:'dir', 'transport_a_bord'), 1, 'la direction est alertée');
SELECT is(pg_temp.avis(:'parent_a', 'transport_descente'), 1, 'la famille d''Awa avertie de la descente');
SELECT ok((SELECT latitude IS NULL AND longitude IS NULL FROM public.trajets_transport WHERE id = :'T'),
  'position effacée à la fin du trajet');
SET LOCAL ROLE authenticated;

SELECT pg_temp.en_tant_que(:'parent_a');
SELECT ok(public.suivi_transport_enfant(:'FA') -> 'trajet_en_cours' = 'null'::jsonb, 'plus de position visible hors trajet');

-- ---------------------------------------------------------------------------
-- 5. Facturation (même circuit que la scolarité)
-- ---------------------------------------------------------------------------
RESET ROLE;
SELECT pg_temp.en_tant_que(:'dir');
INSERT INTO public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, type_frais, montant, saisi_par)
SELECT :'E', :'FA', i.id, 'transport', 200000, :'dir' FROM public.inscriptions i WHERE i.fiche_eleve_id = :'FA';
SET LOCAL ROLE authenticated;
SELECT public.transport_etablissement(:'E') AS tr \gset
SELECT is((SELECT (e ->> 'montant_paye')::numeric FROM jsonb_array_elements(:'tr'::jsonb -> 'circuits' -> 0 -> 'eleves') e
           WHERE e ->> 'prenom' = 'Awa'), 200000.00, 'transport payé par le même circuit que la scolarité');
SELECT is((:'tr'::jsonb -> 'circuits' -> 0 -> 'dernier_trajet' ->> 'restes_a_bord')::int, 1, 'la direction voit le dernier trajet');

SELECT is(public.rechercher_eleves_transport(:'E', 'mariama') -> 0 ->> 'classe', 'CM1 A', 'recherche d''un élève à affecter');
SELECT throws_ok($$ SELECT * FROM public.montees_transport $$, '42501', NULL, 'aucune lecture directe des montées');

SELECT * FROM finish();
ROLLBACK;
