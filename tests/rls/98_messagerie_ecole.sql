-- ============================================================================
-- EcoShop — Test RLS 98 : messagerie famille ↔ école et groupes de classe
-- (REG-34, migration 1580)
--
-- Vérifie que :
--   • le parent écrit à l'enseignant de son enfant ou à la direction, à
--     personne d'autre ; le fil n'est lu que par ce destinataire, la
--     direction et les parents confirmés — pas par un autre enseignant ;
--   • hors des heures de messagerie, la notification au personnel est
--     reportée à l'ouverture ; le service d'envoi ne la prend pas avant ;
--   • groupes de classe : créés par un adulte seulement ; un élève écrit
--     dans le groupe de sa classe, pas ailleurs, ni hors des heures, ni dans
--     un groupe réservé aux annonces ; aucun parent dans les groupes ;
--   • modération : masquage motivé (jamais effacé), signalement, audit.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.sur(p_uid uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  UPDATE public.profiles SET role_racine = p_role::public.role_racine,
         prenom = initcap(split_part(p_email, '@', 1)), nom = 'Test' WHERE id = v_id;
  RETURN v_id;
END $$;

-- Messagerie ouverte tous les jours, toute la journée / fermée aujourd'hui.
CREATE OR REPLACE FUNCTION pg_temp.ouvrir() RETURNS void LANGUAGE sql AS $$
  UPDATE public.etablissements SET messagerie_debut = '00:00', messagerie_fin = '23:59:59', messagerie_jours = '{1,2,3,4,5,6,7}'
   WHERE id = '98000000-0000-0000-0000-00000000000a';
$$;
CREATE OR REPLACE FUNCTION pg_temp.fermer() RETURNS void LANGUAGE sql AS $$
  UPDATE public.etablissements
     SET messagerie_debut = '07:00', messagerie_fin = '19:00',
         messagerie_jours = ARRAY[(extract(isodow from (now() at time zone 'Africa/Conakry'))::int % 7 + 1)::smallint]
   WHERE id = '98000000-0000-0000-0000-00000000000a';
$$;

SELECT plan(55);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('98000000-0000-0000-0000-00000000000a', 'École A', 'ecole-a-98', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('98000000-0000-0000-0000-0000000000a1', '98000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('98000000-0000-0000-0000-0000000000c1', '98000000-0000-0000-0000-00000000000a', '98000000-0000-0000-0000-0000000000a1', '6A', '6e A'),
  ('98000000-0000-0000-0000-0000000000c2', '98000000-0000-0000-0000-00000000000a', '98000000-0000-0000-0000-0000000000a1', '6B', '6e B');

SELECT pg_temp.compte('dir@exemple.gn', 'direction') AS dir \gset
SELECT pg_temp.compte('prof.a@exemple.gn', 'enseignant') AS prof_a \gset
SELECT pg_temp.compte('prof.b@exemple.gn', 'enseignant') AS prof_b \gset
SELECT pg_temp.compte('maman@exemple.gn', 'parent') AS maman \gset
SELECT pg_temp.compte('awa@exemple.gn', 'eleve') AS awa \gset
SELECT pg_temp.compte('sekou@exemple.gn', 'eleve') AS sekou \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir', '98000000-0000-0000-0000-00000000000a', 'direction'),
  (:'prof_a', '98000000-0000-0000-0000-00000000000a', 'enseignant'),
  (:'prof_b', '98000000-0000-0000-0000-00000000000a', 'enseignant');
INSERT INTO public.affectations_enseignants (etablissement_id, annee_scolaire_id, enseignant_profile_id, classe_id) VALUES
  ('98000000-0000-0000-0000-00000000000a', '98000000-0000-0000-0000-0000000000a1', :'prof_a', '98000000-0000-0000-0000-0000000000c1'),
  ('98000000-0000-0000-0000-00000000000a', '98000000-0000-0000-0000-0000000000a1', :'prof_b', '98000000-0000-0000-0000-0000000000c2');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id) VALUES
  ('98000000-0000-0000-0000-0000000000e1', '98000000-0000-0000-0000-00000000000a', 'A98-1', 'BAH', 'Awa', '2014-01-01', :'awa'),
  ('98000000-0000-0000-0000-0000000000e2', '98000000-0000-0000-0000-00000000000a', 'A98-2', 'SOW', 'Sekou', '2014-02-01', :'sekou');
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('98000000-0000-0000-0000-00000000000a', '98000000-0000-0000-0000-0000000000e1', '98000000-0000-0000-0000-0000000000c1', '98000000-0000-0000-0000-0000000000a1'),
  ('98000000-0000-0000-0000-00000000000a', '98000000-0000-0000-0000-0000000000e2', '98000000-0000-0000-0000-0000000000c2', '98000000-0000-0000-0000-0000000000a1');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise) VALUES
  ('98000000-0000-0000-0000-00000000000a', :'maman', '98000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true);
SELECT pg_temp.ouvrir();

-- ---------------------------------------------------------------------------
-- 1. Heures de messagerie
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'maman');
SELECT is((public.heures_messagerie('98000000-0000-0000-0000-00000000000a') ->> 'ouverte')::boolean, true,
          'le parent lit les heures de messagerie de l''école de son enfant');
SELECT throws_ok($$ SELECT public.definir_heures_messagerie('98000000-0000-0000-0000-00000000000a', '07:00', '19:00', '{1,2,3,4,5}') $$,
                 '42501', NULL, 'un parent ne règle pas les heures');
SELECT pg_temp.sur(:'prof_a');
SELECT throws_ok($$ SELECT public.definir_heures_messagerie('98000000-0000-0000-0000-00000000000a', '07:00', '19:00', '{1,2,3,4,5}') $$,
                 '42501', NULL, 'un enseignant ne règle pas les heures');
SELECT pg_temp.sur(:'dir');
SELECT throws_ok($$ SELECT public.definir_heures_messagerie('98000000-0000-0000-0000-00000000000a', '19:00', '07:00', '{1}') $$,
                 '22023', NULL, 'début après la fin : refusé');
SELECT throws_ok($$ SELECT public.definir_heures_messagerie('98000000-0000-0000-0000-00000000000a', '07:00', '19:00', '{0,8}') $$,
                 '22023', NULL, 'jour inconnu : refusé');
SELECT lives_ok($$ SELECT public.definir_heures_messagerie('98000000-0000-0000-0000-00000000000a', '07:30', '18:00', '{5,1,2,2}') $$,
                'la direction règle les heures');
SELECT is(public.heures_messagerie('98000000-0000-0000-0000-00000000000a') -> 'jours', '[1, 2, 5]'::jsonb, 'jours dédoublonnés et triés');
RESET ROLE;
SELECT pg_temp.ouvrir();

-- ---------------------------------------------------------------------------
-- 2. Le parent écrit à l'école
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'maman');
SELECT is((SELECT string_agg(d ->> 'role', ',' ORDER BY d ->> 'role')
           FROM jsonb_array_elements(public.destinataires_liaison('98000000-0000-0000-0000-0000000000e1') -> 'destinataires') d),
          'Direction,Enseignant', 'destinataires : la direction et l''enseignant de la classe — pas celui d''une autre classe');
SELECT is((public.destinataires_liaison('98000000-0000-0000-0000-0000000000e1') -> 'heures' ->> 'ouverte')::boolean, true,
          'les heures de messagerie sont données avec les destinataires');
SELECT throws_ok(format($$ SELECT public.ecrire_mot_parent(gen_random_uuid(), '98000000-0000-0000-0000-0000000000e1', %L, 'Bonjour') $$, :'prof_b'),
                 '22023', NULL, 'enseignant d''une autre classe : destinataire refusé');
SELECT throws_ok(format($$ SELECT public.ecrire_mot_parent(gen_random_uuid(), '98000000-0000-0000-0000-0000000000e2', %L, 'Bonjour') $$, :'prof_b'),
                 '42501', NULL, 'au sujet d''un enfant qui n''est pas le sien : refusé');
SELECT is((public.ecrire_mot_parent('98000000-0000-0000-0000-0000000001f1', '98000000-0000-0000-0000-0000000000e1', :'prof_a',
           'Awa sera absente vendredi.') ->> 'deja_recu')::boolean, false, 'le parent écrit à l''enseignant de son enfant');
SELECT is((public.ecrire_mot_parent('98000000-0000-0000-0000-0000000001f1', '98000000-0000-0000-0000-0000000000e1', :'prof_a',
           'Awa sera absente vendredi.') ->> 'deja_recu')::boolean, true, 'renvoi avec la même clé : pas de doublon');
SELECT is(jsonb_array_length(public.cahier_liaison('98000000-0000-0000-0000-0000000000e1')), 1, 'le parent voit son fil');

SELECT pg_temp.sur(:'awa');
SELECT throws_ok(format($$ SELECT public.ecrire_mot_parent(gen_random_uuid(), '98000000-0000-0000-0000-0000000000e1', %L, 'Bonjour') $$, :'prof_a'),
                 '42501', NULL, 'un élève n''écrit pas au nom de ses parents');

SELECT pg_temp.sur(:'prof_a');
SELECT is(jsonb_array_length(public.cahier_liaison('98000000-0000-0000-0000-0000000000e1')), 1, 'le destinataire voit le fil');
SELECT is((public.eleves_cahier_liaison('98000000-0000-0000-0000-00000000000a') -> 0 ->> 'a_lire')::int, 1,
          'le destinataire a un message à lire');
SELECT is((public.accueil_resume('98000000-0000-0000-0000-00000000000a') ->> 'cahier_non_lu')::int, 1,
          'accueil du destinataire : un message du cahier à lire');
SELECT lives_ok($$ SELECT public.repondre_liaison('98000000-0000-0000-0000-0000000001f2', '98000000-0000-0000-0000-0000000001f1',
                   'Bien noté, merci.') $$, 'le destinataire répond');
SELECT lives_ok($$ SELECT public.confirmer_lecture_liaison('98000000-0000-0000-0000-0000000001f1') $$, 'le destinataire confirme la lecture');

SELECT pg_temp.sur(:'dir');
SELECT is(jsonb_array_length(public.cahier_liaison('98000000-0000-0000-0000-0000000000e1')), 1, 'la direction voit le fil');

SELECT pg_temp.sur(:'prof_b');
SELECT throws_ok($$ SELECT public.cahier_liaison('98000000-0000-0000-0000-0000000000e1') $$, '42501', NULL,
                 'un autre enseignant ne lit pas le fil');
SELECT is((public.accueil_resume('98000000-0000-0000-0000-00000000000a') ->> 'cahier_non_lu')::int, 0,
          'accueil d''un autre enseignant : rien à lire');
SELECT throws_ok($$ SELECT public.repondre_liaison(gen_random_uuid(), '98000000-0000-0000-0000-0000000001f1', 'Intrus') $$,
                 '42501', NULL, 'un autre enseignant ne répond pas');

SELECT pg_temp.sur(:'maman');
SELECT is((public.cahier_liaison('98000000-0000-0000-0000-0000000000e1') -> 0 ->> 'lu_par_ecole')::boolean, true,
          'le parent voit « Lu par l''école »');
SELECT is(jsonb_array_length(public.cahier_liaison('98000000-0000-0000-0000-0000000000e1') -> 0 -> 'reponses'), 1, 'le parent voit la réponse');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 3. Heures calmes : notification reportée
-- ---------------------------------------------------------------------------
SELECT is((SELECT count(*)::int FROM public.notifications WHERE destinataire = :'prof_a' AND envoyer_apres IS NULL), 1,
          'messagerie ouverte : l''enseignant est prévenu tout de suite');
SELECT pg_temp.fermer();
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'maman');
SELECT ok((public.ecrire_mot_parent('98000000-0000-0000-0000-0000000001f3', '98000000-0000-0000-0000-0000000000e1', :'dir',
           'Rendez-vous possible ?') ->> 'ouverture')::timestamptz > now(), 'hors des heures : l''ouverture est annoncée au parent');
RESET ROLE;
SELECT ok((SELECT envoyer_apres > now() FROM public.notifications WHERE destinataire = :'dir'),
          'hors des heures : la notification de la direction attend l''ouverture');
SELECT is((SELECT count(*)::int FROM public.reserver_notifications_push(500) r WHERE r.destinataire = :'dir'), 0,
          'le service d''envoi ne la prend pas avant l''ouverture');
SELECT pg_temp.ouvrir();

-- ---------------------------------------------------------------------------
-- 4. Groupes de classe
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'awa');
SELECT throws_ok($$ SELECT public.creer_groupe_classe('98000000-0000-0000-0000-0000000000c1') $$, '42501', NULL,
                 'un élève ne crée pas de groupe');
SELECT pg_temp.sur(:'prof_b');
SELECT throws_ok($$ SELECT public.creer_groupe_classe('98000000-0000-0000-0000-0000000000c1') $$, '42501', NULL,
                 'un enseignant ne crée pas le groupe d''une classe qui n''est pas la sienne');
SELECT pg_temp.sur(:'prof_a');
SELECT public.creer_groupe_classe('98000000-0000-0000-0000-0000000000c1') AS groupe \gset
SELECT is(public.creer_groupe_classe('98000000-0000-0000-0000-0000000000c1'), :'groupe'::uuid, 'un seul groupe par classe et par année');
SELECT lives_ok(format($$ SELECT public.envoyer_message_groupe('98000000-0000-0000-0000-0000000002a1', %L, 'Bienvenue en 6e A !') $$, :'groupe'),
                'l''enseignant écrit dans le groupe');

SELECT pg_temp.sur(:'awa');
SELECT is((public.mes_groupes_classe('98000000-0000-0000-0000-00000000000a') -> 'groupes' -> 0 ->> 'non_lus')::int, 1,
          'l''élève voit le groupe de sa classe et un message non lu');
SELECT is((public.accueil_resume('98000000-0000-0000-0000-00000000000a') ->> 'groupes_non_lus')::int, 1,
          'accueil de l''élève : un message du groupe à lire');
SELECT lives_ok(format($$ SELECT public.envoyer_message_groupe('98000000-0000-0000-0000-0000000002a2', %L, 'Merci monsieur') $$, :'groupe'),
                'l''élève écrit dans le groupe de sa classe');
SELECT is((public.envoyer_message_groupe('98000000-0000-0000-0000-0000000002a2', :'groupe', 'Merci monsieur') ->> 'deja_recu')::boolean,
          true, 'renvoi avec la même clé : pas de doublon');

SELECT pg_temp.sur(:'sekou');
SELECT throws_ok(format($$ SELECT public.fil_groupe_classe(%L) $$, :'groupe'), '42501', NULL, 'un élève d''une autre classe ne lit pas le groupe');
SELECT throws_ok(format($$ SELECT public.envoyer_message_groupe(gen_random_uuid(), %L, 'Coucou') $$, :'groupe'), '42501', NULL,
                 'un élève d''une autre classe n''écrit pas');
SELECT pg_temp.sur(:'maman');
SELECT throws_ok(format($$ SELECT public.fil_groupe_classe(%L) $$, :'groupe'), '42501', NULL, 'aucun parent dans les groupes');

-- Annonces seulement, puis hors des heures.
SELECT pg_temp.sur(:'prof_a');
SELECT lives_ok(format($$ SELECT public.regler_groupe_classe(%L, false) $$, :'groupe'), 'l''enseignant réserve le groupe aux annonces');
SELECT pg_temp.sur(:'awa');
SELECT throws_ok(format($$ SELECT public.envoyer_message_groupe(gen_random_uuid(), %L, 'Question ?') $$, :'groupe'), '42501', NULL,
                 'groupe d''annonces : l''élève n''écrit pas');
SELECT throws_ok(format($$ INSERT INTO public.messages_groupe (etablissement_id, groupe_id, auteur_id, contenu)
                           VALUES ('98000000-0000-0000-0000-00000000000a', %L, auth.uid(), 'Par la porte de derrière') $$, :'groupe'),
                 '42501', NULL, 'insertion directe : même règle');
SELECT pg_temp.sur(:'prof_a');
SELECT public.regler_groupe_classe(:'groupe', true);
RESET ROLE;
SELECT pg_temp.fermer();
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'awa');
SELECT throws_ok(format($$ SELECT public.envoyer_message_groupe(gen_random_uuid(), %L, 'Il est tard') $$, :'groupe'), '42501', NULL,
                 'hors des heures : l''élève n''écrit pas');
SELECT pg_temp.sur(:'prof_a');
SELECT lives_ok(format($$ SELECT public.envoyer_message_groupe('98000000-0000-0000-0000-0000000002a3', %L, 'Rappel : contrôle demain') $$, :'groupe'),
                'hors des heures : l''enseignant peut écrire (les élèves seront prévenus à l''ouverture)');
RESET ROLE;
SELECT ok((SELECT envoyer_apres > now() FROM public.notifications
           WHERE destinataire = :'awa' AND variables ->> 'message_id' = '98000000-0000-0000-0000-0000000002a3'),
          'hors des heures : la notification aux élèves attend l''ouverture');
SELECT pg_temp.ouvrir();

-- ---------------------------------------------------------------------------
-- 5. Modération
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'awa');
SELECT lives_ok($$ SELECT public.signaler_message_groupe('98000000-0000-0000-0000-0000000002a2', 'Message envoyé par erreur') $$,
                'un membre signale un message');
SELECT throws_ok($$ SELECT public.masquer_message_groupe('98000000-0000-0000-0000-0000000002a2', 'Hors sujet') $$, '42501', NULL,
                 'un élève ne masque pas');
SELECT pg_temp.sur(:'prof_a');
SELECT is((public.mes_groupes_classe('98000000-0000-0000-0000-00000000000a') -> 'groupes' -> 0 ->> 'signalements')::int, 1,
          'le modérateur voit le signalement');
SELECT throws_ok($$ SELECT public.masquer_message_groupe('98000000-0000-0000-0000-0000000002a2', '') $$, '22023', NULL, 'motif obligatoire');
SELECT lives_ok($$ SELECT public.masquer_message_groupe('98000000-0000-0000-0000-0000000002a2', 'Envoyé par erreur') $$, 'le modérateur masque');
SELECT is((SELECT x ->> 'motif' FROM jsonb_array_elements(public.fil_groupe_classe(:'groupe')) x
           WHERE x ->> 'id' = '98000000-0000-0000-0000-0000000002a2'), 'Envoyé par erreur', 'l''adulte voit le motif');
SELECT pg_temp.sur(:'awa');
SELECT ok((SELECT x ->> 'corps' IS NULL AND (x ->> 'masque')::boolean FROM jsonb_array_elements(public.fil_groupe_classe(:'groupe')) x
           WHERE x ->> 'id' = '98000000-0000-0000-0000-0000000002a2'), 'l''élève voit « message retiré », sans le texte');
RESET ROLE;
SELECT is((SELECT contenu FROM public.messages_groupe WHERE id = '98000000-0000-0000-0000-0000000002a2'), 'Merci monsieur',
          'rien n''est effacé : le texte reste pour la direction');

SELECT * FROM finish();
ROLLBACK;
