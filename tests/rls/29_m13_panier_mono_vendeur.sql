-- ============================================================================
-- EcoShop — Test RLS 29 : panier mono-vendeur (M13)
--
-- Vérifie la règle métier stricte « panier mono-vendeur » :
--   • l'ajout d'un produit du commerçant du panier est accepté ;
--   • l'ajout d'un produit d'un AUTRE commerçant est rejeté (23514).
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

SELECT plan(2);

-- ---------------------------------------------------------------------------
-- Tenant + 2 commerçants (1 produit chacun) + acheteur + panier (commerçant 1)
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Panier', 'ecole-panier') RETURNING id AS etab_id \gset

INSERT INTO public.commercants (nom) VALUES ('Commerçant P1') RETURNING id AS comm1 \gset
INSERT INTO public.commercants (nom) VALUES ('Commerçant P2') RETURNING id AS comm2 \gset

INSERT INTO public.catalogues_produits (commercant_id, libelle, prix)
VALUES
  (:'comm1'::uuid, 'Produit P1', 1000),
  (:'comm2'::uuid, 'Produit P2', 2000);

SELECT pg_temp.creer_compte('224600001601', 'parent') AS acheteur \gset

INSERT INTO public.paniers (etablissement_id, profile_id, commercant_id, statut)
VALUES (:'etab_id'::uuid, :'acheteur'::uuid, :'comm1'::uuid, 'actif')
RETURNING id AS panier_id \gset

-- ---------------------------------------------------------------------------
-- Assertions (l'exception du garde-fou est testée via throws_ok)
-- ---------------------------------------------------------------------------
-- 1. Produit du même commerçant → accepté.
INSERT INTO public.lignes_paniers (panier_id, catalogue_produit_id, quantite)
SELECT p.id, cp.id, 1
FROM public.paniers p
JOIN public.catalogues_produits cp ON cp.libelle = 'Produit P1'
WHERE p.id = (SELECT id FROM public.paniers WHERE commercant_id = :'comm1'::uuid LIMIT 1);

SELECT is((SELECT count(*) FROM public.lignes_paniers)::int, 1, 'ajout produit du même commerçant : accepté');

-- 2. Produit d'un autre commerçant → rejet (garde-fou mono-vendeur, SQLSTATE 23514).
SELECT throws_ok(
  $sql$
    INSERT INTO public.lignes_paniers (panier_id, catalogue_produit_id, quantite)
    SELECT p.id, cp.id, 1
    FROM public.paniers p
    JOIN public.catalogues_produits cp ON cp.libelle = 'Produit P2'
    WHERE p.commercant_id IS NOT NULL
  $sql$,
  '23514', NULL, 'ajout produit d''un autre commerçant : rejeté (PANIER_MONO_VENDEUR)'
);

SELECT * FROM finish();
ROLLBACK;
