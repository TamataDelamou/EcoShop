-- ============================================================================
-- EcoShop — Test RLS 99 : journal des portées, synchronisation par différences
-- (REG-35 lot 3, migration 20260906001581)
-- ============================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.sur(p_uid uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

CREATE OR REPLACE FUNCTION pg_temp.compte(p_email text, p_role text)
RETURNS uuid LANGUAGE plpgsql SET search_path = public, auth, pg_catalog AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, email_confirmed_at) VALUES (v_id, p_email, now());
  UPDATE public.profiles SET role_racine = p_role::public.role_racine, prenom = 'Test', nom = 'Test' WHERE id = v_id;
  RETURN v_id;
END $$;

-- Portées signalées modifiées pour [p_portee, p_id] depuis p_depuis.
CREATE OR REPLACE FUNCTION pg_temp.modifiee(p_portee text, p_id uuid, p_depuis timestamptz) RETURNS boolean
LANGUAGE sql AS $$
  SELECT EXISTS (
    SELECT 1 FROM jsonb_array_elements(
      public.portees_modifiees(jsonb_build_array(jsonb_build_object('portee', p_portee, 'id', p_id, 'depuis', p_depuis))) -> 'modifiees'
    ) m WHERE m ->> 'portee' = p_portee AND (m ->> 'id')::uuid = p_id
  );
$$;

SELECT plan(14);

INSERT INTO public.etablissements (id, nom, slug, devise_code) VALUES
  ('99000000-0000-0000-0000-00000000000a', 'École A', 'ecole-a-99', 'GNF'),
  ('99000000-0000-0000-0000-00000000000b', 'École B', 'ecole-b-99', 'GNF');
INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante) VALUES
  ('99000000-0000-0000-0000-0000000000a1', '99000000-0000-0000-0000-00000000000a', '2026-2027', '2026-10-01', '2027-06-30', true);
INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom) VALUES
  ('99000000-0000-0000-0000-0000000000c1', '99000000-0000-0000-0000-00000000000a', '99000000-0000-0000-0000-0000000000a1', '6A', '6e A'),
  ('99000000-0000-0000-0000-0000000000c2', '99000000-0000-0000-0000-00000000000a', '99000000-0000-0000-0000-0000000000a1', '6B', '6e B');
INSERT INTO public.fiches_eleves (id, etablissement_id, matricule, nom, prenom, date_naissance) VALUES
  ('99000000-0000-0000-0000-0000000000e1', '99000000-0000-0000-0000-00000000000a', 'A99-1', 'CAMARA', 'Fanta', '2014-05-06');

SELECT pg_temp.compte('dir.a99@exemple.org', 'direction') AS dir_a \gset
SELECT pg_temp.compte('dir.b99@exemple.org', 'direction') AS dir_b \gset
INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement) VALUES
  (:'dir_a', '99000000-0000-0000-0000-00000000000a', 'direction'),
  (:'dir_b', '99000000-0000-0000-0000-00000000000b', 'direction');

-- ---------------------------------------------------------------------------
-- 1. Les déclencheurs marquent les portées
-- ---------------------------------------------------------------------------
SELECT ok(EXISTS (SELECT 1 FROM public.journal_portees
                  WHERE portee = 'etablissement' AND portee_id = '99000000-0000-0000-0000-00000000000a'),
          'nouvelles classes : l''annuaire de l''école est marqué');
SELECT ok(EXISTS (SELECT 1 FROM public.journal_portees
                  WHERE portee = 'fiche' AND portee_id = '99000000-0000-0000-0000-0000000000e1'),
          'nouvelle fiche élève : sa portée est marquée');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.journal_portees
                      WHERE portee = 'classe' AND portee_id = '99000000-0000-0000-0000-0000000000c1'),
          'classe sans élève ni cours : rien à relire');

INSERT INTO public.inscriptions (id, etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id) VALUES
  ('99000000-0000-0000-0000-0000000000f1', '99000000-0000-0000-0000-00000000000a', '99000000-0000-0000-0000-0000000000e1',
   '99000000-0000-0000-0000-0000000000c1', '99000000-0000-0000-0000-0000000000a1');
SELECT ok(EXISTS (SELECT 1 FROM public.journal_portees
                  WHERE portee = 'classe' AND portee_id = '99000000-0000-0000-0000-0000000000c1'),
          'inscription : la classe est marquée');

UPDATE public.inscriptions SET classe_id = '99000000-0000-0000-0000-0000000000c2'
 WHERE id = '99000000-0000-0000-0000-0000000000f1';
SELECT ok(EXISTS (SELECT 1 FROM public.journal_portees
                  WHERE portee = 'classe' AND portee_id = '99000000-0000-0000-0000-0000000000c2'),
          'changement de classe : la nouvelle classe est marquée aussi');

-- Suppression : la portée est marquée (relue en entier, sans tombstone).
DELETE FROM public.journal_portees WHERE portee = 'classe' AND portee_id = '99000000-0000-0000-0000-0000000000c2';
DELETE FROM public.inscriptions WHERE id = '99000000-0000-0000-0000-0000000000f1';
SELECT ok(EXISTS (SELECT 1 FROM public.journal_portees
                  WHERE portee = 'classe' AND portee_id = '99000000-0000-0000-0000-0000000000c2'),
          'suppression : la classe est marquée');

SELECT is((SELECT etablissement_id FROM public.journal_portees
           WHERE portee = 'classe' AND portee_id = '99000000-0000-0000-0000-0000000000c2'),
          '99000000-0000-0000-0000-00000000000a'::uuid, 'chaque portée connaît son école');

-- ---------------------------------------------------------------------------
-- 2. Lecture par le téléphone
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SELECT pg_temp.sur(:'dir_a');

SELECT throws_ok('SELECT * FROM public.journal_portees', '42501', NULL,
                 'le journal ne se lit pas directement');
SELECT throws_ok($$SELECT public.marquer_portee('classe', gen_random_uuid(), gen_random_uuid())$$, '42501', NULL,
                 'personne ne marque une portée à la main');

SELECT ok(pg_temp.modifiee('classe', '99000000-0000-0000-0000-0000000000c2', now() - interval '1 hour'),
          'classe modifiée depuis la dernière lecture : à relire');
SELECT ok(NOT pg_temp.modifiee('classe', '99000000-0000-0000-0000-0000000000c2', now() + interval '1 hour'),
          'classe lue après sa dernière modification (marge comprise) : rien à relire');
SELECT ok(NOT pg_temp.modifiee('fiche', gen_random_uuid(), now() - interval '1 hour'),
          'portée jamais modifiée : rien à relire');
SELECT ok((public.portees_modifiees('[]'::jsonb) ->> 'maintenant') IS NOT NULL,
          'le serveur donne son heure, date de lecture à garder');

-- Une autre école ne voit pas les dates de l'école A.
SELECT pg_temp.sur(:'dir_b');
SELECT ok(NOT pg_temp.modifiee('classe', '99000000-0000-0000-0000-0000000000c2', now() - interval '1 hour'),
          'une autre école n''apprend rien de l''école A');

SELECT * FROM finish();
ROLLBACK;
