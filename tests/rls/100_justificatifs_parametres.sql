-- ============================================================================
-- EcoShop — Test RLS 100 : justificatifs d'absence, paramètres globaux
-- (REG-36, migrations 20260906001583 et 20260906001584)
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
  UPDATE public.profiles SET role_racine = p_role::public.role_racine, prenom = 'Test', nom = 'Test' WHERE id = v_id;
  RETURN v_id;
END $$;

SELECT plan(17);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('a0000000-0000-0000-0000-00000000000a', 'École A', 'ecole-a-100', 'GNF'),
  ('a0000000-0000-0000-0000-00000000000b', 'École B', 'ecole-b-100', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('a0000000-0000-0000-0000-0000000000a1', 'a0000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('a0000000-0000-0000-0000-0000000000c1', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000a1', '6A', '6e A');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance) VALUES
  ('a0000000-0000-0000-0000-0000000000e1', 'a0000000-0000-0000-0000-00000000000a', 'A100-1', 'CAMARA', 'Fanta', '2014-05-06');

SELECT pg_temp.compte('dir.a100@exemple.org', 'direction') AS dir \gset
SELECT pg_temp.compte('dir.b100@exemple.org', 'direction') AS dir_b \gset
SELECT pg_temp.compte('mere100@exemple.org', 'parent') AS mere \gset
SELECT pg_temp.compte('voisin100@exemple.org', 'parent') AS voisin \gset
SELECT pg_temp.compte('gsg100@exemple.org', 'admin_gsg') AS gsg \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir', 'a0000000-0000-0000-0000-00000000000a', 'direction'),
  (:'dir_b', 'a0000000-0000-0000-0000-00000000000b', 'direction');
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000e1', 'a0000000-0000-0000-0000-0000000000c1', 'a0000000-0000-0000-0000-0000000000a1');
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise) VALUES
  ('a0000000-0000-0000-0000-00000000000a', :'mere', 'a0000000-0000-0000-0000-0000000000e1', 'parent', 'confirmee', true);
INSERT INTO public.presences (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, saisi_par, date_presence, statut) VALUES
  ('a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000a1', 'a0000000-0000-0000-0000-0000000000c1',
   'a0000000-0000-0000-0000-0000000000e1', :'dir', '2026-10-27', 'absent');

SET LOCAL ROLE authenticated;

-- ---------------------------------------------------------------------------
-- 1. Dépôt par la famille
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'mere');
SELECT lives_ok($$
  INSERT INTO public.justificatifs_absence (id, etablissement_id, fiche_eleve_id, date_debut, date_fin, motif, commentaire)
  VALUES ('a0000000-0000-0000-0000-0000000000f1', 'a0000000-0000-0000-0000-00000000000a',
          'a0000000-0000-0000-0000-0000000000e1', '2026-10-27', '2026-10-28', 'maladie', 'Fièvre, certificat joint')
$$, 'la mère confirmée justifie l''absence de sa fille');
SELECT throws_ok($$
  INSERT INTO public.justificatifs_absence (etablissement_id, fiche_eleve_id, date_debut, date_fin, motif, statut)
  VALUES ('a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000e1', '2026-10-29', '2026-10-29', 'maladie', 'accepte')
$$, '42501', NULL, 'la famille ne peut pas se déclarer acceptée');
SELECT throws_ok($$
  INSERT INTO public.justificatifs_absence (etablissement_id, fiche_eleve_id, date_debut, date_fin, motif)
  VALUES ('a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000e1', '2026-10-29', '2026-10-29', 'vacances')
$$, '23514', NULL, 'motif hors liste refusé');
SELECT throws_ok($$ SELECT public.traiter_justificatif('a0000000-0000-0000-0000-0000000000f1', true) $$,
  '42501', NULL, 'la famille ne décide pas');

SELECT pg_temp.sur(:'voisin');
SELECT is((SELECT count(*)::int FROM public.justificatifs_absence), 0, 'un autre parent ne voit rien');
SELECT throws_ok($$
  INSERT INTO public.justificatifs_absence (etablissement_id, fiche_eleve_id, date_debut, date_fin, motif)
  VALUES ('a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000e1', '2026-10-29', '2026-10-29', 'maladie')
$$, '42501', NULL, 'ni ne dépose pour un enfant qui n''est pas le sien');

-- ---------------------------------------------------------------------------
-- 2. Décision par l'école
-- ---------------------------------------------------------------------------
SELECT pg_temp.sur(:'dir_b');
SELECT throws_ok($$ SELECT public.traiter_justificatif('a0000000-0000-0000-0000-0000000000f1', true) $$,
  '42501', NULL, 'la direction d''une autre école ne décide pas');

SELECT pg_temp.sur(:'gsg');
SELECT throws_ok($$ SELECT public.traiter_justificatif('a0000000-0000-0000-0000-0000000000f1', true) $$,
  '42501', NULL, 'l''Administrateur GSG non plus : la décision appartient à l''école');

SELECT pg_temp.sur(:'dir');
SELECT throws_ok($$ SELECT public.traiter_justificatif('a0000000-0000-0000-0000-0000000000f1', false) $$,
  '22023', 'MOTIF_REFUS_REQUIS', 'un refus s''explique');
SELECT is((public.traiter_justificatif('a0000000-0000-0000-0000-0000000000f1', true)).statut::text, 'accepte',
  'la direction accepte');
SELECT ok((SELECT justifie FROM public.presences WHERE fiche_eleve_id = 'a0000000-0000-0000-0000-0000000000e1'
           AND date_presence = '2026-10-27'), 'l''absence couverte devient justifiée');
SELECT is((public.traiter_justificatif('a0000000-0000-0000-0000-0000000000f1', true)).statut::text, 'accepte',
  'même décision rejouée : rien ne change');
SELECT throws_ok($$ SELECT public.traiter_justificatif('a0000000-0000-0000-0000-0000000000f1', false, 'non') $$,
  '22023', 'JUSTIFICATIF_DEJA_TRAITE', 'décision contraire après coup refusée');

INSERT INTO public.presences (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, saisi_par, date_presence, statut) VALUES
  ('a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000a1', 'a0000000-0000-0000-0000-0000000000c1',
   'a0000000-0000-0000-0000-0000000000e1', :'dir', '2026-10-28', 'absent');
SELECT ok((SELECT justifie FROM public.presences WHERE fiche_eleve_id = 'a0000000-0000-0000-0000-0000000000e1'
           AND date_presence = '2026-10-28'), 'absence saisie après l''acceptation : justifiée d''office');

-- ---------------------------------------------------------------------------
-- 3. Paramètres globaux
-- ---------------------------------------------------------------------------
SELECT throws_ok($$ SELECT public.definir_parametre_global('tarif_abonnement_premium_eleve_mensuel', '{"valeur": 5000}') $$,
  '42501', NULL, 'une direction ne règle pas les paramètres de la plateforme');

SELECT pg_temp.sur(:'gsg');
SELECT is(((public.definir_parametre_global('tarif_abonnement_premium_eleve_mensuel', '{"valeur": 5000}')).valeur ->> 'valeur'),
  '5000', 'l''Administrateur GSG règle le tarif ; changement historisé');
SELECT throws_ok($$ SELECT public.definir_parametre_global('tarif_abonnement_premium_eleve_mensuel', '{"valeur": "cinq mille"}') $$,
  '22023', 'TYPE_INVALIDE', 'un tarif reste un nombre');

SELECT * FROM finish();
ROLLBACK;
