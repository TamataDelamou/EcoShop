-- ============================================================================
-- EcoShop — M2 — Authentification, invitations et liaison compte ↔ fiche
--
-- Périmètre (ANALYSE_GLOBALE.md §4.3) : parcours OTP E.164, sélection de rôle,
-- liaison compte ↔ fiche, fédération GSG ID de bout en bout.
--
-- Règles appliquées (cahier v4.1, ch. 5) :
--   • Élève et Parent sont les seuls rôles auto-inscriptibles ; tout rôle à
--     privilège passe par invitation nominative ou demande validée.
--   • Identifiant canonique unique : le premier identifiant authentifié fait
--     foi ; un canal secondaire ne s'ajoute que depuis une session active.
--   • Liaison compte ↔ fiche par double facteur matricule + date de naissance,
--     protégée contre le brute-force.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Canaux et identifiants secondaires (ch. 5.4)
--
-- Deux entrées (téléphone / e-mail) × quatre canaux de délivrance. Le canal
-- décrit *comment* le code est acheminé, l'entrée *ce qui* est authentifié.
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.canal_otp as enum ('sms', 'whatsapp', 'magic_link', 'email_otp');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.type_identifiant as enum ('telephone', 'email');
exception when duplicate_object then null;
end $$;

create table if not exists public.identifiants_comptes (
  id uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  type_identifiant public.type_identifiant not null,
  valeur text not null,                   -- E.164 normalisé, ou e-mail en minuscules
  canonique boolean not null default false,
  verifie_le timestamptz,
  created_at timestamptz not null default now(),
  constraint identifiants_valeur_unique unique (valeur)
);

comment on table public.identifiants_comptes is
  'Identifiants d''un compte. Exactement un canonique ; les autres sont des canaux secondaires ajoutés depuis une session active (ch. 5.4).';

-- Exactement un identifiant canonique par compte.
create unique index if not exists idx_identifiant_canonique_unique
  on public.identifiants_comptes (profile_id)
  where canonique;

-- Un numéro de téléphone doit être stocké au format E.164 : la normalisation
-- est faite côté client avant l'appel OTP, la base la vérifie plutôt que de
-- faire confiance à l'appelant.
do $$ begin
  alter table public.identifiants_comptes
    add constraint identifiants_forme_valide check (
      (type_identifiant = 'telephone' and valeur ~ '^\+[1-9][0-9]{6,14}$')
      or (type_identifiant = 'email' and valeur ~ '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$')
    );
exception when duplicate_object then null;
end $$;

create index if not exists idx_identifiants_profile on public.identifiants_comptes (profile_id);

-- Ajout d'un canal secondaire — refusé si l'identifiant appartient déjà à un
-- autre compte, et impossible hors session authentifiée.
create or replace function public.ajouter_identifiant_secondaire(
  p_type public.type_identifiant,
  p_valeur text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_valeur text;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  v_valeur := case when p_type = 'email' then lower(trim(p_valeur)) else trim(p_valeur) end;

  if exists (select 1 from public.identifiants_comptes where valeur = v_valeur) then
    raise exception 'IDENTIFIANT_DEJA_UTILISE' using errcode = '23505';
  end if;

  insert into public.identifiants_comptes (profile_id, type_identifiant, valeur, canonique)
  values (auth.uid(), p_type, v_valeur, false)
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.ajouter_identifiant_secondaire(public.type_identifiant, text) from public, anon;
grant execute on function public.ajouter_identifiant_secondaire(public.type_identifiant, text) to authenticated;

-- Reprise de handle_new_user : l'identifiant d'inscription devient canonique
-- dans profiles ET dans identifiants_comptes, en une seule transaction.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_valeur text;
  v_type   public.type_identifiant;
begin
  if new.phone is not null and new.phone <> '' then
    -- auth.users.phone est stocké sans le « + » : on rétablit la forme E.164.
    v_valeur := case when left(new.phone, 1) = '+' then new.phone else '+' || new.phone end;
    v_type := 'telephone';
  elsif new.email is not null and new.email <> '' then
    v_valeur := lower(new.email);
    v_type := 'email';
  else
    v_valeur := 'uid:' || new.id::text;
    v_type := null;
  end if;

  insert into public.profiles (id, identifiant_canonique)
  values (new.id, v_valeur)
  on conflict (id) do nothing;

  if v_type is not null then
    insert into public.identifiants_comptes (profile_id, type_identifiant, valeur, canonique, verifie_le)
    values (new.id, v_type, v_valeur, true, now())
    on conflict (valeur) do nothing;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Invitations — voie d'entrée des rôles à privilège (ch. 5.2)
--
-- Le jeton n'est jamais stocké en clair : seule son empreinte SHA-256 est
-- persistée, de sorte qu'une fuite de la table ne permette pas d'accepter les
-- invitations en attente.
-- ---------------------------------------------------------------------------
-- pgcrypto fournit digest(). Sur Supabase les extensions vivent dans le schéma
-- « extensions » ; les fonctions qui appellent digest() incluent donc ce schéma
-- dans leur search_path figé.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

do $$ begin
  create type public.statut_invitation as enum ('en_attente', 'acceptee', 'revoquee', 'expiree');
exception when duplicate_object then null;
end $$;

create table if not exists public.invitations (
  id uuid primary key default uuid_generate_v4(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  role_cible public.role_racine not null,
  poste_id uuid references public.postes (id) on delete set null,
  identifiant_cible text not null,        -- E.164 ou e-mail du destinataire
  jeton_empreinte text not null unique,   -- SHA-256 hexadécimal du jeton
  statut public.statut_invitation not null default 'en_attente',
  invite_par uuid references public.profiles (id) on delete set null,
  accepte_par uuid references public.profiles (id) on delete set null,
  expire_le timestamptz not null default now() + interval '14 days',
  created_at timestamptz not null default now(),
  accepte_le timestamptz
);

comment on column public.invitations.jeton_empreinte is
  'SHA-256 du jeton d''invitation. Le jeton en clair n''existe que dans le message envoyé au destinataire.';

create index if not exists idx_invitations_etablissement on public.invitations (etablissement_id);
create index if not exists idx_invitations_statut on public.invitations (statut) where statut = 'en_attente';

-- Acceptation d'une invitation : crée le rattachement, fixe le rôle racine si
-- le compte n'en a pas encore, et referme l'invitation. Tout est fait côté
-- serveur : le client ne transmet que le jeton reçu.
create or replace function public.accepter_invitation(p_jeton text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_inv record;
  v_membre_id uuid;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  select * into v_inv
  from public.invitations
  where jeton_empreinte = encode(digest(p_jeton, 'sha256'), 'hex')
  for update;

  if not found then
    raise exception 'INVITATION_INTROUVABLE' using errcode = 'P0002';
  end if;

  if v_inv.statut <> 'en_attente' then
    raise exception 'INVITATION_DEJA_TRAITEE' using errcode = '22023';
  end if;

  if v_inv.expire_le < now() then
    update public.invitations set statut = 'expiree' where id = v_inv.id;
    raise exception 'INVITATION_EXPIREE' using errcode = '22023';
  end if;

  -- L'invitation est nominative : elle ne vaut que pour le destinataire.
  if not exists (
    select 1 from public.identifiants_comptes
    where profile_id = auth.uid() and valeur = v_inv.identifiant_cible
  ) then
    raise exception 'INVITATION_AUTRE_DESTINATAIRE' using errcode = '42501';
  end if;

  insert into public.etablissements_membres
    (profile_id, etablissement_id, role_dans_etablissement, poste_id)
  values
    (auth.uid(), v_inv.etablissement_id, v_inv.role_cible::text, v_inv.poste_id)
  on conflict (profile_id, etablissement_id) do update
    set role_dans_etablissement = excluded.role_dans_etablissement,
        poste_id = excluded.poste_id,
        actif = true,
        deleted_at = null
  returning id into v_membre_id;

  -- Le rôle racine n'est attribué que s'il est encore indéfini : une invitation
  -- ne doit jamais rétrograder ni écraser un rôle déjà établi.
  update public.profiles
     set role_racine = v_inv.role_cible
   where id = auth.uid() and role_racine is null;

  update public.invitations
     set statut = 'acceptee', accepte_par = auth.uid(), accepte_le = now()
   where id = v_inv.id;

  return v_membre_id;
end;
$$;

revoke execute on function public.accepter_invitation(text) from public, anon;
grant execute on function public.accepter_invitation(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Demandes d'adhésion — voie d'entrée validée (vendeur, direction…)
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.statut_demande as enum ('en_attente', 'acceptee', 'refusee', 'annulee');
exception when duplicate_object then null;
end $$;

create table if not exists public.demandes_adhesion (
  id uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  role_demande public.role_racine not null,
  motif text,
  statut public.statut_demande not null default 'en_attente',
  traite_par uuid references public.profiles (id) on delete set null,
  traite_le timestamptz,
  motif_refus text,
  created_at timestamptz not null default now()
);

-- Une seule demande en attente par couple (compte, établissement) ; l'historique
-- des demandes refusées ou annulées reste conservé.
create unique index if not exists idx_demandes_une_seule_en_attente
  on public.demandes_adhesion (profile_id, etablissement_id)
  where statut = 'en_attente';

create index if not exists idx_demandes_etablissement on public.demandes_adhesion (etablissement_id)
  where statut = 'en_attente';

-- ---------------------------------------------------------------------------
-- 4. Fiche élève et liaison compte ↔ fiche (ch. 5.8)
--
-- La fiche est créée par l'établissement (scolarité) ; l'élève ou son parent
-- la revendique avec matricule + date de naissance. M5 enrichira la fiche
-- (classe, inscriptions, tuteurs) : seules les colonnes nécessaires à la
-- liaison sont introduites ici.
-- ---------------------------------------------------------------------------
create table if not exists public.fiches_eleves (
  id uuid primary key default uuid_generate_v4(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  matricule text not null,
  nom text not null,
  prenom text not null,
  date_naissance date not null,
  profile_id uuid references public.profiles (id) on delete set null,
  lie_le timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint fiches_matricule_unique unique (etablissement_id, matricule)
);

comment on table public.fiches_eleves is
  'Fiche scolaire de l''élève, créée par l''établissement. Enrichie en M5.';

drop trigger if exists fiches_set_updated_at on public.fiches_eleves;
create trigger fiches_set_updated_at
  before update on public.fiches_eleves
  for each row execute procedure public.set_updated_at();

-- Journal des tentatives de liaison — support de l'anti-brute-force. Une fiche
-- se devine autrement trop facilement : le matricule est souvent séquentiel et
-- la date de naissance a une entropie faible.
create table if not exists public.tentatives_liaison (
  id bigserial primary key,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  matricule_essaye text not null,
  reussie boolean not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_tentatives_profil_date
  on public.tentatives_liaison (profile_id, created_at desc);

-- Liaison du compte authentifié à une fiche élève.
-- Double facteur matricule + date de naissance, 5 échecs par heure maximum.
create or replace function public.lier_compte_a_fiche(
  p_matricule text,
  p_date_naissance date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fiche_id uuid;
  v_echecs   int;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  select count(*) into v_echecs
  from public.tentatives_liaison
  where profile_id = auth.uid()
    and not reussie
    and created_at > now() - interval '1 hour';

  if v_echecs >= 5 then
    raise exception 'TROP_DE_TENTATIVES' using errcode = '54000';
  end if;

  select id into v_fiche_id
  from public.fiches_eleves
  where matricule = trim(p_matricule)
    and date_naissance = p_date_naissance
    and profile_id is null
    and deleted_at is null
  limit 1;

  -- Réponse volontairement indifférenciée : « matricule inconnu », « date
  -- incorrecte » et « fiche déjà liée » renvoient la même erreur, pour ne pas
  -- transformer la fonction en oracle d'énumération des matricules.
  if v_fiche_id is null then
    insert into public.tentatives_liaison (profile_id, matricule_essaye, reussie)
    values (auth.uid(), trim(p_matricule), false);
    raise exception 'LIAISON_IMPOSSIBLE' using errcode = '42501';
  end if;

  update public.fiches_eleves
     set profile_id = auth.uid(), lie_le = now()
   where id = v_fiche_id;

  insert into public.tentatives_liaison (profile_id, matricule_essaye, reussie)
  values (auth.uid(), trim(p_matricule), true);

  -- La liaison vaut rattachement à l'établissement de la fiche.
  insert into public.etablissements_membres
    (profile_id, etablissement_id, role_dans_etablissement)
  select auth.uid(), f.etablissement_id, 'eleve'
  from public.fiches_eleves f where f.id = v_fiche_id
  on conflict (profile_id, etablissement_id) do nothing;

  return v_fiche_id;
end;
$$;

revoke execute on function public.lier_compte_a_fiche(text, date) from public, anon;
grant execute on function public.lier_compte_a_fiche(text, date) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Sélection de l'établissement actif (ch. 4 — enseignant multi-établissement)
-- ---------------------------------------------------------------------------
create or replace function public.definir_etablissement_actif(p_etablissement uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  if not public.est_membre_actif(p_etablissement) then
    raise exception 'ETABLISSEMENT_NON_MEMBRE' using errcode = '42501';
  end if;

  update public.profiles
     set etablissement_actif_id = p_etablissement
   where id = auth.uid();

  return p_etablissement;
end;
$$;

revoke execute on function public.definir_etablissement_actif(uuid) from public, anon;
grant execute on function public.definir_etablissement_actif(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. RLS
-- ---------------------------------------------------------------------------
alter table public.identifiants_comptes enable row level security;
alter table public.invitations enable row level security;
alter table public.demandes_adhesion enable row level security;
alter table public.fiches_eleves enable row level security;
alter table public.tentatives_liaison enable row level security;

-- Identifiants : chacun voit les siens. Aucune écriture directe (RPC dédiée).
drop policy if exists "identifiants_select_propres" on public.identifiants_comptes;
create policy "identifiants_select_propres" on public.identifiants_comptes
  for select using (profile_id = auth.uid());

-- Invitations : gérées par la direction ; le destinataire n'y accède jamais en
-- lecture (il détient le jeton, c'est le seul facteur nécessaire) — cela évite
-- d'exposer l'empreinte et la liste des invitations en attente.
drop policy if exists "invitations_direction" on public.invitations;
create policy "invitations_direction" on public.invitations
  for all
  using (public.a_permission(etablissement_id, 'etablissement.membre.gerer'))
  with check (public.a_permission(etablissement_id, 'etablissement.membre.gerer'));

-- Demandes : le demandeur voit et crée les siennes ; la direction traite
-- celles de son établissement.
drop policy if exists "demandes_select_propres" on public.demandes_adhesion;
create policy "demandes_select_propres" on public.demandes_adhesion
  for select using (profile_id = auth.uid());

drop policy if exists "demandes_insert_propres" on public.demandes_adhesion;
create policy "demandes_insert_propres" on public.demandes_adhesion
  for insert to authenticated
  with check (profile_id = auth.uid() and statut = 'en_attente');

drop policy if exists "demandes_direction" on public.demandes_adhesion;
create policy "demandes_direction" on public.demandes_adhesion
  for all
  using (public.a_permission(etablissement_id, 'etablissement.membre.gerer'))
  with check (public.a_permission(etablissement_id, 'etablissement.membre.gerer'));

-- Fiches élèves : l'élève lié voit la sienne ; la scolarité gère celles de son
-- établissement. La revendication d'une fiche non liée passe exclusivement par
-- lier_compte_a_fiche() : aucune policy ne la rend lisible avant liaison.
drop policy if exists "fiches_select_propre" on public.fiches_eleves;
create policy "fiches_select_propre" on public.fiches_eleves
  for select using (profile_id = auth.uid() and deleted_at is null);

drop policy if exists "fiches_scolarite" on public.fiches_eleves;
create policy "fiches_scolarite" on public.fiches_eleves
  for all
  using (public.a_permission(etablissement_id, 'scolarite.eleve.gerer'))
  with check (public.a_permission(etablissement_id, 'scolarite.eleve.gerer'));

-- Tentatives de liaison : lecture de ses propres tentatives (affichage du
-- verrouillage temporaire). Écriture réservée à la RPC (security definer).
drop policy if exists "tentatives_select_propres" on public.tentatives_liaison;
create policy "tentatives_select_propres" on public.tentatives_liaison
  for select using (profile_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 7. Permissions introduites par M2
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domaine, libelle, description) values
  ('scolarite.eleve.gerer', 'scolarite', 'Gérer les fiches élèves', 'Créer et modifier les fiches scolaires (matricule, état civil).'),
  ('etablissement.invitation.gerer', 'etablissement', 'Gérer les invitations', 'Inviter des membres et révoquer des invitations en attente.')
on conflict (code) do nothing;

-- ============================================================================
-- Fin M2.
-- ============================================================================
