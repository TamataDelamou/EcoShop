-- ============================================================================
-- EcoShop — REG-04 : demande de création d'un nouvel établissement
-- (cahier v4.1 §5.3 « Demande de création d'un nouvel établissement » et
--  §30.1 « Validation des demandes » ; dette tracée le 2026-09-17,
--  docs/AUDIT_ECOSHOP_FLUTTER.md, docs/REGISTRE.md REG-04)
--
-- Jusqu'ici, un établissement ne pouvait être créé que par insertion SQL
-- directe : aucun client réel ne pouvait être accueilli. Parcours livré :
--
--   1. Le fondateur (compte neuf, rôle pas encore choisi — ou Direction
--      existante qui ouvre une nouvelle école) soumet une demande :
--      soumettre_demande_etablissement(). Une seule demande en cours par
--      compte. Le rôle Direction n'est JAMAIS auto-attribué (§5.3).
--   2. L'administrateur GSG la traite : traiter_demande_etablissement().
--      Acceptée => l'établissement est créé (devise et langue du pays
--      pédagogique choisi, fuseau du pays), le demandeur devient Direction,
--      est rattaché à l'établissement et celui-ci devient son établissement
--      actif. Refusée => motif obligatoire, visible du demandeur, qui peut
--      soumettre une nouvelle demande corrigée.
--   3. demandes_etablissement_a_traiter() alimente l'écran du backoffice.
--
-- Hors périmètre (registre) : le courriel automatique de confirmation de
-- soumission (§5.3) — aucune infrastructure d'envoi de courriel n'existe
-- encore dans ce dépôt.
--
-- Migration idempotente.
-- ============================================================================

create table if not exists public.demandes_etablissement (
  id uuid primary key default gen_random_uuid(),
  demandeur_id uuid not null references public.profiles (id) on delete cascade,
  nom_etablissement text not null check (char_length(trim(nom_etablissement)) between 3 and 120),
  pays_code text not null references public.pays_pedagogiques (code_iso),
  ville text not null check (char_length(trim(ville)) between 2 and 80),
  adresse text,
  telephone text not null check (telephone ~ '^\+?[0-9 ]{8,20}$'),
  email text check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  effectif_estime integer check (effectif_estime is null or effectif_estime between 0 and 100000),
  numero_autorisation text,
  message text check (message is null or char_length(message) <= 1000),
  statut text not null default 'en_attente' check (statut in ('en_attente', 'acceptee', 'refusee')),
  motif_refus text,
  traitee_par uuid references public.profiles (id),
  traitee_le timestamptz,
  etablissement_id uuid references public.etablissements (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint demandes_etab_refus_motive check (statut <> 'refusee' or char_length(trim(coalesce(motif_refus, ''))) > 0)
);

create unique index if not exists idx_demandes_etab_une_en_cours
  on public.demandes_etablissement (demandeur_id)
  where statut = 'en_attente';

drop trigger if exists demandes_etab_set_updated_at on public.demandes_etablissement;
create trigger demandes_etab_set_updated_at
  before update on public.demandes_etablissement
  for each row execute function public.set_updated_at();

alter table public.demandes_etablissement enable row level security;

-- Lecture : le demandeur voit ses demandes, l'admin GSG toutes.
-- Aucune écriture directe : RPC uniquement.
drop policy if exists demandes_etab_select on public.demandes_etablissement;
create policy demandes_etab_select on public.demandes_etablissement
  for select using (demandeur_id = auth.uid() or coalesce(public.est_admin_gsg(), false));

revoke insert, update, delete on public.demandes_etablissement from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. Soumission par le fondateur
-- ---------------------------------------------------------------------------
create or replace function public.soumettre_demande_etablissement(
  p_nom text,
  p_pays_code text,
  p_ville text,
  p_telephone text,
  p_adresse text default null,
  p_email text default null,
  p_effectif_estime integer default null,
  p_numero_autorisation text default null,
  p_message text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role public.role_racine;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUISE' using errcode = '42501';
  end if;

  select role_racine into v_role from public.profiles where id = v_uid and deleted_at is null;
  -- Compte neuf (rôle pas encore choisi) ou Direction qui ouvre une école.
  if v_role is not null and v_role <> 'direction' then
    raise exception 'ROLE_INCOMPATIBLE' using errcode = '42501';
  end if;

  if exists (select 1 from public.demandes_etablissement
             where demandeur_id = v_uid and statut = 'en_attente') then
    raise exception 'DEMANDE_DEJA_EN_COURS' using errcode = '55000';
  end if;

  if not exists (select 1 from public.pays_pedagogiques where code_iso = upper(trim(p_pays_code))) then
    raise exception 'PAYS_INCONNU' using errcode = '22023';
  end if;

  insert into public.demandes_etablissement (
    demandeur_id, nom_etablissement, pays_code, ville, adresse, telephone, email,
    effectif_estime, numero_autorisation, message
  ) values (
    v_uid, trim(p_nom), upper(trim(p_pays_code)), trim(p_ville), nullif(trim(p_adresse), ''),
    regexp_replace(trim(p_telephone), '\s+', ' ', 'g'), nullif(lower(trim(p_email)), ''),
    p_effectif_estime, nullif(trim(p_numero_autorisation), ''), nullif(trim(p_message), '')
  )
  returning id into v_id;

  return v_id;
exception
  when check_violation then
    raise exception 'DEMANDE_INVALIDE' using errcode = '22023';
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Traitement par l'administrateur GSG
-- ---------------------------------------------------------------------------
create or replace function public.slug_etablissement(p_nom text, p_suffixe text)
returns text
language sql
immutable
set search_path = public
as $$
  select trim(both '-' from regexp_replace(
           translate(lower(p_nom),
                     'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ',
                     'aaaaaaceeeeiiiinooooouuuuyy'),
           '[^a-z0-9]+', '-', 'g'))
         || '-' || p_suffixe;
$$;

create or replace function public.traiter_demande_etablissement(
  p_demande_id uuid,
  p_decision text,          -- 'acceptee' | 'refusee'
  p_motif text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_admin uuid := auth.uid();
  d public.demandes_etablissement;
  v_pays public.pays_pedagogiques;
  v_role public.role_racine;
  v_etab uuid;
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if p_decision not in ('acceptee', 'refusee') then
    raise exception 'DECISION_INVALIDE' using errcode = '22023';
  end if;

  select * into d from public.demandes_etablissement where id = p_demande_id for update;
  if d.id is null then
    raise exception 'DEMANDE_INTROUVABLE' using errcode = '22023';
  end if;
  if d.statut <> 'en_attente' then
    raise exception 'DEMANDE_DEJA_TRAITEE' using errcode = '55000';
  end if;

  if p_decision = 'refusee' then
    if char_length(trim(coalesce(p_motif, ''))) = 0 then
      raise exception 'MOTIF_REQUIS' using errcode = '22023';
    end if;
    update public.demandes_etablissement
       set statut = 'refusee', motif_refus = trim(p_motif), traitee_par = v_admin, traitee_le = now()
     where id = d.id;
    return jsonb_build_object('statut', 'refusee');
  end if;

  -- Le demandeur a pu changer de rôle entre-temps (invitation acceptée…).
  select role_racine into v_role from public.profiles where id = d.demandeur_id and deleted_at is null;
  if not found or (v_role is not null and v_role <> 'direction') then
    raise exception 'ROLE_INCOMPATIBLE' using errcode = '55000';
  end if;

  select * into v_pays from public.pays_pedagogiques where code_iso = d.pays_code;

  insert into public.etablissements (nom, slug, pays_code, ville, devise_code, langue_code, fuseau_horaire, statut)
  values (
    d.nom_etablissement,
    public.slug_etablissement(d.nom_etablissement, substr(replace(d.id::text, '-', ''), 1, 6)),
    d.pays_code,
    d.ville,
    coalesce(v_pays.devise_code, 'GNF'),
    coalesce(v_pays.langue_enseignement_principale, 'fr'),
    case d.pays_code
      when 'GN' then 'Africa/Conakry'  when 'SN' then 'Africa/Dakar'
      when 'CI' then 'Africa/Abidjan'  when 'ML' then 'Africa/Bamako'
      when 'BF' then 'Africa/Ouagadougou' when 'NE' then 'Africa/Niamey'
      when 'TG' then 'Africa/Lome'     when 'BJ' then 'Africa/Porto-Novo'
      when 'GH' then 'Africa/Accra'    when 'NG' then 'Africa/Lagos'
      when 'SL' then 'Africa/Freetown' when 'LR' then 'Africa/Monrovia'
      when 'GM' then 'Africa/Banjul'   when 'GW' then 'Africa/Bissau'
      when 'CV' then 'Atlantic/Cape_Verde' when 'MR' then 'Africa/Nouakchott'
      else 'Africa/Conakry'
    end,
    'actif'
  )
  returning id into v_etab;

  -- Le demandeur devient Direction (jamais auto-attribué : seule cette
  -- validation GSG le fait) et est rattaché à son établissement.
  update public.profiles
     set role_racine = 'direction'
   where id = d.demandeur_id and role_racine is null;

  insert into public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement, actif)
  values (d.demandeur_id, v_etab, 'direction', true)
  on conflict (profile_id, etablissement_id) do update set role_dans_etablissement = 'direction', actif = true;

  update public.profiles
     set etablissement_actif_id = v_etab
   where id = d.demandeur_id and etablissement_actif_id is null;

  update public.demandes_etablissement
     set statut = 'acceptee', traitee_par = v_admin, traitee_le = now(), etablissement_id = v_etab
   where id = d.id;

  return jsonb_build_object('statut', 'acceptee', 'etablissement_id', v_etab);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. File du backoffice (admin GSG) — avec l'identité du demandeur
-- ---------------------------------------------------------------------------
create or replace function public.demandes_etablissement_a_traiter()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_resultat jsonb;
begin
  if not coalesce(public.est_admin_gsg(), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', d.id,
           'nom_etablissement', d.nom_etablissement,
           'pays_code', d.pays_code,
           'pays_nom', pp.nom,
           'ville', d.ville,
           'adresse', d.adresse,
           'telephone', d.telephone,
           'email', d.email,
           'effectif_estime', d.effectif_estime,
           'numero_autorisation', d.numero_autorisation,
           'message', d.message,
           'created_at', d.created_at,
           'demandeur_nom', nullif(trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')), ''),
           'demandeur_identifiant', p.identifiant_canonique
         ) order by d.created_at), '[]'::jsonb)
    into v_resultat
  from public.demandes_etablissement d
  join public.profiles p on p.id = d.demandeur_id
  left join public.pays_pedagogiques pp on pp.code_iso = d.pays_code
  where d.statut = 'en_attente';

  return v_resultat;
end;
$$;

revoke all on function public.soumettre_demande_etablissement(text, text, text, text, text, text, integer, text, text) from public, anon;
grant execute on function public.soumettre_demande_etablissement(text, text, text, text, text, text, integer, text, text) to authenticated;
revoke all on function public.traiter_demande_etablissement(uuid, text, text) from public, anon;
grant execute on function public.traiter_demande_etablissement(uuid, text, text) to authenticated;
revoke all on function public.demandes_etablissement_a_traiter() from public, anon;
grant execute on function public.demandes_etablissement_a_traiter() to authenticated;
