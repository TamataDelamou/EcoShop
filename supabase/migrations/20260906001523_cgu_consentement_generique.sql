-- ============================================================================
-- EcoShop — Chantier "bloquant lancement" item 1/4 : CGU / consentement
-- générique (cahier §34.10).
--
-- Deux parcours (cahier) : "simplifie" (Élève) et "complet" (Parent,
-- Enseignant, Direction, Vendeur, Fondateur de réseau — Enseignant ajouté par
-- décision du porteur de projet, absent du texte cahier §34.10 lui-même).
-- admin_gsg et admin_contenu (rôles plateforme, pas cités au §34.10) sont
-- hors périmètre du blocage.
--
-- Texte CGU en PLACEHOLDER structurel explicite, comme le barème de l'étape
-- (a) du chantier Facturation : à remplacer par le porteur de projet avant
-- tout lancement réel.
-- ============================================================================

do $$ begin
  create type public.parcours_cgu as enum ('simplifie', 'complet');
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Versions de CGU — historique horodaté, une seule version courante par
--    parcours à la fois.
-- ---------------------------------------------------------------------------
create table if not exists public.cgu_versions (
  id uuid primary key default gen_random_uuid(),
  parcours public.parcours_cgu not null,
  numero_version text not null,
  contenu text not null,
  est_courante boolean not null default false,
  publiee_le timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint cgu_versions_parcours_numero_unique unique (parcours, numero_version)
);

create unique index if not exists idx_cgu_versions_courante_unique
  on public.cgu_versions (parcours) where est_courante;

comment on table public.cgu_versions is
  'Cahier §34.10 — historique horodaté des CGU par parcours (simplifie=Élève, complet=autres rôles). Écriture réservée à publier_version_cgu() (admin_gsg).';

alter table public.cgu_versions enable row level security;

-- Lecture publique (un compte doit pouvoir lire les CGU avant de les
-- accepter) ; aucune policy d'écriture — deny-by-default, seule la RPC
-- publier_version_cgu() (SECURITY DEFINER, réservée admin_gsg) peut écrire.
drop policy if exists "cgu_versions_select" on public.cgu_versions;
create policy "cgu_versions_select" on public.cgu_versions
  for select using (true);

-- ---------------------------------------------------------------------------
-- 2. Acceptations — registre immuable par profil. Aucune policy
--    update/delete : un consentement, une fois enregistré, ne se modifie ni
--    ne se supprime (valeur probante).
-- ---------------------------------------------------------------------------
create table if not exists public.cgu_acceptations (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  cgu_version_id uuid not null references public.cgu_versions (id) on delete restrict,
  accepte_le timestamptz not null default now(),
  constraint cgu_acceptations_profile_version_unique unique (profile_id, cgu_version_id)
);

comment on table public.cgu_acceptations is
  'Cahier §34.10 — registre immuable des acceptations de CGU par profil. Pas de policy update/delete : consentement non modifiable a posteriori.';

alter table public.cgu_acceptations enable row level security;

drop policy if exists "cgu_acceptations_select" on public.cgu_acceptations;
create policy "cgu_acceptations_select" on public.cgu_acceptations
  for select using (profile_id = auth.uid() or public.est_admin_gsg());

drop policy if exists "cgu_acceptations_insert" on public.cgu_acceptations;
create policy "cgu_acceptations_insert" on public.cgu_acceptations
  for insert to authenticated
  with check (profile_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3. Publication d'une nouvelle version — réservée admin_gsg.
-- ---------------------------------------------------------------------------
create or replace function public.publier_version_cgu(
  p_parcours public.parcours_cgu,
  p_numero_version text,
  p_contenu text
)
returns public.cgu_versions
language plpgsql security definer set search_path = public
as $$
declare
  v_row public.cgu_versions;
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  update public.cgu_versions set est_courante = false
  where parcours = p_parcours and est_courante;

  insert into public.cgu_versions (parcours, numero_version, contenu, est_courante)
  values (p_parcours, p_numero_version, p_contenu, true)
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.publier_version_cgu(public.parcours_cgu, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Statut CGU de l'appelant — version courante de son parcours + a-t-il
--    déjà accepté. Ne renvoie aucune ligne pour un profil sans role_racine
--    choisi ou de rôle plateforme (admin_gsg/admin_contenu), hors périmètre.
-- ---------------------------------------------------------------------------
create or replace function public.cgu_statut()
returns table(
  cgu_version_id uuid,
  parcours public.parcours_cgu,
  numero_version text,
  contenu text,
  publiee_le timestamptz,
  acceptee boolean
)
language sql stable security definer set search_path = public
as $$
  with mon_parcours as (
    select case when p.role_racine = 'eleve' then 'simplifie'::public.parcours_cgu
                else 'complet'::public.parcours_cgu end as parcours
    from public.profiles p
    where p.id = auth.uid()
      and p.role_racine is not null
      and p.role_racine not in ('admin_gsg', 'admin_contenu')
      and p.deleted_at is null
  )
  select v.id, v.parcours, v.numero_version, v.contenu, v.publiee_le,
         exists(
           select 1 from public.cgu_acceptations a
           where a.profile_id = auth.uid() and a.cgu_version_id = v.id
         )
  from public.cgu_versions v
  join mon_parcours m on m.parcours = v.parcours
  where v.est_courante;
$$;

comment on function public.cgu_statut() is
  'Cahier §34.10 — version CGU courante du parcours de l''appelant + statut d''acceptation. Sans ligne : rôle non choisi ou rôle plateforme (hors périmètre CGU).';

grant execute on function public.cgu_statut() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Amorçage — une version placeholder par parcours, pour que cgu_statut()
--    renvoie toujours quelque chose dès l'ouverture du chantier.
-- ---------------------------------------------------------------------------
insert into public.cgu_versions (parcours, numero_version, contenu, est_courante, publiee_le)
values
  (
    'simplifie',
    '2026-09-15-v1',
    '[PLACEHOLDER — texte à remplacer par le porteur de projet avant lancement] '
    || 'En utilisant EcoShop, j''accepte que mes notes, mes présences et mes échanges '
    || 'avec mes enseignants soient enregistrés sur la plateforme pour m''aider à suivre '
    || 'ma scolarité. Mes parents peuvent voir certaines de ces informations. Je peux '
    || 'relire ce texte à tout moment depuis mon profil.',
    true,
    now()
  ),
  (
    'complet',
    '2026-09-15-v1',
    '[PLACEHOLDER — texte à remplacer par le porteur de projet avant lancement] '
    || 'Conditions générales d''utilisation d''EcoShop. En créant un compte, vous '
    || 'acceptez le traitement de vos données personnelles et, le cas échéant, de '
    || 'celles des utilisateurs que vous représentez, l''usage de la plateforme pour '
    || 'les fonctionnalités liées à votre rôle, ainsi que les responsabilités associées '
    || 'à votre statut (scolarité, paiement, marketplace selon le cas). Ce texte est un '
    || 'placeholder structurel : le contenu juridique définitif sera fourni par Global '
    || 'Service Groupe avant le lancement réel.',
    true,
    now()
  )
on conflict (parcours, numero_version) do nothing;

-- ============================================================================
-- Fin — CGU / consentement générique.
-- ============================================================================
