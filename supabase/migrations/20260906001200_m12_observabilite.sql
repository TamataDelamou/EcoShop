-- ============================================================================
-- EcoShop — M12 — Intégration & Déploiement continu — Observabilité
--
-- Périmètre (docs/RECHERCHE_COMPARATIVE.md §14, docs/M12_INTEGRATION_DEPLOIEMENT.md) :
--   • Monitoring intelligent : métriques collectées hors-ligne puis rejouées,
--     indicateur de santé de la base (APM minimal : taille, connexions, uptime).
--   • Prédiction des pics de charge : agrégation des évaluations à venir
--     (M6) et des absences récentes (M7) → niveau de charge hebdomadaire.
--   • Optimisation des migrations : ordre M0→M11 déjà séquencé ; cette
--     migration n'ajoute que des objets non invasifs (pas d'ALTER des tables
--     métier), donc sans risque de régression inter-modules.
--
-- Principes : aucune décision automatique (scaling, alertes) ; les fonctions
-- sont des aides à la décision, exécutables par le personnel autorisé.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Journal de métriques — collecte différée (réseau intermittent)
-- ---------------------------------------------------------------------------
create table if not exists public.journal_metriques (
  id bigint generated always as identity primary key,
  etablissement_id uuid references public.etablissements (id) on delete cascade,
  metrique text not null,
  valeur numeric,
  contexte jsonb not null default '{}'::jsonb,
  source text,
  created_at timestamptz not null default now()
);

create index if not exists idx_journal_metriques_metrique on public.journal_metriques (metrique);
create index if not exists idx_journal_metriques_created on public.journal_metriques (created_at);
create index if not exists idx_journal_metriques_etab on public.journal_metriques (etablissement_id);

comment on table public.journal_metriques is
  'Métriques applicatives (latence, erreurs, saturation) collectées localement et rejouées quand le réseau revient.';

-- ---------------------------------------------------------------------------
-- RLS — lecture restreinte au périmètre (établissement, service, admin GSG)
-- ---------------------------------------------------------------------------
alter table public.journal_metriques enable row level security;

drop policy if exists journal_metriques_select on public.journal_metriques;
create policy journal_metriques_select on public.journal_metriques
  for select
  using (
    public.est_admin_gsg()
    or public.est_appel_service()
    or public.est_membre_actif(etablissement_id)
  );

drop policy if exists journal_metriques_insert on public.journal_metriques;
create policy journal_metriques_insert on public.journal_metriques
  for insert
  with check (
    public.est_appel_service()
    or public.est_membre_actif(etablissement_id)
  );

-- ---------------------------------------------------------------------------
-- 2. Indicateur de santé de la base (monitoring intelligent, APM minimal)
-- ---------------------------------------------------------------------------
create or replace function public.indicateurs_sante_base()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'collecte_le', now(),
    'taille_base', pg_size_pretty(pg_database_size(current_database())),
    'connexions_actives', (select count(*) from pg_stat_activity where state = 'active'),
    'connexions_totales', (select count(*) from pg_stat_activity),
    'transactions_en_attente', (select count(*) from pg_stat_activity where state = 'idle in transaction'),
    'uptime', (select extract(epoch from (now() - pg_postmaster_start_time()))::bigint)
  );
$$;

comment on function public.indicateurs_sante_base() is
  'Indicateurs APM minimaux (taille, connexions, transactions en attente, uptime). Aide à la décision de scaling.';

revoke all on function public.indicateurs_sante_base() from public;
grant execute on function public.indicateurs_sante_base() to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Prédiction des pics de charge (rentrée, examens, bulletins)
-- ---------------------------------------------------------------------------
create or replace function public.predire_pics_charge(p_etablissement uuid, p_annee uuid)
returns table (
  semaine date,
  nb_evaluations bigint,
  nb_examens bigint,
  absences_30j bigint,
  niveau_charge text
)
language sql
stable
security definer
set search_path = public
as $$
  with eval as (
    select date_trunc('week', e.date_evaluation)::date as semaine,
           count(*) as nb_evaluations,
           count(*) filter (where e.type in ('examen_blanc', 'controle')) as nb_examens
    from public.evaluations e
    where e.etablissement_id = p_etablissement
      and e.annee_scolaire_id = p_annee
      and e.deleted_at is null
      and e.date_evaluation >= current_date
    group by 1
  ),
  abs as (
    select date_trunc('week', p.date_presence)::date as semaine,
           count(*) as absences
    from public.presences p
    where p.etablissement_id = p_etablissement
      and p.annee_scolaire_id = p_annee
      and p.deleted_at is null
      and p.statut = 'absent'
      and p.date_presence >= current_date - interval '30 days'
    group by 1
  )
  select coalesce(e.semaine, a.semaine) as semaine,
         coalesce(e.nb_evaluations, 0) as nb_evaluations,
         coalesce(e.nb_examens, 0) as nb_examens,
         coalesce(a.absences, 0) as absences_30j,
         case
           when coalesce(e.nb_examens, 0) >= 2 then 'critique'
           when coalesce(e.nb_evaluations, 0) >= 4 or coalesce(a.absences, 0) >= 10 then 'eleve'
           else 'normal'
         end as niveau_charge
  from eval e
  full join abs a using (semaine)
  order by 1;
$$;

comment on function public.predire_pics_charge(uuid, uuid) is
  'Prédit les semaines à forte charge (examens, évaluations, absentéisme) pour recommander un scaling.';

revoke all on function public.predire_pics_charge(uuid, uuid) from public;
grant execute on function public.predire_pics_charge(uuid, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Permissions d'observabilité
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domaine, libelle, description) values
  ('observabilite.metriques.lire', 'observabilite', 'Consulter les métriques de monitoring', 'Lecture du journal de métriques applicatives'),
  ('observabilite.sante.lire',      'observabilite', 'Consulter la santé de la base',    'Exécution de indicateurs_sante_base()'),
  ('observabilite.prediction.lire', 'observabilite', 'Consulter les prédictions de charge', 'Exécution de predire_pics_charge()')
on conflict (code) do nothing;
