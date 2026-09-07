-- ============================================================================
-- EcoShop — Test RLS 33 : fonctions comptables & IA (M14)
--
-- Vérifie que :
--   • le journal restitue les écritures chronologiques ;
--   • le grand livre regroupe les mouvements d'un compte ;
--   • la balance calcule les soldes débit/crédit correctement ;
--   • la détection d'anomalies signale une double saisie.
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
-- Tenant + comptes + journal + direction + écritures
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École États', 'ecole-etats') RETURNING id AS etab_id \gset

INSERT INTO public.plans_comptables (etablissement_id, code, intitule, type) VALUES
  (:'etab_id'::uuid, '520', 'Banque',   'banque'),
  (:'etab_id'::uuid, '600', 'Charges',  'charge'),
  (:'etab_id'::uuid, '701', 'Scolarité','produit');

INSERT INTO public.journaux (etablissement_id, code, intitule)
VALUES (:'etab_id'::uuid, 'BQ', 'Livre de banque');

SELECT pg_temp.creer_compte('224600002001', 'direction') AS direction \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'direction'::uuid, :'etab_id'::uuid, 'direction');

-- Écritures : scolarité 500000, fournitures 85000 (une fois), + une double saisie.
INSERT INTO public.ecritures_comptables
  (etablissement_id, date_ecriture, libelle, compte_debit_id, compte_credit_id, montant, journal_id)
SELECT :'etab_id'::uuid, v.date_ecriture, v.libelle, d.id, c.id, v.montant, j.id
FROM (values
  ('2026-09-15', 'Scolarité',    '520', '701', 500000),
  ('2026-09-25', 'Fournitures',  '600', '520',  85000),
  ('2026-09-25', 'Fournitures',  '600', '520',  85000)
) as v(date_ecriture, libelle, dcode, ccode, montant)
JOIN public.plans_comptables d ON d.code = v.dcode AND d.etablissement_id = :'etab_id'::uuid
JOIN public.plans_comptables c ON c.code = v.ccode AND c.etablissement_id = :'etab_id'::uuid
CROSS JOIN public.journaux j
WHERE j.code = 'BQ' AND j.etablissement_id = :'etab_id'::uuid;

-- ---------------------------------------------------------------------------
-- Assertions (fonctions SECURITY DEFINER, appelées en tant que direction)
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'direction', 'role', 'authenticated')::text, true);

SELECT is(
  (SELECT count(*) FROM public.journal_comptable(
     :'etab_id'::uuid,
     (SELECT id FROM public.journaux WHERE code = 'BQ' AND etablissement_id = :'etab_id'::uuid),
     '2026-01-01', '2026-12-31'))::int,
  3, 'journal : 3 écritures restituées'
);

SELECT is(
  (SELECT count(*) FROM public.grand_livre(
     :'etab_id'::uuid,
     (SELECT id FROM public.plans_comptables WHERE code = '520' AND etablissement_id = :'etab_id'::uuid),
     '2026-01-01', '2026-12-31'))::int,
  3, 'grand livre banque : 3 mouvements (2 crédits + 1 débit)'
);

SELECT is(
  (SELECT solde_debit FROM public.balance_comptable(:'etab_id'::uuid, '2026-12-31')
    WHERE code = '520')::numeric,
  330000, 'balance banque : solde débiteur = 500000 - 2×85000'
);

SELECT is(
  (SELECT count(*) FROM public.detecter_anomalies_comptables(:'etab_id'::uuid))::int,
  2, 'IA anomalies : double saisie « Fournitures » détectée (2 lignes)'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
