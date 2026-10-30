-- ============================================================================
-- EcoShop — Correctifs avant le lot R2 (2026-10-30)
-- ============================================================================
-- 1. Paramètres de la plateforme : certains paramètres sont stockés en
--    valeur nue (`true`, `false`), pas en objet (`{"valeur": …}`) — ainsi
--    `code_compte_obligatoire` et `controle_sessions` (REG-22), lus tels
--    quels par le serveur. `definir_parametre_global` (1583) les refusait ;
--    il accepte désormais toute valeur qui garde la forme et le type de
--    l'actuelle.
--
-- 2. Administrateur de contenu pédagogique (cahier 4.4) : l'Administrateur
--    GSG le désigne depuis l'application, par l'adresse d'un compte déjà
--    inscrit, et peut le retirer. Le compte doit être dédié : ni membre
--    d'une école, ni parent relié, ni élève (séparation des pouvoirs, 34.1).
-- ============================================================================

create or replace function public.definir_parametre_global(p_cle text, p_valeur jsonb)
returns public.parametres_globaux
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ancienne jsonb;
  v_ligne public.parametres_globaux;
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_valeur is null or jsonb_typeof(p_valeur) = 'null' then
    raise exception 'VALEUR_INVALIDE' using errcode = '22023';
  end if;

  select valeur into v_ancienne from public.parametres_globaux where cle = p_cle for update;
  if not found then
    raise exception 'PARAMETRE_INCONNU' using errcode = '22023';
  end if;

  -- Même forme (objet, nombre, texte, oui/non, liste) que l'actuelle.
  if jsonb_typeof(v_ancienne) <> jsonb_typeof(p_valeur) then
    raise exception 'TYPE_INVALIDE' using errcode = '22023';
  end if;
  -- Objet {"valeur": x} : x garde son type (un tarif reste un nombre).
  if jsonb_typeof(v_ancienne) = 'object' and v_ancienne ? 'valeur' and p_valeur ? 'valeur'
     and jsonb_typeof(v_ancienne -> 'valeur') <> jsonb_typeof(p_valeur -> 'valeur') then
    raise exception 'TYPE_INVALIDE' using errcode = '22023';
  end if;

  update public.parametres_globaux
     set valeur = p_valeur, updated_at = now()
   where cle = p_cle
  returning * into v_ligne;

  insert into public.historique_parametres_globaux (cle, ancienne_valeur, nouvelle_valeur, modifie_par)
  values (p_cle, v_ancienne, p_valeur, auth.uid());

  return v_ligne;
end;
$$;

-- ---------------------------------------------------------------------------
-- Administrateurs de contenu pédagogique
-- ---------------------------------------------------------------------------
create or replace function public.admins_contenu()
returns table (profile_id uuid, prenom text, nom text, courriel text)
language plpgsql stable security definer set search_path = public, auth
as $$
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return query
    select p.id, p.prenom, p.nom, u.email::text
      from public.profiles p
      join auth.users u on u.id = p.id
     where p.role_racine = 'admin_contenu' and p.deleted_at is null
     order by p.nom, p.prenom;
end;
$$;

create or replace function public.designer_admin_contenu(p_courriel text)
returns uuid
language plpgsql security definer set search_path = public, auth
as $$
declare
  v_id uuid;
  v_role public.role_racine;
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  select u.id into v_id from auth.users u
   where lower(u.email) = lower(btrim(p_courriel))
   limit 1;
  if v_id is null then
    raise exception 'COMPTE_INTROUVABLE' using errcode = '22023';
  end if;

  select role_racine into v_role from public.profiles where id = v_id and deleted_at is null for update;
  if not found then
    raise exception 'COMPTE_INTROUVABLE' using errcode = '22023';
  end if;
  if v_role = 'admin_contenu' then
    return v_id;                                   -- déjà désigné
  end if;
  if v_role is not null and v_role not in ('eleve', 'parent') then
    raise exception 'COMPTE_DEJA_UTILISE' using errcode = '22023';
  end if;
  if exists (select 1 from public.etablissements_membres where profile_id = v_id and actif)
     or exists (select 1 from public.relations_parent_eleve where parent_profile_id = v_id)
     or exists (select 1 from public.fiches_eleves where profile_id = v_id) then
    raise exception 'COMPTE_DEJA_UTILISE' using errcode = '22023';
  end if;

  update public.profiles set role_racine = 'admin_contenu' where id = v_id;
  return v_id;
end;
$$;

create or replace function public.retirer_admin_contenu(p_profile uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  -- Sans rôle, le compte choisira Élève ou Parent à sa prochaine connexion.
  update public.profiles set role_racine = null
   where id = p_profile and role_racine = 'admin_contenu';
end;
$$;

revoke all on function public.admins_contenu() from public, anon;
revoke all on function public.designer_admin_contenu(text) from public, anon;
revoke all on function public.retirer_admin_contenu(uuid) from public, anon;
grant execute on function public.admins_contenu() to authenticated;
grant execute on function public.designer_admin_contenu(text) to authenticated;
grant execute on function public.retirer_admin_contenu(uuid) to authenticated;
