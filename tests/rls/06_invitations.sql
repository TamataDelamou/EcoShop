-- ============================================================================
-- EcoShop — Test RLS 06 : invitations nominatives (ch. 5.2)
--
-- Vérifie que accepter_invitation() :
--   • accepte l'invitation dont l'identifiant cible correspond au compte ;
--   • fixe le rôle racine cible (rôle indéfini) ;
--   • refuse une invitation destinée à un autre identifiant.
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

SELECT plan(3);

-- ---------------------------------------------------------------------------
-- Données : un établissement et un destinataire sans rôle.
-- Le jeton n'est jamais stocké en clair : seule son empreinte SHA-256 l'est.
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug)
VALUES ('École Invitations', 'ecole-invitations')
RETURNING id AS etab_id \gset

SELECT pg_temp.creer_compte('224600000061', NULL) AS destinataire_id \gset

INSERT INTO public.invitations (etablissement_id, role_cible, identifiant_cible, jeton_empreinte)
VALUES
  (:'etab_id'::uuid, 'enseignant', '+224600000061',
   encode(extensions.digest('jeton-inv-1', 'sha256'), 'hex')),
  (:'etab_id'::uuid, 'enseignant', '+224600000062',
   encode(extensions.digest('jeton-inv-2', 'sha256'), 'hex'));

-- ---------------------------------------------------------------------------
-- 1. Le destinataire accepte l'invitation qui lui est adressée.
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'destinataire_id', 'role', 'authenticated')::text, true);

SELECT ok(
  (SELECT public.accepter_invitation('jeton-inv-1')) IS NOT NULL,
  'invitation : acceptée par le destinataire'
);

-- ---------------------------------------------------------------------------
-- 2. Le rôle racine cible est fixé.
-- ---------------------------------------------------------------------------
SELECT is(
  (SELECT role_racine::text FROM public.profiles WHERE id = :'destinataire_id'::uuid),
  'enseignant',
  'invitation : le rôle racine cible est attribué'
);

-- ---------------------------------------------------------------------------
-- 3. Une invitation destinée à un autre identifiant est refusée.
-- ---------------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT public.accepter_invitation('jeton-inv-2') $$,
  '42501',
  'INVITATION_AUTRE_DESTINATAIRE',
  'invitation : refusée pour un autre destinataire'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
