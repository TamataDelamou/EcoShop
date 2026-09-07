-- ============================================================================
-- EcoShop — M1 — Schéma Supabase avancé
--
-- Périmètre (ANALYSE_GLOBALE.md §4.3) : établissements, unités opérationnelles,
-- années scolaires, postes déclarés et permissions, membres, contraintes
-- multi-tenant, RLS fine.
--
-- Principe directeur : le modèle de rôles est à deux niveaux (ch. 4).
--   Niveau 1 — rôle racine, porté par public.profiles (identité du compte).
--   Niveau 2 — poste déclaré, porté par etablissements_membres, qui agrège des
--              permissions fines et n'a de sens que dans un établissement.
--
-- Aucune permission n'est codée en dur côté client : elles sont référencées
-- dans public.permissions et attribuées aux postes.
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Unités opérationnelles — subdivisions d'un établissement (campus,
--    annexes, sites). Hiérarchie facultative, un seul niveau de parenté suffit
--    aux besoins actuels mais l'auto-référence autorise l'arborescence.
-- ---------------------------------------------------------------------------
create table if not exists public.unites_operationnelles (
  id uuid primary key default uuid_generate_v4(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  parent_id uuid references public.unites_operationnelles (id) on delete restrict,
  code text not null,
  nom text not null,
  adresse text,
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint unites_code_unique_par_etablissement unique (etablissement_id, code),
  constraint unites_pas_son_propre_parent check (parent_id is null or parent_id <> id)
);

comment on table public.unites_operationnelles is
  'Subdivisions d''un établissement (campus, annexes). Toujours rattachées à un seul tenant.';

-- Une unité parente doit appartenir au même établissement que son enfant :
-- une contrainte de clé étrangère ne peut pas l'exprimer, un trigger le fait.
create or replace function public.unites_verifie_tenant()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_etab_parent uuid;
begin
  if new.parent_id is null then
    return new;
  end if;

  select etablissement_id into v_etab_parent
  from public.unites_operationnelles where id = new.parent_id;

  if v_etab_parent is distinct from new.etablissement_id then
    raise exception 'UNITE_PARENT_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists unites_verifie_tenant_trg on public.unites_operationnelles;
create trigger unites_verifie_tenant_trg
  before insert or update on public.unites_operationnelles
  for each row execute procedure public.unites_verifie_tenant();

drop trigger if exists unites_set_updated_at on public.unites_operationnelles;
create trigger unites_set_updated_at
  before update on public.unites_operationnelles
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 2. Années scolaires — le statut Pro, les inscriptions et les bulletins sont
--    cadrés par année scolaire (règle transversale héritée v2.0).
--    Au plus une année « courante » par établissement, garantie par un index
--    unique partiel plutôt que par du code applicatif.
-- ---------------------------------------------------------------------------
create table if not exists public.annees_scolaires (
  id uuid primary key default uuid_generate_v4(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  libelle text not null,                  -- ex. « 2026-2027 »
  date_debut date not null,
  date_fin date not null,
  courante boolean not null default false,
  cloturee boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint annees_libelle_unique unique (etablissement_id, libelle),
  constraint annees_dates_coherentes check (date_fin > date_debut)
);

create unique index if not exists idx_annee_courante_unique
  on public.annees_scolaires (etablissement_id)
  where courante;

drop trigger if exists annees_set_updated_at on public.annees_scolaires;
create trigger annees_set_updated_at
  before update on public.annees_scolaires
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3. Référentiel de permissions — jamais de liste codée en dur dans le client.
--    Le code suit la forme « domaine.action » ou « domaine.objet.action ».
-- ---------------------------------------------------------------------------
create table if not exists public.permissions (
  code text primary key,
  domaine text not null,
  libelle text not null,
  description text,
  created_at timestamptz not null default now(),
  constraint permissions_code_forme check (code ~ '^[a-z_]+(\.[a-z_]+){1,2}$')
);

comment on table public.permissions is
  'Catalogue des permissions fines attribuables à un poste déclaré (ch. 4).';

-- Table de jonction poste ↔ permission (remplace la colonne jsonb de M0, qui
-- ne permettait ni intégrité référentielle ni indexation).
create table if not exists public.poste_permissions (
  poste_id uuid not null references public.postes (id) on delete cascade,
  permission_code text not null references public.permissions (code) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (poste_id, permission_code)
);

-- Enrichissement de la table postes héritée de M0.
alter table public.postes add column if not exists code text;
alter table public.postes add column if not exists description text;
alter table public.postes add column if not exists updated_at timestamptz not null default now();
alter table public.postes add column if not exists deleted_at timestamptz;

-- Le code de poste est unique par établissement lorsqu'il est renseigné.
create unique index if not exists idx_postes_code_unique
  on public.postes (etablissement_id, code)
  where code is not null and deleted_at is null;

drop trigger if exists postes_set_updated_at on public.postes;
create trigger postes_set_updated_at
  before update on public.postes
  for each row execute procedure public.set_updated_at();

-- La colonne jsonb « permissions » de M0 devient un cache dénormalisé, non
-- source de vérité : on la conserve pour compatibilité mais la lecture
-- applicative passe par poste_permissions.
comment on column public.postes.permissions is
  'Obsolète depuis M1 — source de vérité : public.poste_permissions.';

-- ---------------------------------------------------------------------------
-- 4. Membres — rattachement enrichi (unité, période de validité, soft-delete)
-- ---------------------------------------------------------------------------
alter table public.etablissements_membres
  add column if not exists unite_id uuid references public.unites_operationnelles (id) on delete set null;
alter table public.etablissements_membres
  add column if not exists date_debut date not null default current_date;
alter table public.etablissements_membres
  add column if not exists date_fin date;
alter table public.etablissements_membres
  add column if not exists updated_at timestamptz not null default now();
alter table public.etablissements_membres
  add column if not exists deleted_at timestamptz;

do $$ begin
  alter table public.etablissements_membres
    add constraint membres_periode_coherente
    check (date_fin is null or date_fin >= date_debut);
exception when duplicate_object then null;
end $$;

drop trigger if exists membres_set_updated_at on public.etablissements_membres;
create trigger membres_set_updated_at
  before update on public.etablissements_membres
  for each row execute procedure public.set_updated_at();

-- Cohérence multi-tenant : le poste et l'unité d'un membre doivent appartenir
-- à l'établissement du rattachement. C'est le garde-fou central du modèle
-- multi-tenant : une fuite inter-établissement passerait sinon par un simple
-- identifiant deviné.
create or replace function public.membres_verifie_tenant()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_etab uuid;
begin
  if new.poste_id is not null then
    select etablissement_id into v_etab from public.postes where id = new.poste_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'POSTE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;

  if new.unite_id is not null then
    select etablissement_id into v_etab
    from public.unites_operationnelles where id = new.unite_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'UNITE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists membres_verifie_tenant_trg on public.etablissements_membres;
create trigger membres_verifie_tenant_trg
  before insert or update on public.etablissements_membres
  for each row execute procedure public.membres_verifie_tenant();

-- ---------------------------------------------------------------------------
-- 5. Établissement actif — un enseignant peut être rattaché à plusieurs
--    établissements (ch. 4) ; le client mémorise sa sélection côté serveur.
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists etablissement_actif_id uuid
  references public.etablissements (id) on delete set null;

-- Un compte ne peut activer qu'un établissement dont il est membre : le
-- trigger de protection des colonnes (M0-fix) laisse passer cette colonne,
-- c'est donc ici qu'on la valide.
create or replace function public.profiles_verifie_etablissement_actif()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.etablissement_actif_id is null
     or new.etablissement_actif_id is not distinct from old.etablissement_actif_id then
    return new;
  end if;

  if not exists (
    select 1 from public.etablissements_membres m
    where m.profile_id = new.id
      and m.etablissement_id = new.etablissement_actif_id
      and m.actif
      and m.deleted_at is null
  ) then
    raise exception 'ETABLISSEMENT_NON_MEMBRE' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_verifie_etablissement_actif_trg on public.profiles;
create trigger profiles_verifie_etablissement_actif_trg
  before update on public.profiles
  for each row execute procedure public.profiles_verifie_etablissement_actif();

-- ---------------------------------------------------------------------------
-- 6. Résolution des permissions — le serveur fait foi (ch. 34)
-- ---------------------------------------------------------------------------

-- Permissions effectives de l'appelant dans un établissement donné.
create or replace function public.mes_permissions(p_etablissement uuid)
returns setof text
language sql
stable
security definer
set search_path = public
as $$
  select pp.permission_code
  from public.etablissements_membres m
  join public.postes po on po.id = m.poste_id and po.actif and po.deleted_at is null
  join public.poste_permissions pp on pp.poste_id = po.id
  where m.profile_id = auth.uid()
    and m.etablissement_id = p_etablissement
    and m.actif
    and m.deleted_at is null
    and (m.date_fin is null or m.date_fin >= current_date);
$$;

comment on function public.mes_permissions(uuid) is
  'Permissions effectives de l''appelant dans un établissement, via son poste déclaré.';

-- Vrai si l'appelant détient la permission demandée dans l'établissement.
-- L'Administrateur GSG est supra-établissement et détient tout (ch. 4).
create or replace function public.a_permission(p_etablissement uuid, p_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.est_admin_gsg()
      or exists (
        select 1 from public.mes_permissions(p_etablissement) c where c = p_code
      );
$$;

-- Vrai si l'appelant dirige l'établissement (direction ou fondateur du réseau).
create or replace function public.est_direction(p_etablissement uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.etablissements_membres m
    where m.profile_id = auth.uid()
      and m.etablissement_id = p_etablissement
      and m.role_dans_etablissement in ('direction', 'fondateur_reseau')
      and m.actif
      and m.deleted_at is null
  );
$$;

grant execute on function public.mes_permissions(uuid) to authenticated;
grant execute on function public.a_permission(uuid, text) to authenticated;
grant execute on function public.est_direction(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. RLS
-- ---------------------------------------------------------------------------
alter table public.unites_operationnelles enable row level security;
alter table public.annees_scolaires enable row level security;
alter table public.permissions enable row level security;
alter table public.poste_permissions enable row level security;

-- Unités : lecture par les membres, écriture réservée à la direction.
drop policy if exists "unites_select_membre" on public.unites_operationnelles;
create policy "unites_select_membre" on public.unites_operationnelles
  for select using (
    deleted_at is null
    and etablissement_id in (select public.mes_etablissements())
  );

drop policy if exists "unites_ecriture_direction" on public.unites_operationnelles;
create policy "unites_ecriture_direction" on public.unites_operationnelles
  for all
  using (public.a_permission(etablissement_id, 'etablissement.unite.gerer'))
  with check (public.a_permission(etablissement_id, 'etablissement.unite.gerer'));

-- Années scolaires : lecture par les membres, écriture par la direction.
drop policy if exists "annees_select_membre" on public.annees_scolaires;
create policy "annees_select_membre" on public.annees_scolaires
  for select using (etablissement_id in (select public.mes_etablissements()));

drop policy if exists "annees_ecriture_direction" on public.annees_scolaires;
create policy "annees_ecriture_direction" on public.annees_scolaires
  for all
  using (public.a_permission(etablissement_id, 'etablissement.annee.gerer'))
  with check (public.a_permission(etablissement_id, 'etablissement.annee.gerer'));

-- Catalogue de permissions : lisible par tout compte authentifié (il alimente
-- les écrans d'administration des postes), écriture réservée au service_role.
drop policy if exists "permissions_select_authentifie" on public.permissions;
create policy "permissions_select_authentifie" on public.permissions
  for select to authenticated using (true);

-- Attributions poste ↔ permission : lecture par les membres de l'établissement
-- du poste, écriture par qui gère les postes.
drop policy if exists "poste_permissions_select" on public.poste_permissions;
create policy "poste_permissions_select" on public.poste_permissions
  for select using (
    exists (
      select 1 from public.postes po
      where po.id = poste_permissions.poste_id
        and po.etablissement_id in (select public.mes_etablissements())
    )
  );

drop policy if exists "poste_permissions_ecriture" on public.poste_permissions;
create policy "poste_permissions_ecriture" on public.poste_permissions
  for all
  using (
    exists (
      select 1 from public.postes po
      where po.id = poste_permissions.poste_id
        and public.a_permission(po.etablissement_id, 'etablissement.poste.gerer')
    )
  )
  with check (
    exists (
      select 1 from public.postes po
      where po.id = poste_permissions.poste_id
        and public.a_permission(po.etablissement_id, 'etablissement.poste.gerer')
    )
  );

-- Postes : l'écriture s'ouvre à la direction (la lecture est déjà cadrée par
-- la policy « postes_select_etablissement » du correctif M0).
drop policy if exists "postes_ecriture_direction" on public.postes;
create policy "postes_ecriture_direction" on public.postes
  for all
  using (public.a_permission(etablissement_id, 'etablissement.poste.gerer'))
  with check (public.a_permission(etablissement_id, 'etablissement.poste.gerer'));

-- Membres : la direction gère les rattachements de son établissement.
drop policy if exists "membres_ecriture_direction" on public.etablissements_membres;
create policy "membres_ecriture_direction" on public.etablissements_membres
  for all
  using (public.a_permission(etablissement_id, 'etablissement.membre.gerer'))
  with check (public.a_permission(etablissement_id, 'etablissement.membre.gerer'));

-- Établissements : la direction met à jour la fiche de son établissement.
-- La création reste serveur (onboarding validé, M2).
drop policy if exists "etablissements_update_direction" on public.etablissements;
create policy "etablissements_update_direction" on public.etablissements
  for update
  using (public.a_permission(id, 'etablissement.fiche.gerer'))
  with check (public.a_permission(id, 'etablissement.fiche.gerer'));

-- ---------------------------------------------------------------------------
-- 8. Index
-- ---------------------------------------------------------------------------
create index if not exists idx_unites_etablissement on public.unites_operationnelles (etablissement_id);
create index if not exists idx_annees_etablissement on public.annees_scolaires (etablissement_id);
create index if not exists idx_poste_permissions_poste on public.poste_permissions (poste_id);
create index if not exists idx_membres_unite on public.etablissements_membres (unite_id);
create index if not exists idx_membres_poste on public.etablissements_membres (poste_id);

-- ---------------------------------------------------------------------------
-- 9. Catalogue de permissions initial (données de référence, pas un seed de
--    démonstration : le client s'appuie dessus dès le premier démarrage).
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domaine, libelle, description) values
  ('etablissement.fiche.gerer',  'etablissement', 'Gérer la fiche établissement', 'Modifier nom, coordonnées, devise, fuseau.'),
  ('etablissement.unite.gerer',  'etablissement', 'Gérer les unités',             'Créer et modifier campus et annexes.'),
  ('etablissement.annee.gerer',  'etablissement', 'Gérer les années scolaires',   'Ouvrir, clôturer et activer une année scolaire.'),
  ('etablissement.poste.gerer',  'etablissement', 'Gérer les postes',             'Créer des postes et leur attribuer des permissions.'),
  ('etablissement.membre.gerer', 'etablissement', 'Gérer les membres',            'Rattacher, muter et détacher des membres.'),
  ('etablissement.membre.lire',  'etablissement', 'Consulter les membres',        'Accéder à l''annuaire interne.')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 10. Reprise de mes_etablissements() avec les colonnes introduites en M1
--     (soft-delete du rattachement et fin de mandat). Un membre détaché ou
--     dont le mandat est échu perd immédiatement l'accès au tenant.
-- ---------------------------------------------------------------------------
create or replace function public.mes_etablissements()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.etablissement_id
  from public.etablissements_membres m
  join public.profiles p on p.id = m.profile_id
  where m.profile_id = auth.uid()
    and m.actif
    and m.deleted_at is null
    and (m.date_fin is null or m.date_fin >= current_date)
    and p.statut_compte = 'actif'
    and p.deleted_at is null;
$$;

-- ============================================================================
-- Fin M1.
-- ============================================================================
