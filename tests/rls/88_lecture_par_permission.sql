-- ============================================================================
-- EcoShop — Test RLS 88 : lecture par permission (REG-22 partie C, étape 1,
-- migration 1561)
-- ============================================================================
-- Un chauffeur ou un agent du portail, membres du personnel sans poste
-- pédagogique ni financier, ne lisent ni notes, ni bulletins, ni absences,
-- ni sanctions, ni encaissements, ni soldes, ni risques, ni rapports, ni
-- journal d'audit. Chaque poste lit son domaine, et seulement lui. La
-- direction lit tout dans son école, rien dans une autre. La famille garde
-- ce qu'elle voyait.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  UPDATE public.profiles SET role_racine = p_role::public.role_racine, prenom = 'Test',
         nom = initcap(split_part(p_email, '@', 1))
   WHERE id = v_id;
  RETURN v_id;
END $$;

-- Membre du personnel de l'école A, avec un poste portant les codes donnés.
CREATE OR REPLACE FUNCTION pg_temp.personnel(p_email text, p_poste text, p_codes text[])
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid := pg_temp.compte(p_email); v_poste uuid;
BEGIN
  INSERT INTO public.postes (etablissement_id, nom) VALUES ('88000000-0000-0000-0000-00000000000a', p_poste)
  RETURNING id INTO v_poste;
  INSERT INTO public.poste_permissions (poste_id, permission_code) SELECT v_poste, unnest(p_codes);
  INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement, poste_id)
  VALUES (v_id, '88000000-0000-0000-0000-00000000000a', 'personnel', v_poste);
  RETURN v_id;
END $$;

-- Nombre de lignes lisibles, par table sensible, pour l'appelant courant.
CREATE OR REPLACE FUNCTION pg_temp.lus() RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'notes', (SELECT count(*) FROM public.notes),
    'evaluations', (SELECT count(*) FROM public.evaluations),
    'bulletins', (SELECT count(*) FROM public.bulletins),
    'appreciations', (SELECT count(*) FROM public.appreciations),
    'presences', (SELECT count(*) FROM public.presences),
    'retards', (SELECT count(*) FROM public.retards),
    'sanctions', (SELECT count(*) FROM public.sanctions),
    'alertes', (SELECT count(*) FROM public.alertes_decrochage),
    'encaissements', (SELECT count(*) FROM public.encaissements_scolarite),
    'statistiques', (SELECT count(*) FROM public.statistiques_agregats),
    'rapports', (SELECT count(*) FROM public.rapports),
    'indicateurs', (SELECT count(*) FROM public.indicateurs_cles),
    'proclamations', (SELECT count(*) FROM public.proclamations_classes),
    'journal', (SELECT count(*) FROM public.journal_audit
                 WHERE etablissement_id = '88000000-0000-0000-0000-00000000000a'));
$$;

-- Toutes les lectures et tous les calculs refusés à un membre sans droit.
CREATE OR REPLACE FUNCTION pg_temp.aucun_acces(p_uid uuid, p_qui text)
RETURNS SETOF text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.en_tant_que(p_uid);
  RETURN NEXT is(pg_temp.lus(), jsonb_build_object(
    'notes', 0, 'evaluations', 0, 'bulletins', 0, 'appreciations', 0, 'presences', 0,
    'retards', 0, 'sanctions', 0, 'alertes', 0, 'encaissements', 0, 'statistiques', 0,
    'rapports', 0, 'indicateurs', 0, 'proclamations', 0, 'journal', 0),
    p_qui || ' : aucune ligne de notes, bulletins, absences, sanctions, encaissements, risques, rapports ni journal');
  RETURN NEXT throws_ok($q$ SELECT public.calculer_moyenne_eleve('88000000-0000-0000-0000-0000000000e1') $q$,
    '42501', 'PERMISSION_REFUSEE', p_qui || ' : moyenne d''un élève refusée');
  RETURN NEXT throws_ok($q$ SELECT public.calculer_moyenne_classe('88000000-0000-0000-0000-0000000000c1') $q$,
    '42501', 'PERMISSION_REFUSEE', p_qui || ' : moyenne de classe refusée');
  RETURN NEXT is((SELECT count(*)::int FROM public.classer_eleves_classe('88000000-0000-0000-0000-0000000000c1')), 0,
    p_qui || ' : classement vide');
  RETURN NEXT throws_ok($q$ SELECT public.calculer_score_decrochage('88000000-0000-0000-0000-0000000000e1', '88000000-0000-0000-0000-0000000000a1') $q$,
    '42501', 'PERMISSION_REFUSEE', p_qui || ' : score de décrochage refusé');
  RETURN NEXT throws_ok($q$ SELECT public.analyse_comportement('88000000-0000-0000-0000-0000000000e1', '88000000-0000-0000-0000-0000000000a1') $q$,
    '42501', 'PERMISSION_REFUSEE', p_qui || ' : analyse du comportement refusée');
  RETURN NEXT throws_ok($q$ SELECT public.recommander_sanction_educative('88000000-0000-0000-0000-0000000000e1', '88000000-0000-0000-0000-0000000000a1') $q$,
    '42501', 'PERMISSION_REFUSEE', p_qui || ' : recommandation de sanction refusée');
  RETURN NEXT is(public.risque_reussite_actuel('88000000-0000-0000-0000-0000000000e1'), NULL,
    p_qui || ' : risque de réussite non lu');
  RETURN NEXT throws_ok($q$ SELECT public.risque_classe('88000000-0000-0000-0000-0000000000c1') $q$,
    '42501', 'ACCES_REFUSE', p_qui || ' : risque de la classe refusé');
  RETURN NEXT throws_ok($q$ SELECT public.solde_scolarite('88000000-0000-0000-0000-0000000000b1') $q$,
    '42501', 'PERMISSION_REFUSEE', p_qui || ' : solde de scolarité refusé');
  RETURN NEXT throws_ok($q$ SELECT public.rapprochement_mobile_money('88000000-0000-0000-0000-00000000000a') $q$,
    '42501', 'ACCES_REFUSE', p_qui || ' : rapprochement des paiements mobiles refusé');
  RETURN NEXT throws_ok($q$ SELECT public.consolider_indicateurs_etablissement('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000a1') $q$,
    '42501', 'ACCES_REFUSE', p_qui || ' : indicateurs de l''école refusés');
  RETURN NEXT throws_ok($q$ SELECT public.detecter_anomalies('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000a1') $q$,
    '42501', 'ACCES_REFUSE', p_qui || ' : détection d''anomalies refusée');
  RETURN NEXT throws_ok($q$ SELECT public.generer_resume_executif('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000a1') $q$,
    '42501', 'ACCES_REFUSE', p_qui || ' : résumé de direction refusé');
  RETURN NEXT throws_ok($q$ SELECT public.predire_presence('88000000-0000-0000-0000-00000000000a', current_date) $q$,
    '42501', 'ACCES_REFUSE', p_qui || ' : prévision de présence refusée');
  RETURN NEXT throws_ok($q$ SELECT * FROM public.predire_pics_charge('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000a1') $q$,
    '42501', 'ACCES_REFUSE', p_qui || ' : pics de charge refusés');
  RETURN NEXT throws_ok($q$ SELECT public.initier_transaction_cinetpay('licence_pro_etablissement', '88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000a1', NULL, NULL) $q$,
    '42501', 'ACCES_REFUSE', p_qui || ' : paiement de la licence de l''école refusé');
END $$;

SELECT plan(103);

-- ---------------------------------------------------------------------------
-- Données : écoles A et B, classes C1 (prof_c1 titulaire) et C2 (prof_c2)
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('88000000-0000-0000-0000-00000000000a', 'École A', 'ecole-a-88', 'GNF'),
  ('88000000-0000-0000-0000-00000000000b', 'École B', 'ecole-b-88', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('88000000-0000-0000-0000-0000000000a1', '88000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('88000000-0000-0000-0000-0000000000c1', '88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000a1', '6A', '6e A'),
  ('88000000-0000-0000-0000-0000000000c2', '88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000a1', '6B', '6e B');

SELECT pg_temp.compte('dir.a@exemple.org', 'direction') AS dir_a \gset
SELECT pg_temp.compte('dir.b@exemple.org', 'direction') AS dir_b \gset
SELECT pg_temp.compte('prof.c1@exemple.org', 'enseignant') AS prof_c1 \gset
SELECT pg_temp.compte('prof.c2@exemple.org', 'enseignant') AS prof_c2 \gset
SELECT pg_temp.compte('p1@exemple.org', 'parent') AS p1 \gset
SELECT pg_temp.compte('el1@exemple.org', 'eleve') AS el1 \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_a', '88000000-0000-0000-0000-00000000000a', 'direction'),
  (:'dir_b', '88000000-0000-0000-0000-00000000000b', 'direction'),
  (:'prof_c1', '88000000-0000-0000-0000-00000000000a', 'enseignant'),
  (:'prof_c2', '88000000-0000-0000-0000-00000000000a', 'enseignant');
UPDATE public.classes SET enseignant_principal_id = :'prof_c1' WHERE id = '88000000-0000-0000-0000-0000000000c1';
INSERT INTO public.affectations_enseignants (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id) VALUES
  ('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000a1', :'prof_c1', '88000000-0000-0000-0000-0000000000c1'),
  ('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000a1', :'prof_c2', '88000000-0000-0000-0000-0000000000c2');

-- Postes (le chauffeur et l'agent du portail n'ont aucun code de lecture).
SELECT pg_temp.personnel('chauffeur@exemple.org', 'Chauffeur', array[]::text[]) AS chauffeur \gset
SELECT pg_temp.personnel('portail@exemple.org', 'Agent du portail', array['scolarite.presence.gerer']::text[]) AS portail_presence \gset
SELECT pg_temp.personnel('portail2@exemple.org', 'Agent du portail', array[]::text[]) AS portail \gset
SELECT pg_temp.personnel('biblio@exemple.org', 'Bibliothécaire', array['bibliotheque.gerer']) AS biblio \gset
SELECT pg_temp.personnel('censeur@exemple.org', 'Censeur', array['scolarite.note.lire']) AS censeur \gset
SELECT pg_temp.personnel('surveillant@exemple.org', 'Surveillant général',
  array['scolarite.presence.lire', 'scolarite.sanction.lire']) AS surveillant \gset
SELECT pg_temp.personnel('caissier@exemple.org', 'Caissier',
  array['scolarite.encaissement.gerer', 'scolarite.encaissement.lire']) AS caissier \gset
SELECT pg_temp.personnel('secretaire@exemple.org', 'Secrétaire', array['scolarite.inscription.gerer']) AS secretaire \gset
SELECT pg_temp.personnel('auditeur@exemple.org', 'Contrôleur', array['audit.journal.lire']) AS auditeur \gset

INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id) VALUES
  ('88000000-0000-0000-0000-0000000000e1', '88000000-0000-0000-0000-00000000000a', 'A88-1', 'BAH', 'Awa', '2014-01-01', :'el1');
INSERT INTO public.inscriptions (id, etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('88000000-0000-0000-0000-0000000000b1', '88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000e1',
   '88000000-0000-0000-0000-0000000000c1', '88000000-0000-0000-0000-0000000000a1');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise) VALUES
  ('88000000-0000-0000-0000-00000000000a', :'p1', '88000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true);

-- Une ligne par domaine sensible, toutes au sujet de l'élève e1 (classe C1).
INSERT INTO public.evaluations (id, etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, type, libelle, statut, publie_le) VALUES
  ('88000000-0000-0000-0000-0000000000d1', '88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000a1',
   '88000000-0000-0000-0000-0000000000c1', :'prof_c1', 'controle', 'Contrôle 1', 'publiee', now());
INSERT INTO public.notes (etablissement_id, evaluation_id, fiche_eleve_id, valeur, saisi_par) VALUES
  ('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000d1', '88000000-0000-0000-0000-0000000000e1', 14, :'prof_c1');
INSERT INTO public.bulletins (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, statut) VALUES
  ('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000a1', '88000000-0000-0000-0000-0000000000c1',
   '88000000-0000-0000-0000-0000000000e1', 'publie');
INSERT INTO public.appreciations (etablissement_id, fiche_eleve_id, annee_scolaire_id, texte, redige_par) VALUES
  ('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000e1', '88000000-0000-0000-0000-0000000000a1',
   'Bon trimestre.', :'prof_c1');
INSERT INTO public.presences (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, statut, saisi_par) VALUES
  ('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000a1', '88000000-0000-0000-0000-0000000000c1',
   '88000000-0000-0000-0000-0000000000e1', 'absent', :'prof_c1');
INSERT INTO public.retards (etablissement_id, fiche_eleve_id, annee_scolaire_id, minutes_retard, saisi_par) VALUES
  ('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000e1', '88000000-0000-0000-0000-0000000000a1', 10, :'prof_c1');
INSERT INTO public.sanctions (etablissement_id, fiche_eleve_id, annee_scolaire_id, type_sanction, motif, decisionnaire_id) VALUES
  ('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000e1', '88000000-0000-0000-0000-0000000000a1',
   'avertissement', 'Bavardages répétés', :'dir_a');
INSERT INTO public.alertes_decrochage (etablissement_id, fiche_eleve_id, annee_scolaire_id, score, statut) VALUES
  ('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000e1', '88000000-0000-0000-0000-0000000000a1', 0.7, 'transmise');
INSERT INTO public.statistiques_agregats (etablissement_id, annee_scolaire_id, fiche_eleve_id, type_agregat, valeur_numeric) VALUES
  ('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000a1', '88000000-0000-0000-0000-0000000000e1',
   'risque_reussite', 0.42);
INSERT INTO public.rapports (etablissement_id, annee_scolaire_id, classe_id, type, statut) VALUES
  ('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000a1', '88000000-0000-0000-0000-0000000000c1',
   'releve_notes', 'genere');
INSERT INTO public.indicateurs_cles (etablissement_id, annee_scolaire_id, code, valeur_numeric) VALUES
  ('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000a1', 'effectifs', 1);
INSERT INTO public.proclamations_classes (etablissement_id, classe_id, annee_scolaire_id, proclamee_par) VALUES
  ('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000c1', '88000000-0000-0000-0000-0000000000a1', :'dir_a');
-- Le reçu prend l'auteur de la session (contrôle anti-usurpation).
SELECT pg_temp.en_tant_que(:'dir_a');
INSERT INTO public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, montant, saisi_par) VALUES
  ('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000e1', '88000000-0000-0000-0000-0000000000b1', 50000, :'dir_a');
-- Une entrée d'audit d'inscription (passage boursier).
UPDATE public.inscriptions SET boursier = true WHERE id = '88000000-0000-0000-0000-0000000000b1';
SELECT set_config('request.jwt.claims', '{}', true);

SELECT is((SELECT count(*)::int FROM public.journal_audit WHERE etablissement_id = '88000000-0000-0000-0000-00000000000a'
             AND entite = 'inscription'), 1, 'préalable : une entrée d''audit d''inscription');

-- ---------------------------------------------------------------------------
-- 1. Chauffeur, agent du portail, bibliothécaire : rien
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.aucun_acces(:'chauffeur', 'chauffeur');
SELECT pg_temp.aucun_acces(:'portail', 'agent du portail');
SELECT pg_temp.aucun_acces(:'biblio', 'bibliothécaire');
SELECT pg_temp.aucun_acces(:'dir_b', 'direction d''une autre école');

-- Un agent du portail chargé de l'appel (presence.gerer) voit les absences
-- et retards, rien d'autre.
SELECT pg_temp.en_tant_que(:'portail_presence');
SELECT is(pg_temp.lus(), '{"notes":0,"evaluations":0,"bulletins":0,"appreciations":0,"presences":1,"retards":1,"sanctions":0,
  "alertes":1,"encaissements":0,"statistiques":1,"rapports":0,"indicateurs":0,"proclamations":0,"journal":0}'::jsonb,
  'agent du portail chargé de l''appel : absences, retards et suivi (alerte, risque), ni notes ni encaissements');
SELECT throws_ok($$ SELECT public.calculer_moyenne_eleve('88000000-0000-0000-0000-0000000000e1') $$,
  '42501', 'PERMISSION_REFUSEE', 'agent du portail chargé de l''appel : moyenne refusée');
SELECT throws_ok($$ SELECT public.solde_scolarite('88000000-0000-0000-0000-0000000000b1') $$,
  '42501', 'PERMISSION_REFUSEE', 'agent du portail chargé de l''appel : solde refusé');

-- ---------------------------------------------------------------------------
-- 2. Chaque poste lit son domaine
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'censeur');
SELECT is(pg_temp.lus(), '{"notes":1,"evaluations":1,"bulletins":0,"appreciations":0,"presences":0,"retards":0,"sanctions":0,
  "alertes":1,"encaissements":0,"statistiques":1,"rapports":0,"indicateurs":0,"proclamations":0,"journal":0}'::jsonb,
  'censeur (notes) : notes et évaluations, ni absences, ni sanctions, ni encaissements');
SELECT is(public.calculer_moyenne_eleve('88000000-0000-0000-0000-0000000000e1'), 14.00::numeric, 'censeur : moyenne exacte');
SELECT is(public.calculer_moyenne_classe('88000000-0000-0000-0000-0000000000c1'), 14.00::numeric, 'censeur : moyenne de classe');
SELECT is((SELECT count(*)::int FROM public.classer_eleves_classe('88000000-0000-0000-0000-0000000000c1')), 1, 'censeur : classement');
SELECT throws_ok($$ SELECT public.solde_scolarite('88000000-0000-0000-0000-0000000000b1') $$,
  '42501', 'PERMISSION_REFUSEE', 'censeur : solde refusé');
SELECT throws_ok($$ SELECT public.recommander_sanction_educative('88000000-0000-0000-0000-0000000000e1', '88000000-0000-0000-0000-0000000000a1') $$,
  '42501', 'PERMISSION_REFUSEE', 'censeur : recommandation de sanction refusée');

SELECT pg_temp.en_tant_que(:'surveillant');
SELECT is(pg_temp.lus(), '{"notes":0,"evaluations":0,"bulletins":0,"appreciations":0,"presences":1,"retards":1,"sanctions":1,
  "alertes":1,"encaissements":0,"statistiques":1,"rapports":0,"indicateurs":0,"proclamations":0,"journal":0}'::jsonb,
  'surveillant général : absences, retards, sanctions, suivi ; ni notes ni encaissements');
SELECT ok(public.calculer_score_decrochage('88000000-0000-0000-0000-0000000000e1', '88000000-0000-0000-0000-0000000000a1') > 0,
  'surveillant général : score de décrochage calculé (sans voir les notes)');
SELECT ok(public.recommander_sanction_educative('88000000-0000-0000-0000-0000000000e1', '88000000-0000-0000-0000-0000000000a1') IS NOT NULL,
  'surveillant général : recommandation éducative');
SELECT is(public.risque_reussite_actuel('88000000-0000-0000-0000-0000000000e1'), 0.42::numeric, 'surveillant général : risque de réussite');
SELECT throws_ok($$ SELECT public.calculer_moyenne_eleve('88000000-0000-0000-0000-0000000000e1') $$,
  '42501', 'PERMISSION_REFUSEE', 'surveillant général : moyenne refusée');
SELECT throws_ok($$ SELECT public.moyenne_eleve_interne('88000000-0000-0000-0000-0000000000e1') $$,
  '42501', NULL, 'surveillant général : calcul interne de moyenne non appelable');

SELECT pg_temp.en_tant_que(:'caissier');
SELECT is(pg_temp.lus(), '{"notes":0,"evaluations":0,"bulletins":0,"appreciations":0,"presences":0,"retards":0,"sanctions":0,
  "alertes":0,"encaissements":1,"statistiques":0,"rapports":0,"indicateurs":0,"proclamations":0,"journal":0}'::jsonb,
  'caissier : encaissements seulement');
SELECT lives_ok($$ SELECT public.solde_scolarite('88000000-0000-0000-0000-0000000000b1') $$, 'caissier : solde lu');
SELECT lives_ok($$ SELECT public.rapprochement_mobile_money('88000000-0000-0000-0000-00000000000a') $$,
  'caissier : rapprochement des paiements mobiles');
SELECT throws_ok($$ SELECT public.calculer_moyenne_eleve('88000000-0000-0000-0000-0000000000e1') $$,
  '42501', 'PERMISSION_REFUSEE', 'caissier : moyenne refusée');

SELECT pg_temp.en_tant_que(:'secretaire');
SELECT is(pg_temp.lus(), '{"notes":0,"evaluations":0,"bulletins":0,"appreciations":0,"presences":0,"retards":0,"sanctions":0,
  "alertes":0,"encaissements":0,"statistiques":0,"rapports":0,"indicateurs":0,"proclamations":0,"journal":1}'::jsonb,
  'secrétaire (inscriptions) : historique des inscriptions, rien d''autre');

SELECT pg_temp.en_tant_que(:'auditeur');
SELECT ok((pg_temp.lus() ->> 'journal')::int >= 1 AND (pg_temp.lus() ->> 'notes')::int = 0,
  'poste d''audit : tout le journal de l''école, pas les notes');

-- ---------------------------------------------------------------------------
-- 3. Enseignants : leur classe seulement
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'prof_c1');
SELECT is(pg_temp.lus(), '{"notes":1,"evaluations":1,"bulletins":1,"appreciations":1,"presences":1,"retards":1,"sanctions":0,
  "alertes":1,"encaissements":0,"statistiques":1,"rapports":0,"indicateurs":0,"proclamations":1,"journal":0}'::jsonb,
  'titulaire de C1 : notes, appel, bulletins de sa classe ; ni sanctions ni encaissements');
SELECT throws_ok($$ SELECT public.solde_scolarite('88000000-0000-0000-0000-0000000000b1') $$,
  '42501', 'PERMISSION_REFUSEE', 'titulaire : solde refusé');

SELECT pg_temp.en_tant_que(:'prof_c2');
SELECT is(pg_temp.lus(), '{"notes":0,"evaluations":0,"bulletins":0,"appreciations":0,"presences":0,"retards":0,"sanctions":0,
  "alertes":0,"encaissements":0,"statistiques":0,"rapports":0,"indicateurs":0,"proclamations":0,"journal":0}'::jsonb,
  'enseignant de C2 : rien de l''élève de C1');
SELECT throws_ok($$ SELECT public.calculer_moyenne_eleve('88000000-0000-0000-0000-0000000000e1') $$,
  '42501', 'PERMISSION_REFUSEE', 'enseignant de C2 : moyenne d''un élève de C1 refusée');
SELECT throws_ok($$ INSERT INTO public.retards (etablissement_id, fiche_eleve_id, annee_scolaire_id, date_retard, minutes_retard, saisi_par)
  VALUES ('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000e1', '88000000-0000-0000-0000-0000000000a1',
          current_date - 1, 5, auth.uid()) $$,
  '42501', NULL, 'enseignant de C2 : ne saisit pas de retard pour un élève de C1');
SELECT pg_temp.en_tant_que(:'chauffeur');
SELECT throws_ok($$ INSERT INTO public.retards (etablissement_id, fiche_eleve_id, annee_scolaire_id, date_retard, minutes_retard, saisi_par)
  VALUES ('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000e1', '88000000-0000-0000-0000-0000000000a1',
          current_date - 1, 5, auth.uid()) $$,
  '42501', NULL, 'chauffeur : ne saisit pas de retard');

-- ---------------------------------------------------------------------------
-- 4. Direction : tout dans son école ; famille : inchangé
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT is(pg_temp.lus(), '{"notes":1,"evaluations":1,"bulletins":1,"appreciations":1,"presences":1,"retards":1,"sanctions":1,
  "alertes":1,"encaissements":1,"statistiques":1,"rapports":1,"indicateurs":1,"proclamations":1,"journal":1}'::jsonb,
  'direction : tout dans son école');
SELECT lives_ok($$ SELECT public.consolider_indicateurs_etablissement('88000000-0000-0000-0000-00000000000a', '88000000-0000-0000-0000-0000000000a1') $$,
  'direction : indicateurs consolidés');
SELECT lives_ok($$ SELECT public.risque_classe('88000000-0000-0000-0000-0000000000c1') $$, 'direction : risque de la classe');

SELECT pg_temp.en_tant_que(:'p1');
SELECT is(pg_temp.lus(), '{"notes":1,"evaluations":1,"bulletins":1,"appreciations":1,"presences":1,"retards":1,"sanctions":1,
  "alertes":1,"encaissements":1,"statistiques":1,"rapports":0,"indicateurs":0,"proclamations":0,"journal":1}'::jsonb,
  'parent confirmé : ce qui concerne son enfant, comme avant');
SELECT is(public.calculer_moyenne_eleve('88000000-0000-0000-0000-0000000000e1'), 14.00::numeric, 'parent : moyenne de son enfant');
SELECT lives_ok($$ SELECT public.solde_scolarite('88000000-0000-0000-0000-0000000000b1') $$, 'parent : solde de son enfant');

SELECT pg_temp.en_tant_que(:'el1');
SELECT is((pg_temp.lus() ->> 'notes')::int, 1, 'élève : ses notes publiées');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
