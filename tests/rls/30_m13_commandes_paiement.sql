-- ============================================================================
-- EcoShop — Test RLS 30 : commandes & paiements (M13)
--
-- Vérifie que :
--   • le propriétaire de la commande la voit ;
--   • un membre (direction) du même établissement la voit ;
--   • un membre d'un autre établissement ne la voit pas ;
--   • un paiement dont le fournisseur diffère du sous-compte est rejeté (23514).
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

SELECT plan(4);

-- ---------------------------------------------------------------------------
-- Tenants + commerçant + produit + sous-compte cinetpay + commande
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Cmd A', 'ecole-cmd-a') RETURNING id AS etab_a \gset
INSERT INTO public.etablissements (nom, slug) VALUES ('École Cmd B', 'ecole-cmd-b') RETURNING id AS etab_b \gset

INSERT INTO public.commercants (nom) VALUES ('Commerçant Cmd') RETURNING id AS comm_id \gset

INSERT INTO public.catalogues_produits (commercant_id, libelle, prix)
VALUES (:'comm_id'::uuid, 'Produit Cmd', 5000);

INSERT INTO public.sous_comptes_marchands (etablissement_id, fournisseur, libelle, reference_compte)
VALUES (:'etab_a'::uuid, 'cinetpay', 'CinetPay Cmd A', 'CIN-CMD-A');

SELECT pg_temp.creer_compte('224600001701', 'parent')    AS acheteur \gset
SELECT pg_temp.creer_compte('224600001702', 'direction') AS direction_a \gset
SELECT pg_temp.creer_compte('224600001703', 'direction') AS direction_b \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'direction_a'::uuid, :'etab_a'::uuid, 'direction'),
  (:'direction_b'::uuid, :'etab_b'::uuid, 'direction');

INSERT INTO public.commandes
  (etablissement_id, commercant_id, profile_id, reference, statut, montant_total, devise)
VALUES
  (:'etab_a'::uuid, :'comm_id'::uuid, :'acheteur'::uuid, 'CMD-T30-0001', 'confirmee', 5000, 'GNF')
RETURNING id AS commande_id \gset

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'acheteur', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.commandes)::int, 1, 'propriétaire : voit sa commande');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'direction_a', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.commandes)::int, 1, 'direction même établissement : voit la commande');

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'direction_b', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.commandes)::int, 0, 'direction autre établissement : ne voit rien');

-- Paiement incohérent : sous-compte cinetpay + fournisseur mobile_money → 23514.
SELECT throws_ok(
  $sql$
    INSERT INTO public.paiements
      (etablissement_id, commande_id, sous_compte_id, fournisseur, montant, statut)
    SELECT c.etablissement_id, c.id, sc.id, 'mobile_money', c.montant_total, 'initie'
    FROM public.commandes c
    JOIN public.sous_comptes_marchands sc ON sc.etablissement_id = c.etablissement_id AND sc.fournisseur = 'cinetpay'
    WHERE c.reference = 'CMD-T30-0001'
  $sql$,
  '23514', NULL, 'paiement fournisseur incohérent : rejeté (PAIEMENT_FOURNISSEUR_INCOHERENT)'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
