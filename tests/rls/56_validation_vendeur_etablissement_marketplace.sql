-- ============================================================================
-- EcoShop — Test RLS 56 : validation vendeur (GSG) + agrément
-- établissement <-> vendeur (Direction) avant activation marketplace
-- (cahier §27.1-27.2, §30.1-30.2 ; migration 20260906001524).
--
-- Couvre : valider_vendeur() réservée admin_gsg ; decider_agrement_
-- vendeur_etablissement() réservée à la Direction de l'établissement
-- concerné (refus pour une AUTRE direction, isolation réelle), refusée tant
-- que le vendeur n'est pas validé GSG (ordre des paliers) ; porte RLS sur
-- commandes_insert -- refus vendeur non validé, refus vendeur validé GSG
-- mais non agréé par CET établissement, refus vendeur agréé par un AUTRE
-- établissement (pas de fuite d'agrément inter-établissements), succès
-- légitime une fois les deux paliers "valide" ; refus après un "refuse"
-- explicite (pas seulement l'absence de ligne) ; visibilité des agréments
-- (personnel + admin_gsg, jamais un étranger).
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

SELECT plan(18);

-- ---------------------------------------------------------------------------
-- Deux établissements (A cible, B isolation) + deux vendeurs (comm_ok validé
-- GSG en fin de scénario, comm_refuse jamais validé) + un produit chacun.
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Vendeur A', 'ecole-vendeur-56-a') RETURNING id AS etab_a_id \gset
INSERT INTO public.etablissements (nom, slug) VALUES ('École Vendeur B', 'ecole-vendeur-56-b') RETURNING id AS etab_b_id \gset

INSERT INTO public.commercants (nom) VALUES ('Vendeur 56 OK') RETURNING id AS comm_ok_id \gset
INSERT INTO public.commercants (nom) VALUES ('Vendeur 56 Non Valide') RETURNING id AS comm_non_valide_id \gset

INSERT INTO public.catalogues_produits (commercant_id, libelle, prix)
VALUES (:'comm_ok_id'::uuid, 'Produit 56 OK', 1000) RETURNING id AS produit_ok_id \gset
INSERT INTO public.catalogues_produits (commercant_id, libelle, prix)
VALUES (:'comm_non_valide_id'::uuid, 'Produit 56 NV', 1500) RETURNING id AS produit_nv_id \gset

SELECT pg_temp.creer_compte('224630001001', 'parent')     AS acheteur_id    \gset
SELECT pg_temp.creer_compte('224630001002', 'direction')  AS direction_a_id \gset
SELECT pg_temp.creer_compte('224630001003', 'direction')  AS direction_b_id \gset
SELECT pg_temp.creer_compte('224630001004', 'admin_gsg')  AS admin_gsg_id   \gset
SELECT pg_temp.creer_compte('224630001005', 'eleve')      AS etranger_id    \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'direction_a_id'::uuid, :'etab_a_id'::uuid, 'direction'),
  (:'direction_b_id'::uuid, :'etab_b_id'::uuid, 'direction');

-- ===========================================================================
-- 1-3. valider_vendeur() -- réservée admin_gsg.
-- ===========================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.valider_vendeur('%s', 'valide') $$, :'comm_ok_id'),
  '42501', 'PERMISSION_REFUSEE',
  'valider_vendeur : refusée à une direction d''établissement (réservée GSG)'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT lives_ok(
  format($$ SELECT public.valider_vendeur('%s', 'refuse', 'dossier incomplet') $$, :'comm_non_valide_id'),
  'valider_vendeur : admin_gsg refuse le vendeur non conforme'
);
SELECT lives_ok(
  format($$ SELECT public.valider_vendeur('%s', 'valide') $$, :'comm_ok_id'),
  'valider_vendeur : admin_gsg valide le vendeur conforme'
);

-- ===========================================================================
-- 4-6. decider_agrement_vendeur_etablissement() -- réservée à la Direction
-- de l'établissement concerné, refusée tant que le vendeur n'est pas validé
-- GSG (ordre des paliers).
-- ===========================================================================
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.decider_agrement_vendeur_etablissement('%s', '%s', 'valide') $$, :'comm_ok_id', :'etab_a_id'),
  '42501', 'PERMISSION_REFUSEE',
  'decider_agrement_vendeur_etablissement : refusée à admin_gsg lui-même -- ce palier appartient à l''établissement, pas à GSG'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.decider_agrement_vendeur_etablissement('%s', '%s', 'valide') $$, :'comm_non_valide_id', :'etab_a_id'),
  '23514', 'VENDEUR_NON_VALIDE_GSG',
  'decider_agrement_vendeur_etablissement : refusée -- le vendeur n''est pas (encore/plus) validé par GSG'
);
SELECT lives_ok(
  format($$ SELECT public.decider_agrement_vendeur_etablissement('%s', '%s', 'valide') $$, :'comm_ok_id', :'etab_a_id'),
  'decider_agrement_vendeur_etablissement : succès -- direction A agrée le vendeur validé GSG pour SON établissement'
);

-- ===========================================================================
-- 7-12. Porte RLS commandes_insert : refus vendeur non validé GSG, refus
-- vendeur validé GSG mais non agréé par CET établissement, refus agrément
-- d'un AUTRE établissement (pas de fuite), succès légitime une fois les deux
-- paliers "valide" dans le bon établissement.
-- ===========================================================================
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'acheteur_id', 'role', 'authenticated')::text, true);

SELECT throws_ok(
  format(
    $$ insert into public.commandes (etablissement_id, commercant_id, profile_id, reference, montant_total) values ('%s', '%s', '%s', 'CMD-56-001', 1500) $$,
    :'etab_a_id', :'comm_non_valide_id', :'acheteur_id'
  ),
  '42501', NULL,
  'commandes (INSERT) : refusé -- vendeur explicitement refusé par GSG (pas seulement non traité)'
);

-- Un TROISIÈME vendeur jamais traité par GSG (statut par défaut en_attente).
RESET ROLE;
INSERT INTO public.commercants (nom) VALUES ('Vendeur 56 En Attente') RETURNING id AS comm_attente_id \gset
INSERT INTO public.catalogues_produits (commercant_id, libelle, prix) VALUES (:'comm_attente_id'::uuid, 'Produit 56 Attente', 800);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'acheteur_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format(
    $$ insert into public.commandes (etablissement_id, commercant_id, profile_id, reference, montant_total) values ('%s', '%s', '%s', 'CMD-56-002', 800) $$,
    :'etab_a_id', :'comm_attente_id', :'acheteur_id'
  ),
  '42501', NULL,
  'commandes (INSERT) : refusé -- vendeur jamais validé GSG (statut par défaut en_attente)'
);

-- Vendeur validé GSG mais PAS ENCORE agréé par l'établissement A pour cette
-- assertion précise -- on le teste via l'établissement B, où aucun agrément
-- n'existe du tout.
SELECT throws_ok(
  format(
    $$ insert into public.commandes (etablissement_id, commercant_id, profile_id, reference, montant_total) values ('%s', '%s', '%s', 'CMD-56-003', 1000) $$,
    :'etab_b_id', :'comm_ok_id', :'acheteur_id'
  ),
  '42501', NULL,
  'commandes (INSERT) : refusé -- vendeur validé GSG mais PAS agréé par CET établissement (B) -- pas de fuite d''agrément inter-établissements'
);

SELECT lives_ok(
  format(
    $$ insert into public.commandes (etablissement_id, commercant_id, profile_id, reference, montant_total) values ('%s', '%s', '%s', 'CMD-56-004', 1000) $$,
    :'etab_a_id', :'comm_ok_id', :'acheteur_id'
  ),
  'commandes (INSERT) : succès -- vendeur validé GSG ET agréé par l''établissement A'
);
SELECT is(
  (SELECT count(*)::int FROM public.commandes WHERE reference = 'CMD-56-004'),
  1,
  'commandes : la commande légitime existe bien en base'
);

-- Refus explicite d'agrément par la Direction (pas seulement l'absence de
-- ligne) : la Direction A change d'avis et refuse le vendeur pourtant
-- validé GSG -- doit bloquer une NOUVELLE commande.
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT lives_ok(
  format($$ SELECT public.decider_agrement_vendeur_etablissement('%s', '%s', 'refuse', 'litige livraison') $$, :'comm_ok_id', :'etab_a_id'),
  'decider_agrement_vendeur_etablissement : la direction A peut revenir sur sa décision et refuser'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'acheteur_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format(
    $$ insert into public.commandes (etablissement_id, commercant_id, profile_id, reference, montant_total) values ('%s', '%s', '%s', 'CMD-56-005', 1000) $$,
    :'etab_a_id', :'comm_ok_id', :'acheteur_id'
  ),
  '42501', NULL,
  'commandes (INSERT) : refusé après un refus explicite d''agrément, même pour un établissement qui l''avait accepté avant'
);

-- ===========================================================================
-- 13-14. Isolation réelle sur decider_agrement_vendeur_etablissement : la
-- direction de l'établissement B ne peut pas agréer un vendeur POUR
-- l'établissement A.
-- ===========================================================================
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_b_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ SELECT public.decider_agrement_vendeur_etablissement('%s', '%s', 'valide') $$, :'comm_ok_id', :'etab_a_id'),
  '42501', 'PERMISSION_REFUSEE',
  'decider_agrement_vendeur_etablissement : la direction B ne peut pas agréer un vendeur pour l''établissement A'
);
SELECT lives_ok(
  format($$ SELECT public.decider_agrement_vendeur_etablissement('%s', '%s', 'valide') $$, :'comm_ok_id', :'etab_b_id'),
  'decider_agrement_vendeur_etablissement : la direction B agrée légitimement le même vendeur POUR SON PROPRE établissement B'
);

-- ===========================================================================
-- 15-17. Visibilité de agrements_vendeurs_etablissements : personnel +
-- admin_gsg, jamais un étranger sans lien.
-- ===========================================================================
SELECT is(
  (SELECT count(*) FROM public.agrements_vendeurs_etablissements WHERE etablissement_id = :'etab_b_id'::uuid),
  1::bigint,
  'agrements_vendeurs_etablissements : la direction B voit l''agrément de son propre établissement'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.agrements_vendeurs_etablissements),
  0::bigint,
  'agrements_vendeurs_etablissements : un étranger sans lien avec aucun établissement ne voit rien'
);

RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.agrements_vendeurs_etablissements),
  2::bigint,
  'agrements_vendeurs_etablissements : admin_gsg voit les agréments de TOUS les établissements'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
