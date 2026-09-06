-- ============================================================================
-- EcoShop — M9 — Communication & Notifications
--
-- Périmètre (ANALYSE_GLOBALE.md, cahier v4.1) :
--   • Notifications multicanal (SMS, WhatsApp, Email, Push) : absences/retards
--     (parents), notes/évaluations (parents/élèves), congés/sanctions
--     (personnel/direction), alertes décrochage, rappels d'événements.
--   • Préférences de canaux par utilisateur (actif, horaires, fréquence).
--   • Journal des envois (fournisseur, statut, erreur, retry, accusé).
--   • Modèles de messages par établissement, type et canal (variables).
--   • IA en trois niveaux : descriptive (taux de lecture), prédictive (moment
--     opportun), prescriptive (canal préféré, A/B, analyse sémantique).
--
-- Principes (cohérents M1→M8) :
--   • `etablissement_id` dénormalisé + garde-fou multi-tenant.
--   • Visibilité : le destinataire voit ses notifications ; direction/
--     administration voient tout + les logs ; les préférences sont privées.
--   • IA = signaux d'aide, jamais d'envoi automatique aux heures inopportunes
--     sans règle éthique (opt-out par canal, minimisation des données).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Types énumérés
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.canal_notification as enum ('sms', 'whatsapp', 'email', 'push');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.statut_notification as enum ('en_attente', 'envoyee', 'lue', 'echouee', 'annulee');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.statut_envoi as enum ('envoye', 'echoue', 'en_retry');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.frequence_notification as enum ('immediat', 'quotidien', 'hebdomadaire');
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Notifications
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  destinataire uuid not null references public.profiles (id) on delete cascade,
  type text not null,
  canal public.canal_notification not null default 'sms',
  contenu text not null default '',
  variante text,                             -- 'A'/'B' pour les tests A/B
  variables jsonb not null default '{}'::jsonb,
  statut public.statut_notification not null default 'en_attente',
  date_envoi_planifie timestamptz,
  date_envoi timestamptz,
  date_lecture timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint notifications_type_non_vide check (length(type) > 0)
);

-- ---------------------------------------------------------------------------
-- 2. Préférences de canaux (par utilisateur)
-- ---------------------------------------------------------------------------
create table if not exists public.preferences_canaux (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  canal public.canal_notification not null,
  actif boolean not null default true,
  horaire_debut time not null default '08:00',
  horaire_fin time not null default '19:00',
  frequence public.frequence_notification not null default 'immediat',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint prefs_canal_unique unique (profile_id, canal),
  constraint prefs_horaires_coherents check (horaire_debut <= horaire_fin)
);

-- ---------------------------------------------------------------------------
-- 3. Journal des envois (fournisseur, statut, retry, accusé de réception)
-- ---------------------------------------------------------------------------
create table if not exists public.logs_envois (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  notification_id uuid not null references public.notifications (id) on delete cascade,
  fournisseur text not null default '',
  statut public.statut_envoi not null default 'envoye',
  code_erreur text,
  date_retry timestamptz,
  message_id_fournisseur text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 4. Modèles de messages (par établissement, type et canal)
-- ---------------------------------------------------------------------------
create table if not exists public.templates_notifications (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  type text not null,
  canal public.canal_notification not null default 'sms',
  contenu text not null default '',
  variables jsonb not null default '[]'::jsonb,
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint templates_type_canal_unique unique (etablissement_id, type, canal)
);

-- ---------------------------------------------------------------------------
-- 5. Garde-fous multi-tenant
-- ---------------------------------------------------------------------------
create or replace function public.logs_envois_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.notifications where id = new.notification_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'NOTIFICATION_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists logs_envois_verifie_tenant_trg on public.logs_envois;
create trigger logs_envois_verifie_tenant_trg
  before insert or update on public.logs_envois
  for each row execute procedure public.logs_envois_verifie_tenant();

-- Lecture d'une notification : seuls le destinataire (ou le serveur) peuvent
-- marquer « lue ». Un destinataire ne peut pas altérer le contenu/canal/type.
create or replace function public.notifications_verifie_ecriture()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.date_lecture is distinct from old.date_lecture and new.date_lecture is not null then
    if auth.uid() is not null and auth.uid() <> new.destinataire then
      raise exception 'LECTURE_DESTINATAIRE' using errcode = '42501';
    end if;
  end if;

  if auth.uid() is not null and not public.est_comm(new.etablissement_id) then
    -- Appelant = destinataire (garanti par la policy) : champs immuables.
    if new.canal is distinct from old.canal
       or new.contenu is distinct from old.contenu
       or new.type is distinct from old.type
       or new.destinataire is distinct from old.destinataire
       or new.etablissement_id is distinct from old.etablissement_id then
      raise exception 'MODIFICATION_NON_AUTORISEE' using errcode = '42501';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists notifications_verifie_ecriture_trg on public.notifications;
create trigger notifications_verifie_ecriture_trg
  before update on public.notifications
  for each row execute procedure public.notifications_verifie_ecriture();

-- ---------------------------------------------------------------------------
-- 6. Helpers de visibilité (SECURITY DEFINER)
-- ---------------------------------------------------------------------------
create or replace function public.est_membre_etab(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.etablissements_membres m
    where m.profile_id = auth.uid() and m.etablissement_id = p_etablissement
      and m.actif and m.deleted_at is null
      and (m.date_fin is null or m.date_fin >= current_date)
  );
$$;

create or replace function public.est_comm(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.est_direction(p_etablissement)
      or public.a_permission(p_etablissement, 'comm.notifier');
$$;

create or replace function public.notif_visible(p_notification uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.notifications n
    where n.id = p_notification and n.deleted_at is null
      and (n.destinataire = auth.uid() or public.est_comm(n.etablissement_id))
  );
$$;

grant execute on function public.est_membre_etab(uuid) to authenticated;
grant execute on function public.est_comm(uuid) to authenticated;
grant execute on function public.notif_visible(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Fonctions IA — trois niveaux (descriptive / prédictive / prescriptive)
-- ---------------------------------------------------------------------------

-- Niveau descriptif : taux de lecture par canal sur une période.
create or replace function public.analyser_envois(p_etablissement uuid, p_debut date, p_fin date)
returns table (canal text, nb_envoyes bigint, nb_lus bigint, taux_lecture numeric)
language plpgsql stable security definer set search_path = public
as $$
begin
  if auth.uid() is not null and not public.est_comm(p_etablissement) then
    raise exception 'COMM_REQUIS' using errcode = '42501';
  end if;

  return query
  select n.canal::text,
         count(*)::bigint,
         count(n.date_lecture)::bigint,
         round((count(n.date_lecture)::numeric / nullif(count(*), 0)), 2)
  from public.notifications n
  where n.etablissement_id = p_etablissement
    and n.deleted_at is null
    and n.created_at::date between p_debut and p_fin
  group by n.canal
  order by n.canal::text;
end $$;

-- Niveau prédictif : moment opportun d'envoi (créneau préféré, sinon heure de
-- lecture la plus fréquente, sinon 09:00).
create or replace function public.suggere_heure_envoi(p_profile uuid)
returns time
language plpgsql stable security definer set search_path = public
as $$
declare v_heure time;
begin
  if auth.uid() is not null and auth.uid() <> p_profile then
    raise exception 'DESTINATAIRE_REQUIS' using errcode = '42501';
  end if;

  select p.horaire_debut into v_heure
  from public.preferences_canaux p
  where p.profile_id = p_profile and p.actif
  order by p.canal
  limit 1;

  if v_heure is null then
    select (n.date_lecture::time) into v_heure
    from public.notifications n
    where n.destinataire = p_profile and n.date_lecture is not null and n.deleted_at is null
    group by 1
    order by count(*) desc
    limit 1;
  end if;

  return coalesce(v_heure, time '09:00');
end $$;

-- Niveau prescriptif : canal préféré du destinataire (priorité WhatsApp > SMS
-- > Push > Email), repli SMS en l'absence de préférence.
create or replace function public.choisir_canal(p_profile uuid, p_type text)
returns text
language plpgsql stable security definer set search_path = public
as $$
declare v_canal text;
begin
  if auth.uid() is not null and auth.uid() <> p_profile then
    raise exception 'DESTINATAIRE_REQUIS' using errcode = '42501';
  end if;

  select p.canal::text into v_canal
  from public.preferences_canaux p
  where p.profile_id = p_profile and p.actif
  order by case p.canal
    when 'whatsapp' then 1
    when 'sms' then 2
    when 'push' then 3
    when 'email' then 4
  end
  limit 1;

  return coalesce(v_canal, 'sms');
end $$;

-- A/B testing : affectation déterministe d'une variante ('A'/'B') par
-- destinataire et type de message (stable dans le temps, sans état serveur).
create or replace function public.selectionner_variante(p_profile uuid, p_type text)
returns text
language sql stable security definer set search_path = public
as $$
  select case
    when (get_byte(decode(md5(p_profile::text || ':' || p_type), 'hex'), 0) % 2) = 0 then 'A'
    else 'B'
  end;
$$;

-- Analyse sémantique légère des retours (réponses parents/enseignants) :
-- classification de sentiment par lexique français simple.
create or replace function public.analyser_feedback(p_texte text)
returns text
language sql stable security definer set search_path = public
as $$
  select case
    when p_texte ~* '(merci|bien|super|parfait|ok|accord|compris|reçu|recu|oui|d''accord)' then 'positif'
    when p_texte ~* '(problème|probleme|erreur|faux|injuste|refus|non|jamais|incorrect|plainte)' then 'negatif'
    else 'neutre'
  end;
$$;

grant execute on function public.analyser_envois(uuid, date, date) to authenticated;
grant execute on function public.suggere_heure_envoi(uuid) to authenticated;
grant execute on function public.choisir_canal(uuid, text) to authenticated;
grant execute on function public.selectionner_variante(uuid, text) to authenticated;
grant execute on function public.analyser_feedback(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Row Level Security
-- ---------------------------------------------------------------------------
alter table public.notifications enable row level security;
alter table public.preferences_canaux enable row level security;
alter table public.logs_envois enable row level security;
alter table public.templates_notifications enable row level security;

-- Notifications : le destinataire voit les siennes ; direction/admin voient
-- tout l'établissement. Écriture par direction/admin (ou service_role).
drop policy if exists "notifications_select" on public.notifications;
create policy "notifications_select" on public.notifications
  for select using (public.notif_visible(id));

drop policy if exists "notifications_insert_comm" on public.notifications;
create policy "notifications_insert_comm" on public.notifications
  for insert
  with check (public.est_comm(etablissement_id));

drop policy if exists "notifications_update" on public.notifications;
create policy "notifications_update" on public.notifications
  for update
  using (public.est_comm(etablissement_id) or destinataire = auth.uid())
  with check (public.est_comm(etablissement_id) or destinataire = auth.uid());

-- Préférences de canaux : strictement personnelles.
drop policy if exists "preferences_select_own" on public.preferences_canaux;
create policy "preferences_select_own" on public.preferences_canaux
  for select using (profile_id = auth.uid());

drop policy if exists "preferences_ecriture_own" on public.preferences_canaux;
create policy "preferences_ecriture_own" on public.preferences_canaux
  for all
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

-- Logs d'envois : direction/admin uniquement.
drop policy if exists "logs_select_comm" on public.logs_envois;
create policy "logs_select_comm" on public.logs_envois
  for select using (public.est_comm(etablissement_id));

drop policy if exists "logs_ecriture_comm" on public.logs_envois;
create policy "logs_ecriture_comm" on public.logs_envois
  for all
  using (public.est_comm(etablissement_id))
  with check (public.est_comm(etablissement_id));

-- Modèles de messages : lecture par les membres, écriture par direction/admin.
drop policy if exists "templates_select_membre" on public.templates_notifications;
create policy "templates_select_membre" on public.templates_notifications
  for select using (public.est_membre_etab(etablissement_id));

drop policy if exists "templates_ecriture_comm" on public.templates_notifications;
create policy "templates_ecriture_comm" on public.templates_notifications
  for all
  using (public.est_comm(etablissement_id))
  with check (public.est_comm(etablissement_id));

-- ---------------------------------------------------------------------------
-- 9. Index
-- ---------------------------------------------------------------------------
create index if not exists idx_notifications_etablissement on public.notifications (etablissement_id);
create index if not exists idx_notifications_destinataire on public.notifications (destinataire);
create index if not exists idx_preferences_profile on public.preferences_canaux (profile_id);
create index if not exists idx_logs_notification on public.logs_envois (notification_id);
create index if not exists idx_templates_etablissement on public.templates_notifications (etablissement_id);

-- ---------------------------------------------------------------------------
-- 10. Permissions introduites par M9
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domaine, libelle, description) values
  ('comm.notifier',  'comm', 'Envoyer des notifications', 'Créer et envoyer des notifications aux destinataires.'),
  ('comm.voir_logs', 'comm', 'Consulter les logs d''envois', 'Accéder au journal des envois et aux accusés de réception.')
on conflict (code) do nothing;

-- ============================================================================
-- Fin M9.
-- ============================================================================
