-- ============================================================================
-- EcoShop — M14 — Comptabilité sans OHADA
--
-- Périmètre (docs/RECHERCHE_COMPARATIVE.md §16) :
--   • Partie double (débit = crédit), structure OUVERTE : aucun plan OHADA
--     imposé, l'utilisateur crée ses propres comptes.
--   • Documents fondamentaux : Journal, Grand Livre, Balance, Livre de
--     banque/caisse (comptes de type 'banque'/'caisse').
--   • IA en supervision : détection d'anomalies, prédiction de trésorerie,
--     recommandation d'écritures récurrentes, analyse de tendances.
--   • Hors-ligne : saisie en cache (LWW), synchronisation différée.
--
-- Principes : soft-delete, dénormalisation tenant + garde-fou trigger
-- (pattern M1/M5), jamais de décision automatique.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Plan comptable (structure ouverte, arborescente)
-- ---------------------------------------------------------------------------
create table if not exists public.plans_comptables (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  code text not null,
  intitule text not null,
  type text not null default 'autre',
  parent_id uuid references public.plans_comptables (id) on delete set null,
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint plans_comptables_code_unique unique (etablissement_id, code)
);

create index if not exists idx_plans_comptables_parent on public.plans_comptables (parent_id);

-- ---------------------------------------------------------------------------
-- 2. Journaux (livres chronologiques : opérations, banque, caisse, …)
-- ---------------------------------------------------------------------------
create table if not exists public.journaux (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  code text not null,
  intitule text not null,
  type text not null default 'operations',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint journaux_code_unique unique (etablissement_id, code)
);

-- ---------------------------------------------------------------------------
-- 3. Écritures comptables (une ligne = un débit + un crédit de même montant)
-- ---------------------------------------------------------------------------
create table if not exists public.ecritures_comptables (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  date_ecriture date not null default current_date,
  libelle text not null,
  compte_debit_id uuid not null references public.plans_comptables (id) on delete restrict,
  compte_credit_id uuid not null references public.plans_comptables (id) on delete restrict,
  montant numeric(14,2) not null check (montant > 0),
  piece_justificative text,
  journal_id uuid not null references public.journaux (id) on delete restrict,
  user_id uuid references public.profiles (id) on delete set null,
  numero_lot text,
  saisi_hors_ligne boolean not null default false,
  device_id text,
  client_ts timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_ecritures_etab_date on public.ecritures_comptables (etablissement_id, date_ecriture);
create index if not exists idx_ecritures_compte_debit on public.ecritures_comptables (compte_debit_id);
create index if not exists idx_ecritures_compte_credit on public.ecritures_comptables (compte_credit_id);
create index if not exists idx_ecritures_journal on public.ecritures_comptables (journal_id);

-- ---------------------------------------------------------------------------
-- 4. Balances (snapshots générés à la demande, mis en cache pour export)
-- ---------------------------------------------------------------------------
create table if not exists public.balances (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  compte_id uuid not null references public.plans_comptables (id) on delete cascade,
  date_balance date not null default current_date,
  solde_debit numeric(14,2) not null default 0,
  solde_credit numeric(14,2) not null default 0,
  created_at timestamptz not null default now(),
  constraint balances_compte_date_unique unique (compte_id, date_balance)
);

create index if not exists idx_balances_etab_date on public.balances (etablissement_id, date_balance);

-- ---------------------------------------------------------------------------
-- 5. Garde-fous multi-tenant
-- ---------------------------------------------------------------------------

-- 5.1 Plan comptable : le parent doit appartenir au même établissement.
create or replace function public.plans_comptables_verifie_parent()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_etab uuid;
begin
  if new.parent_id is not null then
    select etablissement_id into v_etab from public.plans_comptables where id = new.parent_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'PLAN_COMPTABLE_PARENT_INCOHERENT' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists plans_comptables_verifie_parent on public.plans_comptables;
create trigger plans_comptables_verifie_parent
  before insert or update on public.plans_comptables
  for each row execute procedure public.plans_comptables_verifie_parent();

-- 5.2 Écriture : comptes et journal du même établissement ; débit ≠ crédit.
create or replace function public.ecritures_verifie_tenant()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_deb uuid;
  v_cred uuid;
  v_jour uuid;
begin
  select etablissement_id into v_deb from public.plans_comptables where id = new.compte_debit_id;
  select etablissement_id into v_cred from public.plans_comptables where id = new.compte_credit_id;
  select etablissement_id into v_jour from public.journaux where id = new.journal_id;

  if v_deb is distinct from new.etablissement_id
     or v_cred is distinct from new.etablissement_id
     or v_jour is distinct from new.etablissement_id then
    raise exception 'ECRITURE_TENANT_INCOHERENT' using errcode = '23514';
  end if;

  if new.compte_debit_id = new.compte_credit_id then
    raise exception 'ECRITURE_COMPTES_IDENTIQUES' using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists ecritures_verifie_tenant on public.ecritures_comptables;
create trigger ecritures_verifie_tenant
  before insert or update on public.ecritures_comptables
  for each row execute procedure public.ecritures_verifie_tenant();

-- ---------------------------------------------------------------------------
-- 6. Helpers d'autorisation (direction / finance, via permission fine)
-- ---------------------------------------------------------------------------
create or replace function public.est_comptable(p_etablissement uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.est_admin_gsg()
      or public.est_appel_service()
      or public.est_direction(p_etablissement)
      or public.a_permission(p_etablissement, 'comptabilite.lire');
$$;

create or replace function public.est_comptable_ecriture(p_etablissement uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.est_admin_gsg()
      or public.est_appel_service()
      or public.est_direction(p_etablissement)
      or public.a_permission(p_etablissement, 'comptabilite.ecrire');
$$;

revoke all on function public.est_comptable(uuid) from public;
revoke all on function public.est_comptable_ecriture(uuid) from public;
grant execute on function public.est_comptable(uuid) to authenticated, service_role;
grant execute on function public.est_comptable_ecriture(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. RLS — isolation par établissement, accès direction/finance
-- ---------------------------------------------------------------------------
alter table public.plans_comptables enable row level security;
alter table public.journaux enable row level security;
alter table public.ecritures_comptables enable row level security;
alter table public.balances enable row level security;

create policy plans_comptables_select on public.plans_comptables
  for select using (public.est_comptable(etablissement_id));
create policy plans_comptables_write on public.plans_comptables
  for all using (public.est_comptable_ecriture(etablissement_id))
  with check (public.est_comptable_ecriture(etablissement_id));

create policy journaux_select on public.journaux
  for select using (public.est_comptable(etablissement_id));
create policy journaux_write on public.journaux
  for all using (public.est_comptable_ecriture(etablissement_id))
  with check (public.est_comptable_ecriture(etablissement_id));

create policy ecritures_select on public.ecritures_comptables
  for select using (public.est_comptable(etablissement_id));
create policy ecritures_write on public.ecritures_comptables
  for all using (public.est_comptable_ecriture(etablissement_id))
  with check (public.est_comptable_ecriture(etablissement_id));

create policy balances_select on public.balances
  for select using (public.est_comptable(etablissement_id));

-- ---------------------------------------------------------------------------
-- 8. Fonctions de génération (Journal, Grand Livre, Balance)
-- ---------------------------------------------------------------------------

-- 8.1 Journal — enregistrements chronologiques d'un journal donné.
create or replace function public.journal_comptable(
  p_etablissement uuid, p_journal uuid, p_debut date, p_fin date)
returns table (
  date_ecriture date,
  libelle text,
  compte_debit text,
  compte_credit text,
  montant numeric,
  piece_justificative text
)
language sql
stable
security definer
set search_path = public
as $$
  select e.date_ecriture, e.libelle, d.code, c.code, e.montant, e.piece_justificative
  from public.ecritures_comptables e
  join public.plans_comptables d on d.id = e.compte_debit_id
  join public.plans_comptables c on c.id = e.compte_credit_id
  where e.etablissement_id = p_etablissement
    and e.journal_id = p_journal
    and e.deleted_at is null
    and e.date_ecriture between p_debut and p_fin
  order by e.date_ecriture, e.created_at;
$$;

-- 8.2 Grand Livre — mouvements d'un compte (débit/crédit).
create or replace function public.grand_livre(
  p_etablissement uuid, p_compte uuid, p_debut date, p_fin date)
returns table (
  date_ecriture date,
  libelle text,
  piece_justificative text,
  sens text,
  montant numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select e.date_ecriture, e.libelle, e.piece_justificative, 'debit', e.montant
  from public.ecritures_comptables e
  where e.etablissement_id = p_etablissement
    and e.compte_debit_id = p_compte
    and e.deleted_at is null
    and e.date_ecriture between p_debut and p_fin
  union all
  select e.date_ecriture, e.libelle, e.piece_justificative, 'credit', e.montant
  from public.ecritures_comptables e
  where e.etablissement_id = p_etablissement
    and e.compte_credit_id = p_compte
    and e.deleted_at is null
    and e.date_ecriture between p_debut and p_fin
  order by date_ecriture;
$$;

-- 8.3 Balance — soldes (débit/crédit) par compte à une date donnée.
create or replace function public.balance_comptable(p_etablissement uuid, p_date date)
returns table (
  compte_id uuid,
  code text,
  intitule text,
  total_debit numeric,
  total_credit numeric,
  solde_debit numeric,
  solde_credit numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with mouvements as (
    select compte_debit_id as compte_id, montant as debit, 0::numeric as credit
    from public.ecritures_comptables
    where etablissement_id = p_etablissement and deleted_at is null and date_ecriture <= p_date
    union all
    select compte_credit_id as compte_id, 0::numeric, montant
    from public.ecritures_comptables
    where etablissement_id = p_etablissement and deleted_at is null and date_ecriture <= p_date
  )
  select pc.id, pc.code, pc.intitule,
         coalesce(sum(m.debit), 0)  as total_debit,
         coalesce(sum(m.credit), 0) as total_credit,
         greatest(coalesce(sum(m.debit),0) - coalesce(sum(m.credit),0), 0) as solde_debit,
         greatest(coalesce(sum(m.credit),0) - coalesce(sum(m.debit),0), 0) as solde_credit
  from public.plans_comptables pc
  left join mouvements m on m.compte_id = pc.id
  where pc.etablissement_id = p_etablissement and pc.deleted_at is null
  group by pc.id, pc.code, pc.intitule
  order by pc.code;
$$;

-- 8.4 Génération (snapshot) de la balance à une date — alimente `balances`.
create or replace function public.generer_balance(p_etablissement uuid, p_date date)
returns setof public.balances
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.balances (etablissement_id, compte_id, date_balance, solde_debit, solde_credit)
  select p_etablissement, b.compte_id, p_date, b.solde_debit, b.solde_credit
  from public.balance_comptable(p_etablissement, p_date) b
  on conflict (compte_id, date_balance) do update
    set solde_debit = excluded.solde_debit,
        solde_credit = excluded.solde_credit;

  return query
    select * from public.balances
    where etablissement_id = p_etablissement and date_balance = p_date
    order by compte_id;
end;
$$;

-- 8.5 Export JSON (préparation Excel/PDF côté Edge Function).
create or replace function public.exporter_journal_json(
  p_etablissement uuid, p_journal uuid, p_debut date, p_fin date)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
  from (select * from public.journal_comptable(p_etablissement, p_journal, p_debut, p_fin)) r;
$$;

-- ---------------------------------------------------------------------------
-- 9. Fonctions IA (supervision, jamais de décision automatique)
-- ---------------------------------------------------------------------------

-- 9.1 Détection d'anomalies : montants élevés et doubles saisies.
create or replace function public.detecter_anomalies_comptables(p_etablissement uuid)
returns table (
  ecriture_id uuid,
  date_ecriture date,
  libelle text,
  montant numeric,
  anomalie text
)
language sql
stable
security definer
set search_path = public
as $$
  select e.id, e.date_ecriture, e.libelle, e.montant,
         case when e.montant >= 10000000 then 'montant_eleve' else 'double_saisie' end
  from public.ecritures_comptables e
  where e.etablissement_id = p_etablissement
    and e.deleted_at is null
    and ( e.montant >= 10000000
          or exists (
            select 1 from public.ecritures_comptables e2
            where e2.etablissement_id = p_etablissement
              and e2.id <> e.id
              and e2.compte_debit_id = e.compte_debit_id
              and e2.compte_credit_id = e.compte_credit_id
              and e2.montant = e.montant
              and e2.date_ecriture = e.date_ecriture
              and e2.deleted_at is null
          )
        )
  order by e.date_ecriture desc;
$$;

-- 9.2 Prédiction de trésorerie (méthode directe 30 j, comptes banque/caisse).
create or replace function public.predire_tresorerie(p_etablissement uuid, p_jours int default 30)
returns table (jour date, solde_projete numeric)
language sql
stable
security definer
set search_path = public
as $$
  with flux as (
    select e.date_ecriture as jour,
           coalesce(sum(e.montant) filter (where d.type in ('banque','caisse')), 0)
         - coalesce(sum(e.montant) filter (where c.type in ('banque','caisse')), 0) as net
    from public.ecritures_comptables e
    join public.plans_comptables d on d.id = e.compte_debit_id
    join public.plans_comptables c on c.id = e.compte_credit_id
    where e.etablissement_id = p_etablissement and e.deleted_at is null
      and e.date_ecriture >= current_date - 30
    group by 1
  ),
  solde_actuel as (
    select coalesce(sum(e.montant) filter (where d.type in ('banque','caisse')), 0)
         - coalesce(sum(e.montant) filter (where c.type in ('banque','caisse')), 0) as s
    from public.ecritures_comptables e
    join public.plans_comptables d on d.id = e.compte_debit_id
    join public.plans_comptables c on c.id = e.compte_credit_id
    where e.etablissement_id = p_etablissement and e.deleted_at is null
  ),
  moyenne as (select coalesce(avg(net), 0) as m from flux),
  series as (
    select generate_series(current_date, current_date + p_jours, '1 day')::date as jour
  )
  select s.jour,
         (select s from solde_actuel) + (select m from moyenne) * (row_number() over (order by s.jour)) as solde_projete
  from series s
  order by s.jour;
$$;

-- 9.3 Recommandation d'écritures récurrentes (≥ 2 mois distincts).
create or replace function public.recommander_ecritures(p_etablissement uuid)
returns table (
  libelle text,
  compte_debit text,
  compte_credit text,
  montant numeric,
  mois_distincts bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select e.libelle, d.code, c.code, max(e.montant),
         count(distinct date_trunc('month', e.date_ecriture)) as mois_distincts
  from public.ecritures_comptables e
  join public.plans_comptables d on d.id = e.compte_debit_id
  join public.plans_comptables c on c.id = e.compte_credit_id
  where e.etablissement_id = p_etablissement and e.deleted_at is null
  group by e.libelle, d.code, c.code
  having count(distinct date_trunc('month', e.date_ecriture)) >= 2
  order by mois_distincts desc;
$$;

-- 9.4 Analyse des tendances (dépenses/charges vs revenus/produits par mois).
create or replace function public.analyser_tendances(p_etablissement uuid, p_mois int default 12)
returns table (mois date, total_charges numeric, total_produits numeric, solde_net numeric)
language sql
stable
security definer
set search_path = public
as $$
  select date_trunc('month', e.date_ecriture)::date as mois,
         coalesce(sum(e.montant) filter (where d.type = 'charge'), 0)  as total_charges,
         coalesce(sum(e.montant) filter (where c.type = 'produit'), 0) as total_produits,
         coalesce(sum(e.montant) filter (where c.type = 'produit'), 0)
       - coalesce(sum(e.montant) filter (where d.type = 'charge'), 0)  as solde_net
  from public.ecritures_comptables e
  join public.plans_comptables d on d.id = e.compte_debit_id
  join public.plans_comptables c on c.id = e.compte_credit_id
  where e.etablissement_id = p_etablissement and e.deleted_at is null
    and e.date_ecriture >= (date_trunc('month', current_date) - make_interval(months => p_mois))
  group by 1
  order by 1;
$$;

-- ---------------------------------------------------------------------------
-- 10. Droits d'exécution
-- ---------------------------------------------------------------------------
revoke all on function public.journal_comptable(uuid, uuid, date, date) from public;
revoke all on function public.grand_livre(uuid, uuid, date, date) from public;
revoke all on function public.balance_comptable(uuid, date) from public;
revoke all on function public.generer_balance(uuid, date) from public;
revoke all on function public.exporter_journal_json(uuid, uuid, date, date) from public;
revoke all on function public.detecter_anomalies_comptables(uuid) from public;
revoke all on function public.predire_tresorerie(uuid, int) from public;
revoke all on function public.recommander_ecritures(uuid) from public;
revoke all on function public.analyser_tendances(uuid, int) from public;

grant execute on function public.journal_comptable(uuid, uuid, date, date) to authenticated, service_role;
grant execute on function public.grand_livre(uuid, uuid, date, date) to authenticated, service_role;
grant execute on function public.balance_comptable(uuid, date) to authenticated, service_role;
grant execute on function public.generer_balance(uuid, date) to authenticated, service_role;
grant execute on function public.exporter_journal_json(uuid, uuid, date, date) to authenticated, service_role;
grant execute on function public.detecter_anomalies_comptables(uuid) to authenticated, service_role;
grant execute on function public.predire_tresorerie(uuid, int) to authenticated, service_role;
grant execute on function public.recommander_ecritures(uuid) to authenticated, service_role;
grant execute on function public.analyser_tendances(uuid, int) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 11. Permissions comptables
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domaine, libelle, description) values
  ('comptabilite.lire',        'comptabilite', 'Consulter la comptabilité',    'Lecture journal, grand livre, balance'),
  ('comptabilite.ecrire',      'comptabilite', 'Saisir des écritures',         'Création/modification des écritures'),
  ('comptabilite.plan.gerer',  'comptabilite', 'Gérer le plan comptable',      'Création des comptes et journaux'),
  ('comptabilite.export',      'comptabilite', 'Exporter les états',           'Export Excel/PDF des états financiers')
on conflict (code) do nothing;
