-- ============================================================================
-- EcoShop — Test RLS 43 : M16, sous-livrable 4/7 — Parent IA (déclaration
-- manuelle)
--
-- Vérifie, dans cet ordre : activation par l'élève propriétaire ; REJET de
-- toute action des 3 fonctions SECURITY DEFINER par un tiers (un autre
-- élève, un parent — même confirmé — et le personnel de l'établissement) ;
-- visibilité stricte élève+parent confirmé, JAMAIS le personnel (divergence
-- délibérée de `fiche_visible()`) ; isolation d'un parent non lié même une
-- fois des données réelles présentes ; aucune policy d'écriture cliente sur
-- les 2 tables (INSERT rejeté, UPDATE sans effet) ; repli neutre 50/100 sans
-- donnée de risque ; verrou de 30 jours non contournable même par le
-- propriétaire légitime ; refus sans consentement ; refus sans
-- authentification.
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

SELECT plan(22);

-- ---------------------------------------------------------------------------
-- Tenant + comptes
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Parent IA M16', 'ecole-parent-ia-m16')
RETURNING id AS etab_id \gset

SELECT pg_temp.creer_compte('224600002481', 'eleve')      AS eleve1_id \gset
SELECT pg_temp.creer_compte('224600002482', 'eleve')      AS eleve2_id \gset
SELECT pg_temp.creer_compte('224600002483', 'parent')     AS parent_a_id \gset
SELECT pg_temp.creer_compte('224600002484', 'parent')     AS parent_b_id \gset
SELECT pg_temp.creer_compte('224600002485', 'direction')  AS dir_id \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_id'::uuid, :'etab_id'::uuid, 'direction');

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M16-PIA-001', 'TOURE', 'Fatoumata', '2012-01-01', :'eleve1_id'::uuid, now())
RETURNING id AS fiche1_id \gset

INSERT INTO public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES (:'etab_id'::uuid, 'M16-PIA-002', 'KEITA', 'Moussa', '2012-02-02', :'eleve2_id'::uuid, now())
RETURNING id AS fiche2_id \gset

-- parent_a : parent CONFIRMÉ de fiche1 uniquement. parent_b : aucun lien —
-- le "tiers" au sens de la vérification demandée.
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, statut, autorise)
VALUES (:'etab_id'::uuid, :'parent_a_id'::uuid, :'fiche1_id'::uuid, 'confirmee', true);

SET LOCAL ROLE authenticated;

-- ---------------------------------------------------------------------------
-- 1) Activation par l'élève propriétaire.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);

SELECT public.activer_parent_ia(:'fiche1_id'::uuid, true) AS activation_json \gset
SELECT is((:'activation_json'::jsonb) ->> 'actif', 'true', 'eleve1 active PARENT IA pour sa propre fiche');

-- ---------------------------------------------------------------------------
-- 2) Rejet par un tiers — les 3 fonctions SECURITY DEFINER, appelées avec la
--    fiche d'AUTRUI, doivent toutes refuser, quel que soit l'appelant.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve2_id', 'role', 'authenticated')::text, true);

SELECT throws_ok(
  format($$ SELECT public.activer_parent_ia('%s', true) $$, :'fiche1_id'),
  '42501',
  NULL
);
SELECT throws_ok(
  format($$ SELECT public.desactiver_parent_ia('%s') $$, :'fiche1_id'),
  '42501',
  NULL
);
SELECT throws_ok(
  format($$ SELECT public.enregistrer_restriction_parent_ia('%s', 'TikTok', 60, 80, 'msg forgé') $$, :'fiche1_id'),
  '42501',
  NULL
);

-- Le personnel/direction de l'établissement n'a PAS non plus d'autorité sur
-- cette fonction — seul l'élève propriétaire, jamais l'établissement.
SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.enregistrer_restriction_parent_ia('%s', 'TikTok', 60, 80, 'msg forgé par la direction') $$, :'fiche1_id'),
  '42501',
  NULL
);

-- Même le PARENT CONFIRMÉ de fiche1 ne peut jamais désactiver/activer à la
-- place de l'élève — seule la fiche `profile_id` compte, jamais une relation
-- parentale, même confirmée et autorisée.
SELECT set_config('request.jwt.claims', json_build_object('sub', :'parent_a_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.desactiver_parent_ia('%s') $$, :'fiche1_id'),
  '42501',
  NULL
);

-- ---------------------------------------------------------------------------
-- 3) Visibilité : élève propriétaire + parent confirmé, JAMAIS le
--    personnel/direction (divergence délibérée de `fiche_visible()`).
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM public.parent_ia_config WHERE fiche_eleve_id = :'fiche1_id'::uuid),
  1,
  'parent_a (confirmé) voit la configuration de fiche1'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'parent_b_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*)::int FROM public.parent_ia_config WHERE fiche_eleve_id = :'fiche1_id'::uuid),
  0,
  'parent_b (AUCUN lien avec fiche1) ne voit RIEN de sa configuration'
);
SELECT is(
  (SELECT count(*)::int FROM public.parent_ia_historique WHERE fiche_eleve_id = :'fiche1_id'::uuid),
  0,
  'parent_b ne voit rien de l''historique de fiche1 (encore vide à ce stade)'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*)::int FROM public.parent_ia_config WHERE fiche_eleve_id = :'fiche1_id'::uuid),
  0,
  'la direction de l''établissement ne voit RIEN — donnée de bien-être numérique exclue du personnel, contrairement à fiche_visible()'
);

-- ---------------------------------------------------------------------------
-- 4) Aucune policy d'écriture cliente : INSERT rejeté, UPDATE sans effet —
--    même pour l'élève propriétaire lui-même.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);

SELECT throws_ok(
  format($$ INSERT INTO public.parent_ia_config (fiche_eleve_id, etablissement_id, actif)
     VALUES ('%s', '%s', true) $$, :'fiche2_id', :'etab_id'),
  '42501',
  NULL
);

UPDATE public.parent_ia_config SET actif = false WHERE fiche_eleve_id = :'fiche1_id'::uuid;
SELECT is(
  (SELECT actif FROM public.parent_ia_config WHERE fiche_eleve_id = :'fiche1_id'::uuid),
  true,
  'UPDATE client direct sans effet (aucune policy update) — actif reste true'
);

-- ---------------------------------------------------------------------------
-- 5) Déclaration d'usage — repli neutre 50/100 (aucune donnée de risque
--    matérialisée), puis écriture de la restriction.
-- ---------------------------------------------------------------------------
SELECT public.preparer_declaration_usage_parent_ia(:'fiche1_id'::uuid, 'TikTok', 90) AS preparation_json \gset
SELECT is(
  ((:'preparation_json'::jsonb) ->> 'niveau_risque_echec')::int,
  50,
  'repli neutre 50/100 : aucune donnée de risque matérialisée pour eleve1'
);

SELECT public.enregistrer_restriction_parent_ia(:'fiche1_id'::uuid, 'TikTok', 90, 80, 'Attention à ton temps d''écran.', 'Mathématiques')
  AS restriction_id \gset
SELECT ok(:'restriction_id' IS NOT NULL, 'enregistrer_restriction_parent_ia réussit pour le propriétaire légitime');

SELECT is(
  (SELECT count(*)::int FROM public.parent_ia_historique WHERE fiche_eleve_id = :'fiche1_id'::uuid),
  1,
  'la restriction est bien écrite dans parent_ia_historique'
);
SELECT is(
  (SELECT count(*)::int FROM public.notifications
   WHERE destinataire = :'eleve1_id'::uuid AND type = 'parent_ia_restriction'),
  1,
  'une notification in-app est créée pour l''élève (canal existant M9, pas un mécanisme parallèle)'
);

-- Le parent confirmé voit désormais l'entrée ; le tiers non lié, toujours pas.
SELECT set_config('request.jwt.claims', json_build_object('sub', :'parent_a_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*)::int FROM public.parent_ia_historique WHERE fiche_eleve_id = :'fiche1_id'::uuid),
  1,
  'parent_a (confirmé) voit désormais la restriction, en lecture seule'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'parent_b_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*)::int FROM public.parent_ia_historique WHERE fiche_eleve_id = :'fiche1_id'::uuid),
  0,
  'parent_b reste isolé même une fois une vraie restriction écrite'
);

-- ---------------------------------------------------------------------------
-- 6) « Pas de consentement = pas d'analyse » + consentement requis à
--    l'activation.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve2_id', 'role', 'authenticated')::text, true);

SELECT throws_ok(
  format($$ SELECT public.preparer_declaration_usage_parent_ia('%s', 'YouTube', 30) $$, :'fiche2_id'),
  '22023',
  NULL
);
SELECT throws_ok(
  format($$ SELECT public.activer_parent_ia('%s', false) $$, :'fiche2_id'),
  '22023',
  NULL
);

-- ---------------------------------------------------------------------------
-- 7) Verrou de 30 jours non contournable — même par le propriétaire légitime.
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.desactiver_parent_ia('%s') $$, :'fiche1_id'),
  '42501',
  NULL
);

-- ---------------------------------------------------------------------------
-- 8) Sans authentification.
-- ---------------------------------------------------------------------------
RESET ROLE;
SELECT set_config('request.jwt.claims', NULL, true);

SELECT throws_ok(
  format($$ SELECT public.activer_parent_ia('%s', true) $$, :'fiche1_id'),
  '28000',
  NULL
);

SELECT * FROM finish();
ROLLBACK;
