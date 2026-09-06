-- ============================================================================
-- EcoShop — M8 — RH & Personnel
--
-- Périmètre (ANALYSE_GLOBALE.md, cahier v4.1) :
--   • Employés : dossiers RH adossés aux comptes (profiles) et rattachés à un
--     établissement (tenant). Catégories : enseignant, administratif,
--     direction, personnel.
--   • Contrats : type, durée, renouvellement, salaire de base.
--   • Congés : demande par l'employé, validation humaine (RH/direction),
--     historique et soldes.
--   • Absences personnel : pointage des absences du personnel (justifiées ou
--     non) — alimente le risque de turn-over.
--   • Paie légère : bulletins = base + primes − retenues = net, sans fiscalité
--     complexe (délibérément hors périmètre).
--   • Lien avec M5 (affectations_enseignants → charge de travail) et M4
--     (programmes_matieres → recommandation de formation).
--
-- Principes (cohérents M1/M5/M6/M7) :
--   • `etablissement_id` dénormalisé sur chaque table + garde-fou multi-tenant
--     par trigger.
--   • Visibilité : RH/direction → tout l'établissement ; l'employé → son
--     propre dossier, ses congés et ses bulletins. Jamais de visibilité
--     croisée entre établissements ni entre collègues.
--   • IA en trois niveaux (descriptive/prédictive/prescriptive), signaux non
--     bloquants, soumis à validation humaine : aucune action RH automatisée.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Types énumérés
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.type_contrat as enum ('cdi', 'cdd', 'vacataire', 'stage', 'prestataire');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.statut_employe as enum ('actif', 'en_conge', 'suspendu', 'demissionnaire', 'retraite');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.type_conge as enum ('annuel', 'maladie', 'maternite', 'exceptionnel', 'sans_solde');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.statut_conge as enum ('demande', 'valide', 'refuse');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.statut_paie as enum ('brouillon', 'valide', 'paye');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.type_absence_personnel as enum ('maladie', 'injustifiee', 'autorisee', 'autre');
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Employés — dossier RH adossé au compte (profiles)
-- ---------------------------------------------------------------------------
create table if not exists public.employes (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  matricule text not null,
  categorie text not null default 'personnel'
    check (categorie in ('enseignant', 'administratif', 'direction', 'personnel')),
  date_embauche date not null default current_date,
  statut public.statut_employe not null default 'actif',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint employes_matricule_unique unique (etablissement_id, matricule),
  constraint employes_profile_unique unique (etablissement_id, profile_id)
);

-- ---------------------------------------------------------------------------
-- 2. Contrats
-- ---------------------------------------------------------------------------
create table if not exists public.contrats (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  employe_id uuid not null references public.employes (id) on delete cascade,
  type public.type_contrat not null default 'cdd',
  date_debut date not null default current_date,
  date_fin date,                          -- null = durée indéterminée (CDI)
  salaire_base numeric(12,2) not null check (salaire_base >= 0),
  renouvellement_auto boolean not null default false,
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint contrats_dates_coherentes check (date_fin is null or date_fin >= date_debut),
  constraint contrats_employe_periode_type_unique unique (employe_id, date_debut, type)
);

-- ---------------------------------------------------------------------------
-- 3. Congés — demande par l'employé, validation humaine (RH/direction)
-- ---------------------------------------------------------------------------
create table if not exists public.conges (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  employe_id uuid not null references public.employes (id) on delete cascade,
  type public.type_conge not null default 'annuel',
  date_debut date not null,
  date_fin date not null,
  nb_jours int not null check (nb_jours > 0),
  statut public.statut_conge not null default 'demande',
  motif text,
  valide_par uuid references public.profiles (id) on delete set null,
  date_validation timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint conges_dates_coherentes check (date_fin >= date_debut),
  constraint conges_employe_periode_type_unique unique (employe_id, date_debut, type)
);

-- ---------------------------------------------------------------------------
-- 4. Absences du personnel (pointage) — alimente le risque de turn-over
-- ---------------------------------------------------------------------------
create table if not exists public.absences_personnel (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  employe_id uuid not null references public.employes (id) on delete cascade,
  date_absence date not null default current_date,
  type public.type_absence_personnel not null default 'injustifiee',
  justifie boolean not null default false,
  motif text,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint absences_employe_date_unique unique (employe_id, date_absence)
);

-- ---------------------------------------------------------------------------
-- 5. Paie légère — bulletin mensuel (base + primes − retenues = net)
-- ---------------------------------------------------------------------------
create table if not exists public.paie_bulletins (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  employe_id uuid not null references public.employes (id) on delete cascade,
  contrat_id uuid not null references public.contrats (id) on delete restrict,
  periode_debut date not null,
  periode_fin date not null,
  salaire_base numeric(12,2) not null check (salaire_base >= 0),
  primes numeric(12,2) not null default 0 check (primes >= 0),
  retenues numeric(12,2) not null default 0 check (retenues >= 0),
  net numeric(12,2) not null check (net >= 0),
  statut public.statut_paie not null default 'brouillon',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint paie_periode_coherente check (periode_fin >= periode_debut),
  constraint paie_employe_periode_unique unique (employe_id, periode_debut)
);

-- ---------------------------------------------------------------------------
-- 6. Garde-fous multi-tenant (pattern membres_verifie_tenant, M1)
-- ---------------------------------------------------------------------------
create or replace function public.employes_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
begin
  -- L'employé doit être un membre actif de l'établissement.
  if not exists (
    select 1 from public.etablissements_membres m
    where m.profile_id = new.profile_id
      and m.etablissement_id = new.etablissement_id
      and m.actif and m.deleted_at is null
      and (m.date_fin is null or m.date_fin >= current_date)
  ) then
    raise exception 'EMPLOYE_NON_MEMBRE' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists employes_verifie_tenant_trg on public.employes;
create trigger employes_verifie_tenant_trg
  before insert or update on public.employes
  for each row execute procedure public.employes_verifie_tenant();

create or replace function public.contrats_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.employes where id = new.employe_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'EMPLOYE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists contrats_verifie_tenant_trg on public.contrats;
create trigger contrats_verifie_tenant_trg
  before insert or update on public.contrats
  for each row execute procedure public.contrats_verifie_tenant();

create or replace function public.conges_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.employes where id = new.employe_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'EMPLOYE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists conges_verifie_tenant_trg on public.conges;
create trigger conges_verifie_tenant_trg
  before insert or update on public.conges
  for each row execute procedure public.conges_verifie_tenant();

create or replace function public.absences_personnel_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.employes where id = new.employe_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'EMPLOYE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists absences_personnel_verifie_tenant_trg on public.absences_personnel;
create trigger absences_personnel_verifie_tenant_trg
  before insert or update on public.absences_personnel
  for each row execute procedure public.absences_personnel_verifie_tenant();

create or replace function public.paie_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.employes where id = new.employe_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'EMPLOYE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  select etablissement_id into v_etab from public.contrats where id = new.contrat_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'CONTRAT_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  if not exists (select 1 from public.contrats c where c.id = new.contrat_id and c.employe_id = new.employe_id) then
    raise exception 'CONTRAT_AUTRE_EMPLOYE' using errcode = '23514';
  end if;

  return new;
end $$;

drop trigger if exists paie_verifie_tenant_trg on public.paie_bulletins;
create trigger paie_verifie_tenant_trg
  before insert or update on public.paie_bulletins
  for each row execute procedure public.paie_verifie_tenant();

-- Validation humaine des congés : seul RH/direction (ou le serveur) peut
-- passer une demande en « valide »/« refuse ». L'employé ne peut créer que
-- des demandes (statut « demande »).
create or replace function public.conges_verifie_validation()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.statut in ('valide', 'refuse') then
    if auth.uid() is not null and not public.est_rh(new.etablissement_id) then
      raise exception 'VALIDATION_RH_REQUISE' using errcode = '42501';
    end if;
    new.valide_par := coalesce(new.valide_par, auth.uid());
    new.date_validation := coalesce(new.date_validation, now());
  end if;
  return new;
end $$;

drop trigger if exists conges_verifie_validation_trg on public.conges;
create trigger conges_verifie_validation_trg
  before insert or update on public.conges
  for each row execute procedure public.conges_verifie_validation();

-- Calcul du net de paie (base + primes − retenues), toujours recalculé
-- côté serveur — le client ne fait jamais foi sur le montant net.
create or replace function public.paie_calcule_net()
returns trigger language plpgsql set search_path = public as $$
begin
  new.net := new.salaire_base + new.primes - new.retenues;
  if new.net < 0 then
    raise exception 'NET_NEGATIF' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists paie_calcule_net_trg on public.paie_bulletins;
create trigger paie_calcule_net_trg
  before insert or update on public.paie_bulletins
  for each row execute procedure public.paie_calcule_net();

-- ---------------------------------------------------------------------------
-- 7. Helpers de visibilité (SECURITY DEFINER — jamais de récursion RLS)
-- ---------------------------------------------------------------------------

-- Vrai si l'appelant est RH/direction de l'établissement : soit il dirige,
-- soit son poste porte la permission « rh.employe.gerer ».
create or replace function public.est_rh(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.est_direction(p_etablissement)
      or public.a_permission(p_etablissement, 'rh.employe.gerer');
$$;

-- Vrai si l'appelant est l'employé lui-même (dossier lié à son compte).
create or replace function public.est_employe_self(p_employe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.employes e
    where e.id = p_employe and e.profile_id = auth.uid() and e.deleted_at is null
  );
$$;

create or replace function public.employe_visible(p_employe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.employes e
    where e.id = p_employe and e.deleted_at is null
      and (public.est_rh(e.etablissement_id) or e.profile_id = auth.uid())
  );
$$;

create or replace function public.contrat_visible(p_contrat uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.contrats c
    join public.employes e on e.id = c.employe_id
    where c.id = p_contrat and c.deleted_at is null
      and (public.est_rh(c.etablissement_id) or e.profile_id = auth.uid())
  );
$$;

create or replace function public.conge_visible(p_conge uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.conges c
    join public.employes e on e.id = c.employe_id
    where c.id = p_conge and c.deleted_at is null
      and (public.est_rh(c.etablissement_id) or e.profile_id = auth.uid())
  );
$$;

-- Charge horaire hebdomadaire de l'employé (affectations M5, hors soft-delete).
create or replace function public.charge_horaire(p_employe uuid)
returns int
language sql stable security definer set search_path = public
as $$
  select coalesce(sum(a.volume_horaire_hebdo), 0)::int
  from public.employes e
  join public.affectations_enseignants a on a.enseignant_profile_id = e.profile_id
  where e.id = p_employe and a.deleted_at is null;
$$;

grant execute on function public.est_rh(uuid) to authenticated;
grant execute on function public.est_employe_self(uuid) to authenticated;
grant execute on function public.employe_visible(uuid) to authenticated;
grant execute on function public.contrat_visible(uuid) to authenticated;
grant execute on function public.conge_visible(uuid) to authenticated;
grant execute on function public.charge_horaire(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Fonctions IA — trois niveaux (descriptive / prédictive / prescriptive)
--    Signaux d'aide à la décision, jamais automatisés. Appel serveur ou RH.
-- ---------------------------------------------------------------------------

-- Niveau descriptif : tableau de bord effectifs.
create or replace function public.analyser_effectifs(p_etablissement uuid)
returns table (
  categorie text,
  effectif bigint,
  anciennete_moyenne_jours numeric,
  masse_salariale_base numeric
)
language plpgsql stable security definer set search_path = public
as $$
begin
  if auth.uid() is not null and not public.est_rh(p_etablissement) then
    raise exception 'RH_REQUIS' using errcode = '42501';
  end if;

  return query
  select e.categorie,
         count(*)::bigint,
         round(avg(current_date - e.date_embauche), 1),
         coalesce(sum(c.salaire_base), 0)
  from public.employes e
  left join lateral (
    select c.salaire_base
    from public.contrats c
    where c.employe_id = e.id and c.deleted_at is null and c.actif
      and (c.date_fin is null or c.date_fin >= current_date)
    order by c.date_debut desc
    limit 1
  ) c on true
  where e.etablissement_id = p_etablissement and e.deleted_at is null
  group by e.categorie
  order by e.categorie;
end $$;

-- Niveau prédictif : risque de turn-over (0 = faible, 1 = élevé).
-- Croise absences (M8), ancienneté, charge de travail (M5) et type de contrat.
create or replace function public.calculer_score_turnover(p_employe uuid)
returns numeric
language plpgsql stable security definer set search_path = public
as $$
declare
  v_etab uuid;
  v_profile uuid;
  v_embauche date;
  v_charge int;
  v_abs_injustifiees int;
  v_abs_maladie int;
  v_risk_abs numeric;
  v_risk_anciennete numeric;
  v_risk_charge numeric;
  v_risk_contrat numeric;
  v_type public.type_contrat;
  v_fin date;
begin
  select etablissement_id, profile_id, date_embauche
    into v_etab, v_profile, v_embauche
  from public.employes where id = p_employe and deleted_at is null;

  if v_etab is null then
    raise exception 'EMPLOYE_INTROUVABLE' using errcode = 'P0002';
  end if;

  if auth.uid() is not null and not public.est_rh(v_etab) and auth.uid() <> v_profile then
    raise exception 'RH_REQUIS' using errcode = '42501';
  end if;

  -- Absences (fenêtre 180 jours) : les injustifiées pèsent double.
  select count(*) into v_abs_injustifiees
  from public.absences_personnel
  where employe_id = p_employe and type = 'injustifiee'
    and date_absence >= current_date - 180 and deleted_at is null;

  select count(*) into v_abs_maladie
  from public.conges
  where employe_id = p_employe and type = 'maladie' and statut = 'valide'
    and date_fin >= current_date - 180 and deleted_at is null;

  v_risk_abs := least(1.0, (v_abs_injustifiees * 2 + v_abs_maladie) / 10.0);

  -- Ancienneté : les moins d'un an sont les plus à risque.
  v_risk_anciennete := case
    when current_date - v_embauche < 365 then 1.0
    when current_date - v_embauche < 730 then 0.6
    else 0.2
  end;

  -- Charge : surcharge ou inactivité totale signalent un malaise.
  v_charge := public.charge_horaire(p_employe);
  v_risk_charge := case
    when v_charge = 0 then 0.3
    when v_charge > 30 then 1.0
    when v_charge >= 20 then 0.5
    else 0.1
  end;

  -- Contrat : CDD/vacataire en fin de course = risque de départ imminent.
  select c.type, c.date_fin into v_type, v_fin
  from public.contrats c
  where c.employe_id = p_employe and c.deleted_at is null and c.actif
    and (c.date_fin is null or c.date_fin >= current_date)
  order by c.date_debut desc limit 1;

  v_risk_contrat := case
    when v_type is null then 0.9
    when v_type = 'cdi' then 0.1
    when v_type in ('cdd', 'vacataire') and v_fin is not null and v_fin <= current_date + 90 then 1.0
    else 0.5
  end;

  return round(greatest(0.0, least(1.0,
    0.4 * v_risk_abs + 0.2 * v_risk_anciennete + 0.2 * v_risk_charge + 0.2 * v_risk_contrat
  ))::numeric, 2);
end $$;

-- Niveau prescriptif : recommander une formation (matières du référentiel M4
-- du pays que l'employé n'enseigne pas encore sur l'année donnée).
create or replace function public.recommander_formation(p_employe uuid, p_annee uuid)
returns table (programme_matiere_id uuid, code text, libelle text, raison text)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_etab uuid;
  v_profile uuid;
  v_pays text;
begin
  select e.etablissement_id, e.profile_id, et.pays_code
    into v_etab, v_profile, v_pays
  from public.employes e
  join public.etablissements et on et.id = e.etablissement_id
  where e.id = p_employe and e.deleted_at is null;

  if v_etab is null then
    raise exception 'EMPLOYE_INTROUVABLE' using errcode = 'P0002';
  end if;

  if auth.uid() is not null and not public.est_rh(v_etab) and auth.uid() <> v_profile then
    raise exception 'RH_REQUIS' using errcode = '42501';
  end if;

  return query
  select m.id, m.code, m.nom,
         'Matière du référentiel non couverte par l''enseignant'
  from public.programmes_matieres m
  join public.programmes_officiels p on p.id = m.programme_id
  where p.pays_code = v_pays
    and m.statut = 'publie'
    and m.id not in (
      select a.programme_matiere_id
      from public.affectations_enseignants a
      where a.enseignant_profile_id = v_profile
        and a.annee_scolaire_id = p_annee
        and a.programme_matiere_id is not null
        and a.deleted_at is null
    )
  order by m.code;
end $$;

-- Niveau prescriptif : optimisation des remplacements. Pour chaque enseignant
-- absent à la date donnée, propose le remplaçant actif le moins chargé.
create or replace function public.optimiser_remplacements(p_etablissement uuid, p_date date)
returns table (
  employe_absent_id uuid,
  absent_matricule text,
  remplacant_id uuid,
  remplacant_matricule text
)
language plpgsql stable security definer set search_path = public
as $$
declare
  r record;
begin
  if auth.uid() is not null and not public.est_rh(p_etablissement) then
    raise exception 'RH_REQUIS' using errcode = '42501';
  end if;

  for r in
    select e.id as employe_id, e.matricule
    from public.employes e
    where e.etablissement_id = p_etablissement
      and e.categorie = 'enseignant'
      and e.statut = 'actif'
      and e.deleted_at is null
      and (
        exists (
          select 1 from public.absences_personnel a
          where a.employe_id = e.id and a.date_absence = p_date and a.deleted_at is null
        )
        or exists (
          select 1 from public.conges c
          where c.employe_id = e.id and c.statut = 'valide' and c.deleted_at is null
            and p_date between c.date_debut and c.date_fin
        )
      )
  loop
    return query
    select r.employe_id, r.matricule, cand.id, cand.matricule
    from (
      select e.id, e.matricule, public.charge_horaire(e.id) as charge
      from public.employes e
      where e.etablissement_id = p_etablissement
        and e.categorie = 'enseignant'
        and e.statut = 'actif'
        and e.deleted_at is null
        and e.id <> r.employe_id
        and not exists (
          select 1 from public.absences_personnel a
          where a.employe_id = e.id and a.date_absence = p_date and a.deleted_at is null
        )
        and not exists (
          select 1 from public.conges c
          where c.employe_id = e.id and c.statut = 'valide' and c.deleted_at is null
            and p_date between c.date_debut and c.date_fin
        )
      order by charge asc, e.matricule asc
      limit 1
    ) cand;
  end loop;
end $$;

grant execute on function public.analyser_effectifs(uuid) to authenticated;
grant execute on function public.calculer_score_turnover(uuid) to authenticated;
grant execute on function public.recommander_formation(uuid, uuid) to authenticated;
grant execute on function public.optimiser_remplacements(uuid, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Row Level Security
-- ---------------------------------------------------------------------------
alter table public.employes enable row level security;
alter table public.contrats enable row level security;
alter table public.conges enable row level security;
alter table public.absences_personnel enable row level security;
alter table public.paie_bulletins enable row level security;

-- Employés : lecture par RH ou soi-même ; écriture par RH.
drop policy if exists "employes_select" on public.employes;
create policy "employes_select" on public.employes
  for select using (public.employe_visible(id));

drop policy if exists "employes_ecriture_rh" on public.employes;
create policy "employes_ecriture_rh" on public.employes
  for all
  using (public.est_rh(etablissement_id))
  with check (public.est_rh(etablissement_id));

-- Contrats : lecture par RH ou l'employé concerné ; écriture par RH.
drop policy if exists "contrats_select" on public.contrats;
create policy "contrats_select" on public.contrats
  for select using (public.contrat_visible(id));

drop policy if exists "contrats_ecriture_rh" on public.contrats;
create policy "contrats_ecriture_rh" on public.contrats
  for all
  using (public.est_rh(etablissement_id))
  with check (public.est_rh(etablissement_id));

-- Congés : lecture par RH ou l'employé concerné. Insertion par l'employé (sa
-- propre demande) ou par RH. La validation reste RH (trigger de validation).
drop policy if exists "conges_select" on public.conges;
create policy "conges_select" on public.conges
  for select using (public.conge_visible(id));

drop policy if exists "conges_insert_demande" on public.conges;
create policy "conges_insert_demande" on public.conges
  for insert
  with check (
    public.est_employe_self(employe_id) or public.est_rh(etablissement_id)
  );

drop policy if exists "conges_validation_rh" on public.conges;
create policy "conges_validation_rh" on public.conges
  for update
  using (public.est_rh(etablissement_id))
  with check (public.est_rh(etablissement_id));

drop policy if exists "conges_delete" on public.conges;
create policy "conges_delete" on public.conges
  for delete
  using (
    public.est_rh(etablissement_id)
    or (public.est_employe_self(employe_id) and statut = 'demande')
  );

-- Absences personnel : lecture par RH ou l'employé concerné ; écriture par RH.
drop policy if exists "absences_select" on public.absences_personnel;
create policy "absences_select" on public.absences_personnel
  for select using (
    public.est_rh(etablissement_id) or public.est_employe_self(employe_id)
  );

drop policy if exists "absences_ecriture_rh" on public.absences_personnel;
create policy "absences_ecriture_rh" on public.absences_personnel
  for all
  using (public.est_rh(etablissement_id))
  with check (public.est_rh(etablissement_id));

-- Paie : lecture par RH ou l'employé concerné (son propre net) ; écriture RH.
drop policy if exists "paie_select" on public.paie_bulletins;
create policy "paie_select" on public.paie_bulletins
  for select using (
    public.est_rh(etablissement_id) or public.est_employe_self(employe_id)
  );

drop policy if exists "paie_ecriture_rh" on public.paie_bulletins;
create policy "paie_ecriture_rh" on public.paie_bulletins
  for all
  using (public.est_rh(etablissement_id))
  with check (public.est_rh(etablissement_id));

-- ---------------------------------------------------------------------------
-- 10. Index
-- ---------------------------------------------------------------------------
create index if not exists idx_employes_etablissement on public.employes (etablissement_id);
create index if not exists idx_employes_profile on public.employes (profile_id);
create index if not exists idx_contrats_employe on public.contrats (employe_id);
create index if not exists idx_conges_employe on public.conges (employe_id);
create index if not exists idx_conges_etablissement on public.conges (etablissement_id);
create index if not exists idx_absences_employe on public.absences_personnel (employe_id);
create index if not exists idx_paie_employe on public.paie_bulletins (employe_id);

-- ---------------------------------------------------------------------------
-- 11. Permissions introduites par M8
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domaine, libelle, description) values
  ('rh.employe.voir',    'rh', 'Consulter les dossiers employés', 'Accéder aux dossiers RH des employés de l''établissement.'),
  ('rh.employe.gerer',   'rh', 'Gérer les employés',              'Créer, modifier les dossiers employés et saisir les absences.'),
  ('rh.contrat.gerer',   'rh', 'Gérer les contrats',              'Créer, renouveler et clore les contrats.'),
  ('rh.conge.valider',   'rh', 'Valider les congés',              'Valider ou refuser les demandes de congés.'),
  ('rh.paie.gerer',      'rh', 'Gérer la paie',                   'Établir et valider les bulletins de paie.')
on conflict (code) do nothing;

-- ============================================================================
-- Fin M8.
-- ============================================================================
