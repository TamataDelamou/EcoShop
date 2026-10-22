-- ============================================================================
-- EcoShop — Test RLS 79 : connexion e-mail / Google, téléphone au profil
-- (migration 20260906001552)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.compte_email(p_email text, p_meta jsonb DEFAULT '{}', p_app jsonb DEFAULT '{}',
                                                p_role text DEFAULT 'parent')
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, raw_user_meta_data, raw_app_meta_data) VALUES (v_id, p_email, p_meta, p_app);
  UPDATE public.profiles SET role_racine = p_role::public.role_racine WHERE id = v_id;
  RETURN v_id;
END $$;

SELECT plan(22);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('79000000-0000-0000-0000-000000000001', 'École A', 'ecole-a-79', 'GNF');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance) VALUES
  ('79000000-0000-0000-0000-0000000000e1', '79000000-0000-0000-0000-000000000001', 'A-1', 'CAMARA', 'Fanta', '2015-03-02');

-- ---------------------------------------------------------------------------
-- 1. Nouveau compte Google : nom repris, adresse prouvée
-- ---------------------------------------------------------------------------
SELECT pg_temp.compte_email('Awa.Bah@Gmail.com',
  '{"given_name":"Awa","family_name":"Bah","email_verified":true}', '{"provider":"google"}') AS parent \gset
SELECT is((SELECT prenom || ' ' || nom FROM public.profiles WHERE id = :'parent'), 'Awa Bah', 'prénom et nom repris de Google');
SELECT is((SELECT valeur || '|' || mode_verification || '|' || (verifie_le IS NOT NULL)::text
           FROM public.identifiants_comptes WHERE profile_id = :'parent'),
  'awa.bah@gmail.com|google|true', 'adresse Google enregistrée, vérifiée');

SELECT pg_temp.compte_email('mamadou@exemple.org', '{"full_name":"Mamadou Lamine Diallo"}') AS rival \gset
SELECT is((SELECT prenom || '/' || nom FROM public.profiles WHERE id = :'rival'), 'Mamadou/Lamine Diallo',
  'nom complet découpé quand le fournisseur ne donne que full_name');
SELECT pg_temp.compte_email('sans.nom@exemple.org', '{"name":"sans.nom@exemple.org"}') AS sansnom \gset
SELECT ok((SELECT prenom IS NULL FROM public.profiles WHERE id = :'sansnom'), 'une adresse n''est jamais prise pour un nom');

SELECT pg_temp.compte_email('dir@ecole-a.org', '{}', '{}', 'direction') AS dir \gset
SELECT pg_temp.compte_email('tiers@exemple.org') AS tiers \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir', '79000000-0000-0000-0000-000000000001', 'direction');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id) VALUES
  ('79000000-0000-0000-0000-000000000001', :'parent', '79000000-0000-0000-0000-0000000000e1');

-- ---------------------------------------------------------------------------
-- 2. Téléphone déclaré au profil
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'parent');
SELECT throws_ok($$ SELECT public.declarer_mon_telephone('620 00 00 00') $$, '22023', 'TELEPHONE_INVALIDE',
  'numéro sans indicatif refusé');
SELECT is(public.declarer_mon_telephone('+224 620-11-22-33') ->> 'verifie', 'false', 'numéro déclaré, non vérifié');
SELECT is((SELECT telephone || '|' || verifie::text FROM public.mon_telephone()), '+224620112233|false',
  'mon numéro relu, format E.164');
SELECT is(public.declarer_mon_telephone('+224620112233') ->> 'telephone', '+224620112233', 'redéclarer le même numéro est sans effet');

-- Un autre compte peut déclarer le même numéro : une simple déclaration ne
-- bloque pas le vrai titulaire.
SELECT pg_temp.en_tant_que(:'rival');
SELECT lives_ok($$ SELECT public.declarer_mon_telephone('+224620112233') $$, 'le numéro déclaré par un autre reste libre');

-- Invitation adressée à ce numéro : un numéro seulement déclaré ne suffit pas.
RESET ROLE;
INSERT INTO public.invitations (etablissement_id, role_cible, identifiant_cible, jeton_empreinte)
VALUES ('79000000-0000-0000-0000-000000000001', 'enseignant', '+224620112233',
        encode(extensions.digest('JETON-79', 'sha256'), 'hex'));
SET LOCAL ROLE authenticated;
SELECT throws_ok($$ SELECT public.accepter_invitation('JETON-79') $$, '42501', 'IDENTIFIANT_NON_VERIFIE',
  'invitation refusée sur un numéro non vérifié');

-- ---------------------------------------------------------------------------
-- 3. Confirmation par l'école
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'parent');
SELECT throws_ok($$ SELECT * FROM public.telephones_a_confirmer('79000000-0000-0000-0000-000000000001') $$,
  '42501', NULL, 'un parent ne voit pas la liste');
SELECT pg_temp.en_tant_que(:'dir');
SELECT is((SELECT telephone || ' — ' || enfants FROM public.telephones_a_confirmer('79000000-0000-0000-0000-000000000001')),
  '+224620112233 — Fanta CAMARA', 'la direction voit le numéro à confirmer et l''enfant');
SELECT throws_ok($$ SELECT public.confirmer_telephone('79000000-0000-0000-0000-000000000001', '$$ || :'parent' || $$', '+224620999999') $$,
  '22023', 'TELEPHONE_NON_DECLARE', 'l''agent ne peut pas attribuer un autre numéro');
SELECT throws_ok($$ SELECT public.confirmer_telephone('79000000-0000-0000-0000-000000000001', '$$ || :'tiers' || $$', '+224620112233') $$,
  '42501', 'PERSONNE_HORS_ETABLISSEMENT', 'personne sans lien avec l''école refusée');
SELECT lives_ok($$ SELECT public.confirmer_telephone('79000000-0000-0000-0000-000000000001', '$$ || :'parent' || $$', '+224 620 11 22 33') $$,
  'numéro confirmé en présence du parent');
SELECT is((SELECT count(*)::int FROM public.telephones_a_confirmer('79000000-0000-0000-0000-000000000001')), 0,
  'plus rien à confirmer');

SELECT pg_temp.en_tant_que(:'parent');
SELECT is((SELECT verifie::text || '|' || mode_verification FROM public.mon_telephone()), 'true|ecole', 'numéro vérifié par l''école');
SELECT pg_temp.en_tant_que(:'rival');
SELECT is((SELECT count(*)::int FROM public.mon_telephone()), 0, 'l''autre déclaration du numéro est retirée');
SELECT throws_ok($$ SELECT public.declarer_mon_telephone('+224620112233') $$, '23505', 'TELEPHONE_DEJA_UTILISE',
  'un numéro vérifié ne peut plus être déclaré par un autre');

-- Le numéro vérifié permet d'accepter l'invitation.
SELECT pg_temp.en_tant_que(:'parent');
SELECT lives_ok($$ SELECT public.accepter_invitation('JETON-79') $$, 'invitation acceptée avec le numéro vérifié');

-- Fast-track : la direction retrouve la fratrie par le numéro.
SELECT pg_temp.en_tant_que(:'dir');
SELECT is((SELECT prenom FROM public.rechercher_enfants_par_telephone_parent('79000000-0000-0000-0000-000000000001', '+224620112233')),
  'Fanta', 'fast-track : enfants du titulaire vérifié');

-- Changer de numéro : l'ancien vérifié reste, le nouveau est déclaré.
SELECT pg_temp.en_tant_que(:'rival');
SELECT public.declarer_mon_telephone('+224621000001');
SELECT public.declarer_mon_telephone('+224621000002');
SELECT is((SELECT telephone FROM public.mon_telephone()), '+224621000002', 'une seule déclaration à la fois, la dernière');

SELECT * FROM finish();
ROLLBACK;
