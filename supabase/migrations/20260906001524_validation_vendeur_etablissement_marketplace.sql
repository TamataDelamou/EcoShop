-- ============================================================================
-- EcoShop — Chantier "bloquant lancement" item 3/4 : validation vendeur (GSG)
-- + agrément établissement <-> vendeur (Direction) avant activation
-- marketplace (cahier §27.1-27.2, §30.1-30.2).
--
-- Deux paliers distincts, conformes au cahier (cadrage explicite du porteur
-- de projet, pas une interprétation libre) :
--   1. Validation GSG du compte Vendeur (commercants) — globale, indépendante
--      de tout établissement (§27.2, §30.2).
--   2. Agrément établissement <-> vendeur — CHAQUE établissement instruit et
--      valide/refuse individuellement l'affiliation d'un vendeur DÉJÀ validé
--      par GSG (§27.2, "chaîne d'agrément multi-établissements"). Décision de
--      la Direction de l'établissement concerné, jamais de GSG.
--
-- Hors périmètre (cadrage explicite) : pas de flag marketplace générique par
-- établissement validé par GSG — l'établissement est déjà validé à sa
-- création (§5.3, mécanisme existant). Pas de mécanisme de suspension SLA
-- automatique (§27.2) — seul l'état en_attente/valide/refuse est construit
-- ici, re-décidable dans les deux sens (pas d'irréversibilité comme la
-- proclamation de l'item 2).
--
-- Écart de schéma constaté, PAS corrigé ici (hors périmètre de cette porte
-- RLS) : la table commercants n'a AUCUN lien vers profiles/auth.users — un
-- compte role_racine='vendeur' ne peut aujourd'hui se rattacher à aucune
-- fiche commerçant, donc pas encore consulter le statut de sa propre
-- validation depuis l'application. Géré ici uniquement côté GSG/direction ;
-- signalé pour un futur chantier "portail vendeur".
--
-- Porte RLS : uniquement les NOUVELLES commandes (commandes_insert).
-- est_appel_service() (edge functions, parcours invité M15) reste inchangé,
-- comme partout ailleurs dans ce schéma. La navigation du catalogue public
-- (commercants_select/catalogues_select, déjà "using (true)") N'EST PAS
-- restreinte par ce chantier — seul le passage effectif à la commande est
-- bloqué, pas la simple consultation du catalogue.
-- ============================================================================

do $$ begin
  create type public.statut_validation_vendeur as enum ('en_attente', 'valide', 'refuse');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.statut_agrement_etablissement as enum ('en_attente', 'valide', 'refuse');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 1. Validation GSG du compte Vendeur — palier 1.
-- ---------------------------------------------------------------------------
alter table public.commercants
  add column if not exists statut_validation public.statut_validation_vendeur not null default 'en_attente',
  add column if not exists valide_par uuid references public.profiles (id) on delete set null,
  add column if not exists valide_le timestamptz,
  add column if not exists motif_refus text;

comment on column public.commercants.statut_validation is
  'Cahier §27.2/§30.2 — validation GSG du compte Vendeur, palier 1. Écrite par valider_vendeur() (réservée admin_gsg) ; la policy commercants_update existante permet aussi une écriture directe par admin_gsg/service, inchangée par ce chantier.';

create or replace function public.valider_vendeur(
  p_commercant uuid,
  p_decision public.statut_validation_vendeur,
  p_motif text default null
)
returns public.commercants
language plpgsql security definer set search_path = public
as $$
declare
  v_row public.commercants;
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  if p_decision = 'en_attente' then
    raise exception 'DECISION_INVALIDE' using errcode = '22023';
  end if;

  update public.commercants
    set statut_validation = p_decision,
        valide_par = auth.uid(),
        valide_le = now(),
        motif_refus = case when p_decision = 'refuse' then p_motif else null end
  where id = p_commercant and deleted_at is null
  returning * into v_row;

  if v_row.id is null then
    raise exception 'COMMERCANT_INTROUVABLE' using errcode = '23514';
  end if;

  return v_row;
end;
$$;

grant execute on function public.valider_vendeur(uuid, public.statut_validation_vendeur, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Agrément établissement <-> vendeur — palier 2 (§27.2, "chaîne
--    d'agrément multi-établissements"), décidé par la Direction de
--    l'établissement concerné, jamais par GSG.
-- ---------------------------------------------------------------------------
create table if not exists public.agrements_vendeurs_etablissements (
  id uuid primary key default gen_random_uuid(),
  commercant_id uuid not null references public.commercants (id) on delete cascade,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  statut public.statut_agrement_etablissement not null default 'en_attente',
  decide_par uuid references public.profiles (id) on delete set null,
  decide_le timestamptz,
  motif_refus text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint agrements_vendeur_etablissement_unique unique (commercant_id, etablissement_id)
);

comment on table public.agrements_vendeurs_etablissements is
  'Cahier §27.2 — chaîne d''agrément multi-établissements, palier 2. Une ligne = un établissement s''est prononcé sur un vendeur DÉJÀ validé par GSG. Écriture réservée à decider_agrement_vendeur_etablissement() (Direction de l''établissement concerné, jamais GSG).';

alter table public.agrements_vendeurs_etablissements enable row level security;

drop policy if exists "agrements_select" on public.agrements_vendeurs_etablissements;
create policy "agrements_select" on public.agrements_vendeurs_etablissements
  for select using (
    coalesce(public.est_personnel(etablissement_id), false)
    or coalesce(public.est_admin_gsg(), false)
    or public.est_appel_service()
  );

-- Aucune policy d'écriture : toute création/modification passe par la RPC
-- ci-dessous (garantit l'ordre GSG -> établissement, jamais un INSERT direct
-- qui contournerait la vérification "vendeur déjà validé GSG").
create or replace function public.decider_agrement_vendeur_etablissement(
  p_commercant uuid,
  p_etablissement uuid,
  p_decision public.statut_agrement_etablissement,
  p_motif text default null
)
returns public.agrements_vendeurs_etablissements
language plpgsql security definer set search_path = public
as $$
declare
  v_statut_vendeur public.statut_validation_vendeur;
  v_row public.agrements_vendeurs_etablissements;
begin
  if not coalesce(public.est_direction(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  if p_decision = 'en_attente' then
    raise exception 'DECISION_INVALIDE' using errcode = '22023';
  end if;

  select statut_validation into v_statut_vendeur
  from public.commercants where id = p_commercant and deleted_at is null;

  if v_statut_vendeur is null then
    raise exception 'COMMERCANT_INTROUVABLE' using errcode = '23514';
  end if;

  if v_statut_vendeur <> 'valide' then
    raise exception 'VENDEUR_NON_VALIDE_GSG' using errcode = '23514';
  end if;

  insert into public.agrements_vendeurs_etablissements
    (commercant_id, etablissement_id, statut, decide_par, decide_le, motif_refus)
  values (p_commercant, p_etablissement, p_decision, auth.uid(), now(), case when p_decision = 'refuse' then p_motif else null end)
  on conflict (commercant_id, etablissement_id) do update
    set statut = excluded.statut,
        decide_par = excluded.decide_par,
        decide_le = excluded.decide_le,
        motif_refus = excluded.motif_refus,
        updated_at = now()
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.decider_agrement_vendeur_etablissement(uuid, uuid, public.statut_agrement_etablissement, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Porte RLS — bloque toute NOUVELLE commande tant que les deux paliers ne
--    sont pas "valide". est_appel_service() (edge functions, M15 invité)
--    reste inchangé, comme partout ailleurs dans ce schéma.
-- ---------------------------------------------------------------------------
create or replace function public.vendeur_actif_pour_etablissement(p_commercant uuid, p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((select statut_validation = 'valide' from public.commercants where id = p_commercant and deleted_at is null), false)
     and coalesce((select statut = 'valide' from public.agrements_vendeurs_etablissements where commercant_id = p_commercant and etablissement_id = p_etablissement), false);
$$;

comment on function public.vendeur_actif_pour_etablissement(uuid, uuid) is
  'Cahier §27.1-27.2 — vrai seulement si le vendeur est validé GSG (palier 1) ET agréé par CET établissement (palier 2).';

grant execute on function public.vendeur_actif_pour_etablissement(uuid, uuid) to authenticated;

drop policy if exists "commandes_insert" on public.commandes;
create policy "commandes_insert" on public.commandes
  for insert with check (
    (profile_id = auth.uid() and public.vendeur_actif_pour_etablissement(commercant_id, etablissement_id))
    or public.est_appel_service()
  );

-- ============================================================================
-- Fin — validation vendeur/établissement avant activation marketplace.
-- ============================================================================
