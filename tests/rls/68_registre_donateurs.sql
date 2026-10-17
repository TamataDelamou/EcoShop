-- ============================================================================
-- EcoShop — Test RLS 68 : registre des donateurs et des dons
-- (REG-03 C5, migrations 20260906001539 et 20260906001540)
--
-- Couvre :
--   • comptes SYCEBNL de la générosité chargés (7047 parrainage, 7925…) ;
--   • reçus numérotés par année sans trou ; don → D 571 / C 7041 (CAI) ;
--     quête anonyme Orange Money → D 5521 / C 7044 ; parrainage → 7047 ;
--   • campagne « projet » : don → C 165 fonds affectés ; emploi → D 165 /
--     C 7925 (journal OD) ; fonds insuffisants refusés ; emploi réservé aux
--     projets ;
--   • annulation motivée → contre-passation, audit ; double annulation
--     refusée ; dons immuables (ni modification ni écriture directe) ;
--   • contrôles : date future, nature, montant ; campagne utilisée : type
--     figé ; donateur ayant donné : non supprimable ;
--   • SYSCOHADA : sans exercice → incident, rattrapage → D 571 / C 758 ;
--   • tableau de bord : total, année précédente, nouveaux, fidèles, à
--     relancer, campagnes (collecté / employé / disponible), meilleurs
--     donateurs, engagement de parrainage en retard ;
--   • reçu et relevé annuel ; droits : parent refusé partout ;
--   • comptabilité simplifiée sans règles : registre seul.
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

CREATE OR REPLACE FUNCTION pg_temp.en_tant_que(p_uid uuid) RETURNS void
LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.lignes(p_source uuid) RETURNS text
LANGUAGE sql AS $$
  SELECT string_agg(c.code || ':' || l.debit::bigint || '/' || l.credit::bigint, ' ' ORDER BY l.ordre)
    FROM public.lignes_pieces_comptables l
    JOIN public.plans_comptables c ON c.id = l.compte_id
    JOIN public.pieces_comptables p ON p.id = l.piece_id
   WHERE p.source_id = p_source AND p.origine = 'automatique';
$$;

SELECT plan(46);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('68000000-0000-0000-0000-000000000001', 'École Bambino Dons', 'bambino-dons-68', 'GNF'),
  ('68000000-0000-0000-0000-000000000002', 'Lycée Société Dons', 'lycee-dons-68', 'GNF'),
  ('68000000-0000-0000-0000-000000000003', 'École Simple Dons', 'simple-dons-68', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('68000000-0000-0000-0000-000000000011', '68000000-0000-0000-0000-000000000001', '2026-2027', '2026-09-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('68000000-0000-0000-0000-000000000012', '68000000-0000-0000-0000-000000000001', '68000000-0000-0000-0000-000000000011', 'CP', 'CP');

SELECT pg_temp.creer_compte('224668000001', 'direction') AS dir_id \gset
SELECT pg_temp.creer_compte('224668000002', 'parent') AS parent_id \gset
SELECT pg_temp.creer_compte('224668000003', 'direction') AS dir2_id \gset
SELECT pg_temp.creer_compte('224668000004', 'direction') AS dir3_id \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_id', '68000000-0000-0000-0000-000000000001', 'direction'),
  (:'parent_id', '68000000-0000-0000-0000-000000000001', 'parent'),
  (:'dir2_id', '68000000-0000-0000-0000-000000000002', 'direction'),
  (:'dir3_id', '68000000-0000-0000-0000-000000000003', 'direction');

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.choisir_referentiel_comptable('68000000-0000-0000-0000-000000000001', 'sycebnl', 'confessionnelle');
SELECT public.ouvrir_exercice('68000000-0000-0000-0000-000000000001', '2026-01-01', '2026-12-31');
SELECT public.creer_inscription_nouvel_eleve(
  '68000000-0000-0000-0000-000000000001', 'DIALLO', 'Fatoumata', '2019-04-02',
  '68000000-0000-0000-0000-000000000012', '68000000-0000-0000-0000-000000000011', 'F') AS fiche \gset

SELECT is((SELECT string_agg(code, ',' ORDER BY code) FROM public.plans_comptables
            WHERE etablissement_id = '68000000-0000-0000-0000-000000000001' AND code IN ('7046', '7047', '7925', '475', '636')),
  '475,636,7046,7047,7925', 'SYCEBNL : comptes de la générosité, des fonds affectés et de la recherche de fonds chargés');

INSERT INTO public.donateurs (id, etablissement_id, type, nom, prenom, telephone, accepte_contact) VALUES
  ('68000000-0000-0000-0000-0000000000d1', '68000000-0000-0000-0000-000000000001', 'personne', 'CAMARA', 'Ibrahima', '224620000001', true),
  ('68000000-0000-0000-0000-0000000000d2', '68000000-0000-0000-0000-000000000001', 'eglise', 'Paroisse de Kaloum', NULL, '224620000002', true),
  ('68000000-0000-0000-0000-0000000000d3', '68000000-0000-0000-0000-000000000001', 'organisation', 'ONG Lumière', NULL, NULL, true),
  ('68000000-0000-0000-0000-0000000000d4', '68000000-0000-0000-0000-000000000001', 'personne', 'SOW', 'Mariama', NULL, false);
SELECT is((SELECT count(*)::int FROM public.donateurs WHERE etablissement_id = '68000000-0000-0000-0000-000000000001'), 4,
  'la direction tient le registre des donateurs');

INSERT INTO public.affectations_dons (id, etablissement_id, libelle, type, objectif) VALUES
  ('68000000-0000-0000-0000-0000000000a1', '68000000-0000-0000-0000-000000000001', 'Construction de la bibliothèque', 'projet', 10000000),
  ('68000000-0000-0000-0000-0000000000a2', '68000000-0000-0000-0000-000000000001', 'Parrainage d''élèves', 'parrainage', NULL);

-- ---------------------------------------------------------------------------
-- 1. Dons libres, quête, parrainage
-- ---------------------------------------------------------------------------
SELECT public.enregistrer_don('68000000-0000-0000-0000-000000000001', 500000, 'don', 'especes', '2026-03-10',
  '68000000-0000-0000-0000-0000000000d1') AS r1 \gset
SELECT is(:'r1'::jsonb->>'numero_recu', 'REC-2026-000001', 'premier reçu de l''année : REC-2026-000001');
SELECT ok((:'r1'::jsonb->>'comptabilise')::boolean, 'don comptabilisé à l''enregistrement');
SELECT is(pg_temp.lignes((:'r1'::jsonb->>'id')::uuid), '571:500000/0 7041:0/500000', 'don en espèces : D 571 / C 7041 Dons');
SELECT ok((SELECT reference LIKE 'CAI-2026-%' AND piece_justificative = 'REC-2026-000001' AND libelle = 'Don — CAMARA Ibrahima'
             FROM public.pieces_comptables WHERE source_id = (:'r1'::jsonb->>'id')::uuid),
  'journal Caisse, reçu en pièce justificative, libellé avec le donateur');

SELECT public.enregistrer_don('68000000-0000-0000-0000-000000000001', 75000, 'quete', 'mobile_money', '2026-04-05',
  NULL, NULL, NULL, 'OM-778899', NULL, true) AS r2 \gset
SELECT is(:'r2'::jsonb->>'numero_recu', 'REC-2026-000002', 'numérotation continue');
SELECT is(pg_temp.lignes((:'r2'::jsonb->>'id')::uuid), '5521:75000/0 7044:0/75000', 'quête par Orange Money : D 5521 / C 7044');

SELECT public.enregistrer_don('68000000-0000-0000-0000-000000000001', 300000, 'parrainage', 'especes', '2026-05-02',
  '68000000-0000-0000-0000-0000000000d4', '68000000-0000-0000-0000-0000000000a2', :'fiche') AS r3 \gset
SELECT is(pg_temp.lignes((:'r3'::jsonb->>'id')::uuid), '571:300000/0 7047:0/300000', 'parrainage d''un élève : C 7047');

-- ---------------------------------------------------------------------------
-- 2. Projet à fonds affectés
-- ---------------------------------------------------------------------------
SELECT public.enregistrer_don('68000000-0000-0000-0000-000000000001', 2000000, 'mecenat', 'virement', '2026-06-01',
  '68000000-0000-0000-0000-0000000000d3', '68000000-0000-0000-0000-0000000000a1') AS r4 \gset
SELECT is(pg_temp.lignes((:'r4'::jsonb->>'id')::uuid), '521:2000000/0 165:0/2000000',
  'don affecté au projet : C 165 fonds affectés (pas en produits)');

SELECT public.constater_emploi_fonds('68000000-0000-0000-0000-0000000000a1', 1500000, 'Achat des étagères', '2026-07-15') AS e1 \gset
SELECT is((:'e1'::jsonb->>'solde')::numeric, 500000::numeric, 'emploi des fonds : solde disponible 500 000');
SELECT is(pg_temp.lignes((:'e1'::jsonb->>'id')::uuid), '165:1500000/0 7925:0/1500000', 'emploi : D 165 / C 7925 reprise');
SELECT ok((SELECT reference LIKE 'OD-2026-%' FROM public.pieces_comptables WHERE source_id = (:'e1'::jsonb->>'id')::uuid),
  'emploi passé au journal des opérations diverses');
SELECT throws_ok($$SELECT public.constater_emploi_fonds('68000000-0000-0000-0000-0000000000a1', 600000, 'Peinture', '2026-07-20')$$,
  'FONDS_INSUFFISANTS', 'on n''emploie pas plus que les fonds reçus');
SELECT throws_ok($$SELECT public.constater_emploi_fonds('68000000-0000-0000-0000-0000000000a2', 1000, 'Fournitures', '2026-07-20')$$,
  'AFFECTATION_NON_PROJET', 'emploi réservé aux projets à fonds affectés');
SELECT throws_ok($$UPDATE public.affectations_dons SET type = 'libre' WHERE id = '68000000-0000-0000-0000-0000000000a1'$$,
  'AFFECTATION_UTILISEE', 'une campagne qui a reçu des dons ne change plus de type');

-- ---------------------------------------------------------------------------
-- 3. Annulation et immutabilité
-- ---------------------------------------------------------------------------
SELECT public.enregistrer_don('68000000-0000-0000-0000-000000000001', 50000, 'don', 'especes', '2026-03-11',
  '68000000-0000-0000-0000-0000000000d1') AS r5 \gset
SELECT throws_ok(format($$SELECT public.annuler_don(%L, '')$$, :'r5'::jsonb->>'id'), 'MOTIF_REQUIS', 'annulation sans motif refusée');
SELECT public.annuler_don((:'r5'::jsonb->>'id')::uuid, 'Saisi en double');
SELECT is((SELECT p.origine FROM public.pieces_comptables p
            WHERE p.piece_annulee_id = (SELECT id FROM public.pieces_comptables
                                         WHERE source_id = (:'r5'::jsonb->>'id')::uuid AND origine = 'automatique')),
  'contrepassation', 'don annulé → contre-passation');
SELECT throws_ok(format($$SELECT public.annuler_don(%L, 'encore')$$, :'r5'::jsonb->>'id'), 'DON_DEJA_ANNULE',
  'pas de double annulation');
SELECT throws_ok(format($$UPDATE public.dons SET montant = 1 WHERE id = %L$$, :'r1'::jsonb->>'id'), '42501', NULL,
  'un don ne se modifie pas directement');
SELECT throws_ok($$INSERT INTO public.dons (etablissement_id, numero_recu, nature, montant)
                   VALUES ('68000000-0000-0000-0000-000000000001', 'REC-X', 'don', 1)$$, '42501', NULL,
  'pas d''écriture directe : le numéro de reçu vient du serveur');
SELECT throws_ok($$DELETE FROM public.donateurs WHERE id = '68000000-0000-0000-0000-0000000000d1'$$,
  'DONATEUR_A_DES_DONS', 'un donateur qui a donné s''archive, il ne se supprime pas');
RESET ROLE;
SELECT is((SELECT nouvelle_valeur #>> '{}' FROM public.journal_audit WHERE entite = 'don' AND entite_id = (:'r5'::jsonb->>'id')::uuid),
  'annule', 'l''annulation est tracée au journal d''audit');
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');

-- ---------------------------------------------------------------------------
-- 4. Contrôles de saisie
-- ---------------------------------------------------------------------------
SELECT throws_ok($$SELECT public.enregistrer_don('68000000-0000-0000-0000-000000000001', 1000, 'don', 'especes', current_date + 1)$$,
  'DATE_DON_FUTURE', 'don daté dans le futur refusé');
SELECT throws_ok($$SELECT public.enregistrer_don('68000000-0000-0000-0000-000000000001', 1000, 'tombola')$$,
  'NATURE_INVALIDE', 'nature inconnue refusée');
SELECT throws_ok($$SELECT public.enregistrer_don('68000000-0000-0000-0000-000000000001', 0)$$,
  'MONTANT_INVALIDE', 'montant nul refusé');

-- ---------------------------------------------------------------------------
-- 5. Année précédente sans exercice : registre tenu, incident consigné
-- ---------------------------------------------------------------------------
SELECT public.enregistrer_don('68000000-0000-0000-0000-000000000001', 100000, 'don', 'especes', '2025-12-20',
  '68000000-0000-0000-0000-0000000000d1') AS r6 \gset
SELECT public.enregistrer_don('68000000-0000-0000-0000-000000000001', 200000, 'denier_culte', 'especes', '2025-11-15',
  '68000000-0000-0000-0000-0000000000d2') AS r7 \gset
SELECT is(:'r6'::jsonb->>'numero_recu' || ' ' || (:'r6'::jsonb->>'incident'), 'REC-2025-000001 AUCUN_EXERCICE_OUVERT',
  'numérotation propre à 2025 ; sans exercice, le don est enregistré et l''incident consigné');
SELECT is((public.etat_comptabilisation_automatique('68000000-0000-0000-0000-000000000001')->>'dons_a_comptabiliser')::int, 2,
  'état : deux dons à comptabiliser');

INSERT INTO public.engagements_dons (etablissement_id, donateur_id, affectation_id, fiche_eleve_id, montant, periodicite, date_debut)
VALUES ('68000000-0000-0000-0000-000000000001', '68000000-0000-0000-0000-0000000000d4',
        '68000000-0000-0000-0000-0000000000a2', :'fiche', 100000, 'mensuelle', '2026-01-01');

-- ---------------------------------------------------------------------------
-- 6. Tableau de bord 2026
-- ---------------------------------------------------------------------------
SELECT public.tableau_bord_dons('68000000-0000-0000-0000-000000000001', 2026) AS tb \gset
SELECT is((:'tb'::jsonb->>'total')::numeric, 2875000::numeric, 'total 2026 : dons valides seulement (annulé exclu)');
SELECT is((:'tb'::jsonb->>'total_annee_precedente')::numeric, 300000::numeric, 'comparaison avec 2025');
SELECT is((:'tb'::jsonb->>'nouveaux_donateurs')::int || '/' || (:'tb'::jsonb->>'donateurs_fideles'), '2/1',
  'deux nouveaux donateurs, un fidèle (a donné en 2025 et 2026)');
SELECT is((SELECT string_agg(r->>'nom', ',') FROM jsonb_array_elements(:'tb'::jsonb->'a_relancer') r), 'Paroisse de Kaloum',
  'à relancer : a donné en 2025, pas encore en 2026');
SELECT is((SELECT (r->>'collecte')::numeric::bigint || '/' || (r->>'emploie')::numeric::bigint || '/' || (r->>'disponible')::numeric::bigint
             FROM jsonb_array_elements(:'tb'::jsonb->'affectations') r WHERE r->>'libelle' = 'Construction de la bibliothèque'),
  '2000000/1500000/500000', 'projet : collecté, employé, disponible');
SELECT is((:'tb'::jsonb->'meilleurs_donateurs'->0->>'nom'), 'ONG Lumière', 'meilleur donateur de l''année');
SELECT is((SELECT (r->>'retard')::numeric FROM jsonb_array_elements(:'tb'::jsonb->'engagements') r),
  100000 * extract(month from least(current_date, '2026-12-31'::date)) - 300000,
  'parrainage mensuel : retard = échéances échues − reçu');
SELECT is((SELECT r->>'compte_code' FROM jsonb_array_elements(
             public.etat_comptabilisation_automatique('68000000-0000-0000-0000-000000000001')->'regles') r
            WHERE r->>'cle' = 'don:fonds_affectes'), '165', 'règles : fonds affectés → 165');

-- ---------------------------------------------------------------------------
-- 7. Reçu et relevé annuel
-- ---------------------------------------------------------------------------
SELECT is((SELECT (public.recu_don((:'r1'::jsonb->>'id')::uuid))->'donateur'->>'nom'), 'CAMARA', 'reçu : identité du donateur');
SELECT is((public.releve_donateur('68000000-0000-0000-0000-0000000000d1', 2026)->>'total')::numeric, 500000::numeric,
  'relevé annuel du donateur : dons valides de l''année');

-- ---------------------------------------------------------------------------
-- 8. Droits
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'parent_id');
SELECT is((SELECT count(*)::int FROM public.donateurs) + (SELECT count(*)::int FROM public.dons), 0,
  'un parent ne voit ni donateurs ni dons');
SELECT throws_ok($$SELECT public.enregistrer_don('68000000-0000-0000-0000-000000000001', 1000)$$, '42501', NULL,
  'un parent n''enregistre pas de don');
SELECT throws_ok($$SELECT public.tableau_bord_dons('68000000-0000-0000-0000-000000000001', 2026)$$, '42501', NULL,
  'un parent ne voit pas le tableau de bord');
SELECT throws_ok(format($$SELECT public.comptabiliser_don(%L)$$, :'r1'::jsonb->>'id'), '42501', NULL,
  'fonction interne inaccessible');

-- ---------------------------------------------------------------------------
-- 9. SYSCOHADA : rattrapage ; simplifié : registre seul
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'dir2_id');
SELECT public.choisir_referentiel_comptable('68000000-0000-0000-0000-000000000002', 'syscohada_normal', 'societe');
SELECT public.enregistrer_don('68000000-0000-0000-0000-000000000002', 400000, 'don', 'especes', '2026-02-01') AS r8 \gset
SELECT is(:'r8'::jsonb->>'incident', 'AUCUN_EXERCICE_OUVERT', 'SYSCOHADA sans exercice : incident');
SELECT public.ouvrir_exercice('68000000-0000-0000-0000-000000000002', '2026-01-01', '2026-12-31');
SELECT is(public.comptabiliser_en_attente('68000000-0000-0000-0000-000000000002')->>'comptabilises', '1',
  'rattrapage du don');
SELECT is(pg_temp.lignes((:'r8'::jsonb->>'id')::uuid), '571:400000/0 758:0/400000', 'SYSCOHADA : D 571 / C 758 produits divers');

SELECT pg_temp.en_tant_que(:'dir3_id');
SELECT public.enregistrer_don('68000000-0000-0000-0000-000000000003', 90000) AS r9 \gset
SELECT is((SELECT count(*)::int FROM public.pieces_comptables WHERE source_id = (:'r9'::jsonb->>'id')::uuid)
        + (SELECT count(*)::int FROM public.incidents_comptabilisation WHERE source_id = (:'r9'::jsonb->>'id')::uuid), 0,
  'simplifié sans règles : registre seul, ni pièce ni incident');

SELECT * FROM finish();
ROLLBACK;
