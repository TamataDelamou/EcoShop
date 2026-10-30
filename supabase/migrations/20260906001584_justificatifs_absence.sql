-- ============================================================================
-- EcoShop — REG-36 : le parent justifie une absence depuis l'application
-- ============================================================================
-- Modèle de Pronote (espace parents : « Justifier » une absence passée,
-- « Prévenir » d'une absence à venir) : le parent — ou l'élève lui-même —
-- choisit un motif, ajoute s'il le veut un commentaire et une pièce (photo
-- du certificat), et la vie scolaire accepte ou refuse. Rien n'est
-- « justifié » sans la décision de l'école.
--
-- Acceptée : les absences et retards de l'élève sur la période deviennent
-- justifiés, y compris ceux saisis après coup (absence annoncée à l'avance).
-- Droit de décision : Direction ou poste de l'école portant
-- `scolarite.presence.gerer` (jamais l'Administrateur GSG, voir 1582).
-- Identifiant tiré sur le téléphone : un dépôt fait sans réseau n'est jamais
-- enregistré deux fois (REG-35 lot 4).
-- ============================================================================

do $$ begin
  create type public.statut_justificatif as enum ('depose', 'accepte', 'refuse');
exception when duplicate_object then null; end $$;

create table if not exists public.justificatifs_absence (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  date_debut date not null,
  date_fin date not null,
  motif text not null,
  commentaire text,
  piece_chemin text,
  depose_par uuid not null default auth.uid() references public.profiles (id) on delete set null,
  depose_le timestamptz not null default now(),
  statut public.statut_justificatif not null default 'depose',
  traite_par uuid references public.profiles (id) on delete set null,
  traite_le timestamptz,
  motif_refus text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint justificatifs_periode check (date_fin >= date_debut and date_fin - date_debut <= 60),
  constraint justificatifs_motif check (motif in ('maladie', 'rendez_vous_medical', 'raison_familiale', 'transport', 'autre')),
  constraint justificatifs_commentaire check (commentaire is null or char_length(commentaire) <= 500)
);

create index if not exists idx_justificatifs_fiche on public.justificatifs_absence (fiche_eleve_id, date_debut desc);
create index if not exists idx_justificatifs_ecole on public.justificatifs_absence (etablissement_id, statut, depose_le desc);

drop trigger if exists justificatifs_set_updated_at on public.justificatifs_absence;
create trigger justificatifs_set_updated_at before update on public.justificatifs_absence
  for each row execute function public.set_updated_at();

-- Lecture d'avance et synchronisation par différences (REG-35 lot 3).
drop trigger if exists trg_journal_portees on public.justificatifs_absence;
create trigger trg_journal_portees after insert or update or delete on public.justificatifs_absence
  for each row execute function public.tg_journal_portees('fiche:fiche_eleve_id');

-- Qui dépose pour une fiche : son parent confirmé, ou l'élève lui-même.
create or replace function public.peut_justifier_pour(p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.est_parent_confirme(p_fiche)
      or exists (select 1 from public.fiches_eleves f
                 where f.id = p_fiche and f.profile_id = auth.uid() and f.deleted_at is null);
$$;
grant execute on function public.peut_justifier_pour(uuid) to authenticated;

-- Qui décide : la vie scolaire de l'école de la fiche.
create or replace function public.peut_traiter_justificatifs(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.a_permission_ecole(p_etablissement, 'scolarite.presence.gerer'), false);
$$;
grant execute on function public.peut_traiter_justificatifs(uuid) to authenticated;

alter table public.justificatifs_absence enable row level security;

drop policy if exists justificatifs_select on public.justificatifs_absence;
create policy justificatifs_select on public.justificatifs_absence
  for select to authenticated
  using (public.peut_justifier_pour(fiche_eleve_id) or public.peut_traiter_justificatifs(etablissement_id));

-- Dépôt : par la famille, pour une fiche de cette école, en attente.
drop policy if exists justificatifs_insert on public.justificatifs_absence;
create policy justificatifs_insert on public.justificatifs_absence
  for insert to authenticated
  with check (
    public.peut_justifier_pour(fiche_eleve_id)
    and depose_par = auth.uid()
    and statut = 'depose'
    and traite_par is null and traite_le is null
    and exists (select 1 from public.fiches_eleves f
                where f.id = fiche_eleve_id and f.etablissement_id = justificatifs_absence.etablissement_id)
  );

-- La famille corrige son dépôt tant qu'il n'est pas traité (jamais la
-- décision) ; la décision passe par traiter_justificatif.
drop policy if exists justificatifs_update_famille on public.justificatifs_absence;
create policy justificatifs_update_famille on public.justificatifs_absence
  for update to authenticated
  using (statut = 'depose' and depose_par = auth.uid())
  with check (statut = 'depose' and depose_par = auth.uid() and traite_par is null
              and public.peut_justifier_pour(fiche_eleve_id));

-- Absences et retards couverts par un justificatif accepté.
create or replace function public.appliquer_justificatif(p_justificatif uuid)
returns void
language sql security definer set search_path = public
as $$
  update public.presences p
     set justifie = true
    from public.justificatifs_absence j
   where j.id = p_justificatif and j.statut = 'accepte'
     and p.fiche_eleve_id = j.fiche_eleve_id
     and p.date_presence between j.date_debut and j.date_fin
     and p.statut in ('absent', 'retard') and not p.justifie and p.deleted_at is null;
  update public.retards r
     set justifie = true
    from public.justificatifs_absence j
   where j.id = p_justificatif and j.statut = 'accepte'
     and r.fiche_eleve_id = j.fiche_eleve_id
     and r.date_retard between j.date_debut and j.date_fin
     and not r.justifie and r.deleted_at is null;
$$;
revoke all on function public.appliquer_justificatif(uuid) from public, anon, authenticated;

create or replace function public.traiter_justificatif(p_id uuid, p_accepte boolean, p_motif_refus text default null)
returns public.justificatifs_absence
language plpgsql
security definer
set search_path = public
as $$
declare
  v_j public.justificatifs_absence;
begin
  select * into v_j from public.justificatifs_absence where id = p_id for update;
  if not found then
    raise exception 'JUSTIFICATIF_INTROUVABLE' using errcode = '22023';
  end if;
  if not public.peut_traiter_justificatifs(v_j.etablissement_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if v_j.statut <> 'depose' then
    -- Même décision déjà prise : rien à faire (rejeu) ; autre décision : refus.
    if (v_j.statut = 'accepte') = p_accepte then
      return v_j;
    end if;
    raise exception 'JUSTIFICATIF_DEJA_TRAITE' using errcode = '22023';
  end if;
  if not p_accepte and nullif(trim(coalesce(p_motif_refus, '')), '') is null then
    raise exception 'MOTIF_REFUS_REQUIS' using errcode = '22023';
  end if;

  update public.justificatifs_absence
     set statut = case when p_accepte then 'accepte'::public.statut_justificatif else 'refuse'::public.statut_justificatif end,
         traite_par = auth.uid(), traite_le = now(),
         motif_refus = case when p_accepte then null else trim(p_motif_refus) end
   where id = p_id
  returning * into v_j;

  if p_accepte then
    perform public.appliquer_justificatif(p_id);
  end if;
  return v_j;
end;
$$;
revoke all on function public.traiter_justificatif(uuid, boolean, text) from public, anon;
grant execute on function public.traiter_justificatif(uuid, boolean, text) to authenticated;

-- Absence annoncée à l'avance puis saisie à l'appel : justifiée d'office.
create or replace function public.tg_presence_justifiee_davance()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.statut in ('absent', 'retard') and not new.justifie and exists (
    select 1 from public.justificatifs_absence j
     where j.fiche_eleve_id = new.fiche_eleve_id and j.statut = 'accepte'
       and new.date_presence between j.date_debut and j.date_fin
  ) then
    new.justifie := true;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_presence_justifiee_davance on public.presences;
create trigger trg_presence_justifiee_davance before insert or update of statut on public.presences
  for each row execute function public.tg_presence_justifiee_davance();

-- ---------------------------------------------------------------------------
-- Pièces jointes : photo ou PDF de 2 Mo au plus, dossier = la fiche.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('justificatifs-absence', 'justificatifs-absence', false, 2097152,
        array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.fiche_du_chemin(p_nom text)
returns uuid
language plpgsql immutable
as $$
begin
  return split_part(p_nom, '/', 1)::uuid;
exception when others then
  return null;
end;
$$;

drop policy if exists justificatifs_pieces_select on storage.objects;
create policy justificatifs_pieces_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'justificatifs-absence'
    and (public.peut_justifier_pour(public.fiche_du_chemin(name))
         or public.peut_traiter_justificatifs(public.etablissement_fiche(public.fiche_du_chemin(name))))
  );

drop policy if exists justificatifs_pieces_insert on storage.objects;
create policy justificatifs_pieces_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'justificatifs-absence' and public.peut_justifier_pour(public.fiche_du_chemin(name)));
