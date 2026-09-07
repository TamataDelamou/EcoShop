-- ============================================================================
-- EcoShop — Correctifs de sécurité du schéma cœur (M0)
--
-- Corrige quatre défauts de la migration 20260904000000_core_schema.sql :
--   C1. Escalade de privilège : « profiles_update_own » laissait un compte
--       modifier son propre role_racine (un élève pouvait devenir admin_gsg).
--   C2. Récursion RLS (42P17) : les policies de etablissements /
--       etablissements_membres / postes interrogeaient etablissements_membres,
--       table dont la policy SELECT interroge à son tour etablissements_membres.
--   C3. Custom Access Token Hook inopérant : la fonction lisait public.profiles
--       sans security definer ni droits pour supabase_auth_admin ; RLS la
--       bloquait, aucun claim n'était jamais émis.
--   C4. handle_new_user pouvait violer la contrainte NOT NULL sur
--       identifiant_canonique (utilisateur créé sans téléphone ni e-mail).
--
-- Applique aussi le soft-delete et le statut de compte dans les policies.
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Fonctions d'aide RLS — SECURITY DEFINER pour casser la récursion (C2)
--
-- Une fonction security definer n'évalue pas les policies des tables qu'elle
-- lit : c'est le mécanisme recommandé pour référencer une table depuis sa
-- propre policy sans boucle infinie.
-- ---------------------------------------------------------------------------

-- Vrai si l'appel provient du serveur (service_role, migrations, RPC de
-- confiance) et non d'une requête client directe.
--
-- Deux conditions distinctes, jamais l'une à la place de l'autre :
--   • le rôle Postgres effectif est privilégié — c'est le cas des migrations
--     et, surtout, de l'intérieur d'une fonction SECURITY DEFINER dont nous
--     sommes propriétaires : sans cela, les RPC de confiance
--     (choisir_role_racine, accepter_invitation) seraient elles-mêmes bloquées
--     par le trigger de protection qu'elles doivent traverser ;
--   • ou le jeton porte le rôle service_role (Edge Functions, back-office).
--
-- Une requête PostgREST ordinaire s'exécute sous le rôle « authenticated » :
-- elle ne satisfait ni l'une ni l'autre.
create or replace function public.est_appel_service()
returns boolean
language sql
stable
set search_path = public
as $$
  select current_user in ('service_role', 'supabase_admin', 'supabase_auth_admin', 'postgres')
      or coalesce(
           nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
           ''
         ) = 'service_role';
$$;

comment on function public.est_appel_service() is
  'Vrai pour les appels serveur (service_role, migrations, RPC SECURITY DEFINER) exemptés des garde-fous client.';

-- Établissements dont l'appelant est membre actif (compte actif, non supprimé).
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
    and p.statut_compte = 'actif'
    and p.deleted_at is null;
$$;

comment on function public.mes_etablissements() is
  'Établissements de l''appelant. SECURITY DEFINER : évite la récursion RLS (42P17).';

-- Vrai si l'appelant est membre actif de l'établissement donné.
create or replace function public.est_membre_actif(p_etablissement uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.mes_etablissements() e where e = p_etablissement
  );
$$;

-- Rôle racine de l'appelant, lu dans profiles (jamais dans le jeton).
create or replace function public.mon_role_racine()
returns public.role_racine
language sql
stable
security definer
set search_path = public
as $$
  select role_racine
  from public.profiles
  where id = auth.uid() and deleted_at is null;
$$;

-- Vrai si l'appelant est Administrateur GSG (rôle plateforme supra-tenant).
create or replace function public.est_admin_gsg()
returns boolean
language sql
stable
set search_path = public
as $$
  select public.mon_role_racine() = 'admin_gsg';
$$;

grant execute on function public.est_appel_service() to authenticated;
grant execute on function public.mes_etablissements() to authenticated;
grant execute on function public.est_membre_actif(uuid) to authenticated;
grant execute on function public.mon_role_racine() to authenticated;
grant execute on function public.est_admin_gsg() to authenticated;

-- ---------------------------------------------------------------------------
-- C1 — Verrouillage des colonnes sensibles de profiles
--
-- La policy UPDATE reste « sa propre ligne », mais un trigger BEFORE UPDATE
-- restaure les colonnes à privilège : le client ne peut modifier que son
-- état civil. Rôle, statut, identifiant canonique et gsg_id ne changent que
-- par le serveur (service_role / Edge Function) ou par la RPC dédiée.
-- ---------------------------------------------------------------------------
create or replace function public.profiles_protege_colonnes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.est_appel_service() then
    return new;
  end if;

  new.id                     := old.id;
  new.gsg_id                 := old.gsg_id;
  new.identifiant_canonique  := old.identifiant_canonique;
  new.role_racine            := old.role_racine;
  new.statut_compte          := old.statut_compte;
  new.created_at             := old.created_at;
  new.deleted_at             := old.deleted_at;
  return new;
end;
$$;

comment on function public.profiles_protege_colonnes() is
  'Empêche un client d''élever ses propres privilèges via un UPDATE sur profiles.';

drop trigger if exists profiles_protege_colonnes_trg on public.profiles;
create trigger profiles_protege_colonnes_trg
  before update on public.profiles
  for each row execute procedure public.profiles_protege_colonnes();

-- ---------------------------------------------------------------------------
-- Choix du rôle racine à l'inscription (ch. 5.2)
--
-- Seuls Élève et Parent sont auto-inscriptibles ; tout autre rôle passe par
-- invitation ou demande validée (M2). Le rôle ne peut être choisi qu'une fois.
-- ---------------------------------------------------------------------------
create or replace function public.choisir_role_racine(p_role public.role_racine)
returns public.role_racine
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actuel public.role_racine;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  if p_role not in ('eleve', 'parent') then
    raise exception 'ROLE_NON_AUTO_INSCRIPTIBLE' using errcode = '42501';
  end if;

  select role_racine into v_actuel
  from public.profiles where id = auth.uid() and deleted_at is null
  for update;

  if not found then
    raise exception 'PROFIL_INTROUVABLE' using errcode = 'P0002';
  end if;

  if v_actuel is not null then
    raise exception 'ROLE_DEJA_DEFINI' using errcode = '23505';
  end if;

  update public.profiles set role_racine = p_role where id = auth.uid();
  return p_role;
end;
$$;

comment on function public.choisir_role_racine(public.role_racine) is
  'Fixe une seule fois le rôle racine, restreint aux rôles auto-inscriptibles (ch. 5.2).';

revoke execute on function public.choisir_role_racine(public.role_racine) from public, anon;
grant execute on function public.choisir_role_racine(public.role_racine) to authenticated;

-- ---------------------------------------------------------------------------
-- C4 — handle_new_user : identifiant canonique toujours renseigné
--
-- Un utilisateur peut être créé sans téléphone ni e-mail (invitation, provider
-- externe) : on retombe sur un identifiant technique dérivé de l'uuid plutôt
-- que de faire échouer l'inscription sur une violation NOT NULL.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, identifiant_canonique)
  values (new.id, coalesce(new.phone, new.email, 'uid:' || new.id::text))
  on conflict (id) do nothing;
  return new;
end;
$$;

-- set_updated_at : search_path figé (durcissement, aucun changement de logique)
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- C3 — Custom Access Token Hook exécutable
--
-- Le hook s'exécute sous le rôle supabase_auth_admin, qui n'a par défaut ni
-- accès au schéma public ni droit de lecture sur profiles, et que RLS bloque.
-- On lui accorde explicitement le strict nécessaire.
-- ---------------------------------------------------------------------------
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  claims        jsonb;
  app_metadata  jsonb;
  prof          record;
begin
  claims := coalesce(event->'claims', '{}'::jsonb);

  select role_racine, gsg_id, statut_compte into prof
  from public.profiles
  where id = (event->>'user_id')::uuid
    and deleted_at is null;

  if found then
    -- jsonb_set ne crée pas les segments intermédiaires manquants du chemin :
    -- on construit app_metadata à part (set à un seul niveau, toujours sûr),
    -- puis on la fusionne dans claims en une fois.
    app_metadata := coalesce(claims->'app_metadata', '{}'::jsonb);

    if prof.role_racine is not null then
      app_metadata := jsonb_set(app_metadata, '{role_racine}',
                                to_jsonb(prof.role_racine::text), true);
    end if;
    if prof.gsg_id is not null then
      app_metadata := jsonb_set(app_metadata, '{gsg_id}',
                                to_jsonb(prof.gsg_id::text), true);
    end if;
    app_metadata := jsonb_set(app_metadata, '{statut_compte}',
                              to_jsonb(prof.statut_compte::text), true);

    claims := jsonb_set(claims, '{app_metadata}', app_metadata, true);
  end if;

  -- Rappel : ces claims sont un cache de confort côté client. Toute décision
  -- d'autorisation relit public.profiles côté serveur (ch. 34).
  return jsonb_build_object('claims', claims);
end;
$$;

grant usage on schema public to supabase_auth_admin;
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook(jsonb) from authenticated, anon, public;

-- ---------------------------------------------------------------------------
-- Policies corrigées (C1, C2) + soft-delete et statut de compte
-- ---------------------------------------------------------------------------

-- profiles : sa propre ligne, non supprimée
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id and deleted_at is null);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update
  using (auth.uid() = id and deleted_at is null and statut_compte = 'actif')
  with check (auth.uid() = id);

-- Lecture des profils des membres du même établissement (annuaire interne).
drop policy if exists "profiles_select_meme_etablissement" on public.profiles;
create policy "profiles_select_meme_etablissement" on public.profiles
  for select using (
    deleted_at is null
    and exists (
      select 1
      from public.etablissements_membres m
      where m.profile_id = profiles.id
        and m.actif
        and m.etablissement_id in (select public.mes_etablissements())
    )
  );

-- etablissements : ceux dont on est membre actif (sans récursion)
drop policy if exists "etablissements_select_member" on public.etablissements;
create policy "etablissements_select_member" on public.etablissements
  for select using (
    deleted_at is null
    and (id in (select public.mes_etablissements()) or public.est_admin_gsg())
  );

-- etablissements_membres : ses propres rattachements + ceux de ses établissements
drop policy if exists "membres_select_propres" on public.etablissements_membres;
create policy "membres_select_propres" on public.etablissements_membres
  for select using (profile_id = auth.uid());

drop policy if exists "membres_select_etablissement" on public.etablissements_membres;
create policy "membres_select_etablissement" on public.etablissements_membres
  for select using (etablissement_id in (select public.mes_etablissements()));

-- postes : lecture par les membres de l'établissement
drop policy if exists "postes_select_etablissement" on public.postes;
create policy "postes_select_etablissement" on public.postes
  for select using (etablissement_id in (select public.mes_etablissements()));

-- ============================================================================
-- Fin des correctifs. L'écriture sur etablissements / postes / membres reste
-- réservée au serveur (service_role, Edge Functions) : aucune policy
-- INSERT/UPDATE/DELETE n'est ouverte au client.
-- ============================================================================
