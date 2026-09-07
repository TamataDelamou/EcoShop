-- ============================================================================
-- EcoShop — M13 — Marketplace AssoShop mono-vendeur
--
-- Périmètre (cahier v4.1 ch. 27, docs/RECHERCHE_COMPARATIVE.md §15) :
--   • Commerçants externes + catalogue produits.
--   • Panier MONO-VENDEUR : une commande = un seul commerçant à la fois.
--   • Sous-comptes marchands par établissement : chaque établissement configure
--     ses propres identifiants CinetPay / Mobile Money (encaissements isolés).
--   • Port de paiement AGNOSTIQUE : colonnes génériques (fournisseur, référence,
--     statut), aucun schéma spécifique fournisseur ; les adaptateurs sont des
--     Edge Functions.
--
-- Règles métier arbitrées (strictes) :
--   1. Panier mono-vendeur (garde-fou lignes_paniers_verifie_commercant).
--   2. Isolation des encaissements (sous_comptes_marchands, RLS par
--      établissement, secrets jamais stockés en clair).
--   3. Port paiement agnostique (type_fournisseur_paiement + paiements).
--
-- Principes : soft-delete, dénormalisation tenant + garde-fou trigger
-- (pattern M1/M5), jamais de décision automatique.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Types énumérés
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.type_fournisseur_paiement as enum ('cinetpay', 'mobile_money');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.statut_commande as enum
    ('brouillon', 'confirmee', 'payee', 'expediee', 'livree', 'annulee');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.statut_paiement as enum
    ('initie', 'en_attente', 'reussi', 'echoue', 'rembourse');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 1. Commerçants externes (vendeurs, hors établissement)
-- ---------------------------------------------------------------------------
create table if not exists public.commercants (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  raison_sociale text,
  telephone text,
  email text,
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists idx_commercants_nom_unique
  on public.commercants (nom) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 2. Catalogue produits (porté par un commerçant)
-- ---------------------------------------------------------------------------
create table if not exists public.catalogues_produits (
  id uuid primary key default gen_random_uuid(),
  commercant_id uuid not null references public.commercants (id) on delete cascade,
  libelle text not null,
  description text,
  prix numeric(12,2) not null check (prix >= 0),
  devise text not null default 'XOF',
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_catalogues_commercant on public.catalogues_produits (commercant_id);

create unique index if not exists idx_catalogues_commercant_libelle_unique
  on public.catalogues_produits (commercant_id, libelle) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 3. Paniers — MONO-VENDEUR (un seul commercant_id par panier)
-- ---------------------------------------------------------------------------
create table if not exists public.paniers (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  commercant_id uuid references public.commercants (id) on delete set null,
  statut text not null default 'actif',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_paniers_profile on public.paniers (profile_id);

-- ---------------------------------------------------------------------------
-- 4. Lignes de panier
-- ---------------------------------------------------------------------------
create table if not exists public.lignes_paniers (
  id uuid primary key default gen_random_uuid(),
  panier_id uuid not null references public.paniers (id) on delete cascade,
  catalogue_produit_id uuid not null references public.catalogues_produits (id) on delete cascade,
  quantite int not null default 1 check (quantite > 0),
  created_at timestamptz not null default now(),
  constraint lignes_paniers_unique unique (panier_id, catalogue_produit_id)
);

-- ---------------------------------------------------------------------------
-- 5. Commandes (une commande = un commerçant)
-- ---------------------------------------------------------------------------
create table if not exists public.commandes (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  commercant_id uuid not null references public.commercants (id) on delete restrict,
  profile_id uuid not null references public.profiles (id) on delete restrict,
  panier_id uuid references public.paniers (id) on delete set null,
  reference text not null unique,
  statut public.statut_commande not null default 'brouillon',
  montant_total numeric(12,2) not null default 0 check (montant_total >= 0),
  montant_frais numeric(12,2) not null default 0 check (montant_frais >= 0),
  devise text not null default 'XOF',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_commandes_etab on public.commandes (etablissement_id);
create index if not exists idx_commandes_profile on public.commandes (profile_id);

-- ---------------------------------------------------------------------------
-- 6. Lignes de commande (snapshot prix au moment de la commande)
-- ---------------------------------------------------------------------------
create table if not exists public.lignes_commandes (
  id uuid primary key default gen_random_uuid(),
  commande_id uuid not null references public.commandes (id) on delete cascade,
  catalogue_produit_id uuid not null references public.catalogues_produits (id) on delete restrict,
  quantite int not null default 1 check (quantite > 0),
  prix_unitaire numeric(12,2) not null check (prix_unitaire >= 0),
  montant_ligne numeric(12,2) not null check (montant_ligne >= 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_lignes_commandes_commande on public.lignes_commandes (commande_id);

-- ---------------------------------------------------------------------------
-- 7. Sous-comptes marchands — isolation des encaissements par établissement.
--    Les SECRETS (clés API, tokens) ne sont JAMAIS stockés ici : ils vivent
--    dans Supabase Vault / secrets d'Edge Function. `reference_compte` est un
--    identifiant public (merchant id), pas un secret.
-- ---------------------------------------------------------------------------
create table if not exists public.sous_comptes_marchands (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  fournisseur public.type_fournisseur_paiement not null,
  libelle text not null,
  reference_compte text not null,
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists idx_sous_comptes_etab_fournisseur_unique
  on public.sous_comptes_marchands (etablissement_id, fournisseur)
  where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 8. Paiements — port AGNOSTIQUE (aucune colonne spécifique fournisseur)
-- ---------------------------------------------------------------------------
create table if not exists public.paiements (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  commande_id uuid not null references public.commandes (id) on delete cascade,
  sous_compte_id uuid references public.sous_comptes_marchands (id) on delete set null,
  fournisseur public.type_fournisseur_paiement not null,
  montant numeric(12,2) not null check (montant >= 0),
  statut public.statut_paiement not null default 'initie',
  reference_fournisseur text,
  message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_paiements_commande on public.paiements (commande_id);
create index if not exists idx_paiements_etab on public.paiements (etablissement_id);

-- ---------------------------------------------------------------------------
-- 9. Garde-fous multi-tenant et métier (pattern M1/M5)
-- ---------------------------------------------------------------------------

-- 9.1 Panier mono-vendeur : la ligne doit appartenir au commerçant du panier.
create or replace function public.lignes_paniers_verifie_commercant()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_commercant_panier uuid;
  v_commercant_produit uuid;
begin
  select commercant_id into v_commercant_panier from public.paniers where id = new.panier_id;
  select commercant_id into v_commercant_produit
    from public.catalogues_produits where id = new.catalogue_produit_id;

  if v_commercant_produit is distinct from v_commercant_panier then
    raise exception 'PANIER_MONO_VENDEUR' using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists lignes_paniers_verifie_commercant on public.lignes_paniers;
create trigger lignes_paniers_verifie_commercant
  before insert or update on public.lignes_paniers
  for each row execute procedure public.lignes_paniers_verifie_commercant();

-- 9.2 Commande cohérente avec son panier (même commerçant, même établissement).
create or replace function public.commandes_verifie_panier()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_commercant uuid;
  v_etab uuid;
begin
  if new.panier_id is not null then
    select commercant_id, etablissement_id into v_commercant, v_etab
      from public.paniers where id = new.panier_id;
    if v_commercant is not null and new.commercant_id is distinct from v_commercant then
      raise exception 'COMMANDE_COMMERCANT_INCOHERENT' using errcode = '23514';
    end if;
    if v_etab is not null and new.etablissement_id is distinct from v_etab then
      raise exception 'COMMANDE_ETABLISSEMENT_INCOHERENT' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists commandes_verifie_panier on public.commandes;
create trigger commandes_verifie_panier
  before insert or update on public.commandes
  for each row execute procedure public.commandes_verifie_panier();

-- 9.3 Ligne de commande : le produit appartient au commerçant de la commande.
create or replace function public.lignes_commandes_verifie_commercant()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_commercant_commande uuid;
  v_commercant_produit uuid;
begin
  select commercant_id into v_commercant_commande from public.commandes where id = new.commande_id;
  select commercant_id into v_commercant_produit
    from public.catalogues_produits where id = new.catalogue_produit_id;

  if v_commercant_produit is distinct from v_commercant_commande then
    raise exception 'LIGNE_COMMANDE_COMMERCANT_INCOHERENT' using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists lignes_commandes_verifie_commercant on public.lignes_commandes;
create trigger lignes_commandes_verifie_commercant
  before insert or update on public.lignes_commandes
  for each row execute procedure public.lignes_commandes_verifie_commercant();

-- 9.4 Paiement : le fournisseur doit correspondre à celui du sous-compte.
create or replace function public.paiements_verifie_fournisseur()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_fournisseur public.type_fournisseur_paiement;
begin
  if new.sous_compte_id is not null then
    select fournisseur into v_fournisseur from public.sous_comptes_marchands where id = new.sous_compte_id;
    if v_fournisseur is distinct from new.fournisseur then
      raise exception 'PAIEMENT_FOURNISSEUR_INCOHERENT' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists paiements_verifie_fournisseur on public.paiements;
create trigger paiements_verifie_fournisseur
  before insert or update on public.paiements
  for each row execute procedure public.paiements_verifie_fournisseur();

-- ---------------------------------------------------------------------------
-- 10. RLS
-- ---------------------------------------------------------------------------
alter table public.commercants enable row level security;
alter table public.catalogues_produits enable row level security;
alter table public.paniers enable row level security;
alter table public.lignes_paniers enable row level security;
alter table public.commandes enable row level security;
alter table public.lignes_commandes enable row level security;
alter table public.sous_comptes_marchands enable row level security;
alter table public.paiements enable row level security;

-- Commerçants : catalogue public (lecture), gestion réservée au service/admin.
create policy commercants_select on public.commercants
  for select using (true);
create policy commercants_insert on public.commercants
  for insert with check (public.est_admin_gsg() or public.est_appel_service());
create policy commercants_update on public.commercants
  for update using (public.est_admin_gsg() or public.est_appel_service());
create policy commercants_delete on public.commercants
  for delete using (public.est_admin_gsg() or public.est_appel_service());

-- Catalogue : lecture publique ; gestion service/admin.
create policy catalogues_select on public.catalogues_produits
  for select using (true);
create policy catalogues_insert on public.catalogues_produits
  for insert with check (public.est_admin_gsg() or public.est_appel_service());
create policy catalogues_update on public.catalogues_produits
  for update using (public.est_admin_gsg() or public.est_appel_service());
create policy catalogues_delete on public.catalogues_produits
  for delete using (public.est_admin_gsg() or public.est_appel_service());

-- Paniers : propriétaire uniquement (+ service).
create policy paniers_select on public.paniers
  for select using (profile_id = auth.uid() or public.est_appel_service());
create policy paniers_insert on public.paniers
  for insert with check (profile_id = auth.uid() or public.est_appel_service());
create policy paniers_update on public.paniers
  for update using (profile_id = auth.uid() or public.est_appel_service());
create policy paniers_delete on public.paniers
  for delete using (profile_id = auth.uid() or public.est_appel_service());

-- Lignes de panier : via le panier propriétaire.
create policy lignes_paniers_select on public.lignes_paniers
  for select using (
    exists (select 1 from public.paniers p
             where p.id = panier_id
               and (p.profile_id = auth.uid() or public.est_appel_service()))
  );
create policy lignes_paniers_insert on public.lignes_paniers
  for insert with check (
    exists (select 1 from public.paniers p
             where p.id = panier_id
               and (p.profile_id = auth.uid() or public.est_appel_service()))
  );
create policy lignes_paniers_delete on public.lignes_paniers
  for delete using (
    exists (select 1 from public.paniers p
             where p.id = panier_id
               and (p.profile_id = auth.uid() or public.est_appel_service()))
  );

-- Commandes : propriétaire + membres actifs de l'établissement + service.
create policy commandes_select on public.commandes
  for select using (
    profile_id = auth.uid()
    or public.est_membre_actif(etablissement_id)
    or public.est_appel_service()
  );
create policy commandes_insert on public.commandes
  for insert with check (profile_id = auth.uid() or public.est_appel_service());
create policy commandes_update on public.commandes
  for update using (
    profile_id = auth.uid()
    or public.est_membre_actif(etablissement_id)
    or public.est_appel_service()
  );
create policy commandes_delete on public.commandes
  for delete using (public.est_appel_service());

-- Lignes de commande : via la commande visible.
create policy lignes_commandes_select on public.lignes_commandes
  for select using (
    exists (select 1 from public.commandes c
             where c.id = commande_id
               and (c.profile_id = auth.uid()
                    or public.est_membre_actif(c.etablissement_id)
                    or public.est_appel_service()))
  );
create policy lignes_commandes_insert on public.lignes_commandes
  for insert with check (
    exists (select 1 from public.commandes c
             where c.id = commande_id
               and (c.profile_id = auth.uid() or public.est_appel_service()))
  );

-- Sous-comptes marchands : membres actifs de l'établissement + service/admin.
-- Isolation stricte : un établissement ne voit jamais les comptes d'un autre.
create policy sous_comptes_select on public.sous_comptes_marchands
  for select using (
    public.est_membre_actif(etablissement_id)
    or public.est_appel_service()
    or public.est_admin_gsg()
  );
create policy sous_comptes_insert on public.sous_comptes_marchands
  for insert with check (
    public.est_membre_actif(etablissement_id)
    or public.est_appel_service()
    or public.est_admin_gsg()
  );
create policy sous_comptes_update on public.sous_comptes_marchands
  for update using (
    public.est_membre_actif(etablissement_id)
    or public.est_appel_service()
    or public.est_admin_gsg()
  );
create policy sous_comptes_delete on public.sous_comptes_marchands
  for delete using (public.est_appel_service() or public.est_admin_gsg());

-- Paiements : via l'établissement de la commande.
create policy paiements_select on public.paiements
  for select using (
    public.est_membre_actif(etablissement_id)
    or public.est_appel_service()
    or public.est_admin_gsg()
  );
create policy paiements_insert on public.paiements
  for insert with check (
    public.est_membre_actif(etablissement_id)
    or public.est_appel_service()
  );
create policy paiements_update on public.paiements
  for update using (public.est_appel_service());

-- ---------------------------------------------------------------------------
-- 11. Fonction IA — détection d'anomalies de commandes (aide à la décision)
-- ---------------------------------------------------------------------------
create or replace function public.detecter_anomalies_commandes(p_etablissement uuid)
returns table (
  commande_id uuid,
  reference text,
  montant_total numeric,
  paiements_en_attente bigint,
  anomalie text
)
language sql
stable
security definer
set search_path = public
as $$
  select c.id,
         c.reference,
         c.montant_total,
         (select count(*) from public.paiements p
           where p.commande_id = c.id and p.statut = 'en_attente') as paiements_en_attente,
         case
           when c.montant_total > 1000000 then 'montant_eleve'
           else 'paiement_attente_multiple'
         end as anomalie
  from public.commandes c
  where c.etablissement_id = p_etablissement
    and c.deleted_at is null
    and (c.montant_total > 1000000
         or (select count(*) from public.paiements p
              where p.commande_id = c.id and p.statut = 'en_attente') > 1);
$$;

revoke all on function public.detecter_anomalies_commandes(uuid) from public;
grant execute on function public.detecter_anomalies_commandes(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 12. Permissions marketplace
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domaine, libelle, description) values
  ('marketplace.catalogue.lire',    'marketplace', 'Consulter le catalogue',       'Lecture commerçants et produits'),
  ('marketplace.commande.creer',    'marketplace', 'Créer une commande',           'Passer une commande mono-vendeur'),
  ('marketplace.commande.lire',     'marketplace', 'Consulter les commandes',      'Lecture des commandes de l''établissement'),
  ('marketplace.paiement.lire',     'marketplace', 'Consulter les paiements',      'Lecture des paiements de l''établissement'),
  ('marketplace.souscompte.gerer',  'marketplace', 'Gérer les sous-comptes',       'Configuration CinetPay / Mobile Money')
on conflict (code) do nothing;
