-- ============================================================================
-- EcoShop — REG-23 : slogan de l'établissement, photo de profil
-- (retour du porteur de projet, 2026-10-28)
--
--   • etablissements.slogan : devise de l'école (« Travail – Discipline –
--     Réussite »), 120 caractères au plus. Écrite par
--     definir_identite_visuelle(), avec la couleur et le logo.
--   • profiles.photo_chemin : photo de profil, rangée dans le bucket PRIVÉ
--     `photos-profils`, sous le dossier du compte (`<profile_id>/...`).
--     Chacun dépose la sienne ; la voient : le compte lui-même, les membres
--     d'une même école, l'Administrateur GSG. Lecture par URL signée.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Slogan
-- ---------------------------------------------------------------------------
alter table public.etablissements add column if not exists slogan text;

do $$ begin
  alter table public.etablissements
    add constraint etablissements_slogan_longueur
    check (slogan is null or char_length(slogan) between 2 and 120);
exception when duplicate_object then null; end $$;

-- Nouvelle signature (slogan en plus). p_slogan absent (null) : slogan
-- inchangé — les applications d'avant REG-23 n'effacent pas le slogan ;
-- chaîne vide : slogan retiré.
drop function if exists public.definir_identite_visuelle(uuid, text, text);

create or replace function public.definir_identite_visuelle(
  p_etablissement_id uuid,
  p_couleur text,
  p_logo_chemin text,
  p_slogan text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_couleur text := upper(nullif(trim(p_couleur), ''));
  v_logo text := nullif(trim(p_logo_chemin), '');
  v_slogan text := nullif(regexp_replace(trim(coalesce(p_slogan, '')), '\s+', ' ', 'g'), '');
begin
  if not public.peut_gerer_identite_etablissement(p_etablissement_id) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if v_couleur is not null and v_couleur !~ '^#[0-9A-F]{6}$' then
    raise exception 'COULEUR_INVALIDE' using errcode = '22023';
  end if;
  if v_logo is not null and v_logo not like p_etablissement_id::text || '/%' then
    raise exception 'LOGO_HORS_DOSSIER' using errcode = '22023';
  end if;
  if v_slogan is not null and char_length(v_slogan) not between 2 and 120 then
    raise exception 'SLOGAN_INVALIDE' using errcode = '22023';
  end if;

  update public.etablissements
     set couleur_identite = v_couleur,
         logo_chemin = v_logo,
         slogan = case when p_slogan is null then slogan else v_slogan end,
         updated_at = now()
   where id = p_etablissement_id and deleted_at is null;
  if not found then
    raise exception 'ETABLISSEMENT_INTROUVABLE' using errcode = '22023';
  end if;
end;
$$;

revoke all on function public.definir_identite_visuelle(uuid, text, text, text) from public, anon;
grant execute on function public.definir_identite_visuelle(uuid, text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Photo de profil
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists photo_chemin text;

do $$ begin
  alter table public.profiles
    add constraint profiles_photo_chemin_dossier
    check (photo_chemin is null or photo_chemin like id::text || '/%');
exception when duplicate_object then null; end $$;

-- Voir la photo d'un compte : soi-même, un membre actif d'une même école,
-- l'Administrateur GSG. Tolère un nom d'objet mal formé (renvoie faux).
create or replace function public.peut_voir_photo_profil(p_nom_objet text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_compte uuid;
begin
  begin
    v_compte := split_part(p_nom_objet, '/', 1)::uuid;
  exception when others then
    return false;
  end;
  if v_compte = auth.uid() or coalesce(public.est_admin_gsg(), false) then
    return true;
  end if;
  return exists (
    select 1
      from public.etablissements_membres moi
      join public.etablissements_membres lui
        on lui.etablissement_id = moi.etablissement_id
     where moi.profile_id = auth.uid() and moi.actif and moi.deleted_at is null
       and lui.profile_id = v_compte and lui.actif and lui.deleted_at is null
  );
end;
$$;
grant execute on function public.peut_voir_photo_profil(text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos-profils', 'photos-profils', false, 524288,
        array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists photos_profils_select on storage.objects;
create policy photos_profils_select on storage.objects
  for select to authenticated
  using (bucket_id = 'photos-profils' and public.peut_voir_photo_profil(name));

drop policy if exists photos_profils_insert on storage.objects;
create policy photos_profils_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'photos-profils' and split_part(name, '/', 1) = auth.uid()::text);

drop policy if exists photos_profils_update on storage.objects;
create policy photos_profils_update on storage.objects
  for update to authenticated
  using (bucket_id = 'photos-profils' and split_part(name, '/', 1) = auth.uid()::text)
  with check (bucket_id = 'photos-profils' and split_part(name, '/', 1) = auth.uid()::text);

drop policy if exists photos_profils_delete on storage.objects;
create policy photos_profils_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'photos-profils' and split_part(name, '/', 1) = auth.uid()::text);

-- Seule voie d'écriture de la colonne : son propre profil, son propre dossier.
create or replace function public.definir_photo_profil(p_chemin text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_chemin text := nullif(trim(p_chemin), '');
begin
  if auth.uid() is null then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if v_chemin is not null and v_chemin not like auth.uid()::text || '/%' then
    raise exception 'PHOTO_HORS_DOSSIER' using errcode = '22023';
  end if;
  update public.profiles
     set photo_chemin = v_chemin,
         updated_at = now()
   where id = auth.uid();
end;
$$;
revoke all on function public.definir_photo_profil(text) from public, anon;
grant execute on function public.definir_photo_profil(text) to authenticated;
