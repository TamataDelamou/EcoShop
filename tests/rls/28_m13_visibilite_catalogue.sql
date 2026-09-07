-- ============================================================================
-- EcoShop — Test RLS 28 : visibilité catalogue & sous-comptes marchands (M13)
--
-- Vérifie que :
--   • le catalogue (commerçants + produits) est visible par tout authentifié ;
--   • les sous-comptes marchands ne sont visibles que par les membres actifs
--     de l'établissement concerné (isolation stricte des encaissements) ;
--   • un membre d'un autre établissement et un compte étranger ne voient rien.
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

SELECT plan(5);

-- ---------------------------------------------------------------------------
-- Tenants + commerçant + produit + sous-comptes (établissement A)
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Marché A', 'ecole-marche-a') RETURNING id AS etab_a \gset
INSERT INTO public.etablissements (nom, slug) VALUES ('École Marché B', 'ecole-marche-b') RETURNING id AS etab_b \gset

INSERT INTO public.commercants (nom) VALUES ('Librairie Test M13') RETURNING id AS commercant_id \gset

INSERT INTO public.catalogues_produits (commercant_id, libelle, prix)
VALUES (:'commercant_id'::uuid, 'Manuel Test', 10000);

INSERT INTO public.sous_comptes_marchands (etablissement_id, fournisseur, libelle, reference_compte)
VALUES
  (:'etab_a'::uuid, 'cinetpay',     'CinetPay A',  'CIN-A'),
  (:'etab_a'::uuid, 'mobile_money', 'Mobile Money A', 'MM-A');

-- ---------------------------------------------------------------------------
-- Comptes : membre A, membre B, étranger
-- ---------------------------------------------------------------------------
SELECT pg_temp.creer_compte('224600001501', 'direction') AS membre_a \gset
SELECT pg_temp.creer_compte('224600001502', 'direction') AS membre_b \gset
SELECT pg_temp.creer_compte('224600001503', 'parent')    AS etranger \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'membre_a'::uuid, :'etab_a'::uuid, 'direction'),
  (:'membre_b'::uuid, :'etab_b'::uuid, 'direction');

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'etranger', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.catalogues_produits)::int, 1, 'authentifié : voit le catalogue');
SELECT is((SELECT count(*) FROM public.commercants)::int, 1, 'authentifié : voit les commerçants');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'membre_a', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.sous_comptes_marchands)::int, 2, 'membre A : voit ses sous-comptes');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'membre_b', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.sous_comptes_marchands)::int, 0, 'membre B : isolation (0 sous-compte de A)');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'etranger', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.sous_comptes_marchands)::int, 0, 'étranger : aucun sous-compte visible');

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
