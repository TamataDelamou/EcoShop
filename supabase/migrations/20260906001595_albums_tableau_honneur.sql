-- ============================================================================
-- EcoShop — REG-39 : albums photo et tableau d'honneur.
--
-- Retour du test sur téléphone (2026-10-31) :
--   • « un espace d'albums pour chaque classe ou personnalisable, avec
--     affichage type photo » ;
--   • « un tableau d'honneur (meilleurs élèves, meilleurs professeurs…) ».
--
-- Albums : un album appartient à l'école ; il est rattaché à une classe
-- (visible des élèves et parents de cette classe et du personnel) ou à toute
-- l'école (visible de toute la communauté : personnel, élèves, parents).
-- La direction gère tous les albums ; un enseignant crée les albums de ses
-- classes (ou de toute l'école) et gère ceux qu'il a créés.
--
-- Tableau d'honneur :
--   • meilleurs élèves : calculés à partir des bulletins PUBLIÉS de la
--     période (rang 1 à 3 de chaque classe) — jamais avant la publication ;
--   • distinctions : posées par la direction (meilleur professeur, meilleur
--     élève en conduite, prix d'excellence…), pour un enseignant, un membre
--     du personnel ou un élève.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Albums
-- ---------------------------------------------------------------------------
create table if not exists public.albums (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  classe_id uuid references public.classes (id) on delete cascade,
  titre text not null check (length(trim(titre)) between 1 and 120),
  description text check (description is null or length(description) <= 500),
  couverture_chemin text,
  cree_par uuid not null default auth.uid() references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_albums_etablissement on public.albums (etablissement_id, created_at desc) where deleted_at is null;

create table if not exists public.albums_photos (
  id uuid primary key default gen_random_uuid(),
  album_id uuid not null references public.albums (id) on delete cascade,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  chemin text not null,
  legende text check (legende is null or length(legende) <= 300),
  ajoute_par uuid not null default auth.uid() references public.profiles (id),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists idx_albums_photos_album on public.albums_photos (album_id, created_at) where deleted_at is null;

drop trigger if exists albums_set_updated_at on public.albums;
create trigger albums_set_updated_at before update on public.albums
  for each row execute procedure public.set_updated_at();

-- Voir un album : personnel actif de l'école ; pour un album de classe, les
-- élèves et parents de la classe ; pour un album d'école, toute la
-- communauté de l'école.
create or replace function public.peut_voir_album(p_album uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.albums a
     where a.id = p_album and a.deleted_at is null
       and (
         coalesce(public.est_admin_gsg(), false)
         or exists (select 1 from public.etablissements_membres m
                     where m.etablissement_id = a.etablissement_id and m.profile_id = auth.uid()
                       and m.actif and m.deleted_at is null
                       and m.role_dans_etablissement in ('direction', 'enseignant', 'personnel'))
         or (a.classe_id is null and coalesce(public.concerne_etablissement(a.etablissement_id), false))
         or exists (select 1 from public.inscriptions i
                      join public.fiches_eleves f on f.id = i.fiche_eleve_id and f.deleted_at is null
                     where i.classe_id = a.classe_id and i.statut = 'active' and i.deleted_at is null
                       and (f.profile_id = auth.uid()
                            or exists (select 1 from public.relations_parent_eleve r
                                        where r.fiche_eleve_id = f.id and r.parent_profile_id = auth.uid()
                                          and r.statut = 'confirmee' and r.autorise and r.deleted_at is null)))
       )
  );
$$;

-- Gérer (ajouter des photos, modifier, retirer) : direction, auteur de
-- l'album, ou enseignant de la classe de l'album.
create or replace function public.peut_gerer_album(p_album uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.albums a
     where a.id = p_album and a.deleted_at is null
       and (
         coalesce(public.est_direction(a.etablissement_id), false)
         or a.cree_par = auth.uid()
         or (a.classe_id is not null and exists (
               select 1 from public.affectations_enseignants x
                where x.classe_id = a.classe_id and x.enseignant_profile_id = auth.uid() and x.deleted_at is null))
       )
  );
$$;

-- Créer : direction ; enseignant de l'école (album d'école, ou d'une classe
-- qu'il a).
create or replace function public.peut_creer_album(p_etablissement uuid, p_classe uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.est_direction(p_etablissement), false)
      or (exists (select 1 from public.etablissements_membres m
                   where m.etablissement_id = p_etablissement and m.profile_id = auth.uid()
                     and m.actif and m.deleted_at is null and m.role_dans_etablissement = 'enseignant')
          and (p_classe is null or exists (
                select 1 from public.affectations_enseignants x
                 where x.classe_id = p_classe and x.enseignant_profile_id = auth.uid() and x.deleted_at is null)));
$$;

grant execute on function public.peut_voir_album(uuid), public.peut_gerer_album(uuid),
  public.peut_creer_album(uuid, uuid) to authenticated;

alter table public.albums enable row level security;
alter table public.albums_photos enable row level security;

drop policy if exists albums_select on public.albums;
create policy albums_select on public.albums for select to authenticated
  using (deleted_at is null and public.peut_voir_album(id));

drop policy if exists albums_insert on public.albums;
create policy albums_insert on public.albums for insert to authenticated
  with check (cree_par = auth.uid() and public.peut_creer_album(etablissement_id, classe_id)
              and (classe_id is null or exists (select 1 from public.classes c
                                                 where c.id = classe_id and c.etablissement_id = albums.etablissement_id)));

drop policy if exists albums_update on public.albums;
create policy albums_update on public.albums for update to authenticated
  using (public.peut_gerer_album(id))
  with check (public.peut_creer_album(etablissement_id, classe_id) or public.est_direction(etablissement_id)
              or cree_par = auth.uid());

drop policy if exists albums_photos_select on public.albums_photos;
create policy albums_photos_select on public.albums_photos for select to authenticated
  using (deleted_at is null and public.peut_voir_album(album_id));

drop policy if exists albums_photos_insert on public.albums_photos;
create policy albums_photos_insert on public.albums_photos for insert to authenticated
  with check (ajoute_par = auth.uid() and public.peut_gerer_album(album_id)
              and exists (select 1 from public.albums a where a.id = album_id and a.etablissement_id = albums_photos.etablissement_id));

drop policy if exists albums_photos_update on public.albums_photos;
create policy albums_photos_update on public.albums_photos for update to authenticated
  using (public.peut_gerer_album(album_id))
  with check (public.peut_gerer_album(album_id));

-- Stockage : <etablissement_id>/<album_id>/<photo>.jpg
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('albums', 'albums', false, 1048576, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.album_du_chemin(p_nom_objet text)
returns uuid
language plpgsql
immutable
as $$
begin
  return split_part(p_nom_objet, '/', 2)::uuid;
exception when others then
  return null;
end;
$$;

drop policy if exists albums_objets_select on storage.objects;
create policy albums_objets_select on storage.objects for select to authenticated
  using (bucket_id = 'albums' and public.peut_voir_album(public.album_du_chemin(name)));

drop policy if exists albums_objets_insert on storage.objects;
create policy albums_objets_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'albums' and public.peut_gerer_album(public.album_du_chemin(name)));

drop policy if exists albums_objets_delete on storage.objects;
create policy albums_objets_delete on storage.objects for delete to authenticated
  using (bucket_id = 'albums' and public.peut_gerer_album(public.album_du_chemin(name)));

-- Liste des albums visibles d'une école, avec le nombre de photos.
create or replace function public.albums_etablissement(p_etablissement uuid)
returns table (id uuid, classe_id uuid, classe_nom text, titre text, description text,
               couverture_chemin text, nombre_photos integer, cree_par uuid, peut_gerer boolean, created_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select a.id, a.classe_id, c.nom, a.titre, a.description,
         coalesce(a.couverture_chemin,
                  (select p.chemin from public.albums_photos p
                    where p.album_id = a.id and p.deleted_at is null order by p.created_at limit 1)),
         (select count(*)::int from public.albums_photos p where p.album_id = a.id and p.deleted_at is null),
         a.cree_par, public.peut_gerer_album(a.id), a.created_at
    from public.albums a
    left join public.classes c on c.id = a.classe_id
   where a.etablissement_id = p_etablissement and a.deleted_at is null
     and public.peut_voir_album(a.id)
   order by a.created_at desc;
$$;

revoke all on function public.albums_etablissement(uuid) from public, anon;
grant execute on function public.albums_etablissement(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Tableau d'honneur
-- ---------------------------------------------------------------------------
create table if not exists public.distinctions (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  periode_id uuid references public.periodes_scolaires (id) on delete set null,
  categorie text not null check (categorie in ('eleve', 'enseignant', 'personnel')),
  fiche_eleve_id uuid references public.fiches_eleves (id) on delete cascade,
  profile_id uuid references public.profiles (id) on delete cascade,
  titre text not null check (length(trim(titre)) between 1 and 120),
  motif text check (motif is null or length(motif) <= 500),
  cree_par uuid not null default auth.uid() references public.profiles (id),
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint distinctions_personne check (
    (categorie = 'eleve' and fiche_eleve_id is not null) or (categorie <> 'eleve' and profile_id is not null))
);

create index if not exists idx_distinctions_annee on public.distinctions (etablissement_id, annee_scolaire_id) where deleted_at is null;

alter table public.distinctions enable row level security;

drop policy if exists distinctions_select on public.distinctions;
create policy distinctions_select on public.distinctions for select to authenticated
  using (deleted_at is null and public.concerne_etablissement(etablissement_id));

drop policy if exists distinctions_ecriture on public.distinctions;
create policy distinctions_ecriture on public.distinctions for all to authenticated
  using (public.est_direction(etablissement_id))
  with check (public.est_direction(etablissement_id) and cree_par = auth.uid());

-- Tableau d'honneur d'une période : 3 premiers de chaque classe (bulletins
-- publiés), puis les distinctions de l'année (de la période, ou sans
-- période). Visible de toute la communauté de l'école.
create or replace function public.tableau_honneur(p_etablissement uuid, p_annee uuid, p_periode uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_eleves jsonb;
  v_distinctions jsonb;
begin
  if not coalesce(public.concerne_etablissement(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(x order by x->>'classe_nom', (x->>'rang')::int), '[]'::jsonb) into v_eleves
    from (
      select jsonb_build_object(
               'classe_id', c.id, 'classe_nom', c.nom,
               'fiche_id', f.id, 'prenom', f.prenom, 'nom', f.nom, 'photo_chemin', f.photo_chemin,
               'moyenne', (b.contenu->>'moyenne_generale')::numeric,
               'rang', (b.contenu->>'rang')::int,
               'effectif', (b.contenu->>'effectif_classe')::int) as x
        from public.bulletins b
        join public.classes c on c.id = b.classe_id
        join public.fiches_eleves f on f.id = b.fiche_eleve_id and f.deleted_at is null
       where b.etablissement_id = p_etablissement
         and b.annee_scolaire_id = p_annee
         and b.statut = 'publie' and b.deleted_at is null
         and b.periode_id is not distinct from p_periode
         and (b.contenu->>'rang') ~ '^[0-9]+$'
         and (b.contenu->>'rang')::int between 1 and 3
    ) t;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', d.id, 'categorie', d.categorie, 'titre', d.titre, 'motif', d.motif,
           'periode_id', d.periode_id,
           'nom', coalesce(trim(f.prenom || ' ' || f.nom), trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, ''))),
           'photo_chemin', coalesce(f.photo_chemin, p.photo_chemin),
           'fiche_id', d.fiche_eleve_id, 'profile_id', d.profile_id
         ) order by d.created_at desc), '[]'::jsonb) into v_distinctions
    from public.distinctions d
    left join public.fiches_eleves f on f.id = d.fiche_eleve_id
    left join public.profiles p on p.id = d.profile_id
   where d.etablissement_id = p_etablissement and d.annee_scolaire_id = p_annee and d.deleted_at is null
     and (p_periode is null or d.periode_id is null or d.periode_id = p_periode);

  return jsonb_build_object('eleves', v_eleves, 'distinctions', v_distinctions);
end;
$$;

revoke all on function public.tableau_honneur(uuid, uuid, uuid) from public, anon;
grant execute on function public.tableau_honneur(uuid, uuid, uuid) to authenticated;
