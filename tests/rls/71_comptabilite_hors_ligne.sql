-- ============================================================================
-- EcoShop — Test RLS 71 : saisies comptables faites hors connexion
-- (REG-03 C7, migration 20260906001543)
--
-- Couvre :
--   • don rejoué deux fois (même clé d'appareil) : un seul don, un seul reçu
--     définitif, une seule écriture ; numéro provisoire conservé et rappelé
--     sur le reçu ; date de saisie sur l'appareil gardée ;
--   • clé d'un autre établissement refusée ;
--   • brouillard créé hors connexion sous la clé de l'appareil, renvoyé
--     modifié (une seule pièce, lignes remplacées), puis validé en ligne :
--     un nouvel envoi ne le touche plus ;
--   • refus métier au rejeu (période clôturée) ; droits.
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

CREATE OR REPLACE FUNCTION pg_temp.compte(p_code text) RETURNS uuid
LANGUAGE sql AS $$
  SELECT id FROM public.plans_comptables
   WHERE etablissement_id = '71000000-0000-0000-0000-000000000001' AND code = p_code AND deleted_at IS NULL;
$$;

SELECT plan(16);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('71000000-0000-0000-0000-000000000001', 'École Hors Ligne', 'hors-ligne-71', 'GNF'),
  ('71000000-0000-0000-0000-000000000002', 'Autre école', 'autre-71', 'GNF');
SELECT pg_temp.creer_compte('224671000001', 'direction') AS dir_id \gset
SELECT pg_temp.creer_compte('224671000002', 'parent') AS parent_id \gset
SELECT pg_temp.creer_compte('224671000003', 'direction') AS dir2_id \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_id', '71000000-0000-0000-0000-000000000001', 'direction'),
  (:'parent_id', '71000000-0000-0000-0000-000000000001', 'parent'),
  (:'dir2_id', '71000000-0000-0000-0000-000000000002', 'direction');

SET LOCAL ROLE authenticated;
SELECT pg_temp.en_tant_que(:'dir_id');
SELECT public.choisir_referentiel_comptable('71000000-0000-0000-0000-000000000001', 'sycebnl', 'confessionnelle');
SELECT public.ouvrir_exercice('71000000-0000-0000-0000-000000000001', '2026-01-01', '2026-12-31');
INSERT INTO public.journaux (etablissement_id, code, intitule, type)
VALUES ('71000000-0000-0000-0000-000000000001', 'OP', 'Opérations', 'operations') RETURNING id AS jop \gset

-- ---------------------------------------------------------------------------
-- 1. Don saisi hors connexion, rejoué deux fois
-- ---------------------------------------------------------------------------
SELECT public.enregistrer_don('71000000-0000-0000-0000-000000000001', 250000, 'quete', 'especes', '2026-10-11',
  NULL, NULL, NULL, NULL, 'Quête du dimanche', false,
  '71000000-0000-0000-0000-0000000000d1', 'PROV-A3F2-0001', '2026-10-11 09:30+00') AS r1 \gset
SELECT public.enregistrer_don('71000000-0000-0000-0000-000000000001', 250000, 'quete', 'especes', '2026-10-11',
  NULL, NULL, NULL, NULL, 'Quête du dimanche', false,
  '71000000-0000-0000-0000-0000000000d1', 'PROV-A3F2-0001', '2026-10-11 09:30+00') AS r2 \gset
SELECT is(:'r1'::jsonb->>'numero_recu', 'REC-2026-000001', 'premier envoi : reçu définitif attribué à la réception');
SELECT is((:'r2'::jsonb->>'numero_recu') || '/' || (:'r2'::jsonb->>'deja_recu'), 'REC-2026-000001/true',
  'second envoi (même clé) : le même reçu, rien de créé');
SELECT is((SELECT count(*)::int FROM public.dons WHERE etablissement_id = '71000000-0000-0000-0000-000000000001'), 1,
  'un seul don au registre');
SELECT is((SELECT count(*)::int FROM public.pieces_comptables WHERE source_id = '71000000-0000-0000-0000-0000000000d1'), 1,
  'une seule écriture comptable');
SELECT is((SELECT numero_provisoire || '|' || saisi_le_client::date FROM public.dons
            WHERE id = '71000000-0000-0000-0000-0000000000d1'), 'PROV-A3F2-0001|2026-10-11',
  'numéro provisoire et date de saisie sur l''appareil conservés');
SELECT is(public.recu_don('71000000-0000-0000-0000-0000000000d1')->>'numero_provisoire', 'PROV-A3F2-0001',
  'le reçu définitif rappelle le reçu provisoire qu''il remplace');
SELECT is((public.enregistrer_don('71000000-0000-0000-0000-000000000001', 1000)->>'numero_recu'), 'REC-2026-000002',
  'saisie en ligne sans clé : inchangée, numérotation continue');

SELECT pg_temp.en_tant_que(:'dir2_id');
SELECT throws_ok($$SELECT public.enregistrer_don('71000000-0000-0000-0000-000000000002', 5000, 'don', 'especes', '2026-10-11',
  NULL, NULL, NULL, NULL, NULL, false, '71000000-0000-0000-0000-0000000000d1')$$,
  'CLE_DEJA_UTILISEE', 'la clé d''un don d''une autre école est refusée');
SELECT pg_temp.en_tant_que(:'dir_id');

-- ---------------------------------------------------------------------------
-- 2. Brouillard de pièce saisi hors connexion
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.lignes(p_montant numeric) RETURNS jsonb
LANGUAGE sql AS $$
  SELECT jsonb_build_array(jsonb_build_object('compte_id', pg_temp.compte('605'), 'debit', p_montant),
                           jsonb_build_object('compte_id', pg_temp.compte('571'), 'credit', p_montant));
$$;

SELECT public.enregistrer_piece_hors_ligne('71000000-0000-0000-0000-0000000000b1', '71000000-0000-0000-0000-000000000001',
  :'jop', '2026-10-12', 'Craies', pg_temp.lignes(30000)) AS b1 \gset
SELECT is(:'b1'::jsonb->>'statut', 'brouillard', 'brouillard créé sous la clé de l''appareil');
SELECT public.enregistrer_piece_hors_ligne('71000000-0000-0000-0000-0000000000b1', '71000000-0000-0000-0000-000000000001',
  :'jop', '2026-10-12', 'Craies et cahiers', pg_temp.lignes(45000));
SELECT is((SELECT count(*)::int || '|' || max(p.libelle) || '|' || sum(l.debit)::bigint
             FROM public.pieces_comptables p JOIN public.lignes_pieces_comptables l ON l.piece_id = p.id
            WHERE p.id = '71000000-0000-0000-0000-0000000000b1'), '2|Craies et cahiers|45000',
  'nouvel envoi modifié : même pièce, lignes remplacées');
SELECT ok(public.valider_piece('71000000-0000-0000-0000-0000000000b1') LIKE 'OP-2026-%', 'validation en ligne : numérotée');
SELECT is(public.enregistrer_piece_hors_ligne('71000000-0000-0000-0000-0000000000b1', '71000000-0000-0000-0000-000000000001',
  :'jop', '2026-10-12', 'Autre', pg_temp.lignes(1))->>'deja_validee', 'true', 'pièce validée : un envoi tardif ne la touche plus');
SELECT is((SELECT sum(l.debit)::bigint FROM public.lignes_pieces_comptables l WHERE l.piece_id = '71000000-0000-0000-0000-0000000000b1'),
  45000::bigint, 'lignes validées intactes');

SELECT public.cloturer_periode('71000000-0000-0000-0000-000000000001', '2026-10-31');
SELECT throws_ok(format($$SELECT public.enregistrer_piece_hors_ligne(gen_random_uuid(), '71000000-0000-0000-0000-000000000001',
  %L, '2026-10-20', 'Tardif', pg_temp.lignes(1000))$$, :'jop'),
  'PERIODE_CLOTUREE', 'rejeu dans une période clôturée entre-temps : refus métier explicite');
SELECT is((SELECT count(*)::int FROM public.pieces_comptables WHERE libelle = 'Tardif'), 0, 'et rien n''est créé');

-- ---------------------------------------------------------------------------
-- 3. Droits
-- ---------------------------------------------------------------------------
SELECT pg_temp.en_tant_que(:'parent_id');
SELECT throws_ok($$SELECT public.enregistrer_piece_hors_ligne(gen_random_uuid(), '71000000-0000-0000-0000-000000000001',
  gen_random_uuid(), '2026-11-02', 'X', '[]'::jsonb)$$, '42501', NULL, 'un parent ne pousse pas de pièce');

SELECT * FROM finish();
ROLLBACK;
