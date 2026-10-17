-- ============================================================================
-- EcoShop — REG-07 B : identité visuelle par établissement (couleur + logo)
-- (docs/REGISTRE.md REG-07, décision du porteur de projet du 2026-10-17)
--
-- La Direction choisit la couleur principale et le logo de son école. Ils
-- s'appliquent dans l'application (charte de l'établissement) et sur les
-- documents imprimés (reçus, bulletins).
--
--   • etablissements.couleur_identite : `#RRGGBB`, contrôlée en base. La
--     lisibilité est garantie côté application : la couleur est ajustée
--     automatiquement (luminosité) pour respecter WCAG AA dans les deux modes.
--   • etablissements.logo_chemin : chemin dans le bucket public
--     `logos-etablissements`, toujours rangé sous le dossier de
--     l'établissement (`<etablissement_id>/...`).
--   • Écriture du logo : réservée à la Direction de l'établissement (ou à
--     la permission etablissement.fiche.gerer), dans SON dossier seulement ;
--     lecture publique (le logo figure sur des documents remis aux familles).
--   • definir_identite_visuelle() : seule voie d'écriture des deux colonnes.
--
-- Migration idempotente.
-- ============================================================================

alter table public.etablissements
  add column if not exists couleur_identite text,
  add column if not exists logo_chemin text;

do $$ begin
  alter table public.etablissements
    add constraint etablissements_couleur_identite_format
    check (couleur_identite is null or couleur_identite ~ '^#[0-9A-F]{6}$');
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.etablissements
    add constraint etablissements_logo_chemin_dossier
    check (logo_chemin is null or logo_chemin like id::text || '/%');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Droit de gérer l'identité d'un établissement
-- ---------------------------------------------------------------------------
create or replace function public.peut_gerer_identite_etablissement(p_etablissement_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.est_direction(p_etablissement_id), false)
      or coalesce(public.a_permission(p_etablissement_id, 'etablissement.fiche.gerer'), false)
      or coalesce(public.est_admin_gsg(), false);
$$;

-- Dossier de premier niveau d'un objet Storage = identifiant d'établissement
-- que l'appelant peut gérer. Tolère un nom mal formé (renvoie faux).
create or replace function public.dossier_logo_autorise(p_nom_objet text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_etab uuid;
begin
  begin
    v_etab := split_part(p_nom_objet, '/', 1)::uuid;
  exception when others then
    return false;
  end;
  return public.peut_gerer_identite_etablissement(v_etab);
end;
$$;

grant execute on function public.peut_gerer_identite_etablissement(uuid) to authenticated;
grant execute on function public.dossier_logo_autorise(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Bucket public des logos (≤ 1 Mo, images uniquement)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('logos-etablissements', 'logos-etablissements', true, 1048576,
        array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists logos_etablissements_insert on storage.objects;
create policy logos_etablissements_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'logos-etablissements' and public.dossier_logo_autorise(name));

drop policy if exists logos_etablissements_update on storage.objects;
create policy logos_etablissements_update on storage.objects
  for update to authenticated
  using (bucket_id = 'logos-etablissements' and public.dossier_logo_autorise(name))
  with check (bucket_id = 'logos-etablissements' and public.dossier_logo_autorise(name));

drop policy if exists logos_etablissements_delete on storage.objects;
create policy logos_etablissements_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'logos-etablissements' and public.dossier_logo_autorise(name));

-- ---------------------------------------------------------------------------
-- Seule voie d'écriture de la couleur et du logo
-- ---------------------------------------------------------------------------
create or replace function public.definir_identite_visuelle(
  p_etablissement_id uuid,
  p_couleur text,
  p_logo_chemin text
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

  update public.etablissements
     set couleur_identite = v_couleur,
         logo_chemin = v_logo,
         updated_at = now()
   where id = p_etablissement_id and deleted_at is null;
  if not found then
    raise exception 'ETABLISSEMENT_INTROUVABLE' using errcode = '22023';
  end if;
end;
$$;

revoke all on function public.definir_identite_visuelle(uuid, text, text) from public, anon;
grant execute on function public.definir_identite_visuelle(uuid, text, text) to authenticated;
