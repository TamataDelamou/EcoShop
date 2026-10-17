-- ============================================================================
-- EcoShop — Test RLS 57 : KER-MUT K2/K3, reporting vers le Control Plane du
-- Kernel GSG (migration 20260906001526, docs/REGISTRE.md REG-01.2/01.3).
--
-- Couvre :
--   • aucune fonction kernel_* n'est appelable par anon ni authenticated
--     (REVOKE vérifié empiriquement) ; table des curseurs illisible pour un
--     compte non admin GSG ;
--   • MINIMISATION : un lot d'audit ne contient jamais ancienne_valeur /
--     nouvelle_valeur, ni fiche_eleve_id / groupe_id ;
--   • délai de sécurité : une ligne de moins de 2 minutes n'est pas exportée ;
--   • export incrémental exact : le curseur avance, aucune ligne en double,
--     aucune perdue ;
--   • le curseur ne recule jamais (acquittement tardif ignoré) ;
--   • départage numérique à horodatage égal pour les métriques (id 9 < 10,
--     jamais un tri texte) ;
--   • kernel_metriques_cles() renvoie les agrégats attendus.
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

SELECT plan(18);

-- Isolation : on repart de curseurs vierges et de journaux vides.
DELETE FROM public.journal_metriques;
UPDATE public.kernel_export_curseurs
   SET curseur_horodatage = NULL, curseur_id = NULL, lignes_exportees = 0,
       derniere_reussite = NULL, derniere_erreur = NULL;

INSERT INTO public.etablissements (id, nom, slug)
VALUES ('57000000-0000-0000-0000-000000000001', 'Lycée Test Kernel', 'lycee-test-kernel-57');

-- ---------------------------------------------------------------------------
-- 1. Droits : rien pour anon / authenticated
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT throws_ok($$ SELECT public.kernel_lot_export('audit', 10) $$, '42501', NULL,
  'authenticated ne peut pas appeler kernel_lot_export');
SELECT throws_ok($$ SELECT public.kernel_metriques_cles() $$, '42501', NULL,
  'authenticated ne peut pas appeler kernel_metriques_cles');
SELECT throws_ok($$ SELECT public.kernel_valider_lot('audit', now(), gen_random_uuid()::text, 1) $$, '42501', NULL,
  'authenticated ne peut pas avancer un curseur');
SELECT is((SELECT count(*) FROM public.kernel_export_curseurs), 0::bigint,
  'curseurs invisibles pour un compte non admin GSG');
RESET ROLE;

SET LOCAL ROLE anon;
SELECT throws_ok($$ SELECT public.kernel_lecture('audit') $$, '42501', NULL,
  'anon ne peut pas appeler kernel_lecture');
RESET ROLE;

-- ---------------------------------------------------------------------------
-- 2. Données d'audit : 3 lignes anciennes (une seconde d'écart), 1 récente.
--    Les valeurs contiennent un marqueur qui ne doit JAMAIS sortir.
-- ---------------------------------------------------------------------------
DELETE FROM public.journal_audit;
INSERT INTO public.journal_audit (id, etablissement_id, entite, entite_id, champ, ancienne_valeur, nouvelle_valeur, created_at)
VALUES
  ('57000000-0000-0000-0000-0000000000a1', '57000000-0000-0000-0000-000000000001', 'sanction', gen_random_uuid(), 'statut',
   '"MARQUEUR_CONFIDENTIEL"', '"MARQUEUR_CONFIDENTIEL"', now() - interval '10 minutes'),
  ('57000000-0000-0000-0000-0000000000a2', '57000000-0000-0000-0000-000000000001', 'conge', gen_random_uuid(), 'statut',
   NULL, '{"texte":"MARQUEUR_CONFIDENTIEL"}', now() - interval '9 minutes'),
  ('57000000-0000-0000-0000-0000000000a3', '57000000-0000-0000-0000-000000000001', 'inscription', gen_random_uuid(), 'boursier',
   'false', 'true', now() - interval '8 minutes'),
  ('57000000-0000-0000-0000-0000000000a4', '57000000-0000-0000-0000-000000000001', 'inscription', gen_random_uuid(), 'boursier',
   'false', 'true', now());

SET LOCAL ROLE service_role;

SELECT is(jsonb_array_length(public.kernel_lot_export('audit', 2) -> 'lignes'), 2,
  'premier lot audit : 2 lignes (taille demandée)');

SELECT ok(public.kernel_lot_export('audit', 10)::text NOT LIKE '%MARQUEUR_CONFIDENTIEL%',
  'aucune valeur d''audit ne sort vers le Kernel');

SELECT ok(NOT ((public.kernel_lot_export('audit', 10) -> 'lignes' -> 0) ?| array['ancienne_valeur', 'nouvelle_valeur', 'fiche_eleve_id', 'groupe_id']),
  'les champs nominatifs ne figurent pas dans une ligne exportée');

SELECT is(jsonb_array_length(public.kernel_lot_export('audit', 10) -> 'lignes'), 3,
  'la ligne de moins de 2 minutes n''est pas exportée');

-- Acquittement du lot 1 (a1, a2) puis lot suivant.
SELECT public.kernel_valider_lot('audit',
  (SELECT created_at FROM public.journal_audit WHERE id = '57000000-0000-0000-0000-0000000000a2'),
  '57000000-0000-0000-0000-0000000000a2', 2);

SELECT is(public.kernel_lot_export('audit', 10) #>> '{lignes,0,id}', '57000000-0000-0000-0000-0000000000a3',
  'après acquittement, le lot suivant reprend exactement après la dernière ligne');
SELECT is(jsonb_array_length(public.kernel_lot_export('audit', 10) -> 'lignes'), 1,
  'aucune ligne renvoyée deux fois');

-- Acquittement tardif d'un lot antérieur : ignoré.
SELECT public.kernel_valider_lot('audit',
  (SELECT created_at FROM public.journal_audit WHERE id = '57000000-0000-0000-0000-0000000000a1'),
  '57000000-0000-0000-0000-0000000000a1', 1);
RESET ROLE;

SELECT is((SELECT curseur_id FROM public.kernel_export_curseurs WHERE flux = 'audit'),
  '57000000-0000-0000-0000-0000000000a2', 'le curseur ne recule jamais');
SELECT is((SELECT lignes_exportees FROM public.kernel_export_curseurs WHERE flux = 'audit'),
  2::bigint, 'l''acquittement ignoré ne gonfle pas le compteur');

-- ---------------------------------------------------------------------------
-- 3. Métriques : 11 lignes au MÊME horodatage, départage numérique des id.
-- ---------------------------------------------------------------------------
INSERT INTO public.journal_metriques (etablissement_id, metrique, valeur, created_at)
SELECT '57000000-0000-0000-0000-000000000001', 'latence_ms', g, timestamptz '2026-10-01 10:00:00+00'
FROM generate_series(1, 11) g;

SET LOCAL ROLE service_role;
SELECT public.kernel_valider_lot('metriques', timestamptz '2026-10-01 10:00:00+00',
  (SELECT (min(id) + 8)::text FROM public.journal_metriques), 9);
SELECT is(jsonb_array_length(public.kernel_lot_export('metriques', 100) -> 'lignes'), 2,
  'métriques : reprise après le 9e id, départage numérique (pas un tri texte)');
SELECT is((public.kernel_lot_export('metriques', 100) #>> '{lignes,0,id}')::bigint,
  (SELECT min(id) + 9 FROM public.journal_metriques),
  'métriques : la première ligne du lot suivant est bien la 10e');

-- ---------------------------------------------------------------------------
-- 4. Métriques clés
-- ---------------------------------------------------------------------------
SELECT ok(public.kernel_metriques_cles() ?& array[
    'etablissements_actifs', 'comptes_actifs', 'inscriptions_annee_courante',
    'encaissements_scolarite_30j', 'transactions_paiement_30j',
    'commandes_marketplace_30j', 'sante_base', 'export'],
  'kernel_metriques_cles expose les indicateurs du contrat');
SELECT ok((public.kernel_metriques_cles() ->> 'etablissements_actifs')::int >= 1,
  'l''établissement de test est compté comme actif');
SELECT is(public.kernel_metriques_cles() #>> '{export,audit,lignes_exportees}', '2',
  'l''état de l''export est visible dans l''instantané');
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
