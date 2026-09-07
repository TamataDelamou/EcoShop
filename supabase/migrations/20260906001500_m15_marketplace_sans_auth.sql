-- ============================================================================
-- EcoShop — M15 — Marketplace sans authentification
--
-- Périmètre (docs/RECHERCHE_COMPARATIVE.md §17, docs/MARKETPLACE.md) :
--   • Parcours invité : consultation + achat sans mot de passe.
--   • Profil public : identité minimale persistée (nom, email, téléphone,
--     rôle voulu, établissement si connu), UUID + jeton opaque `token_acces`.
--   • Aucune élévation de privilège : le jeton ne donne accès qu'au parcours
--     invité (catalogue public) ; les espaces protégés restent sur Auth native.
--   • Hors-ligne : panier invité porté par `paniers.visiteur_id` + cache local.
--
-- Principes : soft-delete, RLS par défaut fermée, écritures invitées via
-- Edge Function (service role) — jamais de RLS anon en écriture.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Profils publics (invités marketplace, sans mot de passe)
-- ---------------------------------------------------------------------------
create table if not exists public.profils_publics (
  id uuid primary key default gen_random_uuid(),
  token_acces uuid not null default gen_random_uuid(),
  nom text,
  email text,
  telephone text,
  role_voulu text not null default 'visiteur_marketplace',
  etablissement_id uuid references public.etablissements (id) on delete set null,
  complet boolean not null default false,
  profile_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profils_publics_token_unique unique (token_acces)
);

create unique index if not exists idx_profils_publics_email on public.profils_publics (email)
  where email is not null;
create index if not exists idx_profils_publics_etab on public.profils_publics (etablissement_id);

-- Complétion déduite : le profil est « complet » dès qu'il porte un nom et un
-- canal de contact (email ou téléphone). Le rôle voulu a une valeur par défaut.
create or replace function public.profils_publics_calcule_complet()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.complet := (new.nom is not null and (new.email is not null or new.telephone is not null));
  return new;
end;
$$;

drop trigger if exists profils_publics_calcule_complet on public.profils_publics;
create trigger profils_publics_calcule_complet
  before insert or update on public.profils_publics
  for each row execute procedure public.profils_publics_calcule_complet();

-- ---------------------------------------------------------------------------
-- 2. Extension des paniers et commandes pour le parcours invité
-- ---------------------------------------------------------------------------

-- 2.1 Paniers : propriétaire = profil authentifié OU profil public (invité).
alter table public.paniers alter column profile_id drop not null;
alter table public.paniers add column if not exists visiteur_id uuid
  references public.profils_publics (id) on delete cascade;
alter table public.paniers add column if not exists saisi_hors_ligne boolean not null default false;
alter table public.paniers add column if not exists device_id text;
alter table public.paniers add column if not exists client_ts timestamptz;
alter table public.paniers drop constraint if exists paniers_proprietaire_requis;
alter table public.paniers add constraint paniers_proprietaire_requis
  check (profile_id is not null or visiteur_id is not null);

-- 2.2 Commandes : idem (un seul des deux propriétaires requis).
alter table public.commandes alter column profile_id drop not null;
alter table public.commandes add column if not exists visiteur_id uuid
  references public.profils_publics (id) on delete set null;
alter table public.commandes drop constraint if exists commandes_proprietaire_requis;
alter table public.commandes add constraint commandes_proprietaire_requis
  check (profile_id is not null or visiteur_id is not null);

-- ---------------------------------------------------------------------------
-- 3. RLS
-- ---------------------------------------------------------------------------
alter table public.profils_publics enable row level security;

-- Par défaut : aucune lecture anon/authentifié (données personnelles).
-- Seuls l'admin GSG et le propriétaire lié peuvent relire leur profil public.
create policy profils_publics_select_admin on public.profils_publics
  for select using (public.est_admin_gsg());
create policy profils_publics_select_owner on public.profils_publics
  for select using (profile_id = auth.uid());

-- Catalogue marketplace : déjà public depuis M13 (`for select using (true)`).
-- Aucune écriture anon n'est ajoutée : les écritures invitées transitent par
-- l'Edge Function `creer_profil_marketplace` (service role, RLS contournée).

-- ---------------------------------------------------------------------------
-- 4. Permissions
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domaine, libelle, description) values
  ('marketplace.profil_public.lire', 'marketplace', 'Consulter les profils publics', 'Lecture des profils invités marketplace'),
  ('marketplace.profil_public.lier', 'marketplace', 'Lier un profil public',     'Liaison profil invité ↔ compte authentifié')
on conflict (code) do nothing;
