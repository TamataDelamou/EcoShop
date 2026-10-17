-- ============================================================================
-- EcoShop — REG-04 (fin) : file d'envoi des notifications (courriel Brevo)
--
-- Clôt le reste de REG-04 : le fondateur reçoit un courriel quand sa demande
-- de création d'établissement est reçue, puis quand elle est acceptée ou
-- refusée ; l'équipe GSG est prévenue de chaque nouvelle demande.
--
-- Conception (« boîte d'envoi transactionnelle », transactional outbox) :
--   • Le message est mis en file DANS LA MÊME TRANSACTION que l'événement
--     métier (déclencheur sur demandes_etablissement). Pas de courriel
--     fantôme si la transaction échoue, pas de courriel perdu si elle réussit.
--   • L'Edge Function `envoyer_notifications` (planifiée) réserve un lot avec
--     FOR UPDATE SKIP LOCKED et un bail de 5 min : deux passages simultanés
--     ne prennent jamais le même message, et un passage interrompu libère
--     ses messages à l'expiration du bail.
--   • Échec temporaire (réseau, 429, 5xx) : nouvel essai avec attente
--     croissante (1 min, 5 min, 30 min, 2 h, 12 h, ± 20 %) ; 6 tentatives
--     au plus. Échec définitif (adresse refusée, 4xx) : arrêt immédiat.
--   • Clé d'idempotence unique par événement : un même événement ne peut
--     jamais produire deux messages ; elle est aussi transmise à Brevo.
--   • Minimisation : seules les données nécessaires au message sont
--     stockées ; les messages envoyés sont purgés après 90 jours.
--   • Table secrète : RLS sans politique, aucun droit pour anon/authenticated ;
--     fonctions de traitement réservées à service_role.
--
-- Le canal « sms » est prévu dans le schéma (Orange SMS Guinée ou Brevo, à
-- arbitrer) mais aucun message SMS n'est encore produit.
--
-- Migration idempotente.
-- ============================================================================

create table if not exists public.notifications_sortantes (
  id uuid primary key default gen_random_uuid(),
  canal text not null default 'email' check (canal in ('email', 'sms')),
  modele text not null check (modele ~ '^[a-z_]{3,60}$'),
  destinataire text,
  destinataire_role text check (destinataire_role is null or destinataire_role in ('admin_gsg')),
  donnees jsonb not null default '{}'::jsonb,
  cle_idempotence text not null,
  statut text not null default 'a_envoyer'
    check (statut in ('a_envoyer', 'en_cours', 'envoyee', 'echec_definitif', 'annulee')),
  tentatives integer not null default 0 check (tentatives >= 0),
  prochaine_tentative_le timestamptz not null default now(),
  verrou_jusqu_a timestamptz,
  identifiant_fournisseur text,
  derniere_erreur text,
  envoyee_le timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notifications_destinataire_present check (destinataire is not null or destinataire_role is not null)
);

create unique index if not exists idx_notifications_cle_idempotence
  on public.notifications_sortantes (cle_idempotence);
create index if not exists idx_notifications_a_traiter
  on public.notifications_sortantes (prochaine_tentative_le)
  where statut in ('a_envoyer', 'en_cours');

drop trigger if exists notifications_set_updated_at on public.notifications_sortantes;
create trigger notifications_set_updated_at
  before update on public.notifications_sortantes
  for each row execute function public.set_updated_at();

alter table public.notifications_sortantes enable row level security;
revoke all on public.notifications_sortantes from public, anon, authenticated;
grant all on public.notifications_sortantes to service_role;

-- ---------------------------------------------------------------------------
-- 1. Mise en file (interne : appelée par les déclencheurs, jamais par un client)
-- ---------------------------------------------------------------------------
create or replace function public.mettre_notification_en_file(
  p_modele text,
  p_cle_idempotence text,
  p_donnees jsonb,
  p_destinataire text default null,
  p_destinataire_role text default null,
  p_canal text default 'email'
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_dest text := nullif(lower(trim(p_destinataire)), '');
begin
  if v_dest is null and p_destinataire_role is null then
    return null;  -- aucun moyen de joindre la personne : rien à envoyer
  end if;
  if v_dest is not null and p_canal = 'email' and v_dest !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return null;
  end if;

  insert into public.notifications_sortantes (canal, modele, destinataire, destinataire_role, donnees, cle_idempotence)
  values (p_canal, p_modele, v_dest, p_destinataire_role, coalesce(p_donnees, '{}'::jsonb), p_cle_idempotence)
  on conflict (cle_idempotence) do nothing
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Événements REG-04 → messages
-- ---------------------------------------------------------------------------
create or replace function public.demandes_etab_notifier()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_courriel text;
  v_prenom text;
  v_pays text;
  v_reference text := upper(substr(replace(new.id::text, '-', ''), 1, 8));
  v_base jsonb;
begin
  select u.email into v_courriel from auth.users u where u.id = new.demandeur_id;
  select nullif(trim(p.prenom), '') into v_prenom from public.profiles p where p.id = new.demandeur_id;
  select pp.nom into v_pays from public.pays_pedagogiques pp where pp.code_iso = new.pays_code;

  v_base := jsonb_build_object(
    'prenom', v_prenom,
    'nom_etablissement', new.nom_etablissement,
    'ville', new.ville,
    'pays', coalesce(v_pays, new.pays_code),
    'reference', v_reference
  );

  -- L'adresse saisie dans la demande prime ; à défaut, celle du compte.
  v_courriel := coalesce(new.email, v_courriel);

  if tg_op = 'INSERT' then
    perform public.mettre_notification_en_file(
      'demande_etablissement_recue', 'demande_recue:' || new.id, v_base, v_courriel);
    perform public.mettre_notification_en_file(
      'demande_etablissement_a_traiter', 'demande_a_traiter:' || new.id,
      v_base || jsonb_build_object('effectif_estime', new.effectif_estime),
      null, 'admin_gsg');
  elsif tg_op = 'UPDATE' and old.statut = 'en_attente' and new.statut = 'acceptee' then
    perform public.mettre_notification_en_file(
      'demande_etablissement_acceptee', 'demande_acceptee:' || new.id, v_base, v_courriel);
  elsif tg_op = 'UPDATE' and old.statut = 'en_attente' and new.statut = 'refusee' then
    perform public.mettre_notification_en_file(
      'demande_etablissement_refusee', 'demande_refusee:' || new.id,
      v_base || jsonb_build_object('motif', new.motif_refus), v_courriel);
  end if;

  return null;
end;
$$;

drop trigger if exists demandes_etab_notifier on public.demandes_etablissement;
create trigger demandes_etab_notifier
  after insert or update of statut on public.demandes_etablissement
  for each row execute function public.demandes_etab_notifier();

-- ---------------------------------------------------------------------------
-- 3. Traitement par l'Edge Function (service_role uniquement)
-- ---------------------------------------------------------------------------
create or replace function public.reserver_notifications(p_limite integer default 20)
returns table (
  id uuid,
  canal text,
  modele text,
  destinataire text,
  destinataire_role text,
  donnees jsonb,
  cle_idempotence text,
  tentatives integer
)
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  -- Bail expiré après la dernière tentative autorisée : abandon définitif.
  update public.notifications_sortantes n
     set statut = 'echec_definitif',
         verrou_jusqu_a = null,
         derniere_erreur = coalesce(n.derniere_erreur, 'BAIL_EXPIRE')
   where n.statut = 'en_cours' and n.verrou_jusqu_a < now() and n.tentatives >= 6;

  return query
  with lot as (
    select n.id
      from public.notifications_sortantes n
     where (n.statut = 'a_envoyer' and n.prochaine_tentative_le <= now())
        or (n.statut = 'en_cours' and n.verrou_jusqu_a < now())
     order by n.prochaine_tentative_le
     limit greatest(1, least(coalesce(p_limite, 20), 100))
     for update skip locked
  )
  update public.notifications_sortantes n
     set statut = 'en_cours',
         verrou_jusqu_a = now() + interval '5 minutes',
         tentatives = n.tentatives + 1
    from lot
   where n.id = lot.id
  returning n.id, n.canal, n.modele, n.destinataire, n.destinataire_role, n.donnees, n.cle_idempotence, n.tentatives;
end;
$$;

create or replace function public.marquer_notification_envoyee(p_id uuid, p_identifiant_fournisseur text)
returns boolean
language plpgsql
volatile
security definer
set search_path = public
as $$
begin
  update public.notifications_sortantes
     set statut = 'envoyee',
         envoyee_le = now(),
         verrou_jusqu_a = null,
         derniere_erreur = null,
         identifiant_fournisseur = left(p_identifiant_fournisseur, 200)
   where id = p_id and statut = 'en_cours';
  return found;
end;
$$;

create or replace function public.marquer_notification_echec(p_id uuid, p_erreur text, p_definitif boolean default false)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  n public.notifications_sortantes;
  v_attentes integer[] := array[1, 5, 30, 120, 720];  -- minutes
  v_minutes numeric;
begin
  select * into n from public.notifications_sortantes where id = p_id for update;
  if n.id is null or n.statut <> 'en_cours' then
    return null;
  end if;

  if coalesce(p_definitif, false) or n.tentatives >= 6 then
    update public.notifications_sortantes
       set statut = 'echec_definitif', verrou_jusqu_a = null, derniere_erreur = left(p_erreur, 500)
     where id = p_id;
    return 'echec_definitif';
  end if;

  -- Attente croissante, ± 20 % pour étaler les reprises.
  v_minutes := v_attentes[least(n.tentatives, array_length(v_attentes, 1))] * (0.8 + random() * 0.4);
  update public.notifications_sortantes
     set statut = 'a_envoyer',
         verrou_jusqu_a = null,
         derniere_erreur = left(p_erreur, 500),
         prochaine_tentative_le = now() + make_interval(secs => v_minutes * 60)
   where id = p_id;
  return 'a_envoyer';
end;
$$;

-- Minimisation des données : on ne garde pas indéfiniment le contenu envoyé.
create or replace function public.purger_notifications(p_jours integer default 90)
returns integer
language sql
volatile
security definer
set search_path = public
as $$
  with supprimees as (
    delete from public.notifications_sortantes
     where statut in ('envoyee', 'echec_definitif', 'annulee')
       and updated_at < now() - make_interval(days => greatest(coalesce(p_jours, 90), 7))
    returning 1
  )
  select count(*)::integer from supprimees;
$$;

-- Vue d'ensemble pour la supervision (service_role / Kernel).
create or replace function public.indicateurs_notifications()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'a_envoyer', count(*) filter (where statut = 'a_envoyer'),
    'en_cours', count(*) filter (where statut = 'en_cours'),
    'envoyees_24h', count(*) filter (where statut = 'envoyee' and envoyee_le > now() - interval '24 hours'),
    'echecs_definitifs_7j', count(*) filter (where statut = 'echec_definitif' and updated_at > now() - interval '7 days'),
    'plus_ancienne_en_attente', min(created_at) filter (where statut in ('a_envoyer', 'en_cours'))
  )
  from public.notifications_sortantes;
$$;

revoke all on function public.mettre_notification_en_file(text, text, jsonb, text, text, text) from public, anon, authenticated;
revoke all on function public.demandes_etab_notifier() from public, anon, authenticated;
revoke all on function public.reserver_notifications(integer) from public, anon, authenticated;
revoke all on function public.marquer_notification_envoyee(uuid, text) from public, anon, authenticated;
revoke all on function public.marquer_notification_echec(uuid, text, boolean) from public, anon, authenticated;
revoke all on function public.purger_notifications(integer) from public, anon, authenticated;
revoke all on function public.indicateurs_notifications() from public, anon, authenticated;
grant execute on function public.reserver_notifications(integer) to service_role;
grant execute on function public.marquer_notification_envoyee(uuid, text) to service_role;
grant execute on function public.marquer_notification_echec(uuid, text, boolean) to service_role;
grant execute on function public.purger_notifications(integer) to service_role;
grant execute on function public.indicateurs_notifications() to service_role;
