-- ============================================================================
-- EcoShop — Test RLS 35 : catalogue marketplace public (M15)
--
-- Vérifie le parcours invité : sans authentification, l'utilisateur voit le
-- catalogue (commerçants + produits) mais n'accède pas aux paniers.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

SELECT plan(3);

-- ---------------------------------------------------------------------------
-- Commerçant + produit (insérés hors RLS)
-- ---------------------------------------------------------------------------
INSERT INTO public.commercants (nom) VALUES ('Commerçant Public M15') RETURNING id AS comm_id \gset
INSERT INTO public.catalogues_produits (commercant_id, libelle, prix)
VALUES (:'comm_id'::uuid, 'Ressource publique', 2500);

-- ---------------------------------------------------------------------------
-- Assertions (rôle anon, sans JWT)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE anon;

SELECT is((SELECT count(*) FROM public.commercants)::int, 1, 'anon : voit les commerçants (catalogue public)');
SELECT is((SELECT count(*) FROM public.catalogues_produits)::int, 1, 'anon : voit les produits (catalogue public)');
SELECT is((SELECT count(*) FROM public.paniers)::int, 0, 'anon : aucun panier visible (espaces protégés)');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
