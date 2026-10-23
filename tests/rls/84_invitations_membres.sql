-- ============================================================================
-- EcoShop — Test RLS 84 : invitations du personnel et des vendeurs
-- (migration 20260906001557)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

-- Compte créé par la connexion (adresse prouvée) ; rôle facultatif.
CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  IF p_role IS NOT NULL THEN
    UPDATE public.profiles SET role_racine = p_role::public.role_racine, prenom = 'Test', nom = 'Compte' WHERE id = v_id;
  END IF;
  RETURN v_id;
END $$;

SELECT plan(38);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('84000000-0000-0000-0000-00000000000a', 'École A', 'ecole-a-84', 'GNF'),
  ('84000000-0000-0000-0000-00000000000b', 'École B', 'ecole-b-84', 'GNF');
INSERT INTO public.postes (id, etablissement_id, nom) VALUES
  ('84000000-0000-0000-0000-0000000000c1', '84000000-0000-0000-0000-00000000000a', 'Comptable'),
  ('84000000-0000-0000-0000-0000000000c2', '84000000-0000-0000-0000-00000000000b', 'Secrétariat');

SELECT pg_temp.compte('dir.a@exemple.org', 'direction') AS dir_a \gset
SELECT pg_temp.compte('dir.b@exemple.org', 'direction') AS dir_b \gset
SELECT pg_temp.compte('parent@exemple.org', 'parent') AS parent \gset
SELECT pg_temp.compte('Prof.Nouveau@Exemple.org') AS prof \gset
SELECT pg_temp.compte('autre@exemple.org') AS autre \gset
SELECT pg_temp.compte('tel@exemple.org') AS tel \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_a', '84000000-0000-0000-0000-00000000000a', 'direction'),
  (:'dir_b', '84000000-0000-0000-0000-00000000000b', 'direction');

-- ---------------------------------------------------------------------------
-- 1. Inviter : direction seulement, rôles du personnel et vendeur
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT public.inviter_membre('84000000-0000-0000-0000-00000000000a', '  prof.nouveau@EXEMPLE.org ', 'enseignant',
  '84000000-0000-0000-0000-0000000000c1') AS inv_prof \gset
SELECT is((SELECT identifiant FROM public.invitations_etablissement('84000000-0000-0000-0000-00000000000a')
           WHERE id = :'inv_prof'), 'prof.nouveau@exemple.org',
  'adresse invitée mise en minuscules');
SELECT throws_ok($$ SELECT public.inviter_membre('84000000-0000-0000-0000-00000000000a', 'x@exemple.org', 'eleve') $$,
  '22023', 'ROLE_NON_INVITABLE', 'élève : pas d''invitation (inscription libre)');
SELECT throws_ok($$ SELECT public.inviter_membre('84000000-0000-0000-0000-00000000000a', 'x@exemple.org', 'admin_gsg') $$,
  '22023', 'ROLE_NON_INVITABLE', 'administration GSG : jamais par une école');
SELECT throws_ok($$ SELECT public.inviter_membre('84000000-0000-0000-0000-00000000000a', 'pas-une-adresse', 'enseignant') $$,
  '22023', 'IDENTIFIANT_INVALIDE', 'identifiant ni e-mail ni numéro E.164');
SELECT throws_ok($$ SELECT public.inviter_membre('84000000-0000-0000-0000-00000000000a', 'x@exemple.org', 'enseignant',
  '84000000-0000-0000-0000-0000000000c2') $$, '22023', 'POSTE_INVALIDE', 'poste d''une autre école refusé');
SELECT lives_ok($$ SELECT public.inviter_membre('84000000-0000-0000-0000-00000000000a', 'vendeur@exemple.org', 'vendeur') $$,
  'vendeur : invitable');
SELECT pg_temp.en_tant_que(:'dir_b');
SELECT throws_ok($$ SELECT public.inviter_membre('84000000-0000-0000-0000-00000000000a', 'x@exemple.org', 'enseignant') $$,
  '42501', 'PERMISSION_REFUSEE', 'direction B n''invite pas pour l''école A');
SELECT pg_temp.en_tant_que(:'parent');
SELECT throws_ok($$ SELECT public.inviter_membre('84000000-0000-0000-0000-00000000000a', 'x@exemple.org', 'enseignant') $$,
  '42501', 'PERMISSION_REFUSEE', 'un parent n''invite pas');
SELECT throws_ok($$ SELECT * FROM public.invitations_etablissement('84000000-0000-0000-0000-00000000000a') $$,
  '42501', 'PERMISSION_REFUSEE', 'un parent ne voit pas les invitations de l''école');
RESET ROLE;

SELECT ok(EXISTS (SELECT 1 FROM public.notifications_sortantes WHERE modele = 'invitation_membre'
                  AND destinataire = 'prof.nouveau@exemple.org' AND donnees ->> 'nom_etablissement' = 'École A'
                  AND donnees ->> 'poste' = 'Comptable'),
  'invitation par e-mail : courriel mis en file');

-- ---------------------------------------------------------------------------
-- 2. L'invité voit son invitation après connexion ; personne d'autre
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'prof');
SELECT is((SELECT count(*)::int FROM public.mes_invitations()), 1, 'invité : son invitation est visible');
SELECT ok((SELECT verifie AND NOT par_telephone AND etablissement = 'École A' AND poste = 'Comptable'
           FROM public.mes_invitations()), 'adresse prouvée par la connexion : acceptable');
SELECT pg_temp.en_tant_que(:'autre');
SELECT is((SELECT count(*)::int FROM public.mes_invitations()), 0, 'un autre compte ne la voit pas');
SELECT throws_ok(format('SELECT public.repondre_invitation(%L, true)', :'inv_prof'), '42501', 'INVITATION_AUTRE_DESTINATAIRE',
  'un autre compte ne peut pas l''accepter');
SELECT throws_ok(format('SELECT public.repondre_invitation(%L, false)', :'inv_prof'), '42501', 'INVITATION_AUTRE_DESTINATAIRE',
  'ni la refuser');
SELECT is_empty($$ SELECT id FROM public.invitations $$, 'table des invitations illisible pour l''invité (RLS)');

-- ---------------------------------------------------------------------------
-- 3. Acceptation
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'prof');
SELECT is(public.repondre_invitation(:'inv_prof', true), 'acceptee', 'acceptation');
SELECT throws_ok(format('SELECT public.repondre_invitation(%L, true)', :'inv_prof'), '22023', 'INVITATION_DEJA_TRAITEE',
  'une seconde réponse est refusée');
SELECT is((SELECT count(*)::int FROM public.mes_invitations()), 0, 'plus rien en attente');
RESET ROLE;
SELECT ok(EXISTS (SELECT 1 FROM public.etablissements_membres WHERE profile_id = :'prof'
                  AND etablissement_id = '84000000-0000-0000-0000-00000000000a' AND role_dans_etablissement = 'enseignant'
                  AND poste_id = '84000000-0000-0000-0000-0000000000c1' AND actif), 'membre de l''école, avec son poste');
SELECT is((SELECT role_racine::text FROM public.profiles WHERE id = :'prof'), 'enseignant', 'compte neuf : rôle de l''invitation');
SELECT ok(EXISTS (SELECT 1 FROM public.notifications WHERE destinataire = :'dir_a' AND type = 'invitation_reponse'
                  AND (variables ->> 'acceptee')::boolean), 'la direction est prévenue de l''acceptation');

-- Déjà membre : nouvelle invitation inutile.
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT throws_ok($$ SELECT public.inviter_membre('84000000-0000-0000-0000-00000000000a', 'prof.nouveau@exemple.org', 'enseignant') $$,
  '23505', 'DEJA_MEMBRE', 'déjà membre avec ce rôle : refusé');

-- Un parent invité comme enseignant garde son rôle racine.
SELECT public.inviter_membre('84000000-0000-0000-0000-00000000000a', 'parent@exemple.org', 'enseignant') AS inv_parent \gset
SELECT pg_temp.en_tant_que(:'parent');
SELECT is(public.repondre_invitation(:'inv_parent', true), 'acceptee', 'parent invité : acceptation');
RESET ROLE;
SELECT is((SELECT role_racine::text FROM public.profiles WHERE id = :'parent'), 'parent', 'rôle racine inchangé');

-- ---------------------------------------------------------------------------
-- 4. Par téléphone : seulement avec un numéro vérifié par l'école (REG-16)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT public.inviter_membre('84000000-0000-0000-0000-00000000000a', '+224 620 11 11 11', 'enseignant') AS inv_tel \gset
SELECT pg_temp.en_tant_que(:'tel');
SELECT public.declarer_mon_telephone('+224620111111');
SELECT ok((SELECT par_telephone AND NOT verifie FROM public.mes_invitations()),
  'numéro déclaré : invitation visible, non acceptable');
SELECT throws_ok(format('SELECT public.repondre_invitation(%L, true)', :'inv_tel'), '42501', 'IDENTIFIANT_NON_VERIFIE',
  'numéro déclaré : acceptation refusée');
SELECT throws_ok(format('SELECT public.repondre_invitation(%L, false)', :'inv_tel'), '42501', 'IDENTIFIANT_NON_VERIFIE',
  'numéro déclaré : refus impossible aussi (pas de refus à la place du titulaire)');
RESET ROLE;
SELECT is((SELECT count(*)::int FROM public.notifications_sortantes WHERE donnees ->> 'adresse' = '+224620111111'), 0,
  'par téléphone : aucun message envoyé (SMS suspendus)');
-- L'école confirme le numéro en présence de la personne.
UPDATE public.identifiants_comptes SET verifie_le = now(), mode_verification = 'ecole'
 WHERE profile_id = :'tel' AND valeur = '+224620111111';
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'tel');
SELECT is(public.repondre_invitation(:'inv_tel', false), 'refusee', 'numéro vérifié : refus possible');
RESET ROLE;
SELECT is((SELECT statut::text FROM public.invitations WHERE id = :'inv_tel'), 'refusee', 'invitation refusée');
SELECT ok(EXISTS (SELECT 1 FROM public.notifications WHERE destinataire = :'dir_a' AND type = 'invitation_reponse'
                  AND NOT (variables ->> 'acceptee')::boolean), 'la direction est prévenue du refus');

-- ---------------------------------------------------------------------------
-- 5. Remplacement, retrait, expiration, lien reçu
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT public.inviter_membre('84000000-0000-0000-0000-00000000000a', 'autre@exemple.org', 'enseignant') AS inv1 \gset
SELECT public.inviter_membre('84000000-0000-0000-0000-00000000000a', 'autre@exemple.org', 'direction') AS inv2 \gset
SELECT is((SELECT statut FROM public.invitations_etablissement('84000000-0000-0000-0000-00000000000a') WHERE id = :'inv1'),
  'revoquee', 'nouvelle invitation : l''ancienne est retirée');
SELECT pg_temp.en_tant_que(:'dir_b');
SELECT throws_ok(format('SELECT public.revoquer_invitation(%L)', :'inv2'), '42501', 'PERMISSION_REFUSEE',
  'une autre école ne retire pas l''invitation');
SELECT pg_temp.en_tant_que(:'dir_a');
SELECT public.revoquer_invitation(:'inv2');
SELECT pg_temp.en_tant_que(:'autre');
SELECT is((SELECT count(*)::int FROM public.mes_invitations()), 0, 'invitation retirée : plus visible');
RESET ROLE;

-- Expirée.
INSERT INTO public.invitations (id, etablissement_id, role_cible, identifiant_cible, jeton_empreinte, expire_le)
VALUES ('84000000-0000-0000-0000-0000000000f1', '84000000-0000-0000-0000-00000000000a', 'enseignant',
        'autre@exemple.org', 'empreinte-expiree-84', now() - interval '1 day');
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'autre');
SELECT throws_ok($$ SELECT public.repondre_invitation('84000000-0000-0000-0000-0000000000f1', true) $$,
  '22023', 'INVITATION_EXPIREE', 'invitation expirée : refusée');
RESET ROLE;

-- Lien reçu (jeton) : même règle, même effet.
INSERT INTO public.invitations (etablissement_id, role_cible, identifiant_cible, jeton_empreinte)
VALUES ('84000000-0000-0000-0000-00000000000b', 'vendeur', 'autre@exemple.org',
        encode(extensions.digest('jeton-84', 'sha256'), 'hex'));
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'autre');
SELECT lives_ok($$ SELECT public.accepter_invitation('jeton-84') $$, 'lien reçu : acceptation par le jeton');
RESET ROLE;
SELECT is((SELECT role_dans_etablissement FROM public.etablissements_membres WHERE profile_id = :'autre'
           AND etablissement_id = '84000000-0000-0000-0000-00000000000b'), 'vendeur', 'membre vendeur de l''école B');

SELECT * FROM finish();
ROLLBACK;
