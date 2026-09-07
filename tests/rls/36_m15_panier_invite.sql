-- ============================================================================
-- EcoShop — Test RLS 36 : panier & commande invités (M15)
--
-- Vérifie que :
--   • un panier peut appartenir à un profil public (invité) sans compte ;
--   • un panier sans propriétaire (ni profil ni invité) est rejeté ;
--   • une commande peut être rattachée à un profil public.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

SELECT plan(3);

-- ---------------------------------------------------------------------------
-- Établissement + commerçant + profil public (insérés hors RLS)
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (nom, slug) VALUES ('École Invité M15', 'ecole-invite-m15') RETURNING id AS etab_id \gset
INSERT INTO public.commercants (nom) VALUES ('Commerçant Invité M15') RETURNING id AS comm_id \gset
INSERT INTO public.profils_publics (nom, email) VALUES ('Invité Acheteur', 'invite.acheteur@example.com')
RETURNING id AS visiteur_id \gset

-- ---------------------------------------------------------------------------
-- Assertions (hors RLS, rôle de connexion superutilisateur)
-- ---------------------------------------------------------------------------
INSERT INTO public.paniers (etablissement_id, visiteur_id, commercant_id, statut)
VALUES (:'etab_id'::uuid, :'visiteur_id'::uuid, :'comm_id'::uuid, 'actif');
SELECT is((SELECT count(*) FROM public.paniers WHERE visiteur_id = :'visiteur_id'::uuid)::int, 1,
          'panier invité : accepté (propriétaire = profil public)');

SELECT throws_ok(
  $sql$
    INSERT INTO public.paniers (etablissement_id, commercant_id, statut)
    SELECT e.id, c.id, 'actif'
    FROM public.etablissements e, public.commercants c
    WHERE e.slug = 'ecole-invite-m15' AND c.nom = 'Commerçant Invité M15'
  $sql$,
  '23514', NULL, 'panier sans propriétaire : rejeté (PANIER_PROPRIETAIRE_REQUIS)'
);

INSERT INTO public.commandes
  (etablissement_id, commercant_id, visiteur_id, reference, statut, montant_total, devise)
VALUES
  (:'etab_id'::uuid, :'comm_id'::uuid, :'visiteur_id'::uuid, 'CMD-M15-0001', 'confirmee', 2500, 'GNF');
SELECT is((SELECT count(*) FROM public.commandes WHERE reference = 'CMD-M15-0001')::int, 1,
          'commande invitée : acceptée (rattachée au profil public)');

SELECT * FROM finish();
ROLLBACK;
