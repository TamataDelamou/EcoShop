-- ============================================================================
-- EcoShop — M7 — Absences & Vie scolaire
--
-- Périmètre (cahier v4.1, docs/RECHERCHE_COMPARATIVE.md §9) :
--   • Présences/absences : pointage quotidien, demi-journée ou par cours.
--   • Retards : justifiés/non justifiés, minutes, motifs.
--   • Sanctions : avertissements, blâmes, retenues, exclusions temporaires —
--     **éducatives, jamais punitives par défaut**, avec validation humaine.
--   • Alertes décrochage : score multi-facteurs (croisement M6 notes × M7
--     assiduité), soumises à traitement humain.
--   • Événements scolaires : calendrier, météo, grèves — socle de la
--     prédiction de présence.
--
-- Principes :
--   • Dénormalisation de tenant `etablissement_id` + garde-fou `*_verifie_tenant`.
--   • Hors-ligne : `device_id` + `client_ts` (LWW) sur présences/retards ; la
--     file `sync_queue` (M0) rejoue les pointages.
--   • Éthique IA : les fonctions prédictives/prescriptives produisent des
--     **signaux** ; aucune alerte ni sanction n'est appliquée sans validation
--     humaine (direction, conseil de classe, parent).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Types énumérés
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.statut_presence as enum ('present', 'absent', 'retard', 'exclu', 'dispense');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.type_seance as enum ('demi_journee', 'cours');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.type_sanction as enum
    ('avertissement', 'blame', 'retenue', 'travail_interet', 'exclusion_temporaire', 'conseil_discipline', 'entretien_famille_et_tutorat');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.statut_sanction as enum ('proposee', 'notifiee', 'executee', 'annulee');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.origine_sanction as enum ('humaine', 'ia');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.statut_alerte as enum ('ouverte', 'transmise', 'traitee', 'ignoree');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.type_evenement as enum
    ('ferie', 'vacances', 'greve', 'meteo', 'manifestation', 'examen', 'sortie');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 1. Présences — pointage quotidien, demi-journée ou par cours
-- ---------------------------------------------------------------------------
create table if not exists public.presences (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  classe_id uuid not null references public.classes (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  date_presence date not null default current_date,
  type_seance public.type_seance not null default 'demi_journee',
  programme_matiere_id uuid references public.programmes_matieres (id) on delete set null,
  statut public.statut_presence not null default 'present',
  justifie boolean not null default false,
  motif text,
  saisi_par uuid not null references public.profiles (id) on delete restrict,
  saisi_hors_ligne boolean not null default false,
  device_id text,
  client_ts timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint presences_seance_coherente check (
    (type_seance = 'cours' and programme_matiere_id is not null)
    or type_seance = 'demi_journee'
  )
);

create unique index if not exists idx_presences_demi_journee_unique
  on public.presences (fiche_eleve_id, date_presence)
  where type_seance = 'demi_journee';

create unique index if not exists idx_presences_cours_unique
  on public.presences (fiche_eleve_id, date_presence, programme_matiere_id)
  where type_seance = 'cours';

-- ---------------------------------------------------------------------------
-- 2. Retards
-- ---------------------------------------------------------------------------
create table if not exists public.retards (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  date_retard date not null default current_date,
  minutes_retard int not null check (minutes_retard > 0),
  justifie boolean not null default false,
  motif text,
  saisi_par uuid not null references public.profiles (id) on delete restrict,
  saisi_hors_ligne boolean not null default false,
  device_id text,
  client_ts timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint retards_fiche_date_unique unique (fiche_eleve_id, date_retard)
);

-- ---------------------------------------------------------------------------
-- 3. Sanctions — éducatives, avec validation humaine des recommandations IA
-- ---------------------------------------------------------------------------
create table if not exists public.sanctions (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  type_sanction public.type_sanction not null,
  motif text not null,
  contexte_educatif text,
  date_debut date not null default current_date,
  date_fin date,
  decisionnaire_id uuid not null references public.profiles (id) on delete restrict,
  origine public.origine_sanction not null default 'humaine',
  recommandation_ia jsonb,
  validee_par uuid references public.profiles (id) on delete set null,
  validee_le timestamptz,
  statut public.statut_sanction not null default 'proposee',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint sanctions_periode_coherente check (date_fin is null or date_fin >= date_debut)
);

-- ---------------------------------------------------------------------------
-- 4. Alertes décrochage — score multi-facteurs, traitement humain
-- ---------------------------------------------------------------------------
create table if not exists public.alertes_decrochage (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  score numeric(5,4) not null check (score between 0 and 1),
  seuil numeric(5,4) not null default 0.6 check (seuil between 0 and 1),
  facteurs jsonb not null default '{}'::jsonb,
  date_calcul date not null default current_date,
  statut public.statut_alerte not null default 'ouverte',
  transmise_le timestamptz,
  traitee_par uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists idx_alertes_ouverte_unique
  on public.alertes_decrochage (fiche_eleve_id, annee_scolaire_id)
  where statut in ('ouverte', 'transmise');

-- ---------------------------------------------------------------------------
-- 5. Événements scolaires — socle de la prédiction de présence
-- ---------------------------------------------------------------------------
create table if not exists public.evenements_scolaires (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  type public.type_evenement not null,
  libelle text not null,
  date_debut date not null,
  date_fin date not null,
  impact_presence numeric(5,4) not null default 0 check (impact_presence between 0 and 1),
  source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint evenements_periode_coherente check (date_fin >= date_debut)
);

-- ---------------------------------------------------------------------------
-- 6. Garde-fous multi-tenant
-- ---------------------------------------------------------------------------
create or replace function public.presences_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare
  v_etab uuid;
  v_annee uuid;
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = new.fiche_eleve_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'FICHE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  select etablissement_id into v_etab from public.classes where id = new.classe_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'CLASSE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  -- La classe doit appartenir à l'année scolaire pointée.
  select annee_scolaire_id into v_annee from public.classes where id = new.classe_id;
  if v_annee is distinct from new.annee_scolaire_id then
    raise exception 'CLASSE_AUTRE_ANNEE' using errcode = '23514';
  end if;

  -- L'élève doit être inscrit dans la classe pointée.
  if not exists (
    select 1 from public.inscriptions i
    where i.fiche_eleve_id = new.fiche_eleve_id
      and i.classe_id = new.classe_id
      and i.annee_scolaire_id = new.annee_scolaire_id
      and i.deleted_at is null
  ) then
    raise exception 'ELEVE_NON_INSCRIT' using errcode = '23514';
  end if;

  return new;
end $$;

drop trigger if exists presences_verifie_tenant_trg on public.presences;
create trigger presences_verifie_tenant_trg
  before insert or update on public.presences
  for each row execute procedure public.presences_verifie_tenant();

create or replace function public.retards_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = new.fiche_eleve_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'FICHE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  return new;
end $$;

drop trigger if exists retards_verifie_tenant_trg on public.retards;
create trigger retards_verifie_tenant_trg
  before insert or update on public.retards
  for each row execute procedure public.retards_verifie_tenant();

create or replace function public.sanctions_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = new.fiche_eleve_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'FICHE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  if not exists (
    select 1 from public.etablissements_membres m
    where m.profile_id = new.decisionnaire_id
      and m.etablissement_id = new.etablissement_id
      and m.actif and m.deleted_at is null
  ) then
    raise exception 'DECISIONNAIRE_NON_MEMBRE' using errcode = '23514';
  end if;

  return new;
end $$;

drop trigger if exists sanctions_verifie_tenant_trg on public.sanctions;
create trigger sanctions_verifie_tenant_trg
  before insert or update on public.sanctions
  for each row execute procedure public.sanctions_verifie_tenant();

-- Éthique IA : une sanction d'origine IA reste « proposee » tant qu'elle n'a
-- pas été validée par un humain ; toute activation exige validee_par.
create or replace function public.sanctions_verifie_validation()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.origine = 'ia' and new.statut <> 'proposee' and new.validee_par is null then
    raise exception 'SANCTION_IA_NON_VALIDEE' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists sanctions_verifie_validation_trg on public.sanctions;
create trigger sanctions_verifie_validation_trg
  before insert or update on public.sanctions
  for each row execute procedure public.sanctions_verifie_validation();

create or replace function public.alertes_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = new.fiche_eleve_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'FICHE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  return new;
end $$;

drop trigger if exists alertes_verifie_tenant_trg on public.alertes_decrochage;
create trigger alertes_verifie_tenant_trg
  before insert or update on public.alertes_decrochage
  for each row execute procedure public.alertes_verifie_tenant();

create or replace function public.evenements_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists evenements_verifie_tenant_trg on public.evenements_scolaires;
create trigger evenements_verifie_tenant_trg
  before insert or update on public.evenements_scolaires
  for each row execute procedure public.evenements_verifie_tenant();

-- ---------------------------------------------------------------------------
-- 7. Helpers de droits et de visibilité (SECURITY DEFINER)
-- ---------------------------------------------------------------------------

-- Vrai si l'appelant peut pointer la classe (affecté, principal, ou scolarité).
create or replace function public.peut_pointer(p_classe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.classes c
    where c.id = p_classe and c.deleted_at is null
      and (
        public.a_permission(c.etablissement_id, 'scolarite.presence.gerer')
        or public.est_enseignant_affecte(p_classe)
        or c.enseignant_principal_id = auth.uid()
      )
  );
$$;

create or replace function public.presence_visible(p_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.presences pr
    where pr.id = p_id and pr.deleted_at is null
      and (
        public.est_personnel(pr.etablissement_id)
        or public.fiche_visible(pr.fiche_eleve_id)
      )
  );
$$;

create or replace function public.retard_visible(p_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.retards r
    where r.id = p_id and r.deleted_at is null
      and (
        public.est_personnel(r.etablissement_id)
        or public.fiche_visible(r.fiche_eleve_id)
      )
  );
$$;

create or replace function public.sanction_visible(p_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.sanctions s
    where s.id = p_id and s.deleted_at is null
      and (
        public.est_personnel(s.etablissement_id)
        or public.fiche_visible(s.fiche_eleve_id)
      )
  );
$$;

-- Une alerte n'est visible par l'élève/parent qu'une fois transmise.
create or replace function public.alerte_visible(p_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.alertes_decrochage a
    where a.id = p_id and a.deleted_at is null
      and (
        public.est_personnel(a.etablissement_id)
        or (a.statut = 'transmise' and public.fiche_visible(a.fiche_eleve_id))
      )
  );
$$;

-- Vrai si l'appelant est concerné par l'établissement (personnel, membre,
-- élève lié, ou parent d'un élève lié).
create or replace function public.concerne_etablissement(p_etab uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.est_personnel(p_etab)
      or public.est_membre_actif(p_etab)
      or exists (
        select 1 from public.fiches_eleves f
        where f.etablissement_id = p_etab and f.profile_id = auth.uid() and f.deleted_at is null
      )
      or exists (
        select 1 from public.relations_parent_eleve r
        join public.fiches_eleves f on f.id = r.fiche_eleve_id
        where f.etablissement_id = p_etab
          and r.parent_profile_id = auth.uid()
          and r.statut = 'confirmee' and r.autorise and r.deleted_at is null
          and f.deleted_at is null
      );
$$;

grant execute on function public.peut_pointer(uuid) to authenticated;
grant execute on function public.presence_visible(uuid) to authenticated;
grant execute on function public.retard_visible(uuid) to authenticated;
grant execute on function public.sanction_visible(uuid) to authenticated;
grant execute on function public.alerte_visible(uuid) to authenticated;
grant execute on function public.concerne_etablissement(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Fonctions IA — descriptives, prédictives, prescriptives (signaux)
-- ---------------------------------------------------------------------------

-- Descriptive : tableau de bord comportemental d'un élève sur une année.
create or replace function public.analyse_comportement(p_fiche uuid, p_annee uuid)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
    'absences_non_justifiees',
      (select count(*) from public.presences
       where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee
         and statut = 'absent' and not justifie and deleted_at is null),
    'absences_justifiees',
      (select count(*) from public.presences
       where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee
         and statut = 'absent' and justifie and deleted_at is null),
    'retards_non_justifies',
      (select count(*) from public.retards
       where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee
         and not justifie and deleted_at is null),
    'retards_justifies',
      (select count(*) from public.retards
       where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee
         and justifie and deleted_at is null),
    'retard_moyen_minutes',
      (select round(coalesce(avg(minutes_retard), 0), 1) from public.retards
       where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee and deleted_at is null),
    'sanctions_actives',
      (select count(*) from public.sanctions
       where fiche_eleve_id = p_fiche and statut in ('notifiee', 'executee') and deleted_at is null)
  );
$$;

-- Prédictive : score de décrochage 0-1 (absences 50 %, retards 20 %, notes 30 %).
create or replace function public.calculer_score_decrochage(p_fiche uuid, p_annee uuid)
returns numeric
language plpgsql stable security definer set search_path = public
as $$
declare
  v_taux_abs numeric := 0;
  v_retards numeric := 0;
  v_moyenne numeric;
  v_score numeric;
begin
  select count(*) filter (where statut = 'absent' and not justifie)::numeric
       / nullif(count(*), 0)
    into v_taux_abs
  from public.presences
  where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee and deleted_at is null;

  select count(*) into v_retards
  from public.retards
  where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee
    and not justifie and deleted_at is null;

  select public.calculer_moyenne_eleve(p_fiche, null, null) into v_moyenne;

  v_score := 0.5 * coalesce(v_taux_abs, 0)
           + 0.2 * least(coalesce(v_retards, 0) / 10.0, 1)
           + case
               when v_moyenne is null then 0.15
               else 0.3 * greatest(1 - v_moyenne / 20.0, 0)
             end;

  return round(greatest(least(v_score, 1), 0), 4);
end;
$$;

-- Prescriptive : recommandation éducative non punitive, à valider par un humain.
create or replace function public.recommander_sanction_educative(p_fiche uuid, p_annee uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_abs int;
  v_ret int;
  v_moyenne numeric;
begin
  select count(*) into v_abs from public.presences
  where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee
    and statut = 'absent' and not justifie and deleted_at is null;

  select count(*) into v_ret from public.retards
  where fiche_eleve_id = p_fiche and annee_scolaire_id = p_annee
    and not justifie and deleted_at is null;

  select public.calculer_moyenne_eleve(p_fiche, null, null) into v_moyenne;

  return jsonb_build_object(
    'type_recommande', case
      when v_abs >= 5 then 'entretien_famille_et_tutorat'
      when v_ret >= 8 then 'suivi_ponctualite'
      when v_moyenne is not null and v_moyenne < 8 then 'soutien_scolaire'
      else 'aucune'
    end,
    'niveau_priorite', case when v_abs >= 5 then 'eleve' when v_ret >= 8 then 'moyen' else 'faible' end,
    'motif', jsonb_build_object('absences_non_justifiees', v_abs, 'retards_non_justifies', v_ret, 'moyenne', v_moyenne),
    'non_punitif', true,
    'a_valider_par', 'direction_ou_conseil_classe'
  );
end;
$$;

-- Génération des alertes décrochage (service_role / Edge Function uniquement).
create or replace function public.generer_alertes_decrochage(
  p_etab uuid,
  p_annee uuid,
  p_seuil numeric default 0.6
)
returns setof uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_fiche uuid;
  v_score numeric;
  v_id uuid;
begin
  for v_fiche in
    select distinct i.fiche_eleve_id
    from public.inscriptions i
    where i.annee_scolaire_id = p_annee and i.deleted_at is null
      and exists (
        select 1 from public.fiches_eleves f
        where f.id = i.fiche_eleve_id and f.etablissement_id = p_etab and f.deleted_at is null
      )
  loop
    v_score := public.calculer_score_decrochage(v_fiche, p_annee);

    continue when v_score < p_seuil;

    insert into public.alertes_decrochage
      (etablissement_id, fiche_eleve_id, annee_scolaire_id, score, seuil,
       facteurs, statut)
    select p_etab, v_fiche, p_annee, v_score, p_seuil,
           public.analyse_comportement(v_fiche, p_annee), 'ouverte'
    where not exists (
      select 1 from public.alertes_decrochage a
      where a.fiche_eleve_id = v_fiche
        and a.annee_scolaire_id = p_annee
        and a.statut in ('ouverte', 'transmise')
    )
    returning id into v_id;

    if v_id is not null then
      return next v_id;
    end if;
  end loop;

  return;
end;
$$;

-- Prédictive : taux de présence attendu (historique récent ajusté des événements).
create or replace function public.predire_presence(p_etab uuid, p_date date)
returns numeric
language sql stable security definer set search_path = public
as $$
  select greatest(least(
    coalesce((
      select avg(case when statut = 'present' then 1.0 else 0.0 end)
      from public.presences
      where etablissement_id = p_etab and deleted_at is null
    ), 0.9)
    - coalesce((
      select sum(impact_presence) from public.evenements_scolaires
      where etablissement_id = p_etab
        and p_date between date_debut and date_fin
        and deleted_at is null
    ), 0),
  1), 0);
$$;

grant execute on function public.analyse_comportement(uuid, uuid) to authenticated;
grant execute on function public.calculer_score_decrochage(uuid, uuid) to authenticated;
grant execute on function public.recommander_sanction_educative(uuid, uuid) to authenticated;
grant execute on function public.predire_presence(uuid, date) to authenticated;

-- La génération d'alertes est réservée au serveur (Edge Function / cron).
revoke execute on function public.generer_alertes_decrochage(uuid, uuid, numeric) from public, anon, authenticated;
grant execute on function public.generer_alertes_decrochage(uuid, uuid, numeric) to service_role;

-- ---------------------------------------------------------------------------
-- 9. Row Level Security
-- ---------------------------------------------------------------------------
alter table public.presences enable row level security;
alter table public.retards enable row level security;
alter table public.sanctions enable row level security;
alter table public.alertes_decrochage enable row level security;
alter table public.evenements_scolaires enable row level security;

-- Présences : lecture par visibilité ; écriture par qui peut pointer la classe.
drop policy if exists "presences_select_visible" on public.presences;
create policy "presences_select_visible" on public.presences
  for select using (public.presence_visible(id));

drop policy if exists "presences_insert_pointage" on public.presences;
create policy "presences_insert_pointage" on public.presences
  for insert to authenticated
  with check (public.peut_pointer(classe_id));

drop policy if exists "presences_update_pointage" on public.presences;
create policy "presences_update_pointage" on public.presences
  for update using (public.peut_pointer(classe_id))
  with check (public.peut_pointer(classe_id));

drop policy if exists "presences_delete_pointage" on public.presences;
create policy "presences_delete_pointage" on public.presences
  for delete using (public.peut_pointer(classe_id));

-- Retards : lecture par visibilité ; écriture par le personnel.
drop policy if exists "retards_select_visible" on public.retards;
create policy "retards_select_visible" on public.retards
  for select using (public.retard_visible(id));

drop policy if exists "retards_ecriture_personnel" on public.retards;
create policy "retards_ecriture_personnel" on public.retards
  for all
  using (
    public.a_permission(etablissement_id, 'scolarite.presence.gerer')
    or (saisi_par = auth.uid() and public.est_personnel(etablissement_id))
  )
  with check (
    public.a_permission(etablissement_id, 'scolarite.presence.gerer')
    or (saisi_par = auth.uid() and public.est_personnel(etablissement_id))
  );

-- Sanctions : lecture par visibilité ; écriture par la scolarité.
drop policy if exists "sanctions_select_visible" on public.sanctions;
create policy "sanctions_select_visible" on public.sanctions
  for select using (public.sanction_visible(id));

drop policy if exists "sanctions_ecriture_scolarite" on public.sanctions;
create policy "sanctions_ecriture_scolarite" on public.sanctions
  for all
  using (public.a_permission(etablissement_id, 'scolarite.sanction.gerer'))
  with check (public.a_permission(etablissement_id, 'scolarite.sanction.gerer'));

-- Alertes : lecture par visibilité ; aucune écriture client (calcul serveur).
drop policy if exists "alertes_select_visible" on public.alertes_decrochage;
create policy "alertes_select_visible" on public.alertes_decrochage
  for select using (public.alerte_visible(id));

-- Événements : lecture par toute personne concernée ; écriture par la scolarité.
drop policy if exists "evenements_select_concernes" on public.evenements_scolaires;
create policy "evenements_select_concernes" on public.evenements_scolaires
  for select using (public.concerne_etablissement(etablissement_id));

drop policy if exists "evenements_ecriture_scolarite" on public.evenements_scolaires;
create policy "evenements_ecriture_scolarite" on public.evenements_scolaires
  for all
  using (public.a_permission(etablissement_id, 'scolarite.evenement.gerer'))
  with check (public.a_permission(etablissement_id, 'scolarite.evenement.gerer'));

-- ---------------------------------------------------------------------------
-- 10. Index
-- ---------------------------------------------------------------------------
create index if not exists idx_presences_fiche on public.presences (fiche_eleve_id);
create index if not exists idx_presences_classe_date on public.presences (classe_id, date_presence);
create index if not exists idx_retards_fiche on public.retards (fiche_eleve_id);
create index if not exists idx_retards_etablissement on public.retards (etablissement_id, date_retard);
create index if not exists idx_sanctions_fiche on public.sanctions (fiche_eleve_id);
create index if not exists idx_alertes_fiche on public.alertes_decrochage (fiche_eleve_id, annee_scolaire_id);
create index if not exists idx_alertes_etablissement on public.alertes_decrochage (etablissement_id, statut);
create index if not exists idx_evenements_etablissement on public.evenements_scolaires (etablissement_id, date_debut);

-- ---------------------------------------------------------------------------
-- 11. Permissions introduites par M7
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domaine, libelle, description) values
  ('scolarite.presence.gerer',  'scolarite', 'Gérer les présences',  'Pointer les présences/absences et enregistrer les retards.'),
  ('scolarite.sanction.gerer',  'scolarite', 'Gérer les sanctions',  'Décider, notifier et valider les sanctions éducatives.'),
  ('scolarite.evenement.gerer', 'scolarite', 'Gérer les événements', 'Maintenir le calendrier et les événements affectant la présence.')
on conflict (code) do nothing;

-- ============================================================================
-- Fin M7.
-- ============================================================================
