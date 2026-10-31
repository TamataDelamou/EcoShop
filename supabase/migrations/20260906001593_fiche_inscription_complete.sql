-- ============================================================================
-- EcoShop — REG-39 : fiche d'inscription complète.
--
-- Retour du test sur téléphone (2026-10-31) : l'inscription ne demandait que
-- le nom, le prénom, la date de naissance, le sexe et la classe. Il manquait :
--   • le téléphone de l'élève (surtout à partir du secondaire) ;
--   • les parents, avec leur téléphone ;
--   • le tuteur (qui peut être l'un des parents) ;
--   • la photo de l'élève ;
--   • la situation de handicap (oui / non, précision) ;
--   • le quartier et l'école d'origine ;
--   • le matricule national attribué par l'État guinéen (champ réservé aux
--     écoles de Guinée dans l'application).
--
-- Les colonnes nom_pere, nom_mere, quartier, personne_urgence_* existent
-- déjà (M5) ; on ajoute le reste. L'inscription se fait en une seule
-- transaction : creer_inscription_eleve_complete.
-- ============================================================================

alter table public.fiches_eleves add column if not exists telephone_eleve text;
alter table public.fiches_eleves add column if not exists telephone_pere text;
alter table public.fiches_eleves add column if not exists telephone_mere text;
alter table public.fiches_eleves add column if not exists profession_pere text;
alter table public.fiches_eleves add column if not exists profession_mere text;
alter table public.fiches_eleves add column if not exists tuteur_nom text;
alter table public.fiches_eleves add column if not exists tuteur_lien text;
alter table public.fiches_eleves add column if not exists tuteur_telephone text;
alter table public.fiches_eleves add column if not exists situation_handicap boolean not null default false;
alter table public.fiches_eleves add column if not exists handicap_precision text;
alter table public.fiches_eleves add column if not exists ecole_origine text;
alter table public.fiches_eleves add column if not exists matricule_national text;
alter table public.fiches_eleves add column if not exists photo_chemin text;

-- Lien du tuteur : père, mère ou autre (oncle, tante, grand-parent…).
alter table public.fiches_eleves drop constraint if exists fiches_tuteur_lien_valide;
alter table public.fiches_eleves add constraint fiches_tuteur_lien_valide
  check (tuteur_lien is null or tuteur_lien in ('pere', 'mere', 'autre'));

-- Recherche par matricule national (transferts, examens). Pas d'unicité :
-- un même élève a une fiche par école fréquentée.
create index if not exists idx_fiches_matricule_national
  on public.fiches_eleves (matricule_national) where matricule_national is not null and deleted_at is null;

comment on column public.fiches_eleves.matricule_national is
  'REG-39 : matricule attribué par l''État (Guinée) — distinct du matricule de l''école.';

-- ---------------------------------------------------------------------------
-- Inscription complète, en une transaction
-- ---------------------------------------------------------------------------
-- p_eleve : objet JSON, toutes les clés facultatives sauf nom, prenom,
-- date_naissance (AAAA-MM-JJ). Clés reconnues : sexe, lieu_naissance,
-- nationalite, telephone_eleve, nom_pere, telephone_pere, profession_pere,
-- nom_mere, telephone_mere, profession_mere, tuteur_lien, tuteur_nom,
-- tuteur_telephone, situation_handicap, handicap_precision, quartier,
-- ecole_origine, matricule_national, personne_urgence_nom,
-- personne_urgence_telephone.
create or replace function public.creer_inscription_eleve_complete(
  p_etablissement uuid,
  p_classe_id uuid,
  p_annee_scolaire_id uuid,
  p_eleve jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fiche uuid;
  v_lien text := nullif(trim(p_eleve->>'tuteur_lien'), '');
  v_tuteur_nom text := nullif(trim(p_eleve->>'tuteur_nom'), '');
  v_tuteur_tel text := nullif(trim(p_eleve->>'tuteur_telephone'), '');
begin
  if nullif(trim(p_eleve->>'nom'), '') is null
     or nullif(trim(p_eleve->>'prenom'), '') is null
     or nullif(p_eleve->>'date_naissance', '') is null then
    raise exception 'CHAMPS_OBLIGATOIRES' using errcode = '22023';
  end if;

  -- Même contrôle d'accès, même matricule d'école que l'inscription simple.
  v_fiche := public.creer_inscription_nouvel_eleve(
    p_etablissement,
    trim(p_eleve->>'nom'),
    trim(p_eleve->>'prenom'),
    (p_eleve->>'date_naissance')::date,
    p_classe_id,
    p_annee_scolaire_id,
    nullif(p_eleve->>'sexe', '')
  );

  -- Tuteur = père ou mère : son nom et son téléphone sont repris.
  if v_lien = 'pere' then
    v_tuteur_nom := coalesce(v_tuteur_nom, nullif(trim(p_eleve->>'nom_pere'), ''));
    v_tuteur_tel := coalesce(v_tuteur_tel, nullif(trim(p_eleve->>'telephone_pere'), ''));
  elsif v_lien = 'mere' then
    v_tuteur_nom := coalesce(v_tuteur_nom, nullif(trim(p_eleve->>'nom_mere'), ''));
    v_tuteur_tel := coalesce(v_tuteur_tel, nullif(trim(p_eleve->>'telephone_mere'), ''));
  end if;

  update public.fiches_eleves set
    lieu_naissance = nullif(trim(p_eleve->>'lieu_naissance'), ''),
    nationalite = nullif(trim(p_eleve->>'nationalite'), ''),
    telephone_eleve = nullif(trim(p_eleve->>'telephone_eleve'), ''),
    nom_pere = nullif(trim(p_eleve->>'nom_pere'), ''),
    telephone_pere = nullif(trim(p_eleve->>'telephone_pere'), ''),
    profession_pere = nullif(trim(p_eleve->>'profession_pere'), ''),
    nom_mere = nullif(trim(p_eleve->>'nom_mere'), ''),
    telephone_mere = nullif(trim(p_eleve->>'telephone_mere'), ''),
    profession_mere = nullif(trim(p_eleve->>'profession_mere'), ''),
    tuteur_lien = v_lien,
    tuteur_nom = v_tuteur_nom,
    tuteur_telephone = v_tuteur_tel,
    situation_handicap = coalesce((p_eleve->>'situation_handicap')::boolean, false),
    handicap_precision = case when coalesce((p_eleve->>'situation_handicap')::boolean, false)
                              then nullif(trim(p_eleve->>'handicap_precision'), '') end,
    quartier = nullif(trim(p_eleve->>'quartier'), ''),
    ecole_origine = nullif(trim(p_eleve->>'ecole_origine'), ''),
    matricule_national = nullif(upper(trim(p_eleve->>'matricule_national')), ''),
    -- Personne à prévenir : le tuteur par défaut.
    personne_urgence_nom = coalesce(nullif(trim(p_eleve->>'personne_urgence_nom'), ''), v_tuteur_nom),
    personne_urgence_telephone = coalesce(nullif(trim(p_eleve->>'personne_urgence_telephone'), ''), v_tuteur_tel)
  where id = v_fiche;

  return v_fiche;
end;
$$;

revoke all on function public.creer_inscription_eleve_complete(uuid, uuid, uuid, jsonb) from public, anon;
grant execute on function public.creer_inscription_eleve_complete(uuid, uuid, uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Photo de l'élève : bucket privé, dossier de l'école
-- ---------------------------------------------------------------------------
-- Chemin : <etablissement_id>/<fiche_id>/photo-<horodatage>.jpg
-- Écriture : direction ou poste qui gère les inscriptions de l'école.
-- Lecture : membres actifs de l'école, l'élève lui-même, ses parents liés.
create or replace function public.peut_ecrire_photo_eleve(p_nom_objet text)
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
  return coalesce(public.est_direction(v_etab), false)
      or coalesce(public.a_permission(v_etab, 'scolarite.inscription.gerer'), false);
end;
$$;

create or replace function public.peut_voir_photo_eleve(p_nom_objet text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_etab uuid;
  v_fiche uuid;
begin
  begin
    v_etab := split_part(p_nom_objet, '/', 1)::uuid;
    v_fiche := split_part(p_nom_objet, '/', 2)::uuid;
  exception when others then
    return false;
  end;
  return coalesce(public.est_admin_gsg(), false)
    or exists (select 1 from public.etablissements_membres m
                where m.etablissement_id = v_etab and m.profile_id = auth.uid()
                  and m.actif and m.deleted_at is null
                  and m.role_dans_etablissement in ('direction', 'enseignant', 'personnel'))
    or exists (select 1 from public.fiches_eleves f
                where f.id = v_fiche and f.profile_id = auth.uid() and f.deleted_at is null)
    or exists (select 1 from public.relations_parent_eleve r
                where r.fiche_eleve_id = v_fiche and r.parent_profile_id = auth.uid()
                  and r.statut = 'confirmee' and r.deleted_at is null);
end;
$$;

grant execute on function public.peut_ecrire_photo_eleve(text), public.peut_voir_photo_eleve(text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos-eleves', 'photos-eleves', false, 524288, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists photos_eleves_select on storage.objects;
create policy photos_eleves_select on storage.objects
  for select to authenticated
  using (bucket_id = 'photos-eleves' and public.peut_voir_photo_eleve(name));

drop policy if exists photos_eleves_insert on storage.objects;
create policy photos_eleves_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'photos-eleves' and public.peut_ecrire_photo_eleve(name));

drop policy if exists photos_eleves_update on storage.objects;
create policy photos_eleves_update on storage.objects
  for update to authenticated
  using (bucket_id = 'photos-eleves' and public.peut_ecrire_photo_eleve(name))
  with check (bucket_id = 'photos-eleves' and public.peut_ecrire_photo_eleve(name));

drop policy if exists photos_eleves_delete on storage.objects;
create policy photos_eleves_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'photos-eleves' and public.peut_ecrire_photo_eleve(name));

-- Enregistre le chemin de la photo sur la fiche (dossier de son école).
create or replace function public.definir_photo_eleve(p_fiche uuid, p_chemin text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_etab uuid;
  v_chemin text := nullif(trim(p_chemin), '');
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = p_fiche and deleted_at is null;
  if v_etab is null then
    raise exception 'FICHE_INTROUVABLE' using errcode = '23514';
  end if;
  if not (coalesce(public.est_direction(v_etab), false)
          or coalesce(public.a_permission(v_etab, 'scolarite.inscription.gerer'), false)) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if v_chemin is not null and v_chemin not like v_etab::text || '/' || p_fiche::text || '/%' then
    raise exception 'PHOTO_HORS_DOSSIER' using errcode = '22023';
  end if;
  update public.fiches_eleves set photo_chemin = v_chemin where id = p_fiche;
end;
$$;

revoke all on function public.definir_photo_eleve(uuid, text) from public, anon;
grant execute on function public.definir_photo_eleve(uuid, text) to authenticated;
