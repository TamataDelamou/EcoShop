-- ============================================================================
-- EcoShop — Test RLS 74 : encaissement de scolarité au guichet hors
-- connexion et numérotation des reçus (migration 20260906001547)
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

CREATE OR REPLACE FUNCTION pg_temp.encaisser(p_id uuid, p_etab uuid, p_montant numeric, p_prov text DEFAULT NULL,
                                             p_saisi timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.enregistrer_encaissement_scolarite(p_id, p_etab,
    (SELECT fiche_eleve_id FROM public.inscriptions WHERE etablissement_id = p_etab LIMIT 1),
    (SELECT id FROM public.inscriptions WHERE etablissement_id = p_etab LIMIT 1),
    'scolarite', p_montant, 'especes', NULL, '2026-10-21', p_prov, p_saisi);
$$;

SELECT plan(11);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('74000000-0000-0000-0000-000000000001', 'École Guichet', 'guichet-74', 'GNF'),
  ('74000000-0000-0000-0000-000000000002', 'Autre école', 'autre-74', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('74000000-0000-0000-0000-0000000000a1', '74000000-0000-0000-0000-000000000001', '2026-2027', '2026-10-01', '2027-06-30', true),
  ('74000000-0000-0000-0000-0000000000a2', '74000000-0000-0000-0000-000000000002', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('74000000-0000-0000-0000-0000000000c1', '74000000-0000-0000-0000-000000000001', '74000000-0000-0000-0000-0000000000a1', '6A', '6e A'),
  ('74000000-0000-0000-0000-0000000000c2', '74000000-0000-0000-0000-000000000002', '74000000-0000-0000-0000-0000000000a2', '6A', '6e A');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance) VALUES
  ('74000000-0000-0000-0000-0000000000e1', '74000000-0000-0000-0000-000000000001', 'G-1', 'BAH', 'A', '2014-01-01'),
  ('74000000-0000-0000-0000-0000000000e2', '74000000-0000-0000-0000-000000000002', 'G-2', 'SOW', 'I', '2014-01-01');
INSERT INTO public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('74000000-0000-0000-0000-000000000001', '74000000-0000-0000-0000-0000000000e1', '74000000-0000-0000-0000-0000000000c1', '74000000-0000-0000-0000-0000000000a1'),
  ('74000000-0000-0000-0000-000000000002', '74000000-0000-0000-0000-0000000000e2', '74000000-0000-0000-0000-0000000000c2', '74000000-0000-0000-0000-0000000000a2');

SELECT pg_temp.creer_compte('224674000001', 'direction') AS dir1 \gset
SELECT pg_temp.creer_compte('224674000002', 'direction') AS dir2 \gset
SELECT pg_temp.creer_compte('224674000003', 'parent') AS parent \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir1', '74000000-0000-0000-0000-000000000001', 'direction'),
  (:'dir2', '74000000-0000-0000-0000-000000000002', 'direction');

SELECT id AS insc1 FROM public.inscriptions WHERE etablissement_id = '74000000-0000-0000-0000-000000000001' \gset
SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir1');

SELECT is(pg_temp.encaisser('74000000-0000-0000-0000-00000000aa01', '74000000-0000-0000-0000-000000000001', 100000)->>'numero_recu',
  'SCO-2026-000001', 'premier encaissement : reçu SCO-2026-000001');
SELECT pg_temp.encaisser('74000000-0000-0000-0000-00000000aa02', '74000000-0000-0000-0000-000000000001', 50000,
  'PROV-AB12-0001', now() - interval '2 hours') AS r2 \gset
SELECT is(:'r2'::jsonb->>'numero_recu', 'SCO-2026-000002', 'encaissement saisi sans réseau : numéro définitif à la réception');
SELECT is(:'r2'::jsonb->>'numero_provisoire', 'PROV-AB12-0001', 'le numéro du reçu provisoire est gardé');
SELECT ok((:'r2'::jsonb->>'saisi_le_client')::timestamptz < now() - interval '1 hour', 'heure de saisie au guichet conservée');

SELECT is((pg_temp.encaisser('74000000-0000-0000-0000-00000000aa02', '74000000-0000-0000-0000-000000000001', 50000,
  'PROV-AB12-0001')->>'deja_recu')::boolean, true, 'second envoi du même encaissement : déjà reçu');
SELECT throws_ok(
  $$ SELECT pg_temp.encaisser('74000000-0000-0000-0000-00000000aa03', '74000000-0000-0000-0000-000000000001', 0) $$,
  '23514', NULL, 'montant nul refusé');
SELECT is(pg_temp.encaisser('74000000-0000-0000-0000-00000000aa04', '74000000-0000-0000-0000-000000000001', 25000)->>'numero_recu',
  'SCO-2026-000003', 'ni le renvoi ni le refus n''ont consommé de numéro : aucun trou');
SELECT is((SELECT count(*)::int FROM public.encaissements_scolarite WHERE etablissement_id = '74000000-0000-0000-0000-000000000001'), 3,
  'trois encaissements, pas de doublon');

SELECT throws_ok(
  $$ UPDATE public.encaissements_scolarite SET numero_recu = 'SCO-2026-999999' WHERE id = '74000000-0000-0000-0000-00000000aa01' $$,
  '23514', 'ENCAISSEMENT_CHAMP_IMMUABLE', 'le numéro d''un reçu ne se modifie jamais');

SELECT pg_temp.en_tant_que(:'dir2');
SELECT is(pg_temp.encaisser('74000000-0000-0000-0000-00000000bb01', '74000000-0000-0000-0000-000000000002', 10000)->>'numero_recu',
  'SCO-2026-000001', 'chaque école a sa propre numérotation');

SELECT pg_temp.en_tant_que(:'parent');
SELECT throws_ok(
  format($$ SELECT public.enregistrer_encaissement_scolarite('74000000-0000-0000-0000-00000000cc01', '74000000-0000-0000-0000-000000000001',
       '74000000-0000-0000-0000-0000000000e1', %L, 'scolarite', 1000, 'especes', NULL, '2026-10-21') $$, :'insc1'),
  '42501', NULL, 'un parent n''enregistre pas d''encaissement');

SELECT * FROM finish();
ROLLBACK;
