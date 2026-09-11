-- ============================================================================
-- EcoShop — Test RLS 38 : M15quater (inscription, réinscription, encaissement)
--
-- Vérifie que :
--   • la direction peut créer une inscription (matricule généré serveur) ;
--     un élève ne le peut pas ;
--   • le doublon est détecté après une première inscription ;
--   • une réinscription pour une nouvelle année scolaire fonctionne, une
--     deuxième inscription pour la MÊME année est rejetée (contrainte M5) ;
--   • le statut boursier trace automatiquement qui/quand ;
--   • les paliers de paiement rejettent une somme > 100 % ;
--   • le solde scolaire (tarif − encaissements) est calculé côté serveur ;
--   • un encaissement force `saisi_par = auth.uid()`, est visible à
--     l'élève/au parent, invisible à un tiers, immuable une fois créé
--     (sauf annulation tracée avec motif obligatoire) ; un élève ne peut pas
--     en créer ;
--   • isolation inter-établissement RÉELLE (deux établissements distincts,
--     chacun avec sa propre direction) : la direction d'un établissement B
--     ne peut ni lire ni écrire un encaissement de l'établissement A ;
--   • une annulation valide (motif fourni) réussit, trace automatiquement
--     `annule_par`/`annule_le`, et `solde_scolarite` se recalcule aussitôt
--     (l'encaissement annulé sort de la somme des montants payés).
--
-- Note technique : l'interpolation de variable psql (:'var') ne doit jamais
-- apparaître à l'intérieur d'un bloc dollar-quoté ($$...$$) — on passe les
-- valeurs dynamiques (ids générés par les RPC) via `format(%L, :'var')` en
-- gardant `:'var'` HORS du bloc dollar-quoté (comme argument de format()).
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

SELECT plan(28);

-- ---------------------------------------------------------------------------
-- Établissement (id fixe), 2 années scolaires, 2 classes, comptes.
-- ---------------------------------------------------------------------------
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('42000000-0000-0000-0000-000000000001', 'École Inscription M15q', 'ecole-inscription-m15q');

INSERT INTO public.annees_scolaires (id, etablissement_id, libelle, date_debut, date_fin, courante)
VALUES
  ('42000000-0000-0000-0000-000000000002', '42000000-0000-0000-0000-000000000001', '2025-2026', '2025-10-01', '2026-06-30', false),
  ('42000000-0000-0000-0000-000000000003', '42000000-0000-0000-0000-000000000001', '2026-2027', '2026-10-01', '2027-06-30', true);

INSERT INTO public.classes (id, etablissement_id, annee_scolaire_id, code, nom)
VALUES
  ('42000000-0000-0000-0000-000000000004', '42000000-0000-0000-0000-000000000001',
   '42000000-0000-0000-0000-000000000003', '6A-M15Q', '6e A'),
  ('42000000-0000-0000-0000-000000000005', '42000000-0000-0000-0000-000000000001',
   '42000000-0000-0000-0000-000000000002', '5A-M15Q', '5e A');

SELECT pg_temp.creer_compte('224600003001', 'direction') AS dir_id      \gset
SELECT pg_temp.creer_compte('224600003002', 'eleve')     AS eleve_id    \gset
SELECT pg_temp.creer_compte('224600003003', 'parent')    AS parent_id   \gset
SELECT pg_temp.creer_compte('224600003004', 'eleve')     AS etranger_id \gset
SELECT pg_temp.creer_compte('224600003005', 'direction') AS dir_b_id    \gset

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_id'::uuid, '42000000-0000-0000-0000-000000000001', 'direction');

-- Un second établissement RÉEL, distinct, avec sa propre direction — pour
-- prouver l'isolation inter-établissement (et pas seulement l'exclusion
-- d'un tiers non affilié, cf. 8c).
INSERT INTO public.etablissements (id, nom, slug)
VALUES ('42000000-0000-0000-0000-000000000099', 'École B (isolation)', 'ecole-b-isolation-m15q');

INSERT INTO public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
VALUES (:'dir_b_id'::uuid, '42000000-0000-0000-0000-000000000099', 'direction');

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;

-- 1. Un élève ne peut pas créer d'inscription (règle absolue : adulte seul).
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  $$ SELECT public.creer_inscription_nouvel_eleve(
       '42000000-0000-0000-0000-000000000001', 'CAMARA', 'Mory', '2013-04-12',
       '42000000-0000-0000-0000-000000000004', '42000000-0000-0000-0000-000000000003', 'M') $$,
  '42501',
  NULL
);

-- 2. La direction crée l'inscription : matricule généré, id renvoyé.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT public.creer_inscription_nouvel_eleve(
  '42000000-0000-0000-0000-000000000001', 'CAMARA', 'Mory', '2013-04-12',
  '42000000-0000-0000-0000-000000000004', '42000000-0000-0000-0000-000000000003', 'M'
) AS fiche_id \gset

SELECT ok(:'fiche_id' IS NOT NULL, 'direction : création d''inscription renvoie un id de fiche');
SELECT matches(
  (SELECT matricule FROM public.fiches_eleves WHERE id = :'fiche_id'::uuid),
  '^[A-Z]+-[0-9]{5}$',
  'matricule généré serveur au format attendu'
);
SELECT is(
  (SELECT count(*) FROM public.inscriptions WHERE fiche_eleve_id = :'fiche_id'::uuid)::int, 1,
  'une inscription active a été créée pour la nouvelle fiche'
);

-- 3. Doublon détecté après coup (même nom/prénom/naissance).
SELECT is(
  public.verifier_doublon_eleve('camara', ' Mory ', '2013-04-12'),
  true,
  'doublon détecté (insensible à la casse et aux espaces)'
);
SELECT is(
  public.verifier_doublon_eleve('Diallo', 'Aissatou', '2010-01-01'),
  false,
  'pas de faux positif pour un élève non inscrit'
);

-- 4. Réinscription : nouvelle inscription sur l'année précédente OK ; une
-- deuxième inscription sur la MÊME année échoue (contrainte unique M5,
-- 23505) — id de fiche dynamique passé hors du bloc dollar-quoté via format().
SELECT public.creer_reinscription(
  :'fiche_id'::uuid, '42000000-0000-0000-0000-000000000005', '42000000-0000-0000-0000-000000000002'
) AS reinscription_id \gset
SELECT ok(:'reinscription_id' IS NOT NULL, 'réinscription sur une nouvelle année : créée');

SELECT throws_ok(
  format(
    $$ SELECT public.creer_reinscription(%L, '42000000-0000-0000-0000-000000000004', '42000000-0000-0000-0000-000000000003') $$,
    :'fiche_id'
  ),
  '23505',
  NULL
);

-- ---------------------------------------------------------------------------
-- 5. Statut boursier : trace qui/quand automatiquement.
--
-- Non-régression (patch 20260906001502) : `dir_id` n'a AUCUN poste RH
-- rattaché dans ce test (aucun `poste_id` sur son `etablissements_membres`)
-- — condition explicitement vérifiée ci-dessous, pas seulement supposée —
-- donc `a_permission(..., 'scolarite.inscription.gerer')` est faux pour lui.
-- Si la policy UPDATE de `inscriptions` perdait à nouveau son repli
-- `est_direction()`, l'UPDATE suivant échouerait silencieusement (0 ligne
-- affectée, sans erreur) et les deux assertions boursier ci-dessous
-- échoueraient — exactement le bug trouvé lors de la première exécution
-- locale réelle de ce fichier.
-- ---------------------------------------------------------------------------
SELECT public.creer_inscription_nouvel_eleve(
  '42000000-0000-0000-0000-000000000001', 'DIALLO', 'Fatoumata', '2012-06-01',
  '42000000-0000-0000-0000-000000000004', '42000000-0000-0000-0000-000000000003', 'F'
) AS fiche2_id \gset
SELECT id AS inscription2_id FROM public.inscriptions WHERE fiche_eleve_id = :'fiche2_id'::uuid \gset

SELECT is(
  public.a_permission('42000000-0000-0000-0000-000000000001'::uuid, 'scolarite.inscription.gerer'),
  false,
  'précondition du scénario de non-régression : dir_id n''a aucun poste RH/permission dédiée (seul est_direction() doit permettre la suite)'
);

UPDATE public.inscriptions SET boursier = true WHERE id = :'inscription2_id'::uuid;
SELECT is(
  (SELECT boursier_modifie_par FROM public.inscriptions WHERE id = :'inscription2_id'::uuid)::text,
  :'dir_id',
  'statut boursier : boursier_modifie_par enregistré automatiquement'
);
SELECT ok(
  (SELECT boursier_modifie_le FROM public.inscriptions WHERE id = :'inscription2_id'::uuid) IS NOT NULL,
  'statut boursier : boursier_modifie_le enregistré automatiquement'
);

-- ---------------------------------------------------------------------------
-- 6. Paliers de paiement : la somme ne peut pas dépasser 100 %.
-- ---------------------------------------------------------------------------
INSERT INTO public.paliers_paiement_config (etablissement_id, annee_scolaire_id, nom, pourcentage, ordre)
VALUES ('42000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000003', 'Tranche 1', 40, 1);
INSERT INTO public.paliers_paiement_config (etablissement_id, annee_scolaire_id, nom, pourcentage, ordre)
VALUES ('42000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000003', 'Tranche 2', 60, 2);

SELECT throws_ok(
  $$ INSERT INTO public.paliers_paiement_config (etablissement_id, annee_scolaire_id, nom, pourcentage, ordre)
     VALUES ('42000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000003', 'Tranche 3', 10, 3) $$,
  '23514',
  NULL
);

-- ---------------------------------------------------------------------------
-- 7. Solde scolaire : tarif − encaissements validés.
-- ---------------------------------------------------------------------------
RESET ROLE;
INSERT INTO public.frais_scolarite_config (etablissement_id, annee_scolaire_id, niveau_id, montant_annuel)
VALUES ('42000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000003', null, 1000000);
SET LOCAL ROLE authenticated;

SELECT id AS inscription1_id FROM public.inscriptions
  WHERE fiche_eleve_id = :'fiche_id'::uuid AND annee_scolaire_id = '42000000-0000-0000-0000-000000000003' \gset

SELECT is(
  (SELECT montant_du FROM public.solde_scolarite(:'inscription1_id'::uuid))::numeric,
  1000000::numeric,
  'solde scolaire : montant dû = tarif par défaut de l''établissement'
);

-- ---------------------------------------------------------------------------
-- 8. Encaissements — visibilité, immutabilité, annulation.
-- ---------------------------------------------------------------------------

-- 8a. Un élève ne peut pas enregistrer d'encaissement.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'eleve_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format(
    $$ INSERT INTO public.encaissements_scolarite
       (etablissement_id, fiche_eleve_id, inscription_id, type_frais, montant, saisi_par)
       VALUES ('42000000-0000-0000-0000-000000000001', %L, %L, 'scolarite', 100000, auth.uid()) $$,
    :'fiche_id', :'inscription1_id'
  ),
  '42501',
  NULL
);

-- 8b. La direction enregistre un encaissement — saisi_par forcé au serveur
-- même si un autre id était transmis dans la requête.
--
-- Non-régression (patch 20260906001502) : même `dir_id` sans poste RH
-- (vérifié explicitement ci-dessous, pas seulement `scolarite.inscription.
-- gerer` comme au-dessus, mais aussi `scolarite.encaissement.gerer` —
-- seul `est_direction()` doit autoriser cet INSERT). Le `RETURNING`
-- ci-dessous (via `\gset`) est précisément le chemin qui échouait avant le
-- patch : `INSERT ... RETURNING` échouait pour TOUT LE MONDE (pas
-- seulement les comptes sans poste) à cause de la policy SELECT
-- auto-référentielle `encaissement_visible(id)` — c'est aussi le chemin
-- réel emprunté par `SupabaseScolariteRepository.enregistrerEncaissement()`
-- (`.insert(...).select().single()`). Si l'un ou l'autre bug revenait, ce
-- `\gset` échouerait dur (erreur RLS), arrêtant tout le fichier.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT is(
  public.a_permission('42000000-0000-0000-0000-000000000001'::uuid, 'scolarite.encaissement.gerer'),
  false,
  'précondition du scénario de non-régression : dir_id n''a pas non plus la permission encaissement dédiée'
);
INSERT INTO public.encaissements_scolarite
  (etablissement_id, fiche_eleve_id, inscription_id, type_frais, montant, saisi_par)
VALUES ('42000000-0000-0000-0000-000000000001', :'fiche_id'::uuid, :'inscription1_id'::uuid,
        'scolarite', 400000, :'eleve_id'::uuid)
RETURNING id AS encaissement_id \gset

SELECT is(
  (SELECT saisi_par FROM public.encaissements_scolarite WHERE id = :'encaissement_id'::uuid)::text,
  :'dir_id',
  'encaissement : saisi_par forcé au serveur (auth.uid()), pas la valeur transmise'
);

-- 8c. Un tiers (étranger) ne voit pas l'encaissement ; le parent, oui.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'etranger_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.encaissements_scolarite WHERE id = :'encaissement_id'::uuid)::int, 0,
  'encaissement : invisible à un tiers'
);

-- Remettre les claims sur dir_id avant cet INSERT de fixture : le trigger
-- `relations_verifie_tenant` (M5) n'est pas SECURITY DEFINER (comme la
-- majorité des triggers `*_verifie_tenant` du projet — seuls M9-patch et
-- M15quater dérogent, avec justification explicite) — son lookup sur
-- `fiches_eleves` est donc filtré par RLS ; rester sur les claims
-- d'`etranger_id` (laissés actifs par l'assertion précédente) échouerait
-- avec un `FICHE_AUTRE_ETABLISSEMENT` trompeur, faute de visibilité.
--
-- Non-régression (patch 20260906001503) : ce même dir_id (toujours sans
-- poste RH) réussit maintenant cet INSERT ... RETURNING directement via
-- RLS — la policy `relations_scolarite` n'avait auparavant PAS le repli
-- `est_direction()` (même défaut que `inscriptions_ecriture_scolarite`
-- avant 20260906001502) : seul un compte avec `scolarite.relation.gerer`
-- explicite pouvait écrire, une direction sans poste échouait en 42501.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
INSERT INTO public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
VALUES ('42000000-0000-0000-0000-000000000001', :'parent_id'::uuid, :'fiche_id'::uuid, 'parent', 'confirmee', true)
RETURNING id AS relation_regression_id \gset
SELECT ok(
  :'relation_regression_id' IS NOT NULL,
  'non-régression : direction sans poste peut lier un parent (repli est_direction() sur relations_scolarite)'
);

SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'parent_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.encaissements_scolarite WHERE id = :'encaissement_id'::uuid)::int, 1,
  'encaissement : visible au parent confirmé de l''élève'
);

-- 8d. Le montant est immuable ; l'annulation exige un motif.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);
SELECT throws_ok(
  format($$ UPDATE public.encaissements_scolarite SET montant = 1 WHERE id = %L $$, :'encaissement_id'),
  '23514',
  NULL
);
SELECT throws_ok(
  format($$ UPDATE public.encaissements_scolarite SET statut = 'annule' WHERE id = %L $$, :'encaissement_id'),
  '23514',
  NULL
);

-- ---------------------------------------------------------------------------
-- 9. Isolation RÉELLE inter-établissement — deux établissements distincts,
-- chacun avec sa propre direction (pas seulement un tiers non affilié).
-- ---------------------------------------------------------------------------

-- 9a. La direction de l'établissement B ne voit pas l'encaissement de A.
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_b_id', 'role', 'authenticated')::text, true);
SELECT is(
  (SELECT count(*) FROM public.encaissements_scolarite WHERE id = :'encaissement_id'::uuid)::int, 0,
  'encaissement : invisible à la direction d''un autre établissement (isolation réelle, pas juste un tiers non affilié)'
);

-- 9b. La direction de l'établissement B ne peut pas insérer un encaissement
-- rattaché à l'établissement A (elle n'est direction que de B).
SELECT throws_ok(
  format(
    $$ INSERT INTO public.encaissements_scolarite
       (etablissement_id, fiche_eleve_id, inscription_id, type_frais, montant, saisi_par)
       VALUES ('42000000-0000-0000-0000-000000000001', %L, %L, 'scolarite', 1000, auth.uid()) $$,
    :'fiche_id', :'inscription1_id'
  ),
  '42501',
  NULL
);

-- ---------------------------------------------------------------------------
-- 10. Annulation valide (motif fourni) : succès, traçabilité auto, solde
-- recalculé côté serveur (jamais stocké).
-- ---------------------------------------------------------------------------
SELECT set_config('request.jwt.claims',
       json_build_object('sub', :'dir_id', 'role', 'authenticated')::text, true);

UPDATE public.encaissements_scolarite
SET statut = 'annule', motif_annulation = 'Erreur de saisie - double encaissement'
WHERE id = :'encaissement_id'::uuid;

SELECT is(
  (SELECT statut::text FROM public.encaissements_scolarite WHERE id = :'encaissement_id'::uuid),
  'annule',
  'annulation motivée : acceptée, statut passé à annule'
);
SELECT is(
  (SELECT annule_par FROM public.encaissements_scolarite WHERE id = :'encaissement_id'::uuid)::text,
  :'dir_id',
  'annulation : annule_par enregistré automatiquement (auth.uid()), jamais transmis par le client'
);
SELECT ok(
  (SELECT annule_le FROM public.encaissements_scolarite WHERE id = :'encaissement_id'::uuid) IS NOT NULL,
  'annulation : annule_le horodaté automatiquement'
);

SELECT is(
  (SELECT montant_paye FROM public.solde_scolarite(:'inscription1_id'::uuid))::numeric,
  0::numeric,
  'solde scolaire : recalculé automatiquement, l''encaissement annulé sort de la somme payée'
);
SELECT is(
  (SELECT solde FROM public.solde_scolarite(:'inscription1_id'::uuid))::numeric,
  1000000::numeric,
  'solde scolaire : redevient égal au tarif complet après annulation du seul encaissement'
);

RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
