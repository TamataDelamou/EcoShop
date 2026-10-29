-- ============================================================================
-- EcoShop — Test RLS 92 : postes du personnel (REG-22 partie C, migrations
-- 1566-1567)
-- ============================================================================
-- Chaque modèle de poste : ce qu'il lit et fait, et ce qui lui est refusé.
-- Un chauffeur ou un agent du portail ne lit ni notes ni encaissements.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  UPDATE public.profiles SET role_racine = p_role::public.role_racine, prenom = 'Test',
         nom = initcap(split_part(p_email, '@', 1)) WHERE id = v_id;
  RETURN v_id;
END $$;

-- Membre du personnel de l'école A sur le poste créé d'après le modèle.
CREATE OR REPLACE FUNCTION pg_temp.au_poste(p_email text, p_modele text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_id uuid := pg_temp.compte(p_email);
BEGIN
  INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement, poste_id)
  SELECT v_id, '92000000-0000-0000-0000-00000000000a', m.role, p.id
    FROM public.postes p JOIN public.modeles_postes m ON m.code = p.modele_code
   WHERE p.etablissement_id = '92000000-0000-0000-0000-00000000000a' AND p.modele_code = p_modele;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.lus() RETURNS text LANGUAGE sql AS $$
  SELECT format('notes=%s encaissements=%s presences=%s sanctions=%s',
    (SELECT count(*) FROM public.notes), (SELECT count(*) FROM public.encaissements_scolarite),
    (SELECT count(*) FROM public.presences), (SELECT count(*) FROM public.sanctions));
$$;

CREATE OR REPLACE FUNCTION pg_temp.codes(p_modele text) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce(string_agg(pp.permission_code, ',' ORDER BY pp.permission_code), '')
    FROM public.postes p LEFT JOIN public.poste_permissions pp ON pp.poste_id = p.id
   WHERE p.etablissement_id = '92000000-0000-0000-0000-00000000000a' AND p.modele_code = p_modele;
$$;

SELECT plan(65);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('92000000-0000-0000-0000-00000000000a', 'École A', 'ecole-a-92', 'GNF'),
  ('92000000-0000-0000-0000-00000000000b', 'École B', 'ecole-b-92', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('92000000-0000-0000-0000-0000000000a1', '92000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('92000000-0000-0000-0000-0000000000c1', '92000000-0000-0000-0000-00000000000a', '92000000-0000-0000-0000-0000000000a1', '6A', '6e A');

-- ---------------------------------------------------------------------------
-- 1. Modèles et postes par défaut
-- ---------------------------------------------------------------------------
SELECT is((SELECT count(*)::int FROM public.postes WHERE etablissement_id = '92000000-0000-0000-0000-00000000000a'
             AND modele_code IS NOT NULL), 15, 'nouvelle école : un poste par modèle (15, dont les 3 de REG-26)');
SELECT is(public.creer_postes_par_defaut('92000000-0000-0000-0000-00000000000a'), 0, 'rattrapage : aucun doublon');
SELECT is(pg_temp.codes('caissier'), 'scolarite.encaissement.gerer,scolarite.encaissement.lire', 'caissier : encaisser, lire les reçus');
SELECT is(pg_temp.codes('comptable'),
  'comptabilite.ecrire,comptabilite.lire,comptabilite.valider,paiement.mobile.gerer,scolarite.encaissement.lire,sms.credits.acheter',
  'comptable : comptabilité, lecture des encaissements, Orange Money et crédits SMS (REG-26), pas d''encaissement');
SELECT is(pg_temp.codes('agent_portail'), 'portail.scanner', 'agent du portail : scanner, rien d''autre');
SELECT is(pg_temp.codes('chauffeur'), '', 'chauffeur : aucun code (son circuit, par affectation)');
SELECT is(pg_temp.codes('bibliothecaire'), 'bibliotheque.gerer', 'bibliothécaire : la bibliothèque');
SELECT ok(pg_temp.codes('directeur_etudes') LIKE '%scolarite.note.lire%' AND pg_temp.codes('directeur_etudes') NOT LIKE '%encaissement%',
  'censeur : notes, pas d''encaissement');
SELECT is((SELECT count(*)::int FROM public.permissions WHERE code IN ('comm.voir_logs', 'comptabilite.export',
  'comptabilite.plan.gerer', 'etablissement.invitation.gerer', 'etablissement.membre.lire', 'marketplace.catalogue.lire',
  'marketplace.commande.creer', 'marketplace.profil_public.lier', 'marketplace.profil_public.lire',
  'marketplace.souscompte.gerer', 'observabilite.metriques.lire', 'observabilite.prediction.lire',
  'observabilite.sante.lire')), 0, 'les 13 codes sans effet sont retirés du catalogue');
SELECT is((SELECT count(*)::int FROM public.permissions WHERE code IN ('portail.scanner', 'comptabilite.valider',
  'rh.conge.valider', 'rh.contrat.gerer', 'rh.employe.voir', 'rh.paie.gerer')), 6, 'codes de métier présents, codes RH gardés (branchés)');

-- Personnes
SELECT pg_temp.compte('dir.a@exemple.org', 'direction') AS dir_a \gset
SELECT pg_temp.compte('dir.b@exemple.org', 'direction') AS dir_b \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_a', '92000000-0000-0000-0000-00000000000a', 'direction'),
  (:'dir_b', '92000000-0000-0000-0000-00000000000b', 'direction');
SELECT pg_temp.au_poste('chauffeur@exemple.org', 'chauffeur') AS chauffeur \gset
SELECT pg_temp.au_poste('portail@exemple.org', 'agent_portail') AS portail \gset
SELECT pg_temp.au_poste('biblio@exemple.org', 'bibliothecaire') AS biblio \gset
SELECT pg_temp.au_poste('caissier@exemple.org', 'caissier') AS caissier \gset
SELECT pg_temp.au_poste('comptable@exemple.org', 'comptable') AS comptable \gset
SELECT pg_temp.au_poste('secretaire@exemple.org', 'secretaire') AS secretaire \gset
SELECT pg_temp.au_poste('surveillant@exemple.org', 'surveillant_general') AS surveillant \gset
SELECT pg_temp.au_poste('censeur@exemple.org', 'directeur_etudes') AS censeur \gset

-- Une note, un encaissement, une absence, une sanction
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance) VALUES
  ('92000000-0000-0000-0000-0000000000e1', '92000000-0000-0000-0000-00000000000a', 'A92-1', 'BAH', 'Awa', '2014-01-01');
INSERT INTO public.inscriptions (id, etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('92000000-0000-0000-0000-0000000000b1', '92000000-0000-0000-0000-00000000000a', '92000000-0000-0000-0000-0000000000e1',
   '92000000-0000-0000-0000-0000000000c1', '92000000-0000-0000-0000-0000000000a1');
INSERT INTO public.evaluations (id, etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, type, libelle, statut) VALUES
  ('92000000-0000-0000-0000-0000000000d1', '92000000-0000-0000-0000-00000000000a', '92000000-0000-0000-0000-0000000000a1',
   '92000000-0000-0000-0000-0000000000c1', :'dir_a', 'controle', 'Contrôle', 'publiee');
INSERT INTO public.notes (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par) VALUES
  ('92000000-0000-0000-0000-00000000000a', '92000000-0000-0000-0000-0000000000d1', '92000000-0000-0000-0000-0000000000e1', 12, :'dir_a');
INSERT INTO public.presences (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, statut, saisi_par) VALUES
  ('92000000-0000-0000-0000-00000000000a', '92000000-0000-0000-0000-0000000000a1', '92000000-0000-0000-0000-0000000000c1',
   '92000000-0000-0000-0000-0000000000e1', 'absent', :'dir_a');
INSERT INTO public.sanctions (etablissement_id, fiche_eleve_id, annee_scolaire_id, type_sanction, motif, decisionnaire_id) VALUES
  ('92000000-0000-0000-0000-00000000000a', '92000000-0000-0000-0000-0000000000e1', '92000000-0000-0000-0000-0000000000a1',
   'avertissement', 'Retards', :'dir_a');
SELECT pg_temp.en_tant_que(:'dir_a');
INSERT INTO public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, montant, saisi_par) VALUES
  ('92000000-0000-0000-0000-00000000000a', '92000000-0000-0000-0000-0000000000e1', '92000000-0000-0000-0000-0000000000b1', 50000, :'dir_a');
SELECT set_config('request.jwt.claims', '{}', true);

-- ---------------------------------------------------------------------------
-- 2. Chaque poste : accès et refus
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

SELECT pg_temp.en_tant_que(:'chauffeur');
SELECT is(pg_temp.lus(), 'notes=0 encaissements=0 presences=0 sanctions=0', 'chauffeur : ni notes, ni encaissements, ni absences, ni sanctions');
SELECT throws_ok($$ SELECT public.calculer_moyenne_eleve('92000000-0000-0000-0000-0000000000e1') $$, '42501', NULL, 'chauffeur : moyenne refusée');
SELECT throws_ok($$ SELECT public.solde_scolarite('92000000-0000-0000-0000-0000000000b1') $$, '42501', NULL, 'chauffeur : solde refusé');
SELECT throws_ok($$ SELECT * FROM public.cartes_portail('92000000-0000-0000-0000-00000000000a') $$, '42501', NULL, 'chauffeur : pas le portail');
SELECT throws_ok($$ SELECT public.cloturer_periode('92000000-0000-0000-0000-00000000000a', current_date) $$, '42501', NULL,
  'chauffeur : pas de clôture');

SELECT pg_temp.en_tant_que(:'portail');
SELECT is(pg_temp.lus(), 'notes=0 encaissements=0 presences=0 sanctions=0', 'agent du portail : ni notes, ni encaissements, ni absences, ni sanctions');
SELECT lives_ok($$ SELECT * FROM public.cartes_portail('92000000-0000-0000-0000-00000000000a') $$, 'agent du portail : cartes à scanner');
SELECT lives_ok($$ SELECT public.signaler_portail('92000000-0000-0000-0000-00000000000a', 'Portail nord', 0) $$, 'agent du portail : signale son appareil');
SELECT throws_ok($$ SELECT public.presence_du_jour('92000000-0000-0000-0000-00000000000a', current_date) $$, '42501', NULL,
  'agent du portail : pas le tableau des absences');
SELECT throws_ok($$ SELECT public.calculer_moyenne_eleve('92000000-0000-0000-0000-0000000000e1') $$, '42501', NULL, 'agent du portail : moyenne refusée');
SELECT throws_ok($$ SELECT public.solde_scolarite('92000000-0000-0000-0000-0000000000b1') $$, '42501', NULL, 'agent du portail : solde refusé');
SELECT throws_ok($$ INSERT INTO public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, montant, saisi_par)
  VALUES ('92000000-0000-0000-0000-00000000000a', '92000000-0000-0000-0000-0000000000e1', '92000000-0000-0000-0000-0000000000b1', 1000, auth.uid()) $$,
  '42501', NULL, 'agent du portail : n''encaisse pas');

SELECT is(public.gere_presences('92000000-0000-0000-0000-00000000000a'), false,
  'compte sans rôle racine : gere_presences vaut faux, plus NULL (faille corrigée)');
SELECT is(public.est_admin_gsg(), false, 'compte sans rôle racine : est_admin_gsg vaut faux, plus NULL');

SELECT pg_temp.en_tant_que(:'biblio');
SELECT is(pg_temp.lus(), 'notes=0 encaissements=0 presences=0 sanctions=0', 'bibliothécaire : rien de la scolarité');
SELECT throws_ok($$ SELECT * FROM public.cartes_portail('92000000-0000-0000-0000-00000000000a') $$, '42501', NULL, 'bibliothécaire : pas le portail');

SELECT pg_temp.en_tant_que(:'caissier');
SELECT is(pg_temp.lus(), 'notes=0 encaissements=1 presences=0 sanctions=0', 'caissier : les encaissements, pas les notes');
SELECT lives_ok($$ SELECT public.solde_scolarite('92000000-0000-0000-0000-0000000000b1') $$, 'caissier : solde');
SELECT lives_ok($$ INSERT INTO public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, montant, saisi_par)
  VALUES ('92000000-0000-0000-0000-00000000000a', '92000000-0000-0000-0000-0000000000e1', '92000000-0000-0000-0000-0000000000b1', 1000, auth.uid()) $$,
  'caissier : encaisse');
SELECT throws_ok($$ SELECT public.cloturer_periode('92000000-0000-0000-0000-00000000000a', current_date) $$, '42501',
  'COMPTABLE_VALIDATION_REQUIS', 'caissier : pas de clôture');
SELECT throws_ok($$ SELECT public.calculer_moyenne_eleve('92000000-0000-0000-0000-0000000000e1') $$, '42501', NULL, 'caissier : moyenne refusée');

SELECT pg_temp.en_tant_que(:'comptable');
SELECT is(pg_temp.lus(), 'notes=0 encaissements=2 presences=0 sanctions=0', 'comptable : lit les encaissements, pas les notes');
SELECT throws_ok($$ INSERT INTO public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, montant, saisi_par)
  VALUES ('92000000-0000-0000-0000-00000000000a', '92000000-0000-0000-0000-0000000000e1', '92000000-0000-0000-0000-0000000000b1', 1000, auth.uid()) $$,
  '42501', NULL, 'comptable : n''encaisse pas (séparation des tâches)');
SELECT ok(public.est_comptable_validation('92000000-0000-0000-0000-00000000000a'), 'comptable : valide et clôture');

SELECT pg_temp.en_tant_que(:'secretaire');
SELECT is(pg_temp.lus(), 'notes=0 encaissements=0 presences=0 sanctions=0', 'secrétaire : ni notes ni encaissements');
SELECT ok(public.gere_inscriptions('92000000-0000-0000-0000-00000000000a'), 'secrétaire : gère les inscriptions');

SELECT pg_temp.en_tant_que(:'surveillant');
SELECT is(pg_temp.lus(), 'notes=0 encaissements=0 presences=1 sanctions=1', 'surveillant général : absences et sanctions, ni notes ni encaissements');
SELECT lives_ok($$ SELECT * FROM public.cartes_portail('92000000-0000-0000-0000-00000000000a') $$, 'surveillant général : le portail');

SELECT pg_temp.en_tant_que(:'censeur');
SELECT is(pg_temp.lus(), 'notes=1 encaissements=0 presences=0 sanctions=0', 'censeur : les notes, pas les encaissements');
SELECT is(public.calculer_moyenne_eleve('92000000-0000-0000-0000-0000000000e1'), 12.00::numeric, 'censeur : moyenne');

SELECT pg_temp.en_tant_que(:'dir_a');
SELECT is(pg_temp.lus(), 'notes=1 encaissements=2 presences=1 sanctions=1', 'direction : tout dans son école');
SELECT pg_temp.en_tant_que(:'dir_b');
SELECT is(pg_temp.lus(), 'notes=0 encaissements=0 presences=0 sanctions=0', 'direction d''une autre école : rien');

-- ---------------------------------------------------------------------------
-- 3. Séparation des tâches
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT throws_ok($$ SELECT public.creer_poste('92000000-0000-0000-0000-00000000000a', 'caissier', 'Caissier-comptable',
  array['scolarite.encaissement.gerer', 'comptabilite.valider']) $$, '23514', 'CUMUL_INTERDIT', 'encaisser et valider : refusé');
SELECT throws_ok(format($$ SELECT public.modifier_poste(%L, 'Caissier', array['scolarite.encaissement.gerer', 'comptabilite.ecrire']) $$,
  (SELECT id FROM public.postes WHERE etablissement_id = '92000000-0000-0000-0000-00000000000a' AND modele_code = 'caissier')),
  '23514', 'CUMUL_INTERDIT', 'encaisser et saisir la comptabilité : refusé');
RESET ROLE;
SELECT throws_ok($$ INSERT INTO public.poste_permissions (poste_id, permission_code)
  SELECT id, 'comptabilite.valider' FROM public.postes WHERE etablissement_id = '92000000-0000-0000-0000-00000000000a' AND modele_code = 'caissier' $$,
  '23514', 'CUMUL_INTERDIT', 'même par écriture directe du serveur : refusé');
SET LOCAL ROLE authenticated;

-- ---------------------------------------------------------------------------
-- 4. Postes personnalisés : direction seulement ; faille d'élévation fermée
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT public.creer_poste('92000000-0000-0000-0000-00000000000a', 'secretaire', 'Secrétaire principale',
  array['scolarite.inscription.gerer', 'etablissement.membre.gerer', 'etablissement.poste.gerer']) AS poste_perso \gset
SELECT is((SELECT count(*)::int FROM public.postes_etablissement('92000000-0000-0000-0000-00000000000a') WHERE nom = 'Secrétaire principale'
            AND modele_code = 'secretaire' AND 'etablissement.poste.gerer' = ANY (codes)), 1, 'direction : poste personnalisé à partir d''un modèle');
SELECT throws_ok($$ SELECT public.creer_poste('92000000-0000-0000-0000-00000000000a', NULL, 'Inventé', array['code.invente']) $$,
  '22023', 'DROIT_INCONNU', 'droit inconnu refusé');
SELECT lives_ok(format($$ SELECT public.modifier_membre('92000000-0000-0000-0000-00000000000a', %L, 'personnel', %L) $$, :'secretaire', :'poste_perso'),
  'direction : change le poste d''un membre');
SELECT throws_ok(format($$ SELECT public.modifier_membre('92000000-0000-0000-0000-00000000000a', %L, 'personnel', NULL) $$, :'chauffeur'),
  '22023', 'POSTE_OBLIGATOIRE', 'personnel sans poste : refusé');
SELECT throws_ok(format($$ SELECT public.modifier_membre('92000000-0000-0000-0000-00000000000a', %L, 'personnel', NULL) $$, :'dir_a'),
  '42501', 'MODIFICATION_SOI_MEME', 'la direction ne change pas son propre rôle');
SELECT is((SELECT count(*)::int FROM public.journal_audit WHERE entite = 'membre' AND entite_id = :'secretaire'), 1,
  'journal : changement de poste inscrit, lu par la direction');
SELECT pg_temp.en_tant_que(:'dir_b');
SELECT throws_ok($$ SELECT * FROM public.postes_etablissement('92000000-0000-0000-0000-00000000000a') $$, '42501', NULL,
  'direction d''une autre école : pas les postes');

-- La secrétaire a maintenant « gérer les membres » et « gérer les postes ».
SELECT pg_temp.en_tant_que(:'secretaire');
SELECT ok((SELECT count(*) FROM public.postes_etablissement('92000000-0000-0000-0000-00000000000a')) > 0, 'gérer les membres : voit les postes');
SELECT throws_ok($$ SELECT public.creer_poste('92000000-0000-0000-0000-00000000000a', NULL, 'Tout', array['scolarite.note.lire']) $$,
  '42501', 'PERMISSION_REFUSEE', 'gérer les postes ne suffit pas : seule la direction crée un poste');
SELECT throws_ok(format($$ INSERT INTO public.poste_permissions (poste_id, permission_code) VALUES (%L, 'scolarite.note.lire') $$, :'poste_perso'),
  '42501', NULL, 'élévation fermée : pas d''ajout direct de droit à son propre poste');
SELECT throws_ok(format($$ UPDATE public.etablissements_membres SET role_dans_etablissement = 'direction' WHERE profile_id = %L $$, :'secretaire'),
  '42501', NULL, 'élévation fermée : pas de rôle direction par écriture directe');
SELECT throws_ok(format($$ SELECT public.modifier_membre('92000000-0000-0000-0000-00000000000a', %L, 'direction', NULL) $$, :'caissier'),
  '42501', 'PERMISSION_REFUSEE', 'gérer les membres : ne nomme pas la direction');

-- ---------------------------------------------------------------------------
-- 5. Invitation : rôle personnel, poste obligatoire
-- ---------------------------------------------------------------------------
SELECT throws_ok($$ SELECT public.inviter_membre('92000000-0000-0000-0000-00000000000a', 'nouveau.dir@exemple.org', 'direction', NULL) $$,
  '42501', 'PERMISSION_REFUSEE', 'gérer les membres : n''invite pas la direction');
SELECT throws_ok($$ SELECT public.inviter_membre('92000000-0000-0000-0000-00000000000a', 'gardien@exemple.org', 'personnel', NULL) $$,
  '22023', 'POSTE_OBLIGATOIRE', 'personnel invité sans poste : refusé');
SELECT public.inviter_membre('92000000-0000-0000-0000-00000000000a', 'gardien@exemple.org', 'personnel',
  (SELECT id FROM public.postes WHERE etablissement_id = '92000000-0000-0000-0000-00000000000a' AND modele_code = 'agent_portail')) AS inv \gset
RESET ROLE;
SELECT pg_temp.compte('gardien@exemple.org') AS gardien \gset
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'gardien');
SELECT is(public.repondre_invitation(:'inv', true), 'acceptee', 'invitation acceptée');
RESET ROLE;
SELECT is((SELECT role_racine::text FROM public.profiles WHERE id = :'gardien'), 'personnel', 'compte au rôle « personnel »');
SELECT is((SELECT p.modele_code FROM public.etablissements_membres m JOIN public.postes p ON p.id = m.poste_id
            WHERE m.profile_id = :'gardien'), 'agent_portail', 'membre sur le poste « Agent du portail »');
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'gardien');
SELECT is(pg_temp.lus(), 'notes=0 encaissements=0 presences=0 sanctions=0', 'agent du portail invité : ni notes ni encaissements');

-- ---------------------------------------------------------------------------
-- 6. Codes RH branchés
-- ---------------------------------------------------------------------------
RESET ROLE;
INSERT INTO public.employes (etablissement_id, profile_id, matricule) VALUES
  ('92000000-0000-0000-0000-00000000000a', :'chauffeur', 'EMP-1');
UPDATE public.poste_permissions SET permission_code = permission_code WHERE false;
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT public.creer_poste('92000000-0000-0000-0000-00000000000a', NULL, 'Assistant RH', array['rh.employe.voir']) AS poste_rh \gset
SELECT public.modifier_membre('92000000-0000-0000-0000-00000000000a', :'biblio', 'personnel', :'poste_rh');
SELECT pg_temp.en_tant_que(:'biblio');
SELECT is((SELECT count(*)::int FROM public.employes), 1, 'rh.employe.voir : lit les fiches des employés');
SELECT pg_temp.en_tant_que(:'caissier');
SELECT is((SELECT count(*)::int FROM public.employes), 0, 'sans ce droit : aucune fiche');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
