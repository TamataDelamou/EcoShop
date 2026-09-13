-- ============================================================================
-- EcoShop — Test RLS 47 : D6 (perception des frais par classe & fast-track
-- d'inscription — dernier module de la Phase D)
--
-- Vérifie que :
--   • `rechercher_enfants_par_telephone_parent` (cahier §7.1) renvoie la
--     fratrie COMPLÈTE d'un numéro de téléphone parent (jamais un seul
--     enfant pris arbitrairement, contrairement au prototype source) ;
--   • seules les relations parent↔enfant CONFIRMÉES et AUTORISÉES sont
--     renvoyées (une relation en attente ou non autorisée est exclue) ;
--   • un numéro inconnu renvoie un ensemble vide (pas une erreur) ;
--   • la recherche est bien scopée à l'établissement demandé (même parent,
--     même numéro, mais aucune relation dans l'établissement B ⇒ vide) ;
--   • un compte sans droit de gestion de la scolarité ni direction ne peut
--     pas l'appeler (42501) ;
--   • correctif de sécurité — `solde_scolarite` (M15quater) n'avait AUCUNE
--     vérification d'autorisation : elle exige désormais
--     `est_personnel(etablissement) or fiche_visible(fiche)`, exactement la
--     frontière déjà retenue pour `encaissements_scolarite` (20260906001502).
--     Vérifié : direction (personnel) OK, parent confirmé de l'enfant OK
--     (régression), un tiers authentifié SANS lien ni rôle dans
--     l'établissement REFUSÉ (42501 — c'est la fuite financière inter-tenant
--     corrigée), la direction d'un AUTRE établissement REFUSÉE (42501),
--     une inscription inexistante lève une erreur dédiée (23514) ;
--   • le calcul du solde (tarif − encaissements validés) reste correct après
--     la conversion sql -> plpgsql (non-régression arithmétique).
--
-- Note technique : même convention que 38_m15quater_inscription_encaissement
-- (helper `pg_temp.creer_compte`, `format(%L, :'var')` hors des blocs
-- dollar-quotés). La perception par classe elle-même n'ajoute aucune RPC
-- (elle réutilise `inscriptions_de_classe` + `solde_scolarite`) — rien à
-- tester ici au-delà du correctif de `solde_scolarite` ci-dessus.
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

SELECT plan(14);

-- ---------------------------------------------------------------------------
-- Établissements A et B, année courante, une classe en A, comptes.
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('47000000-0000-0000-0000-000000000001', 'École D6 Fast-Track', 'ecole-d6-fasttrack');

INSERT INTO public.etablissements (id, nom, slug)
VALUES ('47000000-0000-0000-0000-000000000099', 'École D6 B (isolation)', 'ecole-d6-b-isolation');

INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('47000000-0000-0000-0000-000000000002', '47000000-0000-0000-0000-000000000001', '2026-2027', '2026-10-01', '2027-06-30', true);

INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom)
VALUES ('47000000-0000-0000-0000-000000000003', '47000000-0000-0000-0000-000000000001',
        '47000000-0000-0000-0000-000000000002', '6A-D6', '6e A');

SELECT pg_temp.creer_compte('224700001001', 'direction') AS dir_id       \gset
SELECT pg_temp.creer_compte('224700001002', 'parent')    AS parent_id    \gset
SELECT pg_temp.creer_compte('224700001003', 'eleve')     AS etranger_id  \gset
SELECT pg_temp.creer_compte('224700001004', 'direction') AS dir_b_id     \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_id'::uuid, '47000000-0000-0000-0000-000000000001', 'direction');

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_b_id'::uuid, '47000000-0000-0000-0000-000000000099', 'direction');

-- ---------------------------------------------------------------------------
-- Fiches : deux enfants confirmés+autorisés (fratrie réelle), un troisième
-- non autorisé, un quatrième en attente — tous rattachés au même parent.
-- ---------------------------------------------------------------------------
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance)
VALUES
  ('47000000-0000-0000-0000-000000000010', '47000000-0000-0000-0000-000000000001', 'D6-0001', 'CAMARA', 'Mory', '2013-04-12'),
  ('47000000-0000-0000-0000-000000000011', '47000000-0000-0000-0000-000000000001', 'D6-0002', 'CAMARA', 'Aicha', '2015-06-20'),
  ('47000000-0000-0000-0000-000000000012', '47000000-0000-0000-0000-000000000001', 'D6-0003', 'SANGARE', 'Ibrahim', '2012-01-05'),
  ('47000000-0000-0000-0000-000000000013', '47000000-0000-0000-0000-000000000001', 'D6-0004', 'BARRY', 'Fatoumata', '2014-09-09');

INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
VALUES
  ('47000000-0000-0000-0000-000000000001', :'parent_id'::uuid, '47000000-0000-0000-0000-000000000010'::uuid, 'parent', 'confirmee', true),
  ('47000000-0000-0000-0000-000000000001', :'parent_id'::uuid, '47000000-0000-0000-0000-000000000011'::uuid, 'parent', 'confirmee', true),
  ('47000000-0000-0000-0000-000000000001', :'parent_id'::uuid, '47000000-0000-0000-0000-000000000012'::uuid, 'parent', 'confirmee', false),
  ('47000000-0000-0000-0000-000000000001', :'parent_id'::uuid, '47000000-0000-0000-0000-000000000013'::uuid, 'parent', 'en_attente', true);

-- Inscription de Mory dans la classe A, pour les tests de solde_scolarite.
INSERT INTO public.inscriptions (id, etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
VALUES ('47000000-0000-0000-0000-000000000020', '47000000-0000-0000-0000-000000000001',
        '47000000-0000-0000-0000-000000000010'::uuid, '47000000-0000-0000-0000-000000000003'::uuid,
        '47000000-0000-0000-0000-000000000002'::uuid, 'active');

INSERT INTO public.frais_scolarite_config (etablissement_id, annee_scolaire_id, niveau_id, montant_annuel)
VALUES ('47000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000002', null, 1000000);

-- ---------------------------------------------------------------------------
-- Assertions — fast-track d'inscription (§7.1)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

-- L'encaissement fixture doit être inséré APRÈS le passage en rôle
-- `authenticated` avec les claims de dir_id : le trigger
-- `encaissements_verifie_tenant` impose `saisi_par := auth.uid()`
-- inconditionnellement (jamais transmis par le client, cf. M15quater) — un
-- INSERT fait en tant que `postgres` (sans claims) échouerait sur la
-- contrainte NOT NULL, comme le fait déjà `38_m15quater...` pour la même
-- raison.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
INSERT INTO public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, montant)
VALUES ('47000000-0000-0000-0000-000000000001', '47000000-0000-0000-0000-000000000010'::uuid,
        '47000000-0000-0000-0000-000000000020'::uuid, 400000);

-- 1. Direction : la fratrie complète est renvoyée (2 enfants, jamais 1 seul).
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.rechercher_enfants_par_telephone_parent(
     '47000000-0000-0000-0000-000000000001', '+224700001002'))::int,
  2,
  'fast-track : la fratrie complète (2 enfants confirmés+autorisés) est renvoyée, jamais un seul (eleves.first)'
);

-- 2. Les matricules renvoyés sont bien ceux des deux enfants confirmés.
SELECT is(
  (SELECT array_agg(matricule ORDER BY matricule) FROM public.rechercher_enfants_par_telephone_parent(
     '47000000-0000-0000-0000-000000000001', '+224700001002')),
  ARRAY['D6-0001', 'D6-0002'],
  'fast-track : matricules exacts des deux enfants confirmés+autorisés'
);

-- 3. L'enfant non autorisé (autorise = false) est exclu.
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.rechercher_enfants_par_telephone_parent(
      '47000000-0000-0000-0000-000000000001', '+224700001002')
    WHERE matricule = 'D6-0003'
  ),
  'fast-track : une relation non autorisée (autorise = false) est exclue'
);

-- 4. L'enfant à la relation "en_attente" (non confirmée) est exclu.
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.rechercher_enfants_par_telephone_parent(
      '47000000-0000-0000-0000-000000000001', '+224700001002')
    WHERE matricule = 'D6-0004'
  ),
  'fast-track : une relation non confirmée (en_attente) est exclue'
);

-- 5. Numéro inconnu : ensemble vide, pas une erreur.
SELECT is(
  (SELECT count(*) FROM public.rechercher_enfants_par_telephone_parent(
     '47000000-0000-0000-0000-000000000001', '+224799999999'))::int,
  0,
  'fast-track : numéro inconnu renvoie un ensemble vide, pas une erreur'
);

-- 6. Même parent, même numéro, mais établissement B : scopé, donc vide (pas
-- de fuite d'une fratrie enregistrée dans un autre établissement).
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_b_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.rechercher_enfants_par_telephone_parent(
     '47000000-0000-0000-0000-000000000099', '+224700001002'))::int,
  0,
  'fast-track : scopé à l''établissement demandé — aucune relation dans B pour ce numéro'
);

-- 7. Un compte sans droit de gestion ni direction ne peut pas rechercher.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT * FROM public.rechercher_enfants_par_telephone_parent(
       '47000000-0000-0000-0000-000000000001', '+224700001002') $$,
  '42501',
  NULL
);

-- ---------------------------------------------------------------------------
-- Assertions — correctif de sécurité solde_scolarite (fuite inter-tenant)
-- ---------------------------------------------------------------------------

-- 8. Direction (personnel) : lecture autorisée, calcul correct (tarif
-- 1 000 000 − 400 000 payés = 600 000), non-régression après conversion en
-- plpgsql.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT montant_du FROM public.solde_scolarite('47000000-0000-0000-0000-000000000020'::uuid))::numeric,
  1000000::numeric,
  'solde_scolarite : montant dû correct (non-régression après conversion plpgsql)'
);
SELECT is(
  (SELECT montant_paye FROM public.solde_scolarite('47000000-0000-0000-0000-000000000020'::uuid))::numeric,
  400000::numeric,
  'solde_scolarite : montant payé correct'
);
SELECT is(
  (SELECT solde FROM public.solde_scolarite('47000000-0000-0000-0000-000000000020'::uuid))::numeric,
  600000::numeric,
  'solde_scolarite : solde correct (dû − payé)'
);

-- 9. Parent confirmé de l'enfant concerné : lecture autorisée (fiche_visible).
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'parent_id', 'role', 'authenticated')::text, true);
SELECT lives_ok(
  $$ SELECT * FROM public.solde_scolarite('47000000-0000-0000-0000-000000000020'::uuid) $$,
  'solde_scolarite : parent confirmé de l''enfant concerné peut lire son solde'
);

-- 10. CORRECTIF — un tiers authentifié sans lien ni rôle dans l'établissement
-- ne peut PAS lire le solde d'un inscription qui ne le concerne pas (avant
-- correctif : aucune vérification, la fuite était totale et inter-tenant).
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT * FROM public.solde_scolarite('47000000-0000-0000-0000-000000000020'::uuid) $$,
  '42501',
  NULL
);

-- 11. CORRECTIF — la direction d'un AUTRE établissement ne peut pas non plus
-- lire ce solde (isolation inter-établissement réelle, pas juste un tiers
-- non affilié).
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_b_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT * FROM public.solde_scolarite('47000000-0000-0000-0000-000000000020'::uuid) $$,
  '42501',
  NULL
);

-- 12. Inscription inexistante : erreur dédiée, jamais un solde à zéro
-- silencieux qui masquerait la faute de frappe d'un appelant.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT * FROM public.solde_scolarite('00000000-0000-0000-0000-000000000000'::uuid) $$,
  '23514',
  NULL
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
