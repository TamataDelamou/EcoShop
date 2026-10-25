-- ============================================================================
-- EcoShop — Test RLS 89 : code du compte et appareils à vérifier (REG-22
-- partie A, migration 1562)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- Session simulée : compte + identifiant de session du jeton.
CREATE OR REPLACE FUNCTION pg_temp.sur(p_uid uuid, p_session uuid, p_chemin text DEFAULT NULL) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated', 'session_id', p_session)::text, true),
         set_config('request.path', coalesce(p_chemin, ''), true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  UPDATE public.profiles SET role_racine = p_role::public.role_racine, prenom = initcap(split_part(p_email, '.', 1)),
         nom = 'Test' WHERE id = v_id;
  RETURN v_id;
END $$;

-- Nouvelle connexion (ligne dans auth.sessions).
CREATE OR REPLACE FUNCTION pg_temp.connexion(p_uid uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.sessions (id, user_id, created_at, updated_at) VALUES (v_id, p_uid, now(), now());
  RETURN v_id;
END $$;

SELECT plan(101);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('89000000-0000-0000-0000-00000000000a', 'École A', 'ecole-a-89', 'GNF'),
  ('89000000-0000-0000-0000-00000000000b', 'École B', 'ecole-b-89', 'GNF');
SELECT pg_temp.compte('awa.diallo@exemple.org') AS awa \gset
SELECT pg_temp.compte('dir.a@exemple.org', 'direction') AS dir_a \gset
SELECT pg_temp.compte('dir2.a@exemple.org', 'direction') AS dir2_a \gset
SELECT pg_temp.compte('dir.b@exemple.org', 'direction') AS dir_b \gset
SELECT pg_temp.compte('prof.a@exemple.org', 'enseignant') AS prof_a \gset
SELECT pg_temp.compte('admin.gsg@exemple.org', 'admin_gsg') AS gsg \gset
SELECT pg_temp.compte('sanscode.x@exemple.org') AS sans_code \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'awa', '89000000-0000-0000-0000-00000000000a', 'personnel'),
  (:'dir_a', '89000000-0000-0000-0000-00000000000a', 'direction'),
  (:'dir2_a', '89000000-0000-0000-0000-00000000000a', 'direction'),
  (:'dir_b', '89000000-0000-0000-0000-00000000000b', 'direction'),
  (:'prof_a', '89000000-0000-0000-0000-00000000000a', 'enseignant');

SELECT pg_temp.connexion(:'awa') AS s1 \gset
SELECT pg_temp.connexion(:'awa') AS s2 \gset
SELECT pg_temp.connexion(:'sans_code') AS sx \gset

-- ---------------------------------------------------------------------------
-- 1. Premier code : règles, comptes existants, aucune lecture directe
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'awa', :'s1');
SELECT throws_ok($$ SELECT public.definir_code_compte('123456') $$, '22023', 'CODE_EVIDENT', 'code évident 123456 refusé');
SELECT throws_ok($$ SELECT public.definir_code_compte('118811') $$, '22023', 'CODE_EVIDENT', 'deux chiffres seulement refusé');
SELECT throws_ok($$ SELECT public.definir_code_compte('345678') $$, '22023', 'CODE_EVIDENT', 'suite montante refusée');
SELECT throws_ok($$ SELECT public.definir_code_compte('987654') $$, '22023', 'CODE_EVIDENT', 'suite descendante refusée');
SELECT throws_ok($$ SELECT public.definir_code_compte('480480') $$, '22023', 'CODE_EVIDENT', 'motif répété refusé');
SELECT throws_ok($$ SELECT public.definir_code_compte('12345') $$, '22023', 'CODE_FORMAT', 'moins de 6 chiffres refusé');
SELECT is(public.definir_code_compte('739146') ->> 'a_un_code', 'true', 'code du compte défini');
SELECT throws_ok($$ SELECT public.definir_code_compte('739146') $$, '23505', 'CODE_DEJA_DEFINI', 'un seul premier code');
SELECT is((SELECT string_agg(methode, ',' ORDER BY methode) FROM public.sessions_appareils WHERE statut = 'approuvee'),
  'creation,existant', 'les deux sessions déjà ouvertes deviennent des appareils connus (personne n''est coupé)');
SELECT throws_ok($$ SELECT * FROM public.codes_compte $$, '42501', NULL, 'empreintes : aucune lecture directe');
SELECT throws_ok($$ SELECT * FROM public.essais_code_compte $$, '42501', NULL, 'essais : aucune lecture directe');
SELECT throws_ok($$ SELECT * FROM public.jetons_pas_moi $$, '42501', NULL, 'jetons : aucune lecture directe');
SELECT throws_ok($$ SELECT public.empreinte_code_compte('739146') $$, '42501', NULL, 'calcul d''empreinte non appelable');
SELECT throws_ok($$ UPDATE public.sessions_appareils SET statut = 'approuvee' $$, '42501', NULL,
  'aucune écriture directe sur les appareils');
RESET ROLE;
SELECT ok((SELECT empreinte LIKE '$2a$10$%' AND empreinte NOT LIKE '%739146%' FROM public.codes_compte WHERE profile_id = :'awa'),
  'empreinte bcrypt coût 10, sans le code en clair');
SELECT isnt((SELECT empreinte FROM public.codes_compte WHERE profile_id = :'awa'),
            extensions.crypt('739146', (SELECT empreinte FROM public.codes_compte WHERE profile_id = :'awa')),
  'empreinte poivrée : un bcrypt du seul code ne la retrouve pas (copie de la base inutile)');

-- ---------------------------------------------------------------------------
-- 2. Contrôle avant chaque requête
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.connexion(:'awa') AS s3 \gset
SELECT pg_temp.sur(:'awa', :'s3');
SELECT is(public.enregistrer_appareil('Samsung Galaxy A14', 'Android 14', '1.4.0') ->> 'statut', 'a_verifier',
  'nouvelle connexion d''un compte doté d''un code : appareil à vérifier');
SELECT pg_temp.sur(:'awa', :'s3', '/notes');
SELECT lives_ok($$ SELECT public.controle_requete() $$, 'interrupteur coupé : rien n''est bloqué (livraison sans risque)');
RESET ROLE;
UPDATE public.parametres_globaux SET valeur = 'true'::jsonb WHERE cle = 'code_compte_obligatoire';
SET LOCAL ROLE authenticated;
SELECT throws_ok($$ SELECT public.controle_requete() $$, '42501', 'APPAREIL_A_VERIFIER',
  'appareil à vérifier : lecture des tables refusée');
SELECT pg_temp.sur(:'awa', :'s3', '/rpc/calculer_moyenne_eleve');
SELECT throws_ok($$ SELECT public.controle_requete() $$, '42501', 'APPAREIL_A_VERIFIER', 'appareil à vérifier : fonctions refusées');
SELECT pg_temp.sur(:'awa', :'s3', '/rpc/changer_code_compte');
SELECT throws_ok($$ SELECT public.controle_requete() $$, '42501', 'APPAREIL_A_VERIFIER',
  'changer le code : pas depuis un appareil à vérifier');
SELECT pg_temp.sur(:'awa', :'s3', '/rpc/etat_appareil_bis');
SELECT throws_ok($$ SELECT public.controle_requete() $$, '42501', 'APPAREIL_A_VERIFIER', 'liste fermée : nom voisin refusé');
SELECT pg_temp.sur(:'awa', :'s3', '/rpc/etat_appareil');
SELECT lives_ok($$ SELECT public.controle_requete() $$, 'liste fermée : etat_appareil permis');
SELECT pg_temp.sur(:'awa', :'s3', '/rpc/verifier_code_compte');
SELECT lives_ok($$ SELECT public.controle_requete() $$, 'liste fermée : verifier_code_compte permis');
SELECT pg_temp.sur(:'awa', :'s3', '/rpc/finaliser_recuperation_code');
SELECT lives_ok($$ SELECT public.controle_requete() $$, 'liste fermée : finaliser_recuperation_code permis');
SELECT is(public.session_autorisee(), false, 'fichiers (Storage) : même refus pour l''appareil à vérifier');
SELECT pg_temp.sur(:'awa', :'s1', '/notes');
SELECT lives_ok($$ SELECT public.controle_requete() $$, 'appareil connu : tout permis');
SELECT pg_temp.sur(:'sans_code', :'sx', '/notes');
SELECT lives_ok($$ SELECT public.controle_requete() $$, 'compte sans code serveur : passe (mise en service sans coupure)');
SELECT pg_temp.sur(:'awa', gen_random_uuid(), '/notes');
SELECT throws_ok($$ SELECT public.controle_requete() $$, '42501', 'SESSION_REVOQUEE',
  'session déconnectée : refusée dès la requête suivante, jeton encore valable ou non');
SELECT pg_temp.sur(:'prof_a', :'s1', '/notes');
SELECT throws_ok($$ SELECT public.controle_requete() $$, '42501', 'SESSION_REVOQUEE', 'session d''un autre compte : refusée');
SELECT is(public.session_autorisee(), false, 'fichiers : session d''un autre compte refusée');
SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SELECT lives_ok($$ SELECT public.controle_requete() $$, 'visiteur sans compte : non concerné');
RESET ROLE;
UPDATE public.parametres_globaux SET valeur = 'false'::jsonb WHERE cle = 'controle_sessions';
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'sans_code', gen_random_uuid(), '/notes');
SELECT lives_ok($$ SELECT public.controle_requete() $$, 'interrupteur des sessions coupé : session déconnectée plus refusée');
SELECT pg_temp.sur(:'awa', gen_random_uuid(), '/notes');
SELECT throws_ok($$ SELECT public.controle_requete() $$, '42501', 'APPAREIL_A_VERIFIER',
  'interrupteur des sessions coupé : la vérification de l''appareil reste due');
RESET ROLE;
UPDATE public.parametres_globaux SET valeur = 'true'::jsonb WHERE cle = 'controle_sessions';
SELECT is((SELECT count(*)::int FROM public.notifications_sortantes
            WHERE modele = 'code_compte_nouvel_appareil' AND destinataire = 'awa.diallo@exemple.org'
              AND donnees ->> 'modele' = 'Samsung Galaxy A14' AND length(donnees ->> 'jeton_pas_moi') = 48), 1,
  'courriel « nouvel appareil » avec le modèle et un lien « Ce n''est pas moi »');

-- ---------------------------------------------------------------------------
-- 3. Code faux : 5 échecs → 1 h, puis 10 échecs → 24 h
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'awa', :'s3');
SELECT public.verifier_code_compte('000001'), public.verifier_code_compte('000002'), public.verifier_code_compte('000003');
SELECT is(public.verifier_code_compte('000004') ->> 'essais_restants', '1', '4 codes faux : un essai restant');
SELECT is(public.verifier_code_compte('000005') ->> 'resultat', 'bloque', '5e code faux : bloqué');
SELECT ok((public.etat_appareil() ->> 'bloque_jusqu_a')::timestamptz BETWEEN now() + interval '59 minutes' AND now() + interval '61 minutes',
  'premier palier : 1 heure');
SELECT throws_ok($$ SELECT public.verifier_code_compte('739146') $$, '42501', 'CODE_BLOQUE', 'bloqué : même le bon code est refusé');
RESET ROLE;
UPDATE public.essais_code_compte SET bloque_jusqu_a = now() - interval '1 second' WHERE profile_id = :'awa';
SET LOCAL ROLE authenticated;
SELECT public.verifier_code_compte('000006'), public.verifier_code_compte('000007'), public.verifier_code_compte('000008'),
       public.verifier_code_compte('000009');
SELECT is(public.verifier_code_compte('000010') ->> 'resultat', 'bloque', '10e code faux : bloqué de nouveau');
SELECT ok((public.etat_appareil() ->> 'bloque_jusqu_a')::timestamptz BETWEEN now() + interval '23 hours 59 minutes' AND now() + interval '24 hours 1 minute',
  'second palier : 24 heures');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications_sortantes WHERE modele = 'code_compte_appareils_bloques'
             AND destinataire = 'awa.diallo@exemple.org'), 2, 'un courriel à chaque blocage');
UPDATE public.essais_code_compte SET bloque_jusqu_a = now() - interval '1 second' WHERE profile_id = :'awa';
SET LOCAL ROLE authenticated;
SELECT is(public.verifier_code_compte('739146') ->> 'resultat', 'bon', 'bon code : appareil vérifié');
SELECT pg_temp.sur(:'awa', :'s3', '/notes');
SELECT lives_ok($$ SELECT public.controle_requete() $$, 'appareil vérifié : tout permis');
SELECT is((SELECT methode FROM public.sessions_appareils WHERE session_id = :'s3'), 'code', 'méthode retenue : code');
RESET ROLE;
SELECT is((SELECT echecs FROM public.essais_code_compte WHERE profile_id = :'awa'), 0, 'compteur remis à zéro');

-- ---------------------------------------------------------------------------
-- 4. Voie (a) : autorisation depuis un appareil connu
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.connexion(:'awa') AS s4 \gset
SELECT pg_temp.sur(:'awa', :'s4');
SELECT public.enregistrer_appareil('Tecno Spark 10', 'Android 13', '1.4.0');
SELECT public.demander_approbation_appareil() ->> 'id' AS dem4 \gset
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications WHERE destinataire = :'awa' AND type = 'appareil_a_autoriser'
             AND canal = 'push'), 1, 'notification push sur les appareils connus');
SET LOCAL ROLE authenticated;
SELECT throws_ok(format($$ SELECT public.approuver_appareil(%L) $$, :'dem4'), '42501', 'APPAREIL_A_VERIFIER',
  'un appareil à vérifier n''autorise pas (pas même lui-même)');
SELECT pg_temp.sur(:'awa', :'s1');
SELECT is(jsonb_array_length(public.etat_appareil() -> 'a_traiter'), 1, 'appareil connu : l''invite « Autoriser ce nouvel appareil ? »');
SELECT is(public.etat_appareil() -> 'a_traiter' -> 0 ->> 'modele', 'Tecno Spark 10', 'invite : modèle de l''appareil');
SELECT pg_temp.sur(:'prof_a', :'s1');
SELECT throws_ok(format($$ SELECT public.approuver_appareil(%L) $$, :'dem4'), '42501', 'SESSION_INCONNUE',
  'un autre compte n''autorise pas');
SELECT pg_temp.sur(:'awa', :'s1');
SELECT lives_ok(format($$ SELECT public.approuver_appareil(%L) $$, :'dem4'), 'appareil connu : « Autoriser »');
SELECT is((SELECT methode FROM public.sessions_appareils WHERE session_id = :'s4'), 'appareil_connu', 'nouvel appareil vérifié par un appareil connu');
SELECT throws_ok(format($$ SELECT public.approuver_appareil(%L) $$, :'dem4'), '22023', 'DEMANDE_EXPIREE', 'une demande ne sert qu''une fois');
SELECT pg_temp.connexion(:'awa') AS s5 \gset
SELECT pg_temp.sur(:'awa', :'s5');
SELECT public.enregistrer_appareil('Itel A70', 'Android 13', '1.4.0');
SELECT public.demander_approbation_appareil() ->> 'id' AS dem5 \gset
RESET ROLE;
UPDATE public.demandes_appareil SET echeance = now() - interval '1 second' WHERE id = :'dem5';
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'awa', :'s1');
SELECT throws_ok(format($$ SELECT public.approuver_appareil(%L) $$, :'dem5'), '22023', 'DEMANDE_EXPIREE', 'demande de plus de 10 minutes : expirée');

-- « Ce n'est pas moi » depuis l'appareil connu : session fermée, nouveaux appareils bloqués
SELECT pg_temp.sur(:'awa', :'s5');
SELECT public.demander_approbation_appareil() ->> 'id' AS dem5b \gset
SELECT pg_temp.sur(:'awa', :'s1');
SELECT lives_ok(format($$ SELECT public.refuser_appareil(%L) $$, :'dem5b'), 'appareil connu : « Ce n''est pas moi »');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM auth.sessions WHERE id = :'s5'), 0, 'la session de l''intrus est fermée');
SELECT is((SELECT motif_blocage || '/' || (bloque_jusqu_a = 'infinity')::text FROM public.essais_code_compte WHERE profile_id = :'awa'),
  'pas_moi/true', 'nouveaux appareils bloqués sans limite de durée');
SET LOCAL ROLE authenticated;
SELECT pg_temp.connexion(:'awa') AS s6 \gset
SELECT pg_temp.sur(:'awa', :'s6');
SELECT public.enregistrer_appareil('Inconnu', 'Android', '1.4.0');
SELECT throws_ok($$ SELECT public.verifier_code_compte('739146') $$, '42501', 'CODE_BLOQUE', 'après « Ce n''est pas moi » : bon code refusé');
SELECT throws_ok($$ SELECT public.demander_approbation_appareil() $$, '42501', 'CODE_BLOQUE', 'après « Ce n''est pas moi » : pas de demande d''autorisation');

-- Changement du code depuis un appareil connu : lève le blocage
SELECT throws_ok($$ SELECT public.changer_code_compte('739146', '582014') $$, '42501', 'APPAREIL_A_VERIFIER',
  'changer le code : refusé depuis un appareil à vérifier');
SELECT pg_temp.sur(:'awa', :'s1');
SELECT throws_ok($$ SELECT public.changer_code_compte('111110', '582014') $$, '42501', 'CODE_FAUX', 'changer le code : ancien code exigé');
SELECT throws_ok($$ SELECT public.changer_code_compte('739146', '654321') $$, '22023', 'CODE_EVIDENT', 'changer le code : code évident refusé');
SELECT is(public.changer_code_compte('739146', '582014') ->> 'version_code', '2', 'code changé : version 2');
SELECT pg_temp.sur(:'awa', :'s6');
SELECT is(public.verifier_code_compte('739146') ->> 'resultat', 'faux', 'ancien code : faux');
SELECT is(public.verifier_code_compte('582014') ->> 'resultat', 'bon', 'nouveau code : blocage levé, appareil vérifié');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications_sortantes WHERE modele = 'code_compte_change'
             AND destinataire = 'awa.diallo@exemple.org'), 1, 'courriel « code changé »');

-- ---------------------------------------------------------------------------
-- 5. Voie (b) : récupération par e-mail, 48 h, annulable
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.connexion(:'awa') AS s7 \gset
SELECT pg_temp.connexion(:'awa') AS s8 \gset
SELECT pg_temp.sur(:'awa', :'s7');
SELECT public.enregistrer_appareil('Nokia G21', 'Android 13', '1.4.0');
SELECT public.lancer_recuperation_code() ->> 'id' AS rec1 \gset
SELECT ok((SELECT echeance BETWEEN now() + interval '47 hours 59 minutes' AND now() + interval '48 hours 1 minute'
             FROM public.demandes_appareil WHERE id = :'rec1'), 'récupération : effective dans 48 h');
SELECT throws_ok($$ SELECT public.finaliser_recuperation_code('602417') $$, '22023', 'RECUPERATION_TROP_TOT', 'récupération : trop tôt refusée');
SELECT pg_temp.sur(:'awa', :'s8');
SELECT throws_ok($$ SELECT public.lancer_recuperation_code() $$, '23505', 'RECUPERATION_EN_COURS', 'une seule récupération à la fois');
SELECT throws_ok(format($$ SELECT public.annuler_recuperation(%L) $$, :'rec1'), '42501', 'APPAREIL_A_VERIFIER',
  'annulation : pas depuis un appareil à vérifier');
SELECT pg_temp.sur(:'awa', :'s1');
SELECT is(public.etat_appareil() -> 'a_traiter' -> 0 ->> 'type', 'recuperation', 'appareil connu : bandeau « récupération en cours »');
SELECT lives_ok(format($$ SELECT public.annuler_recuperation(%L) $$, :'rec1'), 'appareil connu : « Annuler »');
RESET ROLE;
UPDATE public.demandes_appareil SET echeance = now() - interval '1 second' WHERE id = :'rec1';
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'awa', :'s7');
SELECT throws_ok($$ SELECT public.finaliser_recuperation_code('602417') $$, 'P0002', 'AUCUNE_RECUPERATION', 'récupération annulée : rien à finaliser, même après 48 h');
SELECT public.lancer_recuperation_code() ->> 'id' AS rec2 \gset
RESET ROLE;
UPDATE public.demandes_appareil SET echeance = now() - interval '1 second' WHERE id = :'rec2';
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'awa', :'s8');
SELECT throws_ok($$ SELECT public.finaliser_recuperation_code('602417') $$, 'P0002', 'AUCUNE_RECUPERATION',
  'récupération mûre : seulement par l''appareil qui l''a lancée');
SELECT pg_temp.sur(:'awa', :'s7');
SELECT is(public.finaliser_recuperation_code('602417') ->> 'version_code', '3', 'récupération après 48 h : nouveau code, version 3');
SELECT is((SELECT methode FROM public.sessions_appareils WHERE session_id = :'s7'), 'recuperation', 'appareil vérifié par récupération');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications_sortantes WHERE destinataire = 'awa.diallo@exemple.org'
             AND modele IN ('code_compte_recuperation_lancee', 'code_compte_recuperation_terminee')), 3,
  'courriels au début (deux fois) et à la fin');

-- ---------------------------------------------------------------------------
-- 6. Voie (c) : déblocage à l'école
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.connexion(:'dir_a') AS sd \gset
SELECT pg_temp.connexion(:'dir2_a') AS sd2 \gset
SELECT pg_temp.sur(:'dir2_a', :'sd2');
SELECT public.definir_code_compte('914273');
SELECT pg_temp.sur(:'dir_a', :'sd');
SELECT public.definir_code_compte('306158');
SELECT throws_ok(format($$ SELECT public.debloquer_code_membre(%L, 'Téléphone perdu', '89000000-0000-0000-0000-00000000000a') $$, :'dir_a'),
  '42501', 'DEBLOCAGE_SOI_MEME', 'personne ne se débloque soi-même');
SELECT throws_ok(format($$ SELECT public.debloquer_code_membre(%L, 'Téléphone perdu', '89000000-0000-0000-0000-00000000000a') $$, :'dir2_a'),
  '42501', 'DEBLOCAGE_DIRECTION_PAR_GSG', 'un membre de la direction ne débloque pas un autre membre de la direction');
SELECT throws_ok(format($$ SELECT public.debloquer_code_membre(%L, '', '89000000-0000-0000-0000-00000000000a') $$, :'awa'),
  '22023', 'MOTIF_OBLIGATOIRE', 'motif obligatoire');
SELECT throws_ok(format($$ SELECT public.debloquer_code_membre(%L, 'Téléphone perdu', '89000000-0000-0000-0000-00000000000b') $$, :'awa'),
  '42501', 'PERMISSION_REFUSEE', 'direction : pas au nom d''une autre école');
SELECT lives_ok(format($$ SELECT public.debloquer_code_membre(%L, 'Présente au bureau, carte vérifiée', '89000000-0000-0000-0000-00000000000a') $$, :'awa'),
  'direction : débloque un membre du personnel présent');
SELECT pg_temp.sur(:'dir_b', :'sd');
SELECT throws_ok(format($$ SELECT public.debloquer_code_membre(%L, 'Téléphone perdu', '89000000-0000-0000-0000-00000000000b') $$, :'awa'),
  '42501', 'SESSION_INCONNUE', 'jeton d''une autre session : refusé');
SELECT pg_temp.connexion(:'dir_b') AS sdb \gset
SELECT pg_temp.sur(:'dir_b', :'sdb');
SELECT throws_ok(format($$ SELECT public.debloquer_code_membre(%L, 'Téléphone perdu', '89000000-0000-0000-0000-00000000000b') $$, :'awa'),
  '42501', 'PERMISSION_REFUSEE', 'direction d''une autre école : refusée');
SELECT pg_temp.connexion(:'prof_a') AS sp \gset
SELECT pg_temp.sur(:'prof_a', :'sp');
SELECT throws_ok(format($$ SELECT public.debloquer_code_membre(%L, 'Téléphone perdu', '89000000-0000-0000-0000-00000000000a') $$, :'awa'),
  '42501', 'PERMISSION_REFUSEE', 'un enseignant ne débloque pas');
SELECT pg_temp.connexion(:'awa') AS s9 \gset
SELECT pg_temp.sur(:'awa', :'s9');
SELECT public.enregistrer_appareil('Samsung Galaxy A05', 'Android 14', '1.4.0');
SELECT is(public.finaliser_recuperation_code('520731') ->> 'version_code', '4', 'dans les 30 minutes : nouveau code choisi sur le nouvel appareil');
SELECT is((SELECT methode FROM public.sessions_appareils WHERE session_id = :'s9'), 'ecole', 'appareil vérifié à l''école');
SELECT throws_ok($$ SELECT public.finaliser_recuperation_code('629417') $$, 'P0002', 'AUCUNE_RECUPERATION', 'déblocage à usage unique');
SELECT pg_temp.connexion(:'gsg') AS sg \gset
SELECT pg_temp.sur(:'gsg', :'sg');
SELECT lives_ok(format($$ SELECT public.debloquer_code_membre(%L, 'Identité vérifiée par visioconférence') $$, :'dir2_a'),
  'administrateur GSG : débloque un membre de la direction');
RESET ROLE;
UPDATE public.demandes_appareil SET echeance = now() - interval '1 second' WHERE profile_id = :'dir2_a' AND type = 'ecole';
SET LOCAL ROLE authenticated;
SELECT pg_temp.connexion(:'dir2_a') AS sd3 \gset
SELECT pg_temp.sur(:'dir2_a', :'sd3');
SELECT throws_ok($$ SELECT public.finaliser_recuperation_code('629417') $$, 'P0002', 'AUCUNE_RECUPERATION', 'déblocage de plus de 30 minutes : expiré');
SELECT pg_temp.sur(:'dir_a', :'sd');
SELECT is((SELECT count(*)::int FROM public.journal_audit WHERE entite = 'code_compte' AND entite_id = :'awa'), 1,
  'journal : la direction voit le déblocage qu''elle a fait');
SELECT is((SELECT nouvelle_valeur ->> 'motif' FROM public.journal_audit WHERE entite = 'code_compte' AND entite_id = :'awa'),
  'Présente au bureau, carte vérifiée', 'journal : motif conservé');
SELECT pg_temp.sur(:'prof_a', :'sp');
SELECT is((SELECT count(*)::int FROM public.journal_audit WHERE entite = 'code_compte'), 0, 'journal : un enseignant ne voit pas les déblocages');

-- ---------------------------------------------------------------------------
-- 7. Lien « Ce n'est pas moi » du courriel
-- ---------------------------------------------------------------------------
RESET ROLE;
SELECT donnees ->> 'jeton_pas_moi' AS jeton FROM public.notifications_sortantes
 WHERE modele = 'code_compte_nouvel_appareil' AND donnees ->> 'modele' = 'Samsung Galaxy A05' \gset
SET LOCAL ROLE authenticated;
SELECT throws_ok(format($$ SELECT public.pas_moi_par_jeton(%L) $$, :'jeton'), '42501', NULL, 'lien : jamais appelable par un compte');
RESET ROLE;
SET LOCAL ROLE service_role;
SELECT is(public.pas_moi_par_jeton('jeton-invente'), 'invalide', 'lien : jeton inventé sans effet');
SELECT is(public.pas_moi_par_jeton(:'jeton'), 'fait', 'lien valable : pris en compte');
SELECT is(public.pas_moi_par_jeton(:'jeton'), 'deja_fait', 'lien : usage unique');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM auth.sessions WHERE id = :'s9'), 0, 'lien : la session signalée est fermée');
SELECT is((SELECT motif_blocage FROM public.essais_code_compte WHERE profile_id = :'awa'), 'pas_moi', 'lien : nouveaux appareils bloqués');
UPDATE public.jetons_pas_moi SET expire_le = now() - interval '1 second', utilise_le = NULL;
SET LOCAL ROLE service_role;
SELECT is(public.pas_moi_par_jeton(:'jeton'), 'invalide', 'lien de plus de 7 jours : sans effet');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
