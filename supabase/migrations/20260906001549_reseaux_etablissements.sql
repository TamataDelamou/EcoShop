-- ============================================================================
-- EcoShop — M19 : réseaux d'établissements (cahier v4.1, ch. 28 et 30.1/30.3)
--
-- 1. Demande de création d'un réseau (nom, dénomination, courriel,
--    téléphone, adresse, premier responsable, devise…), validée par GSG ;
--    courriels de confirmation (même file que REG-04). L'acceptation crée le
--    réseau et sa Direction Générale (le demandeur), sans toucher au rôle de
--    son compte : un directeur reste directeur, un fondateur indépendant
--    garde son accès famille.
-- 2. Invitation des écoles par l'annuaire (recherche insensible à la casse
--    et aux accents) ; la Direction de l'école accepte ou refuse.
-- 3. Retrait : demandé par l'école, finalisé seulement par GSG (règle 28.4).
--    Dissolution : par la Direction Générale, confirmée en ressaisissant le
--    nom exact du réseau (double confirmation côté serveur aussi).
-- 4. Pilotage : circulaires aux directions des écoles membres (push +
--    boîte de notifications, accusé de lecture) ; calendrier commun
--    (rentrée, congés, examens) que chaque école importe dans son agenda
--    si elle le souhaite (harmonisation déclarative, 28.2).
-- 5. Tableau de bord consolidé (28.5) : effectifs, présence sur 30 jours,
--    recouvrement des frais, alertes de décrochage, personnel, par école et
--    au total. Chiffres agrégés seulement : aucun nom d'élève ne sort de
--    son école (étanchéité 28.1).
-- 6. Vue d'ensemble GSG en lecture seule (30.3), retraits à décider.
--
-- Toute écriture passe par les fonctions ; clés générées par l'appareil pour
-- la demande, les circulaires et les événements (renvoi hors connexion sans
-- doublon). Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Recherche insensible à la casse et aux accents
-- ---------------------------------------------------------------------------
create or replace function public.texte_recherche(p text)
returns text
language sql immutable parallel safe set search_path = public
as $$
  select trim(regexp_replace(
    translate(lower(coalesce(p, '')),
              'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ''’-',
              'aaaaaaceeeeiiiinooooouuuuyy   '),
    '\s+', ' ', 'g'));
$$;

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------
create table if not exists public.demandes_reseau (
  id uuid primary key,
  demandeur_id uuid not null references public.profiles (id) on delete cascade,
  nom text not null check (char_length(trim(nom)) between 3 and 120),
  denomination text not null check (char_length(trim(denomination)) between 3 and 160),
  type_reseau text not null default 'confessionnel'
    check (type_reseau in ('confessionnel', 'prive_laique', 'communautaire', 'public', 'autre')),
  pays_code text not null references public.pays_pedagogiques (code_iso),
  devise_code text not null default 'GNF' check (devise_code ~ '^[A-Z]{3}$'),
  courriel text not null check (courriel ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  telephone text not null check (telephone ~ '^\+?[0-9 ]{8,20}$'),
  adresse text not null check (char_length(trim(adresse)) between 3 and 200),
  premier_responsable text not null check (char_length(trim(premier_responsable)) between 3 and 120),
  message text check (message is null or char_length(message) <= 1000),
  statut text not null default 'en_attente' check (statut in ('en_attente', 'acceptee', 'refusee')),
  motif_refus text,
  frais_creation_regles boolean not null default false,
  traitee_par uuid references public.profiles (id),
  traitee_le timestamptz,
  reseau_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint demandes_reseau_refus_motive check (statut <> 'refusee' or char_length(trim(coalesce(motif_refus, ''))) > 0)
);
create unique index if not exists idx_demandes_reseau_une_en_cours
  on public.demandes_reseau (demandeur_id) where statut = 'en_attente';

create table if not exists public.reseaux (
  id uuid primary key default gen_random_uuid(),
  nom text not null,
  denomination text not null,
  type_reseau text not null,
  pays_code text not null,
  devise_code text not null,
  courriel text,
  telephone text,
  adresse text,
  statut text not null default 'actif' check (statut in ('actif', 'dissous')),
  demande_id uuid references public.demandes_reseau (id),
  cree_le timestamptz not null default now(),
  dissous_le timestamptz,
  dissous_par uuid references public.profiles (id),
  updated_at timestamptz not null default now()
);

create table if not exists public.reseaux_responsables (
  reseau_id uuid not null references public.reseaux (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'direction_generale'
    check (role in ('direction_generale', 'adjoint', 'observateur')),
  nomme_par uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  primary key (reseau_id, profile_id)
);
create index if not exists idx_reseaux_responsables_profil on public.reseaux_responsables (profile_id);

create table if not exists public.reseaux_etablissements (
  reseau_id uuid not null references public.reseaux (id) on delete cascade,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  statut text not null default 'invite'
    check (statut in ('invite', 'membre', 'refuse', 'retrait_demande', 'retire')),
  invite_par uuid references public.profiles (id),
  invite_le timestamptz not null default now(),
  repondu_par uuid references public.profiles (id),
  repondu_le timestamptz,
  retrait_motif text,
  retrait_demande_par uuid references public.profiles (id),
  retrait_demande_le timestamptz,
  retrait_decide_par uuid references public.profiles (id),
  retrait_decide_le timestamptz,
  primary key (reseau_id, etablissement_id)
);
create index if not exists idx_reseaux_etab_etab on public.reseaux_etablissements (etablissement_id);

create table if not exists public.circulaires_reseau (
  id uuid primary key,
  reseau_id uuid not null references public.reseaux (id) on delete cascade,
  titre text not null check (char_length(trim(titre)) between 3 and 120),
  corps text not null check (char_length(trim(corps)) between 3 and 4000),
  importante boolean not null default false,
  publiee_par uuid not null references public.profiles (id),
  publiee_le timestamptz not null default now()
);
create index if not exists idx_circulaires_reseau on public.circulaires_reseau (reseau_id, publiee_le desc);

create table if not exists public.lectures_circulaires_reseau (
  circulaire_id uuid not null references public.circulaires_reseau (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  lue_le timestamptz not null default now(),
  primary key (circulaire_id, profile_id)
);

create table if not exists public.evenements_reseau (
  id uuid primary key,
  reseau_id uuid not null references public.reseaux (id) on delete cascade,
  titre text not null check (char_length(trim(titre)) between 3 and 120),
  type_evenement text not null default 'autre'
    check (type_evenement in ('rentree', 'conges', 'examen', 'formation', 'reunion', 'fete', 'autre')),
  date_debut date not null,
  date_fin date not null,
  description text check (description is null or char_length(description) <= 1000),
  cree_par uuid not null references public.profiles (id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint evenements_reseau_periode check (date_fin >= date_debut)
);
create index if not exists idx_evenements_reseau on public.evenements_reseau (reseau_id, date_debut);

-- Import d'un événement commun dans l'agenda d'une école : une seule fois.
alter table public.evenements_agenda
  add column if not exists evenement_reseau_id uuid references public.evenements_reseau (id) on delete set null;
create unique index if not exists idx_agenda_evenement_reseau
  on public.evenements_agenda (etablissement_id, evenement_reseau_id)
  where evenement_reseau_id is not null and deleted_at is null;

drop trigger if exists demandes_reseau_set_updated_at on public.demandes_reseau;
create trigger demandes_reseau_set_updated_at before update on public.demandes_reseau
  for each row execute function public.set_updated_at();
drop trigger if exists reseaux_set_updated_at on public.reseaux;
create trigger reseaux_set_updated_at before update on public.reseaux
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 2. Droits
-- ---------------------------------------------------------------------------
create or replace function public.role_reseau(p_reseau uuid)
returns text
language sql stable security definer set search_path = public
as $$
  select r.role from public.reseaux_responsables r
  join public.reseaux n on n.id = r.reseau_id
  where r.reseau_id = p_reseau and r.profile_id = auth.uid() and n.statut = 'actif';
$$;

create or replace function public.pilote_reseau(p_reseau uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.role_reseau(p_reseau) in ('direction_generale', 'adjoint'), false);
$$;

create or replace function public.voit_reseau(p_reseau uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.role_reseau(p_reseau) is not null
      or coalesce(public.est_admin_gsg(), false)
      or exists (select 1 from public.reseaux_etablissements re
                 where re.reseau_id = p_reseau and re.statut in ('invite', 'membre', 'retrait_demande')
                   and coalesce(public.est_direction(re.etablissement_id), false));
$$;

alter table public.demandes_reseau enable row level security;
alter table public.reseaux enable row level security;
alter table public.reseaux_responsables enable row level security;
alter table public.reseaux_etablissements enable row level security;
alter table public.circulaires_reseau enable row level security;
alter table public.lectures_circulaires_reseau enable row level security;
alter table public.evenements_reseau enable row level security;

drop policy if exists demandes_reseau_select on public.demandes_reseau;
create policy demandes_reseau_select on public.demandes_reseau
  for select using (demandeur_id = auth.uid() or coalesce(public.est_admin_gsg(), false));
drop policy if exists reseaux_select on public.reseaux;
create policy reseaux_select on public.reseaux for select using (public.voit_reseau(id));
drop policy if exists reseaux_responsables_select on public.reseaux_responsables;
create policy reseaux_responsables_select on public.reseaux_responsables for select using (public.voit_reseau(reseau_id));
drop policy if exists reseaux_etablissements_select on public.reseaux_etablissements;
create policy reseaux_etablissements_select on public.reseaux_etablissements
  for select using (public.role_reseau(reseau_id) is not null or coalesce(public.est_admin_gsg(), false)
                    or coalesce(public.est_direction(etablissement_id), false));
drop policy if exists evenements_reseau_select on public.evenements_reseau;
create policy evenements_reseau_select on public.evenements_reseau
  for select using (deleted_at is null and public.voit_reseau(reseau_id));

-- Circulaires et lectures : uniquement par les fonctions (taux de lecture).
revoke all on public.circulaires_reseau, public.lectures_circulaires_reseau from anon, authenticated;
revoke insert, update, delete on public.demandes_reseau, public.reseaux, public.reseaux_responsables,
  public.reseaux_etablissements, public.evenements_reseau from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Demande de création, validation GSG
-- ---------------------------------------------------------------------------
create or replace function public.soumettre_demande_reseau(
  p_id uuid, p_nom text, p_denomination text, p_type text, p_pays_code text, p_devise_code text,
  p_courriel text, p_telephone text, p_adresse text, p_premier_responsable text, p_message text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v public.demandes_reseau;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUISE' using errcode = '42501'; end if;
  select * into v from public.demandes_reseau where id = p_id;
  if found then
    if v.demandeur_id <> auth.uid() then raise exception 'CLE_DEJA_UTILISEE' using errcode = '23505'; end if;
    return jsonb_build_object('id', v.id, 'statut', v.statut, 'deja_recue', true);
  end if;
  if exists (select 1 from public.demandes_reseau where demandeur_id = auth.uid() and statut = 'en_attente') then
    raise exception 'DEMANDE_DEJA_EN_COURS' using errcode = '23505';
  end if;
  insert into public.demandes_reseau (id, demandeur_id, nom, denomination, type_reseau, pays_code, devise_code,
                                      courriel, telephone, adresse, premier_responsable, message)
  values (p_id, auth.uid(), trim(p_nom), trim(p_denomination), coalesce(p_type, 'confessionnel'), upper(p_pays_code),
          upper(coalesce(p_devise_code, 'GNF')), lower(trim(p_courriel)), trim(p_telephone), trim(p_adresse),
          trim(p_premier_responsable), nullif(trim(coalesce(p_message, '')), ''))
  returning * into v;
  return jsonb_build_object('id', v.id, 'statut', v.statut, 'deja_recue', false);
end;
$$;

create or replace function public.demandes_reseau_a_traiter()
returns setof public.demandes_reseau
language plpgsql stable security definer set search_path = public
as $$
begin
  if not coalesce(public.est_admin_gsg(), false) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  return query select * from public.demandes_reseau order by (statut = 'en_attente') desc, created_at desc limit 200;
end;
$$;

create or replace function public.traiter_demande_reseau(
  p_demande uuid, p_accepter boolean, p_motif text default null, p_frais_regles boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v public.demandes_reseau;
  v_reseau uuid;
begin
  if not coalesce(public.est_admin_gsg(), false) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  select * into v from public.demandes_reseau where id = p_demande for update;
  if not found then raise exception 'DEMANDE_INTROUVABLE' using errcode = 'P0002'; end if;
  if v.statut <> 'en_attente' then raise exception 'DEMANDE_DEJA_TRAITEE' using errcode = '23514'; end if;

  if not p_accepter then
    if char_length(trim(coalesce(p_motif, ''))) = 0 then raise exception 'MOTIF_REQUIS' using errcode = '23514'; end if;
    update public.demandes_reseau set statut = 'refusee', motif_refus = trim(p_motif),
           traitee_par = auth.uid(), traitee_le = now() where id = p_demande;
    return jsonb_build_object('statut', 'refusee');
  end if;

  -- Frais de création (17.7) : exigés une seule fois, constatés par GSG.
  if not coalesce(p_frais_regles, false) then raise exception 'FRAIS_CREATION_NON_REGLES' using errcode = '23514'; end if;

  insert into public.reseaux (nom, denomination, type_reseau, pays_code, devise_code, courriel, telephone, adresse, demande_id)
  values (v.nom, v.denomination, v.type_reseau, v.pays_code, v.devise_code, v.courriel, v.telephone, v.adresse, v.id)
  returning id into v_reseau;
  insert into public.reseaux_responsables (reseau_id, profile_id, role, nomme_par)
  values (v_reseau, v.demandeur_id, 'direction_generale', auth.uid());
  update public.demandes_reseau set statut = 'acceptee', frais_creation_regles = true, reseau_id = v_reseau,
         traitee_par = auth.uid(), traitee_le = now() where id = p_demande;
  return jsonb_build_object('statut', 'acceptee', 'reseau_id', v_reseau);
end;
$$;

-- Courriels (file REG-04) : reçue au demandeur, à traiter pour GSG, décision.
create or replace function public.demandes_reseau_notifier()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_prenom text;
  v_pays text;
  v_base jsonb;
begin
  select nullif(trim(p.prenom), '') into v_prenom from public.profiles p where p.id = new.demandeur_id;
  select pp.nom into v_pays from public.pays_pedagogiques pp where pp.code_iso = new.pays_code;
  v_base := jsonb_build_object('prenom', v_prenom, 'nom_reseau', new.nom, 'denomination', new.denomination,
    'pays', coalesce(v_pays, new.pays_code), 'reference', upper(substr(replace(new.id::text, '-', ''), 1, 8)));
  if tg_op = 'INSERT' then
    perform public.mettre_notification_en_file('demande_reseau_recue', 'reseau_recue:' || new.id, v_base, new.courriel);
    perform public.mettre_notification_en_file('demande_reseau_a_traiter', 'reseau_a_traiter:' || new.id,
      v_base || jsonb_build_object('premier_responsable', new.premier_responsable, 'telephone', new.telephone),
      null, 'admin_gsg');
  elsif old.statut = 'en_attente' and new.statut = 'acceptee' then
    perform public.mettre_notification_en_file('demande_reseau_acceptee', 'reseau_acceptee:' || new.id, v_base, new.courriel);
  elsif old.statut = 'en_attente' and new.statut = 'refusee' then
    perform public.mettre_notification_en_file('demande_reseau_refusee', 'reseau_refusee:' || new.id,
      v_base || jsonb_build_object('motif', new.motif_refus), new.courriel);
  end if;
  return null;
end;
$$;
drop trigger if exists demandes_reseau_notifier on public.demandes_reseau;
create trigger demandes_reseau_notifier after insert or update of statut on public.demandes_reseau
  for each row execute function public.demandes_reseau_notifier();

-- ---------------------------------------------------------------------------
-- 4. Responsables, annuaire, invitations, retrait, dissolution
-- ---------------------------------------------------------------------------
create or replace function public.nommer_responsable_reseau(p_reseau uuid, p_identifiant text, p_role text)
returns uuid
language plpgsql volatile security definer set search_path = public, auth
as $$
declare
  v_profil uuid;
  v_id text := lower(trim(coalesce(p_identifiant, '')));
  v_tel text := regexp_replace(coalesce(p_identifiant, ''), '[^0-9]', '', 'g');
begin
  if coalesce(public.role_reseau(p_reseau), '') <> 'direction_generale' then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if p_role not in ('direction_generale', 'adjoint', 'observateur') then raise exception 'ROLE_INVALIDE' using errcode = '22023'; end if;
  if v_tel like '00%' then v_tel := substr(v_tel, 3); end if;
  if length(v_tel) = 9 and v_tel like '6%' then v_tel := '224' || v_tel; end if;
  select u.id into v_profil from auth.users u
  where (v_id like '%@%' and lower(u.email) = v_id) or (v_id not like '%@%' and length(v_tel) >= 8 and u.phone = v_tel)
  limit 1;
  if v_profil is null then raise exception 'COMPTE_INTROUVABLE' using errcode = 'P0002'; end if;
  insert into public.reseaux_responsables (reseau_id, profile_id, role, nomme_par)
  values (p_reseau, v_profil, p_role, auth.uid())
  on conflict (reseau_id, profile_id) do update set role = excluded.role, nomme_par = excluded.nomme_par;
  return v_profil;
end;
$$;

create or replace function public.retirer_responsable_reseau(p_reseau uuid, p_profil uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if coalesce(public.role_reseau(p_reseau), '') <> 'direction_generale' then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if (select role from public.reseaux_responsables where reseau_id = p_reseau and profile_id = p_profil) = 'direction_generale'
     and (select count(*) from public.reseaux_responsables where reseau_id = p_reseau and role = 'direction_generale') <= 1 then
    raise exception 'DERNIERE_DIRECTION_GENERALE' using errcode = '23514';
  end if;
  delete from public.reseaux_responsables where reseau_id = p_reseau and profile_id = p_profil;
end;
$$;

-- Annuaire (28.3) : nom et ville seulement, jamais d'autre donnée.
create or replace function public.rechercher_etablissements_reseau(p_reseau uuid, p_texte text)
returns table (etablissement_id uuid, nom text, ville text, pays_code text, statut_reseau text)
language plpgsql stable security definer set search_path = public
as $$
declare
  v_q text := public.texte_recherche(p_texte);
begin
  if not public.pilote_reseau(p_reseau) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  if char_length(v_q) < 2 then return; end if;
  return query
  select e.id, e.nom, e.ville, e.pays_code, re.statut
  from public.etablissements e
  left join public.reseaux_etablissements re on re.reseau_id = p_reseau and re.etablissement_id = e.id
  where e.deleted_at is null and e.statut = 'actif'
    and (public.texte_recherche(e.nom) like '%' || v_q || '%' or public.texte_recherche(e.ville) like '%' || v_q || '%')
  order by public.texte_recherche(e.nom) like v_q || '%' desc, e.nom
  limit 20;
end;
$$;

-- Directions actives d'une école (destinataires des messages du réseau).
create or replace function public.directions_etablissement(p_etablissement uuid)
returns setof uuid
language sql stable security definer set search_path = public
as $$
  select m.profile_id from public.etablissements_membres m
  where m.etablissement_id = p_etablissement and m.actif and m.role_dans_etablissement in ('direction', 'fondateur_reseau');
$$;

create or replace function public.inviter_etablissement_reseau(p_reseau uuid, p_etablissement uuid)
returns text
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_statut text;
  v_nom text;
  d uuid;
begin
  if not public.pilote_reseau(p_reseau) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  if not exists (select 1 from public.etablissements where id = p_etablissement and deleted_at is null and statut = 'actif') then
    raise exception 'ETABLISSEMENT_INTROUVABLE' using errcode = 'P0002';
  end if;
  select statut into v_statut from public.reseaux_etablissements where reseau_id = p_reseau and etablissement_id = p_etablissement;
  if v_statut in ('invite', 'membre', 'retrait_demande') then return v_statut; end if;
  insert into public.reseaux_etablissements (reseau_id, etablissement_id, statut, invite_par, invite_le)
  values (p_reseau, p_etablissement, 'invite', auth.uid(), now())
  on conflict (reseau_id, etablissement_id) do update
    set statut = 'invite', invite_par = auth.uid(), invite_le = now(), repondu_par = null, repondu_le = null;
  select nom into v_nom from public.reseaux where id = p_reseau;
  for d in select * from public.directions_etablissement(p_etablissement) loop
    perform public.notifier_push(p_etablissement, d, 'reseau_invitation',
      format('Le réseau « %s » invite votre établissement à le rejoindre.', v_nom),
      jsonb_build_object('reseau_id', p_reseau));
  end loop;
  return 'invite';
end;
$$;

create or replace function public.repondre_invitation_reseau(p_reseau uuid, p_etablissement uuid, p_accepter boolean)
returns text
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_statut text;
begin
  if not coalesce(public.est_direction(p_etablissement), false) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  select statut into v_statut from public.reseaux_etablissements
  where reseau_id = p_reseau and etablissement_id = p_etablissement for update;
  if v_statut is null then raise exception 'INVITATION_INTROUVABLE' using errcode = 'P0002'; end if;
  -- Renvoi de la même réponse (hors connexion) : déjà fait.
  if (v_statut = 'membre' and p_accepter) or (v_statut = 'refuse' and not p_accepter) then return v_statut; end if;
  if v_statut <> 'invite' then raise exception 'INVITATION_PLUS_VALABLE' using errcode = '23514'; end if;
  if not exists (select 1 from public.reseaux where id = p_reseau and statut = 'actif') then
    raise exception 'RESEAU_DISSOUS' using errcode = '23514';
  end if;
  update public.reseaux_etablissements
     set statut = case when p_accepter then 'membre' else 'refuse' end, repondu_par = auth.uid(), repondu_le = now()
   where reseau_id = p_reseau and etablissement_id = p_etablissement;
  return case when p_accepter then 'membre' else 'refuse' end;
end;
$$;

create or replace function public.demander_retrait_reseau(p_reseau uuid, p_etablissement uuid, p_motif text)
returns text
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_statut text;
begin
  if not coalesce(public.est_direction(p_etablissement), false) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  if char_length(trim(coalesce(p_motif, ''))) < 3 then raise exception 'MOTIF_REQUIS' using errcode = '23514'; end if;
  select statut into v_statut from public.reseaux_etablissements
  where reseau_id = p_reseau and etablissement_id = p_etablissement for update;
  if v_statut = 'retrait_demande' then return v_statut; end if;
  if v_statut is distinct from 'membre' then raise exception 'PAS_MEMBRE' using errcode = '23514'; end if;
  update public.reseaux_etablissements
     set statut = 'retrait_demande', retrait_motif = trim(p_motif), retrait_demande_par = auth.uid(), retrait_demande_le = now()
   where reseau_id = p_reseau and etablissement_id = p_etablissement;
  return 'retrait_demande';
end;
$$;

-- Règle 28.4 : le retrait n'est finalisé qu'avec l'autorisation de GSG.
create or replace function public.decider_retrait_reseau(p_reseau uuid, p_etablissement uuid, p_accorder boolean)
returns text
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_nouveau text := case when p_accorder then 'retire' else 'membre' end;
begin
  if not coalesce(public.est_admin_gsg(), false) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  update public.reseaux_etablissements
     set statut = v_nouveau, retrait_decide_par = auth.uid(), retrait_decide_le = now()
   where reseau_id = p_reseau and etablissement_id = p_etablissement and statut = 'retrait_demande';
  if not found then raise exception 'AUCUN_RETRAIT_EN_ATTENTE' using errcode = 'P0002'; end if;
  return v_nouveau;
end;
$$;

-- Dissolution (28.4) : deuxième confirmation = nom exact du réseau ressaisi.
create or replace function public.dissoudre_reseau(p_reseau uuid, p_confirmation_nom text)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_nom text;
begin
  if coalesce(public.role_reseau(p_reseau), '') <> 'direction_generale' then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  select nom into v_nom from public.reseaux where id = p_reseau for update;
  if public.texte_recherche(p_confirmation_nom) <> public.texte_recherche(v_nom) then
    raise exception 'CONFIRMATION_INCORRECTE' using errcode = '23514';
  end if;
  update public.reseaux set statut = 'dissous', dissous_le = now(), dissous_par = auth.uid() where id = p_reseau;
  update public.reseaux_etablissements set statut = 'retire'
   where reseau_id = p_reseau and statut in ('invite', 'membre', 'retrait_demande');
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Mes réseaux (responsable ou direction d'une école concernée)
-- ---------------------------------------------------------------------------
create or replace function public.mes_reseaux()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(x order by x ->> 'nom'), '[]'::jsonb) from (
    select jsonb_build_object(
      'reseau_id', n.id, 'nom', n.nom, 'denomination', n.denomination, 'devise_code', n.devise_code,
      'statut', n.statut, 'mon_role', public.role_reseau(n.id),
      'ecoles', (select coalesce(jsonb_agg(jsonb_build_object(
                    'etablissement_id', e.id, 'nom', e.nom, 'ville', e.ville, 'statut', re.statut,
                    'retrait_motif', re.retrait_motif) order by e.nom), '[]'::jsonb)
                 from public.reseaux_etablissements re join public.etablissements e on e.id = re.etablissement_id
                 where re.reseau_id = n.id
                   and (public.role_reseau(n.id) is not null or coalesce(public.est_direction(e.id), false))),
      'responsables', case when public.role_reseau(n.id) is not null then
                 (select coalesce(jsonb_agg(jsonb_build_object('profile_id', r.profile_id, 'role', r.role,
                    'nom', trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, ''))) order by r.role), '[]'::jsonb)
                  from public.reseaux_responsables r join public.profiles p on p.id = r.profile_id
                  where r.reseau_id = n.id) else '[]'::jsonb end
    ) as x
    from public.reseaux n
    where n.statut = 'actif' and (public.role_reseau(n.id) is not null
       or exists (select 1 from public.reseaux_etablissements re
                  where re.reseau_id = n.id and re.statut in ('invite', 'membre', 'retrait_demande')
                    and coalesce(public.est_direction(re.etablissement_id), false)))
  ) s;
$$;

-- Vue d'ensemble GSG (30.3), lecture seule ; retraits à décider.
create or replace function public.reseaux_vue_ensemble()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not coalesce(public.est_admin_gsg(), false) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'reseau_id', n.id, 'nom', n.nom, 'denomination', n.denomination, 'statut', n.statut, 'cree_le', n.cree_le,
    'membres', (select count(*) from public.reseaux_etablissements re where re.reseau_id = n.id and re.statut in ('membre', 'retrait_demande')),
    'invitations', (select count(*) from public.reseaux_etablissements re where re.reseau_id = n.id and re.statut = 'invite'),
    'retraits_a_decider', (select coalesce(jsonb_agg(jsonb_build_object('etablissement_id', e.id, 'nom', e.nom,
                              'motif', re.retrait_motif, 'demande_le', re.retrait_demande_le)), '[]'::jsonb)
                           from public.reseaux_etablissements re join public.etablissements e on e.id = re.etablissement_id
                           where re.reseau_id = n.id and re.statut = 'retrait_demande')
  ) order by n.statut, n.nom), '[]'::jsonb) from public.reseaux n);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Circulaires et calendrier commun
-- ---------------------------------------------------------------------------
create or replace function public.publier_circulaire_reseau(
  p_id uuid, p_reseau uuid, p_titre text, p_corps text, p_importante boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_existe uuid;
  v_n integer := 0;
  e record;
  d uuid;
begin
  if not public.pilote_reseau(p_reseau) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  select reseau_id into v_existe from public.circulaires_reseau where id = p_id;
  if found then
    if v_existe <> p_reseau then raise exception 'CLE_DEJA_UTILISEE' using errcode = '23505'; end if;
    return jsonb_build_object('id', p_id, 'deja_recue', true);
  end if;
  insert into public.circulaires_reseau (id, reseau_id, titre, corps, importante, publiee_par)
  values (p_id, p_reseau, trim(p_titre), trim(p_corps), coalesce(p_importante, false), auth.uid());
  for e in select re.etablissement_id from public.reseaux_etablissements re
           where re.reseau_id = p_reseau and re.statut in ('membre', 'retrait_demande') loop
    for d in select * from public.directions_etablissement(e.etablissement_id) loop
      perform public.notifier_push(e.etablissement_id, d, 'reseau_circulaire',
        case when p_importante then 'Important — ' else '' end || trim(p_titre),
        jsonb_build_object('reseau_id', p_reseau, 'circulaire_id', p_id));
      v_n := v_n + 1;
    end loop;
  end loop;
  return jsonb_build_object('id', p_id, 'deja_recue', false, 'destinataires', v_n);
end;
$$;

-- Circulaires d'un réseau : pour ses responsables (avec taux de lecture) et
-- pour les directions des écoles membres (avec « lue »).
create or replace function public.circulaires_reseau_liste(p_reseau uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_pilote boolean := public.role_reseau(p_reseau) is not null;
  v_destinataires integer;
begin
  if not v_pilote and not exists (
      select 1 from public.reseaux_etablissements re
      where re.reseau_id = p_reseau and re.statut in ('membre', 'retrait_demande')
        and coalesce(public.est_direction(re.etablissement_id), false)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  select count(*) into v_destinataires
  from public.reseaux_etablissements re, lateral public.directions_etablissement(re.etablissement_id) d
  where re.reseau_id = p_reseau and re.statut in ('membre', 'retrait_demande');
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'titre', c.titre, 'corps', c.corps, 'importante', c.importante, 'publiee_le', c.publiee_le,
      'lue', exists (select 1 from public.lectures_circulaires_reseau l where l.circulaire_id = c.id and l.profile_id = auth.uid()),
      'lectures', case when v_pilote then (select count(*) from public.lectures_circulaires_reseau l where l.circulaire_id = c.id) end,
      'destinataires', case when v_pilote then v_destinataires end
    ) order by c.publiee_le desc), '[]'::jsonb)
    from (select * from public.circulaires_reseau where reseau_id = p_reseau order by publiee_le desc limit 100) c);
end;
$$;

create or replace function public.marquer_circulaire_lue(p_circulaire uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUISE' using errcode = '42501'; end if;
  if not exists (select 1 from public.circulaires_reseau c where c.id = p_circulaire and public.voit_reseau(c.reseau_id)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  insert into public.lectures_circulaires_reseau (circulaire_id, profile_id) values (p_circulaire, auth.uid())
  on conflict do nothing;
end;
$$;

create or replace function public.enregistrer_evenement_reseau(
  p_id uuid, p_reseau uuid, p_titre text, p_type text, p_debut date, p_fin date, p_description text default null)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if not public.pilote_reseau(p_reseau) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  if exists (select 1 from public.evenements_reseau where id = p_id and reseau_id <> p_reseau) then
    raise exception 'CLE_DEJA_UTILISEE' using errcode = '23505';
  end if;
  insert into public.evenements_reseau (id, reseau_id, titre, type_evenement, date_debut, date_fin, description, cree_par)
  values (p_id, p_reseau, trim(p_titre), coalesce(p_type, 'autre'), p_debut, coalesce(p_fin, p_debut),
          nullif(trim(coalesce(p_description, '')), ''), auth.uid())
  on conflict (id) do update set titre = excluded.titre, type_evenement = excluded.type_evenement,
    date_debut = excluded.date_debut, date_fin = excluded.date_fin, description = excluded.description,
    deleted_at = null, updated_at = now();
end;
$$;

create or replace function public.supprimer_evenement_reseau(p_id uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if not exists (select 1 from public.evenements_reseau e where e.id = p_id and public.pilote_reseau(e.reseau_id)) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  update public.evenements_reseau set deleted_at = now(), updated_at = now() where id = p_id;
end;
$$;

-- Événements du réseau ; pour une école, indique s'il est déjà dans son agenda.
create or replace function public.evenements_reseau_liste(p_reseau uuid, p_etablissement uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.voit_reseau(p_reseau) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', e.id, 'titre', e.titre, 'type', e.type_evenement, 'date_debut', e.date_debut, 'date_fin', e.date_fin,
      'description', e.description,
      'importe', p_etablissement is not null and exists (select 1 from public.evenements_agenda a
                   where a.etablissement_id = p_etablissement and a.evenement_reseau_id = e.id and a.deleted_at is null)
    ) order by e.date_debut), '[]'::jsonb)
    from public.evenements_reseau e
    where e.reseau_id = p_reseau and e.deleted_at is null and e.date_fin >= current_date - 30);
end;
$$;

-- Harmonisation déclarative (28.2) : l'école choisit d'importer l'événement.
create or replace function public.importer_evenement_reseau(p_evenement uuid, p_etablissement uuid)
returns uuid
language plpgsql volatile security definer set search_path = public
as $$
declare
  v public.evenements_reseau;
  v_annee uuid;
  v_id uuid;
begin
  if not coalesce(public.est_direction(p_etablissement), false) then raise exception 'ACCES_REFUSE' using errcode = '42501'; end if;
  select * into v from public.evenements_reseau where id = p_evenement and deleted_at is null;
  if not found or not exists (select 1 from public.reseaux_etablissements re where re.reseau_id = v.reseau_id
                              and re.etablissement_id = p_etablissement and re.statut in ('membre', 'retrait_demande')) then
    raise exception 'EVENEMENT_INTROUVABLE' using errcode = 'P0002';
  end if;
  select id into v_id from public.evenements_agenda
  where etablissement_id = p_etablissement and evenement_reseau_id = p_evenement and deleted_at is null;
  if v_id is not null then return v_id; end if;
  select id into v_annee from public.annees_scolaires where etablissement_id = p_etablissement and courante limit 1;
  if v_annee is null then raise exception 'ANNEE_COURANTE_ABSENTE' using errcode = '23514'; end if;
  insert into public.evenements_agenda (etablissement_id, annee_scolaire_id, titre, type, date_debut, date_fin, evenement_reseau_id)
  values (p_etablissement, v_annee, v.titre,
          case v.type_evenement when 'examen' then 'examen' when 'reunion' then 'reunion' when 'fete' then 'fete' else 'autre' end,
          v.date_debut, v.date_fin, p_evenement)
  returning id into v_id;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Tableau de bord consolidé (28.5) — chiffres agrégés uniquement
-- ---------------------------------------------------------------------------
create or replace function public.tableau_bord_reseau(p_reseau uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_ecoles jsonb;
begin
  if public.role_reseau(p_reseau) is null and not coalesce(public.est_admin_gsg(), false) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  with membres as (
    select e.id, e.nom, e.ville, e.devise_code,
           (select a.id from public.annees_scolaires a where a.etablissement_id = e.id and a.courante limit 1) as annee
    from public.reseaux_etablissements re
    join public.etablissements e on e.id = re.etablissement_id
    where re.reseau_id = p_reseau and re.statut in ('membre', 'retrait_demande') and e.deleted_at is null
  ),
  insc as (
    select m.id as etab, i.id, i.statut, c.niveau_id, i.annee_scolaire_id
    from membres m
    join public.inscriptions i on i.etablissement_id = m.id and i.annee_scolaire_id = m.annee and i.deleted_at is null
    join public.classes c on c.id = i.classe_id
  ),
  du as (
    select insc.etab, insc.id,
      coalesce(
        (select f.montant_annuel from public.frais_scolarite_config f where f.etablissement_id = insc.etab
           and f.annee_scolaire_id = insc.annee_scolaire_id and f.niveau_id = insc.niveau_id and f.deleted_at is null limit 1),
        (select f.montant_annuel from public.frais_scolarite_config f where f.etablissement_id = insc.etab
           and f.annee_scolaire_id = insc.annee_scolaire_id and f.niveau_id is null and f.deleted_at is null limit 1),
        0) as montant
    from insc where insc.statut in ('active', 'redoublante')
  ),
  paye as (
    select es.etablissement_id as etab, sum(es.montant) as montant
    from public.encaissements_scolarite es
    join insc on insc.id = es.inscription_id
    where es.statut = 'valide' and es.type_frais = 'scolarite'
    group by es.etablissement_id
  ),
  presence as (
    select p.etablissement_id as etab,
           count(*) filter (where p.statut in ('present', 'retard')) as presents,
           count(*) filter (where p.statut <> 'dispense') as comptes
    from public.presences p
    join membres m on m.id = p.etablissement_id and p.annee_scolaire_id = m.annee
    where p.deleted_at is null and p.type_seance = 'demi_journee' and p.date_presence >= current_date - 30
    group by p.etablissement_id
  ),
  ligne as (
    select m.id, m.nom, m.ville, m.devise_code, m.annee is not null as annee_ouverte,
      (select count(*) from insc where insc.etab = m.id and insc.statut in ('active', 'redoublante')) as effectif,
      (select count(*) from insc where insc.etab = m.id and insc.statut = 'retiree') as retraits,
      (select coalesce(sum(montant), 0) from du where du.etab = m.id) as montant_du,
      coalesce((select montant from paye where paye.etab = m.id), 0) as montant_encaisse,
      (select case when comptes > 0 then round(100.0 * presents / comptes, 1) end from presence where presence.etab = m.id) as taux_presence,
      (select count(*) from public.alertes_decrochage a where a.etablissement_id = m.id and a.annee_scolaire_id = m.annee
         and a.statut = 'ouverte' and a.deleted_at is null) as alertes_decrochage,
      (select count(*) from public.employes em where em.etablissement_id = m.id and em.statut = 'actif' and em.deleted_at is null) as personnel,
      (select count(*) from public.employes em where em.etablissement_id = m.id and em.statut = 'actif' and em.deleted_at is null
         and em.categorie = 'enseignant') as enseignants
    from membres m
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'etablissement_id', l.id, 'nom', l.nom, 'ville', l.ville, 'devise_code', l.devise_code, 'annee_ouverte', l.annee_ouverte,
      'effectif', l.effectif, 'retraits', l.retraits, 'montant_du', l.montant_du, 'montant_encaisse', l.montant_encaisse,
      'taux_recouvrement', case when l.montant_du > 0 then round(100.0 * l.montant_encaisse / l.montant_du, 1) end,
      'taux_presence', l.taux_presence, 'alertes_decrochage', l.alertes_decrochage,
      'personnel', l.personnel, 'enseignants', l.enseignants,
      'eleves_par_enseignant', case when l.enseignants > 0 then round(l.effectif::numeric / l.enseignants, 1) end
    ) order by l.nom), '[]'::jsonb)
  into v_ecoles from ligne l;

  return jsonb_build_object(
    'reseau', (select jsonb_build_object('id', id, 'nom', nom, 'denomination', denomination, 'devise_code', devise_code)
               from public.reseaux where id = p_reseau),
    'ecoles', v_ecoles,
    'totaux', (select jsonb_build_object(
        'ecoles', count(*),
        'effectif', coalesce(sum((x ->> 'effectif')::int), 0),
        'montant_du', coalesce(sum((x ->> 'montant_du')::numeric), 0),
        'montant_encaisse', coalesce(sum((x ->> 'montant_encaisse')::numeric), 0),
        'taux_recouvrement', case when sum((x ->> 'montant_du')::numeric) > 0
          then round(100.0 * sum((x ->> 'montant_encaisse')::numeric) / sum((x ->> 'montant_du')::numeric), 1) end,
        'alertes_decrochage', coalesce(sum((x ->> 'alertes_decrochage')::int), 0),
        'personnel', coalesce(sum((x ->> 'personnel')::int), 0),
        'enseignants', coalesce(sum((x ->> 'enseignants')::int), 0))
      from jsonb_array_elements(v_ecoles) x),
    'genere_le', now());
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Droits d'exécution
-- ---------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'public.soumettre_demande_reseau(uuid, text, text, text, text, text, text, text, text, text, text)',
    'public.demandes_reseau_a_traiter()',
    'public.traiter_demande_reseau(uuid, boolean, text, boolean)',
    'public.nommer_responsable_reseau(uuid, text, text)',
    'public.retirer_responsable_reseau(uuid, uuid)',
    'public.rechercher_etablissements_reseau(uuid, text)',
    'public.inviter_etablissement_reseau(uuid, uuid)',
    'public.repondre_invitation_reseau(uuid, uuid, boolean)',
    'public.demander_retrait_reseau(uuid, uuid, text)',
    'public.decider_retrait_reseau(uuid, uuid, boolean)',
    'public.dissoudre_reseau(uuid, text)',
    'public.mes_reseaux()',
    'public.reseaux_vue_ensemble()',
    'public.publier_circulaire_reseau(uuid, uuid, text, text, boolean)',
    'public.circulaires_reseau_liste(uuid)',
    'public.marquer_circulaire_lue(uuid)',
    'public.enregistrer_evenement_reseau(uuid, uuid, text, text, date, date, text)',
    'public.supprimer_evenement_reseau(uuid)',
    'public.evenements_reseau_liste(uuid, uuid)',
    'public.importer_evenement_reseau(uuid, uuid)',
    'public.tableau_bord_reseau(uuid)',
    'public.role_reseau(uuid)',
    'public.pilote_reseau(uuid)',
    'public.voit_reseau(uuid)',
    'public.texte_recherche(text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

revoke all on function public.directions_etablissement(uuid) from public, anon, authenticated;
revoke all on function public.demandes_reseau_notifier() from public, anon, authenticated;
