-- ============================================================================
-- EcoShop — M0 — Schéma cœur : identité, rôles, multi-tenant, RLS, hook GSG ID
-- Migration idempotente. Ne pas modifier après application : ajouter une
-- nouvelle migration pour tout changement.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------------------------
-- Types énumérés
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.role_racine as enum (
    'eleve',             -- rôle racine (auto-inscriptible)
    'parent',            -- rôle racine (auto-inscriptible)
    'enseignant',        -- rôle racine (invitation)
    'direction',         -- rôle racine (invitation / demande)
    'vendeur',           -- rôle racine (demande validée)
    'fondateur_reseau',  -- rôle racine (demande validée)
    'admin_gsg',         -- rôle plateforme (supra-établissement)
    'admin_contenu'      -- rôle plateforme (CMS pédagogique)
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.statut_compte as enum ('actif', 'suspendu', 'supprime');
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- Table profiles — source de vérité des attributs métier (ch. 4 & 5)
-- Le jeton JWT ne fait foi qu'en copie ; cette table fait foi à chaque
-- vérification serveur.
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  gsg_id uuid,                            -- identité fédérée GSG ID (additif, nullable)
  identifiant_canonique text not null,    -- E.164 (téléphone) ou e-mail normalisé
  role_racine public.role_racine,         -- null tant que le rôle n'est pas choisi (anti-élévation)
  statut_compte public.statut_compte not null default 'actif',
  prenom text,
  nom text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,                 -- soft-delete
  constraint profiles_identifiant_unique unique (identifiant_canonique)
);

-- ---------------------------------------------------------------------------
-- Table etablissements — racine multi-tenant (établissement = point de
-- livraison et de facturation, ch. 27)
-- ---------------------------------------------------------------------------
create table if not exists public.etablissements (
  id uuid primary key default uuid_generate_v4(),
  nom text not null,
  slug text unique not null,
  pays_code text,                 -- code ISO 3166-1 alpha-2 (référentiel pédagogique)
  ville text,
  devise_code text not null default 'GNF',
  langue_code text not null default 'fr',
  fuseau_horaire text not null default 'Africa/Conakry',
  statut text not null default 'actif',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ---------------------------------------------------------------------------
-- Table postes — postes déclarés (modèle de rôles à deux niveaux, ch. 4)
-- ---------------------------------------------------------------------------
create table if not exists public.postes (
  id uuid primary key default uuid_generate_v4(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  nom text not null,
  permissions jsonb not null default '[]'::jsonb,
  actif boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Table etablissements_membres — rattachement d'un profil à un établissement
-- avec rôle dans l'établissement et poste déclaré.
-- ---------------------------------------------------------------------------
create table if not exists public.etablissements_membres (
  id uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  role_dans_etablissement text not null,  -- ex. 'direction', 'enseignant', 'eleve', 'parent'
  poste_id uuid references public.postes (id) on delete set null,
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  constraint membres_profile_etablissement_unique unique (profile_id, etablissement_id)
);

-- ---------------------------------------------------------------------------
-- Table parametres_globaux — aucune configuration codée en dur (règle v2.0)
-- ---------------------------------------------------------------------------
create table if not exists public.parametres_globaux (
  cle text primary key,
  valeur jsonb not null,
  description text,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Fonction utilitaire : mise à jour de updated_at
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute procedure public.set_updated_at();

drop trigger if exists etablissements_set_updated_at on public.etablissements;
create trigger etablissements_set_updated_at
  before update on public.etablissements
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Trigger : création automatique du profil à l'insertion dans auth.users
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, identifiant_canonique)
  values (new.id, coalesce(new.phone, new.email))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Custom Access Token Hook (fédération GSG ID, ch. 5.6)
-- Recopie role_racine et gsg_id dans le JWT à l'émission/rafraîchissement.
-- Source de vérité = table profiles, jamais le contenu du jeton.
-- À activer dans le dashboard : Authentication > Hooks > Custom Access Token.
-- ---------------------------------------------------------------------------
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
as $$
declare
  claims jsonb;
  prof record;
begin
  claims := coalesce(event->'claims', '{}'::jsonb);

  select role_racine, gsg_id into prof
  from public.profiles
  where id = (event->>'user_id')::uuid;

  if found then
    if prof.role_racine is not null then
      claims := jsonb_set(claims, '{app_metadata,role_racine}', to_jsonb(prof.role_racine::text));
    end if;
    if prof.gsg_id is not null then
      claims := jsonb_set(claims, '{app_metadata,gsg_id}', to_jsonb(prof.gsg_id::text));
    end if;
  end if;

  return jsonb_build_object('claims', claims);
end;
$$;

grant execute on function public.custom_access_token_hook(event jsonb) to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook(event jsonb) from authenticated, anon, public;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.etablissements enable row level security;
alter table public.etablissements_membres enable row level security;
alter table public.postes enable row level security;
alter table public.parametres_globaux enable row level security;

-- profiles : lecture et mise à jour de SON propre profil
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- etablissements : lecture des établissements dont on est membre actif
drop policy if exists "etablissements_select_member" on public.etablissements;
create policy "etablissements_select_member" on public.etablissements
  for select using (
    exists (
      select 1 from public.etablissements_membres m
      where m.etablissement_id = etablissements.id
        and m.profile_id = auth.uid()
        and m.actif
    )
  );

-- etablissements_membres : lecture de ses propres rattachements et de ceux
-- de son établissement (liste des membres — affinage par rôle en M1/M2)
drop policy if exists "membres_select_propres" on public.etablissements_membres;
create policy "membres_select_propres" on public.etablissements_membres
  for select using (profile_id = auth.uid());

drop policy if exists "membres_select_etablissement" on public.etablissements_membres;
create policy "membres_select_etablissement" on public.etablissements_membres
  for select using (
    exists (
      select 1 from public.etablissements_membres me
      where me.etablissement_id = etablissements_membres.etablissement_id
        and me.profile_id = auth.uid()
        and me.actif
    )
  );

-- postes : lecture par les membres de l'établissement
drop policy if exists "postes_select_etablissement" on public.postes;
create policy "postes_select_etablissement" on public.postes
  for select using (
    exists (
      select 1 from public.etablissements_membres me
      where me.etablissement_id = postes.etablissement_id
        and me.profile_id = auth.uid()
        and me.actif
    )
  );

-- parametres_globaux : lecture publique (valeurs non sensibles), écriture
-- réservée au back-office via service_role (aucune policy d'écriture RLS)
drop policy if exists "parametres_select" on public.parametres_globaux;
create policy "parametres_select" on public.parametres_globaux
  for select using (true);

-- ---------------------------------------------------------------------------
-- Index
-- ---------------------------------------------------------------------------
create index if not exists idx_membres_profile on public.etablissements_membres (profile_id);
create index if not exists idx_membres_etablissement on public.etablissements_membres (etablissement_id);
create index if not exists idx_postes_etablissement on public.postes (etablissement_id);

-- ============================================================================
-- NB : l'écriture (insert/update) sur etablissements, postes et membres est
-- déléguée aux parcours d'onboarding/validation (M1/M2) via Edge Functions et
-- service_role, conformément à la règle « le serveur fait foi ».
-- ============================================================================
