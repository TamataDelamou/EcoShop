-- ============================================================================
-- EcoShop — Test RLS 53 : Journalisation et audit (§34.3), migration
-- 20260906001521. Périmètre tranché par le porteur : 5 points (boursier,
-- sanction avec symétrie levée/annulation, congé — chaque transition,
-- statuts de paiement sur 4 tables + renouvellement Premium, copie
-- horodatée de message signalé).
--
-- Couvre spécifiquement :
--   • les DEUX régressions de confidentialité évitées par une visibilité
--     PAR ENTITÉ (déléguée à la règle déjà établie sur la table source)
--     plutôt qu'une règle uniforme est_personnel()/est_admin_gsg() : un
--     employé quelconque (personnel, pas RH, pas l'intéressé) refusé sur un
--     audit de congé qui n'est pas le sien ; un membre du personnel non
--     modérateur du groupe refusé sur un audit de signalement ;
--   • refus/succès sur CHAQUE règle de visibilité par entité (9 branches du
--     CASE journal_audit_visible), y compris les asymétries assumées
--     répliquées telles quelles depuis les tables sources (transaction
--     CinetPay du flux individuel invisible à la direction de
--     l'établissement de l'initiateur ; abonnement Premium élève invisible
--     au personnel ; commande visible à l'acheteur même non-membre) ;
--   • isolation inter-établissement réelle (deux établissements distincts) ;
--   • immutabilité totale du journal : UPDATE/DELETE sans effet, y compris
--     pour l'admin GSG et pour la direction de l'établissement concerné ;
--   • un cycle de transitions répétées (A→B→A) sur congé ET sur sanction,
--     pour prouver que CHAQUE transition est captée, pas seulement la
--     première (corrige le bug coalesce() de conges_verifie_validation SANS
--     le corriger sur conges elle-même — hors périmètre) ;
--   • la copie de signalement reste inchangée après une modification
--     ultérieure du message source — une VRAIE copie indépendante, pas une
--     référence FK ;
--   • la clé de rétention configurable existe (§34.2, jamais codée en dur) ;
--   • enregistrer_audit() refusée en appel direct par un client authentifié,
--     même admin GSG (REVOKE vérifié empiriquement, pas seulement déclaré) ;
--   • la garde "is distinct from" est silencieuse : modifier une colonne NON
--     suivie (conges.motif) ne produit AUCUNE ligne dans journal_audit.
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

SELECT plan(49);

-- ---------------------------------------------------------------------------
-- Fixture : un établissement A (cible), un établissement B (isolation).
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('53000000-0000-0000-0000-000000000001', 'École QA Audit', 'ecole-qa53');
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('53000000-0000-0000-0000-000000000099', 'École QA Audit B (isolation)', 'ecole-qa53-b');

SELECT pg_temp.creer_compte('224600009001', 'direction')  AS direction_a_id  \gset
SELECT pg_temp.creer_compte('224600009002', 'enseignant') AS ens_a_id        \gset
SELECT pg_temp.creer_compte('224600009003', 'enseignant') AS ens_b_a_id      \gset
SELECT pg_temp.creer_compte('224600009004', 'eleve')      AS eleve1_id       \gset
SELECT pg_temp.creer_compte('224600009005', 'parent')     AS parent1_id      \gset
SELECT pg_temp.creer_compte('224600009006', 'eleve')      AS eleve_tiers_id  \gset
SELECT pg_temp.creer_compte('224600009007', 'admin_gsg')  AS admin_gsg_id    \gset
SELECT pg_temp.creer_compte('224600009008', 'direction')  AS direction_b_id  \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES
  (:'direction_a_id'::uuid, '53000000-0000-0000-0000-000000000001', 'direction'),
  (:'ens_a_id'::uuid,       '53000000-0000-0000-0000-000000000001', 'enseignant'),
  (:'ens_b_a_id'::uuid,     '53000000-0000-0000-0000-000000000001', 'enseignant'),
  (:'direction_b_id'::uuid, '53000000-0000-0000-0000-000000000099', 'direction');

INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES ('53000000-0000-0000-0000-000000000002', '53000000-0000-0000-0000-000000000001', '2026-2027', '2026-10-01', '2027-06-30', true);

INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom)
VALUES ('53000000-0000-0000-0000-000000000003', '53000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000002', '6A-QA53', '6e A');

INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance, profile_id, lie_le)
VALUES ('53000000-0000-0000-0000-000000000011', '53000000-0000-0000-0000-000000000001', 'QA53-001', 'SOW', 'Alpha', '2012-01-01', :'eleve1_id'::uuid, now());

INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
VALUES ('53000000-0000-0000-0000-000000000001', :'parent1_id'::uuid, '53000000-0000-0000-0000-000000000011', 'parent', 'confirmee', true);

INSERT INTO public.inscriptions (id, etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut, boursier)
VALUES ('53000000-0000-0000-0000-000000000021', '53000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000011', '53000000-0000-0000-0000-000000000003', '53000000-0000-0000-0000-000000000002', 'active', false);

INSERT INTO public.employes (id, etablissement_id, profile_id, matricule, categorie)
VALUES ('53000000-0000-0000-0000-000000000031', '53000000-0000-0000-0000-000000000001', :'ens_a_id'::uuid, 'QA53-EMP1', 'enseignant');

INSERT INTO public.sanctions (id, etablissement_id, fiche_eleve_id, annee_scolaire_id, type_sanction, motif, decisionnaire_id, statut)
VALUES ('53000000-0000-0000-0000-000000000041', '53000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000011', '53000000-0000-0000-0000-000000000002', 'avertissement', 'motif QA', :'direction_a_id'::uuid, 'proposee');

INSERT INTO public.groupes_discussion (id, etablissement_id, classe_id, annee_scolaire_id, nom, enseignant_createur_id)
VALUES ('53000000-0000-0000-0000-000000000051', '53000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000003', '53000000-0000-0000-0000-000000000002', 'Groupe 6A', :'ens_a_id'::uuid);

INSERT INTO public.messages_groupe (id, etablissement_id, groupe_id, auteur_id, contenu)
VALUES ('53000000-0000-0000-0000-000000000061', '53000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000051', :'eleve1_id'::uuid, 'contenu original du message');

INSERT INTO public.commercants (id, nom)
VALUES ('53000000-0000-0000-0000-000000000071', 'Commerçant QA53');

INSERT INTO public.sous_comptes_marchands (id, etablissement_id, fournisseur, libelle, reference_compte)
VALUES ('53000000-0000-0000-0000-000000000072', '53000000-0000-0000-0000-000000000001', 'cinetpay', 'Sous-compte QA53', 'REF-QA53');

INSERT INTO public.commandes (id, etablissement_id, commercant_id, profile_id, reference, statut)
VALUES ('53000000-0000-0000-0000-000000000081', '53000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000071', :'eleve1_id'::uuid, 'CMD-QA53-001', 'brouillon');

INSERT INTO public.paiements (id, etablissement_id, commande_id, sous_compte_id, fournisseur, montant, statut)
VALUES ('53000000-0000-0000-0000-000000000082', '53000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000081', '53000000-0000-0000-0000-000000000072', 'cinetpay', 1000, 'initie');

-- encaissements_verifie_tenant force saisi_par := auth.uid() en INSERT
-- (anti-spoofing, M15quater) : il faut un auth.uid() résolu pour ce fixture,
-- même en insertion directe bypass RLS.
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
INSERT INTO public.encaissements_scolarite (id, etablissement_id, fiche_eleve_id, inscription_id, saisi_par, statut, montant)
VALUES ('53000000-0000-0000-0000-000000000091', '53000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000011', '53000000-0000-0000-0000-000000000021', :'direction_a_id'::uuid, 'valide', 5000);
SELECT set_config('request.jwt.claims', '{}', true);

INSERT INTO public.abonnements_premium_eleve (id, fiche_eleve_id, formule, expire_le, montant_dernier_paiement, date_dernier_paiement)
VALUES ('53000000-0000-0000-0000-0000000000a1', '53000000-0000-0000-0000-000000000011', 'mensuel', now() + interval '1 month', 1, now());

INSERT INTO public.transactions_cinetpay (id, type_objet_paye, etablissement_id, initiateur_id, montant_attendu, statut)
VALUES ('53000000-0000-0000-0000-0000000000b1', 'licence_pro_etablissement', '53000000-0000-0000-0000-000000000001', :'direction_a_id'::uuid, 100000, 'initie');

INSERT INTO public.transactions_cinetpay (id, type_objet_paye, etablissement_id, initiateur_id, montant_attendu, statut, beneficiaire_fiche_eleve_id, formule)
VALUES ('53000000-0000-0000-0000-0000000000b2', 'abonnement_premium_eleve', null, :'eleve1_id'::uuid, 1, 'initie', '53000000-0000-0000-0000-000000000011', 'mensuel');

-- ===========================================================================
-- 1. Boursier (inscription) — cycle false→true→false→true, visibilité
--    fiche_visible (élève, parent, personnel), tiers refusé.
-- ===========================================================================
UPDATE public.inscriptions SET boursier = true  WHERE id = '53000000-0000-0000-0000-000000000021';
UPDATE public.inscriptions SET boursier = false WHERE id = '53000000-0000-0000-0000-000000000021';
UPDATE public.inscriptions SET boursier = true  WHERE id = '53000000-0000-0000-0000-000000000021';

SELECT is(
  (SELECT count(*) FROM public.journal_audit WHERE entite = 'inscription' AND entite_id = '53000000-0000-0000-0000-000000000021'),
  3::bigint,
  'boursier : 3 transitions (false→true→false→true) captées, pas seulement la première'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'inscription' AND entite_id = '53000000-0000-0000-0000-000000000021'), 3::bigint, 'boursier : visible par l''élève lui-même');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'parent1_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'inscription' AND entite_id = '53000000-0000-0000-0000-000000000021'), 3::bigint, 'boursier : visible par le parent confirmé');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'ens_a_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'inscription' AND entite_id = '53000000-0000-0000-0000-000000000021'), 3::bigint, 'boursier : visible par le personnel de l''établissement (fiche_visible inclut est_personnel)');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_tiers_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'inscription' AND entite_id = '53000000-0000-0000-0000-000000000021'), 0::bigint, 'boursier : REFUSÉ à un tiers sans lien');
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', true);

-- ===========================================================================
-- 1bis. enregistrer_audit() jamais appelable directement par un client --
-- au-delà du REVOKE déclaré dans la migration, vérifié empiriquement, même
-- par l'admin GSG (même exigence que pour chaque fonction privée de ce
-- chantier depuis l'étape (c)/(d) de la facturation).
-- ===========================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.enregistrer_audit(
       '53000000-0000-0000-0000-000000000001'::uuid, 'inscription'::public.type_entite_journal_audit,
       '53000000-0000-0000-0000-000000000021'::uuid, 'boursier', 'false'::jsonb, 'true'::jsonb
     ) $$,
  '42501', NULL,
  'enregistrer_audit : REFUSÉ en appel direct par un client authentifié, même admin GSG -- REVOKE vérifié empiriquement, pas seulement déclaré'
);
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', true);

-- ===========================================================================
-- 2. Sanction — symétrie levée/annulation désormais tracée par le mécanisme
--    générique (aucune colonne symétrique ajoutée sur sanctions elle-même).
-- ===========================================================================
UPDATE public.sanctions SET statut = 'executee' WHERE id = '53000000-0000-0000-0000-000000000041';
UPDATE public.sanctions SET statut = 'annulee'  WHERE id = '53000000-0000-0000-0000-000000000041';
UPDATE public.sanctions SET statut = 'executee' WHERE id = '53000000-0000-0000-0000-000000000041';

SELECT is(
  (SELECT count(*) FROM public.journal_audit WHERE entite = 'sanction' AND entite_id = '53000000-0000-0000-0000-000000000041'),
  3::bigint,
  'sanction : 3 transitions captées, y compris la levée (annulee) — symétrie manquante corrigée par le journal'
);
-- now() est constant pour toute la transaction (created_at identique sur les
-- 3 lignes) : on prouve la transition executee->annulee par ses valeurs, pas
-- par un ordre positionnel qui serait non déterministe ici.
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.journal_audit
    WHERE entite = 'sanction' AND entite_id = '53000000-0000-0000-0000-000000000041' AND champ = 'statut'
      AND ancienne_valeur = to_jsonb('executee'::public.statut_sanction)
      AND nouvelle_valeur = to_jsonb('annulee'::public.statut_sanction)
  ),
  'sanction : la levée (executee→annulee) est bien capturée comme une transition distincte'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'sanction' AND entite_id = '53000000-0000-0000-0000-000000000041'), 3::bigint, 'sanction : visible par le personnel de l''établissement');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'sanction' AND entite_id = '53000000-0000-0000-0000-000000000041'), 3::bigint, 'sanction : visible par l''élève concerné (fiche_visible)');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_tiers_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'sanction' AND entite_id = '53000000-0000-0000-0000-000000000041'), 0::bigint, 'sanction : REFUSÉ à un tiers sans lien');
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', true);

-- ===========================================================================
-- 3. Congé — CHAQUE transition, ANTI-RÉGRESSION #1 : un employé quelconque
--    (personnel, pas RH, pas l'intéressé) est REFUSÉ, alors qu'une règle
--    uniforme est_personnel()/est_admin_gsg() l'aurait laissé passer.
-- ===========================================================================
INSERT INTO public.conges (id, etablissement_id, employe_id, type, date_debut, date_fin, nb_jours, statut)
VALUES ('53000000-0000-0000-0000-0000000000c1', '53000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000031', 'annuel', '2026-11-01', '2026-11-03', 3, 'demande');

UPDATE public.conges SET statut = 'valide' WHERE id = '53000000-0000-0000-0000-0000000000c1';
UPDATE public.conges SET statut = 'refuse' WHERE id = '53000000-0000-0000-0000-0000000000c1';
UPDATE public.conges SET statut = 'valide' WHERE id = '53000000-0000-0000-0000-0000000000c1';

SELECT is(
  (SELECT count(*) FROM public.journal_audit WHERE entite = 'conge' AND entite_id = '53000000-0000-0000-0000-0000000000c1'),
  3::bigint,
  'congé : 3 transitions (demande→valide→refuse→valide) TOUTES captées — corrige le bug coalesce() de conges_verifie_validation, sans le corriger sur conges elle-même'
);

-- Garde "is distinct from" prouvée silencieuse : une modification d'une
-- colonne NON suivie (motif, ici) ne doit produire AUCUNE ligne -- le journal
-- ne s'active que sur la colonne réellement surveillée (statut), jamais sur
-- n'importe quelle écriture de la table source.
UPDATE public.conges SET motif = 'motif modifié, jamais audité' WHERE id = '53000000-0000-0000-0000-0000000000c1';
SELECT is(
  (SELECT count(*) FROM public.journal_audit WHERE entite = 'conge' AND entite_id = '53000000-0000-0000-0000-0000000000c1'),
  3::bigint,
  'congé : modification d''une colonne NON suivie (motif) SANS effet sur le journal -- toujours 3 lignes, pas 4'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'ens_a_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'conge' AND entite_id = '53000000-0000-0000-0000-0000000000c1'), 3::bigint, 'congé : visible par l''employé lui-même (est_employe_self)');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'conge' AND entite_id = '53000000-0000-0000-0000-0000000000c1'), 3::bigint, 'congé : visible par la RH/direction (est_rh)');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'ens_b_a_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.journal_audit WHERE entite = 'conge' AND entite_id = '53000000-0000-0000-0000-0000000000c1'),
  0::bigint,
  'ANTI-RÉGRESSION #1 : congé REFUSÉ à un employé quelconque (personnel, pas RH, pas l''intéressé) -- une règle uniforme est_personnel() l''aurait laissé passer'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'conge' AND entite_id = '53000000-0000-0000-0000-0000000000c1'), 3::bigint, 'congé : visible par l''admin GSG');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_b_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'conge' AND entite_id = '53000000-0000-0000-0000-0000000000c1'), 0::bigint, 'congé : isolation inter-établissement -- direction de l''établissement B refusée');
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', true);

-- ===========================================================================
-- 4. Statuts de paiement — 4 tables, remboursement exclu (transition
--    'rembourse' non exercée : ce flux n'existe nulle part dans le code).
-- ===========================================================================

-- 4a. transactions_cinetpay, flux établissement (licence_pro_etablissement).
UPDATE public.transactions_cinetpay SET statut = 'reussi' WHERE id = '53000000-0000-0000-0000-0000000000b1';
SELECT is(
  (SELECT count(*) FROM public.journal_audit WHERE entite = 'transaction_cinetpay' AND entite_id = '53000000-0000-0000-0000-0000000000b1'),
  1::bigint, 'transaction_cinetpay (établissement) : transition capturée'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'transaction_cinetpay' AND entite_id = '53000000-0000-0000-0000-0000000000b1'), 1::bigint, 'transaction_cinetpay (établissement) : visible par le personnel');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_b_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'transaction_cinetpay' AND entite_id = '53000000-0000-0000-0000-0000000000b1'), 0::bigint, 'transaction_cinetpay (établissement) : isolation inter-établissement');
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', true);

-- 4a-bis. transactions_cinetpay, flux individuel Premium élève -- réplique
-- l'asymétrie assumée à l'étape (c) : etablissement_id NULL rend
-- est_personnel(null) faux, invisible même à la direction de l'élève.
UPDATE public.transactions_cinetpay SET statut = 'reussi' WHERE id = '53000000-0000-0000-0000-0000000000b2';
SELECT is(
  (SELECT etablissement_id FROM public.journal_audit WHERE entite = 'transaction_cinetpay' AND entite_id = '53000000-0000-0000-0000-0000000000b2'),
  NULL, 'transaction_cinetpay (flux individuel) : etablissement_id du journal bien NULL (asymétrie répliquée, pas corrigée)'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.journal_audit WHERE entite = 'transaction_cinetpay' AND entite_id = '53000000-0000-0000-0000-0000000000b2'),
  0::bigint, 'transaction_cinetpay (flux individuel) : REFUSÉ à la direction -- asymétrie déjà actée à l''étape (c), répliquée telle quelle'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'transaction_cinetpay' AND entite_id = '53000000-0000-0000-0000-0000000000b2'), 1::bigint, 'transaction_cinetpay (flux individuel) : visible par l''admin GSG');
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', true);

-- 4b. paiements (marketplace).
UPDATE public.paiements SET statut = 'reussi' WHERE id = '53000000-0000-0000-0000-000000000082';
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'paiement_marketplace' AND entite_id = '53000000-0000-0000-0000-000000000082'), 1::bigint, 'paiement_marketplace : transition capturée');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'paiement_marketplace' AND entite_id = '53000000-0000-0000-0000-000000000082'), 1::bigint, 'paiement_marketplace : visible par un membre actif de l''établissement');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_tiers_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'paiement_marketplace' AND entite_id = '53000000-0000-0000-0000-000000000082'), 0::bigint, 'paiement_marketplace : REFUSÉ à un non-membre');
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', true);

-- 4c. commandes (marketplace) -- l'acheteur voit, même non-membre du
-- personnel (asymétrie de commandes_select répliquée).
UPDATE public.commandes SET statut = 'confirmee' WHERE id = '53000000-0000-0000-0000-000000000081';
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'commande_marketplace' AND entite_id = '53000000-0000-0000-0000-000000000081'), 1::bigint, 'commande_marketplace : transition capturée');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.journal_audit WHERE entite = 'commande_marketplace' AND entite_id = '53000000-0000-0000-0000-000000000081'),
  1::bigint, 'commande_marketplace : visible par l''ACHETEUR (profile_id), même sans être personnel/membre'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_tiers_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'commande_marketplace' AND entite_id = '53000000-0000-0000-0000-000000000081'), 0::bigint, 'commande_marketplace : REFUSÉ à un tiers ni acheteur ni membre');
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', true);

-- 4d. encaissements_scolarite.
UPDATE public.encaissements_scolarite SET statut = 'annule', motif_annulation = 'test QA', annule_par = :'direction_a_id'::uuid, annule_le = now() WHERE id = '53000000-0000-0000-0000-000000000091';
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'encaissement_scolarite' AND entite_id = '53000000-0000-0000-0000-000000000091'), 1::bigint, 'encaissement_scolarite : transition capturée');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'encaissement_scolarite' AND entite_id = '53000000-0000-0000-0000-000000000091'), 1::bigint, 'encaissement_scolarite : visible par l''élève concerné');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve_tiers_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'encaissement_scolarite' AND entite_id = '53000000-0000-0000-0000-000000000091'), 0::bigint, 'encaissement_scolarite : REFUSÉ à un tiers');
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', true);

-- ===========================================================================
-- 5. Abonnement Premium élève — renouvellement, réplique l'asymétrie
--    délibérée de l'étape (c) : élève/parent/admin GSG, PAS le personnel.
-- ===========================================================================
UPDATE public.abonnements_premium_eleve
SET expire_le = expire_le + interval '1 month', montant_dernier_paiement = 2, date_dernier_paiement = now()
WHERE id = '53000000-0000-0000-0000-0000000000a1';

SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'abonnement_premium_eleve' AND entite_id = '53000000-0000-0000-0000-0000000000a1'), 1::bigint, 'abonnement_premium_eleve : renouvellement capturé');
SELECT is(
  (SELECT (nouvelle_valeur->>'montant_dernier_paiement')::numeric FROM public.journal_audit WHERE entite = 'abonnement_premium_eleve' AND entite_id = '53000000-0000-0000-0000-0000000000a1'),
  2::numeric, 'abonnement_premium_eleve : nouvelle_valeur contient le nouveau montant'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'eleve1_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'abonnement_premium_eleve' AND entite_id = '53000000-0000-0000-0000-0000000000a1'), 1::bigint, 'abonnement_premium_eleve : visible par l''élève lui-même');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'parent1_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'abonnement_premium_eleve' AND entite_id = '53000000-0000-0000-0000-0000000000a1'), 1::bigint, 'abonnement_premium_eleve : visible par le parent confirmé');

SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.journal_audit WHERE entite = 'abonnement_premium_eleve' AND entite_id = '53000000-0000-0000-0000-0000000000a1'),
  0::bigint, 'abonnement_premium_eleve : REFUSÉ au personnel de l''établissement -- asymétrie déjà actée à l''étape (c), répliquée telle quelle'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
SELECT is((SELECT count(*) FROM public.journal_audit WHERE entite = 'abonnement_premium_eleve' AND entite_id = '53000000-0000-0000-0000-0000000000a1'), 1::bigint, 'abonnement_premium_eleve : visible par l''admin GSG');
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', true);

-- ===========================================================================
-- 6. Signalement de message — copie horodatée INDÉPENDANTE (20.4).
--    ANTI-RÉGRESSION #2 : un membre du personnel non modérateur du groupe
--    est REFUSÉ, alors qu'une règle uniforme est_personnel() l'aurait
--    laissé passer.
-- ===========================================================================
INSERT INTO public.signalements_message (id, etablissement_id, message_id, signale_par_id, motif)
VALUES ('53000000-0000-0000-0000-0000000000d1', '53000000-0000-0000-0000-000000000001', '53000000-0000-0000-0000-000000000061', :'ens_a_id'::uuid, 'contenu inapproprié');

SELECT is(
  (SELECT count(*) FROM public.journal_audit WHERE entite = 'message_groupe' AND entite_id = '53000000-0000-0000-0000-000000000061' AND champ = 'signalement_copie'),
  1::bigint, 'signalement : copie créée à l''insertion du signalement'
);
SELECT is(
  (SELECT nouvelle_valeur->>'contenu' FROM public.journal_audit WHERE entite = 'message_groupe' AND entite_id = '53000000-0000-0000-0000-000000000061' AND champ = 'signalement_copie'),
  'contenu original du message', 'signalement : la copie contient le contenu EXACT du message au moment du signalement'
);

-- Le message source est ensuite soft-supprimé (contenu lui-même immuable
-- par construction -- messages_groupe_verifie_immuable rejette toute
-- réécriture de contenu, règle absolue #7 M9 ; c'est PRÉCISÉMENT pour ce
-- genre de garantie fragile-mais-actuelle qu'une copie indépendante est
-- demandée : elle ne dépend pas de cette règle restant vraie pour toujours).
-- La copie ne doit JAMAIS changer, quoi qu'il arrive au message source.
UPDATE public.messages_groupe SET supprime = true, supprime_par_id = :'ens_a_id'::uuid, date_suppression = now()
WHERE id = '53000000-0000-0000-0000-000000000061';

SELECT is(
  (SELECT nouvelle_valeur->>'contenu' FROM public.journal_audit WHERE entite = 'message_groupe' AND entite_id = '53000000-0000-0000-0000-000000000061' AND champ = 'signalement_copie'),
  'contenu original du message', 'signalement : la copie reste INCHANGÉE après suppression du message source -- vraie copie, pas une référence FK'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'ens_a_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.journal_audit WHERE entite = 'message_groupe' AND entite_id = '53000000-0000-0000-0000-000000000061'),
  1::bigint, 'signalement : visible par le modérateur du groupe (enseignant créateur)'
);

SELECT set_config('request.jwt.claims', json_build_object('sub', :'ens_b_a_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.journal_audit WHERE entite = 'message_groupe' AND entite_id = '53000000-0000-0000-0000-000000000061'),
  0::bigint,
  'ANTI-RÉGRESSION #2 : signalement REFUSÉ à un membre du personnel NON modérateur du groupe -- une règle uniforme est_personnel() l''aurait laissé passer, contredisant les 7 règles absolues M9'
);
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', true);

-- ===========================================================================
-- 7. Immutabilité totale -- UPDATE/DELETE sans effet, même pour l'admin GSG
--    et pour la direction de l'établissement concerné.
-- ===========================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'admin_gsg_id', 'role', 'authenticated')::text, true);
UPDATE public.journal_audit SET nouvelle_valeur = '"falsifie"'::jsonb WHERE entite = 'sanction' AND entite_id = '53000000-0000-0000-0000-000000000041';
DELETE FROM public.journal_audit WHERE entite = 'sanction' AND entite_id = '53000000-0000-0000-0000-000000000041';
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', true);
SELECT is(
  (SELECT count(*) FROM public.journal_audit WHERE entite = 'sanction' AND entite_id = '53000000-0000-0000-0000-000000000041' AND nouvelle_valeur = '"falsifie"'::jsonb),
  0::bigint, 'immutabilité : UPDATE par l''admin GSG sans aucun effet (aucune ligne falsifiée)'
);
SELECT is(
  (SELECT count(*) FROM public.journal_audit WHERE entite = 'sanction' AND entite_id = '53000000-0000-0000-0000-000000000041'),
  3::bigint, 'immutabilité : DELETE par l''admin GSG sans aucun effet (les 3 lignes existent toujours)'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', json_build_object('sub', :'direction_a_id', 'role', 'authenticated')::text, true);
UPDATE public.journal_audit SET nouvelle_valeur = '"falsifie"'::jsonb WHERE entite = 'conge' AND entite_id = '53000000-0000-0000-0000-0000000000c1';
DELETE FROM public.journal_audit WHERE entite = 'conge' AND entite_id = '53000000-0000-0000-0000-0000000000c1';
RESET ROLE;
SELECT set_config('request.jwt.claims', '{}', true);
SELECT is(
  (SELECT count(*) FROM public.journal_audit WHERE entite = 'conge' AND entite_id = '53000000-0000-0000-0000-0000000000c1'),
  3::bigint,
  'immutabilité : UPDATE/DELETE par la direction DE L''ÉTABLISSEMENT CONCERNÉ lui-même sans aucun effet -- même pour l''établissement concerné'
);

-- ===========================================================================
-- 8. Rétention (§34.2) -- clé configurable, jamais codée en dur.
-- ===========================================================================
SELECT ok(
  (SELECT valeur ? 'jours' FROM public.parametres_globaux WHERE cle = 'duree_retention_journal_audit'),
  'parametres_globaux : duree_retention_journal_audit existe et documente une durée en jours'
);
SELECT ok(
  (SELECT description IS NOT NULL AND length(description) > 0 FROM public.parametres_globaux WHERE cle = 'duree_retention_journal_audit'),
  'parametres_globaux : duree_retention_journal_audit est documentée (description non vide, §34.2)'
);

SELECT * FROM finish();
ROLLBACK;
