-- ============================================================================
-- EcoShop — Test RLS 72 : inscriptions et réinscriptions en ligne
-- (REG-08 lot I1, migration 20260906001544)
--
-- Couvre :
--   • campagne réservée à la Direction ; places par niveau ;
--   • réinscription par le parent (niveau suivant, frais, place réservée) ;
--     par l'élève lui-même dès le collège (frais nuls → inscrit, payeur
--     « élève ») ; refusée à l'élève de primaire ;
--   • impayé → « à examiner », jamais bloqué ; « ne revient pas » ;
--   • nouvel élève : demande, pièces manquantes puis déposées, acceptation,
--     liste d'attente quand le niveau est complet, retrait → promotion ;
--   • hors connexion : second envoi de la même clé, clé d'un autre compte,
--     saisie faite avant la date limite reçue après ;
--   • expiration de l'offre → place au suivant ;
--   • paiement Orange Money des frais → inscription + encaissement ;
--     paiement au guichet ; fiche, lien parent et notifications créés ;
--   • confidentialité des dossiers et des pièces.
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

SELECT plan(43);

-- ---------------------------------------------------------------------------
-- Fixtures : référentiel, établissement, deux années, classes, élèves
-- ---------------------------------------------------------------------------
INSERT INTO public.systemes_educatifs (code, nom) VALUES ('francophone_cfa', 'Francophone (CFA)')
ON CONFLICT (code) DO NOTHING;
INSERT INTO public.pays_pedagogiques (code_iso, nom, type_systeme, langue_enseignement_principale, statut_deploiement)
VALUES ('Z8', 'Pays Test 72', 'francophone_cfa', 'français', 'deploye') ON CONFLICT (code_iso) DO NOTHING;
INSERT INTO public.cycles_educatifs (pays_code, code, nom, ordre, duree_annees, isced_min, isced_max, statut) VALUES
  ('Z8', 'prim72', 'Primaire', 1, 6, 1, 1, 'publie'),
  ('Z8', 'coll72', 'Collège', 2, 4, 2, 2, 'publie');
INSERT INTO public.niveaux_educatifs (cycle_id, pays_code, code, nom, grade_level_normalise, isced, ordre, statut)
SELECT c.id, 'Z8', v.code, v.nom, v.g, v.isced, v.g, 'publie'
FROM (VALUES ('prim72', 'CM1_72', 'CM1', 5, 1), ('prim72', 'CM2_72', 'CM2', 6, 1),
             ('coll72', '6E_72', '6e', 7, 2), ('coll72', '5E_72', '5e', 8, 2)) AS v(cy, code, nom, g, isced)
JOIN public.cycles_educatifs c ON c.pays_code = 'Z8' AND c.code = v.cy;
SELECT id AS n_cm1 FROM public.niveaux_educatifs WHERE code = 'CM1_72' \gset
SELECT id AS n_cm2 FROM public.niveaux_educatifs WHERE code = 'CM2_72' \gset
SELECT id AS n_6e FROM public.niveaux_educatifs WHERE code = '6E_72' \gset
SELECT id AS n_5e FROM public.niveaux_educatifs WHERE code = '5E_72' \gset

INSERT INTO public.etablissements (id, nom, slug, ville, devise_code) VALUES
  ('72000000-0000-0000-0000-000000000001', 'Collège Emmaüs Test', 'emmaus-72', 'Conakry', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('72000000-0000-0000-0000-0000000000a1', '72000000-0000-0000-0000-000000000001', '2025-2026', '2025-10-01', '2026-06-30', true),
  ('72000000-0000-0000-0000-0000000000a2', '72000000-0000-0000-0000-000000000001', '2026-2027', '2026-10-01', '2027-06-30', false);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, niveau_id, code, nom, capacite) VALUES
  ('72000000-0000-0000-0000-0000000000c1', '72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-0000000000a1', :'n_cm1', 'CM1-25', 'CM1', NULL),
  ('72000000-0000-0000-0000-0000000000c2', '72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-0000000000a1', :'n_cm2', 'CM2-25', 'CM2', NULL),
  ('72000000-0000-0000-0000-0000000000c3', '72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-0000000000a1', :'n_6e', '6E-25', '6e', NULL),
  ('72000000-0000-0000-0000-0000000000d1', '72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-0000000000a2', :'n_cm2', 'CM2-26', 'CM2', NULL),
  ('72000000-0000-0000-0000-0000000000d2', '72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-0000000000a2', :'n_6e', '6E-26', '6e A', 3),
  ('72000000-0000-0000-0000-0000000000d3', '72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-0000000000a2', :'n_5e', '5E-26', '5e', NULL);
INSERT INTO public.frais_scolarite_config (etablissement_id, annee_scolaire_id, niveau_id, montant_annuel, frais_inscription) VALUES
  ('72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-0000000000a1', NULL, 900000, 0),
  ('72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-0000000000a2', :'n_6e', 1200000, 100000),
  ('72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-0000000000a2', NULL, 1000000, 0);

SELECT pg_temp.creer_compte('224672000001', 'direction') AS dir_id \gset
SELECT pg_temp.creer_compte('224672000002', 'parent') AS p1 \gset
SELECT pg_temp.creer_compte('224672000003', 'eleve') AS s2 \gset
SELECT pg_temp.creer_compte('224672000004', 'eleve') AS s4 \gset
SELECT pg_temp.creer_compte('224672000005', 'parent') AS p5 \gset
SELECT pg_temp.creer_compte('224672000006', 'parent') AS p6 \gset
SELECT pg_temp.creer_compte('224672000007', 'parent') AS p7 \gset
SELECT pg_temp.creer_compte('224672000008', 'enseignant') AS ens \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_id', '72000000-0000-0000-0000-000000000001', 'direction'),
  (:'ens', '72000000-0000-0000-0000-000000000001', 'enseignant');

-- e1 : CM2 (parent p1, scolarité soldée) ; e2 : 6e, compte élève s2 ;
-- e3 : CM2 (parent p1, impayé) ; e4 : CM1, compte élève s4.
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id) VALUES
  ('72000000-0000-0000-0000-0000000000e1', '72000000-0000-0000-0000-000000000001', 'EMM-00001', 'BAH', 'Aïssatou', '2015-01-10', NULL),
  ('72000000-0000-0000-0000-0000000000e2', '72000000-0000-0000-0000-000000000001', 'EMM-00002', 'DIALLO', 'Mamadou', '2013-03-02', :'s2'),
  ('72000000-0000-0000-0000-0000000000e3', '72000000-0000-0000-0000-000000000001', 'EMM-00003', 'CAMARA', 'Fanta', '2015-05-20', NULL),
  ('72000000-0000-0000-0000-0000000000e4', '72000000-0000-0000-0000-000000000001', 'EMM-00004', 'SOW', 'Ibrahima', '2016-07-07', :'s4');
INSERT INTO public.inscriptions (id, etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('72000000-0000-0000-0000-0000000000f1', '72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-0000000000e1', '72000000-0000-0000-0000-0000000000c2', '72000000-0000-0000-0000-0000000000a1'),
  ('72000000-0000-0000-0000-0000000000f2', '72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-0000000000e2', '72000000-0000-0000-0000-0000000000c3', '72000000-0000-0000-0000-0000000000a1'),
  ('72000000-0000-0000-0000-0000000000f3', '72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-0000000000e3', '72000000-0000-0000-0000-0000000000c2', '72000000-0000-0000-0000-0000000000a1'),
  ('72000000-0000-0000-0000-0000000000f4', '72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-0000000000e4', '72000000-0000-0000-0000-0000000000c1', '72000000-0000-0000-0000-0000000000a1');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise) VALUES
  ('72000000-0000-0000-0000-000000000001', :'p1', '72000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true),
  ('72000000-0000-0000-0000-000000000001', :'p1', '72000000-0000-0000-0000-0000000000e3', 'parent', 'confirmee', true);
-- Scolarité 2025-2026 soldée pour e1, e2, e4 (e3 reste devoir 900 000).
INSERT INTO public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, montant, saisi_par)
SELECT '72000000-0000-0000-0000-000000000001', i.fiche_eleve_id, i.id, 900000, :'dir_id'
FROM public.inscriptions i WHERE i.id IN ('72000000-0000-0000-0000-0000000000f1', '72000000-0000-0000-0000-0000000000f2', '72000000-0000-0000-0000-0000000000f4');

-- ---------------------------------------------------------------------------
-- 1. Campagne
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'ens');
SELECT throws_ok(
  $$ SELECT public.enregistrer_campagne_inscription('72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-0000000000a2',
       current_date - 5, current_date - 5, current_date + 30) $$,
  '42501', NULL, 'un enseignant ne peut pas ouvrir la campagne');

SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.enregistrer_campagne_inscription('72000000-0000-0000-0000-000000000001', '72000000-0000-0000-0000-0000000000a2',
  current_date - 5, current_date - 5, current_date + 30, 7,
  '[{"code":"acte_naissance","libelle":"Acte de naissance","obligatoire":true},{"code":"bulletin","libelle":"Dernier bulletin","obligatoire":true}]',
  '{}', 'Dossiers complets uniquement', true) AS campagne \gset
SELECT is(public.places_restantes_inscription(:'campagne', :'n_6e'), 3, '6e : 3 places (capacité de la classe)');
SELECT is(public.places_restantes_inscription(:'campagne', :'n_5e'), NULL::int, '5e : capacité non renseignée → illimitée');

SELECT pg_temp.en_tant_que(:'p5');
SELECT is(jsonb_array_length(public.campagnes_inscription_ouvertes('emmaüs')), 1, 'un parent trouve la campagne publiée');

-- ---------------------------------------------------------------------------
-- 2. Réinscriptions
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'p1');
SELECT is(jsonb_array_length(public.reinscriptions_possibles()), 2, 'le parent voit ses deux enfants à réinscrire');
SELECT is((SELECT x->>'niveau_propose_nom' FROM jsonb_array_elements(public.reinscriptions_possibles()) x
           WHERE x->>'fiche_eleve_id' = '72000000-0000-0000-0000-0000000000e1'), '6e', 'niveau suivant proposé (CM2 → 6e)');

SELECT public.soumettre_demande_inscription('72000000-0000-0000-0000-0000000001d1', :'campagne',
  '{"type":"reinscription","fiche_eleve_id":"72000000-0000-0000-0000-0000000000e1","intention":"revient"}',
  'PROV-AB12-0001', now()) AS r1 \gset
SELECT is(:'r1'::jsonb->>'statut', 'acceptee', 'réinscription sans alerte : place réservée tout de suite');
SELECT is((:'r1'::jsonb->>'montant_a_regler')::numeric, 100000::numeric, 'frais d''inscription de la 6e à régler');
SELECT ok((:'r1'::jsonb->>'numero_dossier') LIKE 'INS-2026-%', 'numéro de dossier attribué par le serveur');

SELECT public.soumettre_demande_inscription('72000000-0000-0000-0000-0000000001d1', :'campagne',
  '{"type":"reinscription","fiche_eleve_id":"72000000-0000-0000-0000-0000000000e1","intention":"revient"}',
  'PROV-AB12-0001', now()) AS r1b \gset
SELECT is((:'r1b'::jsonb->>'deja_recue')::boolean, true, 'second envoi de la même clé : le dossier déjà reçu');
SELECT is((SELECT count(*)::int FROM public.demandes_inscription WHERE fiche_eleve_id = '72000000-0000-0000-0000-0000000000e1'), 1,
  'une seule demande pour l''élève');

SELECT public.soumettre_demande_inscription('72000000-0000-0000-0000-0000000001d3', :'campagne',
  '{"type":"reinscription","fiche_eleve_id":"72000000-0000-0000-0000-0000000000e3","intention":"revient"}') AS r3 \gset
SELECT is(:'r3'::jsonb->>'statut', 'a_examiner', 'impayé : à examiner par la Direction, pas bloqué');
SELECT is((SELECT (alertes->>'impaye')::numeric FROM public.demandes_inscription WHERE id = '72000000-0000-0000-0000-0000000001d3'),
  900000::numeric, 'le montant de l''impayé est signalé à la Direction');

SELECT pg_temp.en_tant_que(:'p6');
SELECT throws_ok(
  $$ SELECT public.soumettre_demande_inscription('72000000-0000-0000-0000-0000000001d1', '00000000-0000-0000-0000-000000000000', '{}') $$,
  '23505', 'CLE_DEJA_UTILISEE', 'la clé d''un autre compte est refusée');
SELECT is((SELECT count(*)::int FROM public.demandes_inscription), 0, 'un autre parent ne voit aucun dossier');

-- L'élève de 6e se réinscrit lui-même et paie lui-même (5e : frais nuls).
SELECT pg_temp.en_tant_que(:'s2');
SELECT public.soumettre_demande_inscription('72000000-0000-0000-0000-0000000001d2', :'campagne',
  '{"type":"reinscription","fiche_eleve_id":"72000000-0000-0000-0000-0000000000e2","intention":"revient","responsable_financier":"eleve"}') AS r2 \gset
SELECT is(:'r2'::jsonb->>'statut', 'inscrite', 'collégien autonome : frais nuls → inscrit directement');
RESET ROLE;
SELECT is((SELECT responsable_financier FROM public.fiches_eleves WHERE id = '72000000-0000-0000-0000-0000000000e2'), 'eleve',
  'payeur enregistré : l''élève lui-même');
SELECT is((SELECT c.niveau_id FROM public.inscriptions i JOIN public.classes c ON c.id = i.classe_id
           WHERE i.fiche_eleve_id = '72000000-0000-0000-0000-0000000000e2' AND i.annee_scolaire_id = '72000000-0000-0000-0000-0000000000a2'),
  :'n_5e'::uuid, 'inscrit en 5e pour la nouvelle année');
SET LOCAL ROLE authenticated;

SELECT pg_temp.en_tant_que(:'s4');
SELECT throws_ok(
  $$ SELECT public.soumettre_demande_inscription('72000000-0000-0000-0000-0000000001d4', (SELECT id FROM public.campagnes_inscription LIMIT 1),
       '{"type":"reinscription","fiche_eleve_id":"72000000-0000-0000-0000-0000000000e4"}') $$,
  '42501', 'ACCES_REFUSE', 'un élève de primaire ne se réinscrit pas lui-même');

-- ---------------------------------------------------------------------------
-- 3. Nouveaux élèves
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'p5');
SELECT public.soumettre_demande_inscription('72000000-0000-0000-0000-0000000002a1', :'campagne',
  format('{"type":"nouvelle","nom":"KOUROUMA","prenom":"Sékou","date_naissance":"2014-09-01","sexe":"M","niveau_id":"%s","ecole_precedente":"EP Kipé"}', :'n_6e')::jsonb,
  'PROV-CD34-0001', now() - interval '1 hour') AS n1 \gset
SELECT is(:'n1'::jsonb->>'statut', 'soumise', 'demande de nouvel élève : soumise à l''école');
SELECT ok(public.piece_inscription_deposable('72000000-0000-0000-0000-0000000002a1/acte_naissance-1.jpg'),
  'le demandeur peut déposer ses pièces');

SELECT pg_temp.en_tant_que(:'s4');
SELECT throws_ok(
  format($$ SELECT public.soumettre_demande_inscription('72000000-0000-0000-0000-0000000002a9', %L,
       '{"type":"nouvelle","nom":"X","prenom":"Y","date_naissance":"2017-01-01","niveau_id":"%s","demandeur_qualite":"eleve"}') $$,
       :'campagne', :'n_cm2'),
  '42501', 'PARENT_REQUIS_AVANT_COLLEGE', 'avant le collège, seul un parent fait la demande');
SELECT ok(NOT public.piece_inscription_deposable('72000000-0000-0000-0000-0000000002a1/acte_naissance-1.jpg'),
  'un autre compte ne peut pas déposer de pièce dans ce dossier');
SELECT ok(NOT public.piece_inscription_lisible('72000000-0000-0000-0000-0000000002a1/acte_naissance-1.jpg'),
  'ni lire les pièces du dossier');

SELECT pg_temp.en_tant_que(:'p1');
SELECT throws_ok(
  $$ SELECT public.traiter_demande_inscription('72000000-0000-0000-0000-0000000002a1', 'accepter') $$,
  '42501', NULL, 'un parent ne traite pas les dossiers');

SELECT pg_temp.en_tant_que(:'dir_id');
SELECT throws_ok(
  $$ SELECT public.traiter_demande_inscription('72000000-0000-0000-0000-0000000002a1', 'incomplete') $$,
  '22023', 'MOTIF_OBLIGATOIRE', 'pièces réclamées : le motif est obligatoire');
SELECT is(public.traiter_demande_inscription('72000000-0000-0000-0000-0000000002a1', 'incomplete', 'Acte de naissance et bulletin manquants')::text,
  'incomplete', 'la Direction réclame des pièces');

SELECT pg_temp.en_tant_que(:'p5');
SELECT public.deposer_piece_inscription('72000000-0000-0000-0000-0000000002a1', 'acte_naissance', '72000000-0000-0000-0000-0000000002a1/acte_naissance-1.jpg');
SELECT public.deposer_piece_inscription('72000000-0000-0000-0000-0000000002a1', 'bulletin', '72000000-0000-0000-0000-0000000002a1/bulletin-1.jpg');
SELECT is((SELECT statut::text FROM public.demandes_inscription WHERE id = '72000000-0000-0000-0000-0000000002a1'), 'soumise',
  'pièces obligatoires déposées : le dossier revient en examen');

SELECT pg_temp.en_tant_que(:'dir_id');
SELECT is(public.traiter_demande_inscription('72000000-0000-0000-0000-0000000002a1', 'accepter')::text, 'acceptee',
  'nouvel élève accepté (2e place de 6e réservée)');

-- Deux autres familles demandent la 6e : une place reste, puis complet.
SELECT pg_temp.en_tant_que(:'p6');
SELECT public.soumettre_demande_inscription('72000000-0000-0000-0000-0000000002a2', :'campagne',
  format('{"type":"nouvelle","nom":"BARRY","prenom":"Kadiatou","date_naissance":"2014-04-04","niveau_id":"%s"}', :'n_6e')::jsonb);
SELECT pg_temp.en_tant_que(:'p7');
SELECT public.soumettre_demande_inscription('72000000-0000-0000-0000-0000000002a3', :'campagne',
  format('{"type":"nouvelle","nom":"TOURE","prenom":"Alpha","date_naissance":"2014-02-02","niveau_id":"%s"}', :'n_6e')::jsonb);
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT is(public.traiter_demande_inscription('72000000-0000-0000-0000-0000000002a2', 'accepter')::text, 'acceptee', '3e et dernière place');
SELECT is(public.traiter_demande_inscription('72000000-0000-0000-0000-0000000002a3', 'accepter')::text, 'liste_attente',
  'niveau complet : liste d''attente (rang 1)');

-- La famille p6 retire sa demande : la place passe au premier en attente.
SELECT pg_temp.en_tant_que(:'p6');
SELECT public.retirer_demande_inscription('72000000-0000-0000-0000-0000000002a2');
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT is((SELECT statut::text FROM public.demandes_inscription WHERE id = '72000000-0000-0000-0000-0000000002a3'), 'acceptee',
  'retrait : le premier de la liste d''attente reçoit la place');

-- ---------------------------------------------------------------------------
-- 4. Expiration de l'offre
-- ---------------------------------------------------------------------------
RESET ROLE;
UPDATE public.demandes_inscription SET offre_expire_le = now() - interval '1 minute'
 WHERE id = '72000000-0000-0000-0000-0000000002a3';
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT is(public.expirer_offres_inscription(), 1, 'une offre échue est expirée');
RESET ROLE;
SELECT is((SELECT statut::text FROM public.demandes_inscription WHERE id = '72000000-0000-0000-0000-0000000002a3'), 'expiree',
  'la demande non réglée à temps est expirée');

-- ---------------------------------------------------------------------------
-- 5. Paiements : Orange Money puis guichet
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.enregistrer_identifiants_orange_money('72000000-0000-0000-0000-000000000001', 'client-72', 'secret-72', 'MERCHANTKEY0072', 'test');

SELECT pg_temp.en_tant_que(:'p1');
SELECT (public.initier_transaction_mobile_money('frais_inscription', '72000000-0000-0000-0000-0000000001d1', 5)) AS tx \gset
SELECT is((:'tx'::jsonb->>'montant')::numeric, 100000::numeric, 'montant fixé par l''école, jamais par le client');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT is(public.traiter_resultat_mobile_money((:'tx'::jsonb->>'transaction_id')::uuid, 'reussi', 100000, 'OM-72-001'), 'reussi',
  'paiement confirmé par l''opérateur');
RESET ROLE;
SELECT is((SELECT statut::text FROM public.demandes_inscription WHERE id = '72000000-0000-0000-0000-0000000001d1'), 'inscrite',
  'paiement reçu : réinscription confirmée');
SELECT is((SELECT e.montant FROM public.encaissements_scolarite e JOIN public.demandes_inscription d ON d.inscription_id = e.inscription_id
           WHERE d.id = '72000000-0000-0000-0000-0000000001d1' AND e.type_frais = 'inscription'), 100000::numeric,
  'encaissement des frais d''inscription créé (Orange Money)');

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.finaliser_inscription_guichet('72000000-0000-0000-0000-0000000002a1') AS insc_n1 \gset
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.relations_parent_eleve r JOIN public.inscriptions i ON i.fiche_eleve_id = r.fiche_eleve_id
           WHERE i.id = :'insc_n1' AND r.parent_profile_id = :'p5' AND r.statut = 'confirmee'), 1,
  'nouvel élève payé au guichet : fiche créée, parent lié');
SELECT ok((SELECT count(*) FROM public.notifications WHERE destinataire = :'p5' AND type = 'inscription_confirmee') = 1,
  'le parent est notifié de l''inscription');

-- ---------------------------------------------------------------------------
-- 6. Hors connexion : saisie avant la date limite, reçue après
-- ---------------------------------------------------------------------------
UPDATE public.campagnes_inscription SET date_limite = current_date - 2,
  ouverture_reinscriptions = current_date - 10, ouverture_nouvelles = current_date - 10 WHERE id = :'campagne';
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'p7');
SELECT is(public.soumettre_demande_inscription('72000000-0000-0000-0000-0000000002b1', :'campagne',
  format('{"type":"nouvelle","nom":"TOURE","prenom":"Mariama","date_naissance":"2014-06-06","niveau_id":"%s"}', :'n_5e')::jsonb,
  'PROV-EF56-0001', now() - interval '3 days')->>'statut', 'soumise',
  'saisie sans réseau avant la date limite : reçue après, toujours recevable');
SELECT throws_ok(
  format($$ SELECT public.soumettre_demande_inscription('72000000-0000-0000-0000-0000000002b2', %L,
       '{"type":"nouvelle","nom":"T","prenom":"M","date_naissance":"2014-06-06","niveau_id":"%s"}') $$, :'campagne', :'n_5e'),
  '22023', 'CAMPAGNE_TERMINEE', 'saisie faite après la date limite : refusée');

SELECT pg_temp.en_tant_que(:'dir_id');
SELECT is((public.tableau_campagne_inscription(:'campagne')->>'reinscrits')::int, 2, 'tableau de bord : 2 réinscrits');
SELECT * FROM finish();
ROLLBACK;
