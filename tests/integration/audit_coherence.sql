-- ============================================================================
-- EcoShop — M12 — Audit de cohérence inter-modules (M0 → M12)
--
-- Usage :
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/integration/audit_coherence.sql
--
-- Sortie : une table de contrôles (OK/KO), puis un résumé GO/NO-GO.
--   • 0 KO  → GO (socle cohérent)
--   • >0 KO → NO-GO (corriger avant déploiement)
--
-- L'audit est non destructif (lecture seule) et idempotent.
-- ============================================================================

\set ON_ERROR_STOP on
\pset pager off

-- ---------------------------------------------------------------------------
-- 0. Table de résultat temporaire
-- ---------------------------------------------------------------------------
drop table if exists pg_temp._audit_m12;
create temp table _audit_m12 (
  categorie text not null,
  controle text not null,
  statut text not null,
  detail text
);

-- Helper : existence d'une fonction dans le schéma public (par nom).
create or replace function pg_temp.fn_ok(p_nom text)
returns text
language sql
stable
as $$
  select case when exists (
    select 1 from information_schema.routines
    where routine_schema = 'public' and routine_name = p_nom
  ) then 'OK' else 'KO' end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Présence des tables structurantes
-- ---------------------------------------------------------------------------
insert into _audit_m12 values
  ('tables', 'profiles',            case when to_regclass('public.profiles')             is not null then 'OK' else 'KO' end, 'M0 — identité'),
  ('tables', 'etablissements',      case when to_regclass('public.etablissements')       is not null then 'OK' else 'KO' end, 'M0 — multi-tenant'),
  ('tables', 'etablissements_membres', case when to_regclass('public.etablissements_membres') is not null then 'OK' else 'KO' end, 'M0/M1 — rattachements'),
  ('tables', 'permissions',         case when to_regclass('public.permissions')          is not null then 'OK' else 'KO' end, 'M1 — catalogue'),
  ('tables', 'poste_permissions',   case when to_regclass('public.poste_permissions')    is not null then 'OK' else 'KO' end, 'M1 — jonction'),
  ('tables', 'unites_operationnelles', case when to_regclass('public.unites_operationnelles') is not null then 'OK' else 'KO' end, 'M1 — organisation'),
  ('tables', 'annees_scolaires',    case when to_regclass('public.annees_scolaires')     is not null then 'OK' else 'KO' end, 'M1 — temps scolaire'),
  ('tables', 'periodes_scolaires',  case when to_regclass('public.periodes_scolaires')   is not null then 'OK' else 'KO' end, 'M4 — périodes'),
  ('tables', 'programmes_officiels', case when to_regclass('public.programmes_officiels') is not null then 'OK' else 'KO' end, 'M4 — référentiel'),
  ('tables', 'programmes_matieres', case when to_regclass('public.programmes_matieres')  is not null then 'OK' else 'KO' end, 'M4 — matières'),
  ('tables', 'fiches_eleves',       case when to_regclass('public.fiches_eleves')        is not null then 'OK' else 'KO' end, 'M2/M5 — scolarité'),
  ('tables', 'classes',             case when to_regclass('public.classes')              is not null then 'OK' else 'KO' end, 'M5 — classes'),
  ('tables', 'evaluations',         case when to_regclass('public.evaluations')          is not null then 'OK' else 'KO' end, 'M6 — notation'),
  ('tables', 'notes',               case when to_regclass('public.notes')                is not null then 'OK' else 'KO' end, 'M6 — notes'),
  ('tables', 'bulletins',           case when to_regclass('public.bulletins')            is not null then 'OK' else 'KO' end, 'M6 — bulletins'),
  ('tables', 'presences',           case when to_regclass('public.presences')            is not null then 'OK' else 'KO' end, 'M7 — assiduité'),
  ('tables', 'retards',             case when to_regclass('public.retards')              is not null then 'OK' else 'KO' end, 'M7 — vie scolaire'),
  ('tables', 'journal_metriques',   case when to_regclass('public.journal_metriques')    is not null then 'OK' else 'KO' end, 'M12 — observabilité');

-- ---------------------------------------------------------------------------
-- 2. Intégrité référentielle (orphelins = corruption inter-modules)
-- ---------------------------------------------------------------------------
insert into _audit_m12 values
  ('integrite', 'notes.sans_evaluation',
    (select case when count(*) = 0 then 'OK' else 'KO' end
       from public.notes n left join public.evaluations e on e.id = n.evaluation_id
      where e.id is null), 'notes orphelines'),
  ('integrite', 'notes.sans_fiche_eleve',
    (select case when count(*) = 0 then 'OK' else 'KO' end
       from public.notes n left join public.fiches_eleves f on f.id = n.fiche_eleve_id
      where f.id is null), 'notes sans élève'),
  ('integrite', 'evaluations.sans_classe',
    (select case when count(*) = 0 then 'OK' else 'KO' end
       from public.evaluations e left join public.classes c on c.id = e.classe_id
      where c.id is null), 'évaluations sans classe'),
  ('integrite', 'evaluations.sans_annee',
    (select case when count(*) = 0 then 'OK' else 'KO' end
       from public.evaluations e left join public.annees_scolaires a on a.id = e.annee_scolaire_id
      where a.id is null), 'évaluations sans année'),
  ('integrite', 'presences.sans_fiche',
    (select case when count(*) = 0 then 'OK' else 'KO' end
       from public.presences p left join public.fiches_eleves f on f.id = p.fiche_eleve_id
      where f.id is null), 'présences sans élève'),
  ('integrite', 'poste_permissions.sans_poste',
    (select case when count(*) = 0 then 'OK' else 'KO' end
       from public.poste_permissions pp left join public.postes p on p.id = pp.poste_id
      where p.id is null), 'permissions sans poste'),
  ('integrite', 'poste_permissions.sans_code',
    (select case when count(*) = 0 then 'OK' else 'KO' end
       from public.poste_permissions pp left join public.permissions pe on pe.code = pp.permission_code
      where pe.code is null), 'permissions sans code'),
  ('integrite', 'membres.sans_poste',
    (select case when count(*) = 0 then 'OK' else 'KO' end
       from public.etablissements_membres m left join public.postes p on p.id = m.poste_id
      where m.poste_id is not null and p.id is null), 'membres avec poste inexistant');

-- ---------------------------------------------------------------------------
-- 3. RLS activée sur les tables sensibles
-- ---------------------------------------------------------------------------
insert into _audit_m12 values
  ('rls', 'profiles',          (select case when relrowsecurity then 'OK' else 'KO' end from pg_class where oid = 'public.profiles'::regclass), 'RLS identité'),
  ('rls', 'etablissements',    (select case when relrowsecurity then 'OK' else 'KO' end from pg_class where oid = 'public.etablissements'::regclass), 'RLS multi-tenant'),
  ('rls', 'etablissements_membres', (select case when relrowsecurity then 'OK' else 'KO' end from pg_class where oid = 'public.etablissements_membres'::regclass), 'RLS rattachements'),
  ('rls', 'fiches_eleves',     (select case when relrowsecurity then 'OK' else 'KO' end from pg_class where oid = 'public.fiches_eleves'::regclass), 'RLS scolarité'),
  ('rls', 'classes',           (select case when relrowsecurity then 'OK' else 'KO' end from pg_class where oid = 'public.classes'::regclass), 'RLS classes'),
  ('rls', 'evaluations',       (select case when relrowsecurity then 'OK' else 'KO' end from pg_class where oid = 'public.evaluations'::regclass), 'RLS notation'),
  ('rls', 'notes',             (select case when relrowsecurity then 'OK' else 'KO' end from pg_class where oid = 'public.notes'::regclass), 'RLS notes'),
  ('rls', 'presences',         (select case when relrowsecurity then 'OK' else 'KO' end from pg_class where oid = 'public.presences'::regclass), 'RLS assiduité'),
  ('rls', 'journal_metriques', (select case when relrowsecurity then 'OK' else 'KO' end from pg_class where oid = 'public.journal_metriques'::regclass), 'RLS observabilité');

-- ---------------------------------------------------------------------------
-- 4. Fonctions transverses et IA présentes (nom uniquement, via catalogues)
-- ---------------------------------------------------------------------------
insert into _audit_m12 values
  ('fonctions', 'set_updated_at',        pg_temp.fn_ok('set_updated_at'),        'helper audit'),
  ('fonctions', 'est_admin_gsg',         pg_temp.fn_ok('est_admin_gsg'),         'rôle global'),
  ('fonctions', 'est_appel_service',     pg_temp.fn_ok('est_appel_service'),     'rôle service'),
  ('fonctions', 'est_membre_actif',      pg_temp.fn_ok('est_membre_actif'),      'membre actif'),
  ('fonctions', 'a_permission',          pg_temp.fn_ok('a_permission'),          'contrôle fin de permission'),
  ('fonctions', 'membres_verifie_tenant', pg_temp.fn_ok('membres_verifie_tenant'), 'garde-fou multi-tenant'),
  ('fonctions', 'indicateurs_sante_base', pg_temp.fn_ok('indicateurs_sante_base'), 'monitoring M12'),
  ('fonctions', 'predire_pics_charge',   pg_temp.fn_ok('predire_pics_charge'),   'prédiction charge M12');

-- ---------------------------------------------------------------------------
-- 5. Permissions d'observabilité M12 dans le catalogue
-- ---------------------------------------------------------------------------
insert into _audit_m12 values
  ('permissions', 'observabilite.metriques.lire',
    (select case when exists (select 1 from public.permissions where code = 'observabilite.metriques.lire') then 'OK' else 'KO' end), 'métriques'),
  ('permissions', 'observabilite.sante.lire',
    (select case when exists (select 1 from public.permissions where code = 'observabilite.sante.lire') then 'OK' else 'KO' end), 'santé base'),
  ('permissions', 'observabilite.prediction.lire',
    (select case when exists (select 1 from public.permissions where code = 'observabilite.prediction.lire') then 'OK' else 'KO' end), 'prédiction charge');

-- ---------------------------------------------------------------------------
-- 6. Restitution
-- ---------------------------------------------------------------------------
\echo '================= AUDIT DE COHÉRENCE M0→M12 ================='
select categorie, controle, statut, coalesce(detail, '') as detail
from _audit_m12
order by categorie, controle;

\echo '================= RÉSUMÉ ================='
select
  count(*) as total,
  count(*) filter (where statut = 'OK') as ok,
  count(*) filter (where statut = 'KO') as ko,
  case when count(*) filter (where statut = 'KO') = 0 then 'GO' else 'NO-GO' end as verdict
from _audit_m12;
