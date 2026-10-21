-- ============================================================================
-- EcoShop — REG-09 : pointage des élèves au portail, alertes aux familles,
-- notifications push, crédits SMS (alertes et relances d'impayés)
--
-- Décisions du porteur de projet (2026-10-18) :
--   • GPS abandonné : carte d'élève à QR code scannée au portail par un
--     téléphone (ou une douchette) de l'école, hors connexion d'abord ;
--   • l'appel en classe (M7) reste la preuve officielle ; le portail sert
--     à prévenir vite et à repérer les écarts ;
--   • notifications automatiques en PUSH (gratuit) : arrivée et sortie,
--     absence non justifiée à l'heure limite, sortie anticipée ;
--   • GSG ne paie pas les SMS : l'établissement ACHÈTE des crédits SMS à
--     GSG (packs payés par CinetPay, circuit GSG, ou crédités par GSG) ;
--     chaque SMS est décompté ; sans crédit, push seul ; un SMS en échec
--     définitif est recrédité ;
--   • les crédits servent aussi aux RELANCES des familles en retard de
--     paiement de la scolarité.
--
-- Garde-fou : aucune alerte d'absence tant que le téléphone du portail n'a
-- pas transmis ses scans postérieurs à l'heure limite (sinon, un portail
-- resté sans réseau ferait croire toute l'école absente).
--
-- Tâches planifiées à créer au déploiement (pg_cron) :
--   detecter_absences_portail()  toutes les 10 minutes, jours de classe ;
--   envoi des notifications push et SMS : Edge Functions `envoyer_push`
--   et `envoyer_notifications`, chaque minute.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Paramètres du pointage (par établissement)
-- ---------------------------------------------------------------------------
create table if not exists public.parametres_pointage (
  etablissement_id uuid primary key references public.etablissements (id) on delete cascade,
  actif boolean not null default false,
  heure_limite_arrivee time not null default '08:15',
  heure_fin_cours time not null default '15:00',
  jours_classe smallint[] not null default '{1,2,3,4,5}',      -- 1 = lundi … 7 = dimanche
  notifier_arrivee_sortie boolean not null default true,
  sms_absence boolean not null default true,
  sms_sortie_anticipee boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint parametres_pointage_heures check (heure_limite_arrivee < heure_fin_cours)
);

-- Préférence de chaque parent / élève : recevoir ou non les avis
-- d'arrivée et de sortie (les alertes d'absence partent toujours).
create table if not exists public.preferences_pointage (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  arrivee_sortie boolean not null default true,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 2. Cartes d'élève : jeton secret imprimé dans le QR code (le numéro de
--    fiche seul ne suffit jamais : une carte ne se fabrique pas).
-- ---------------------------------------------------------------------------
create table if not exists public.cartes_eleves (
  fiche_eleve_id uuid primary key references public.fiches_eleves (id) on delete cascade,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  jeton text not null unique,
  version integer not null default 1,
  emise_le timestamptz not null default now()
);

create or replace function public.nouveau_jeton_carte()
returns text
language sql volatile
as $$
  select translate(encode(extensions.gen_random_bytes(12), 'base64'), '+/=', '-_');
$$;

-- ---------------------------------------------------------------------------
-- 3. Pointages, état des portails, autorisations, alertes
-- ---------------------------------------------------------------------------
create table if not exists public.pointages_portail (
  id uuid primary key,                         -- clé générée par le téléphone du portail
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  sens text not null check (sens in ('arrivee', 'sortie')),
  jour date not null,                          -- date locale de l'établissement
  scanne_le timestamptz not null,
  recu_le timestamptz not null default now(),
  en_retard boolean not null default false,
  appareil_id text,
  saisi_par uuid references public.profiles (id)
);
create index if not exists idx_pointages_etab_jour on public.pointages_portail (etablissement_id, jour);
create index if not exists idx_pointages_fiche_jour on public.pointages_portail (fiche_eleve_id, jour);

create table if not exists public.etats_portail (
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  appareil_id text not null,
  derniere_synchro timestamptz not null default now(),
  primary key (etablissement_id, appareil_id)
);

create table if not exists public.autorisations_sortie (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  jour date not null,
  motif text not null,
  accordee_par uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  constraint autorisations_sortie_unique unique (fiche_eleve_id, jour)
);

create table if not exists public.alertes_presence (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  jour date not null,
  type text not null check (type in ('absence', 'sortie_anticipee')),
  sms_envoyes integer not null default 0,
  created_at timestamptz not null default now(),
  constraint alertes_presence_unique unique (fiche_eleve_id, jour, type)
);

create table if not exists public.traitements_absences (
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  jour date not null,
  traite_le timestamptz not null default now(),
  alertes integer not null default 0,
  primary key (etablissement_id, jour)
);

-- ---------------------------------------------------------------------------
-- 4. Crédits SMS
-- ---------------------------------------------------------------------------
create table if not exists public.packs_sms (
  code text primary key check (code ~ '^[a-z0-9_]{2,30}$'),
  libelle text not null,
  quantite integer not null check (quantite > 0),
  prix numeric(12, 2) not null check (prix >= 0),
  devise text not null default 'GNF',
  actif boolean not null default false
);

-- Packs proposés ; prix à fixer par GSG (inactifs tant que le prix est 0).
insert into public.packs_sms (code, libelle, quantite, prix, actif) values
  ('sms_500', '500 SMS', 500, 0, false),
  ('sms_2000', '2 000 SMS', 2000, 0, false),
  ('sms_10000', '10 000 SMS', 10000, 0, false)
on conflict (code) do nothing;

create table if not exists public.credits_sms (
  etablissement_id uuid primary key references public.etablissements (id) on delete cascade,
  solde integer not null default 0 check (solde >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.mouvements_credits_sms (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  quantite integer not null,                   -- + achat / remboursement, − envoi
  motif text not null check (motif in ('achat', 'envoi', 'remboursement', 'ajustement')),
  reference text,
  notification_id uuid,
  cree_par uuid references public.profiles (id),
  created_at timestamptz not null default now()
);
create index if not exists idx_mouvements_sms_etab on public.mouvements_credits_sms (etablissement_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 5. Relances d'impayés et jetons push
-- ---------------------------------------------------------------------------
create table if not exists public.relances_impayes (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  inscription_id uuid not null references public.inscriptions (id) on delete cascade,
  montant_en_retard numeric(12, 2) not null,
  sms boolean not null default false,
  envoyee_par uuid references public.profiles (id),
  created_at timestamptz not null default now()
);
create index if not exists idx_relances_inscription on public.relances_impayes (inscription_id, created_at desc);

create table if not exists public.jetons_push (
  jeton text primary key,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  plateforme text not null default 'android' check (plateforme in ('android', 'ios', 'web')),
  updated_at timestamptz not null default now()
);
create index if not exists idx_jetons_push_profile on public.jetons_push (profile_id);

-- Suivi de l'envoi push des notifications de l'application (M9).
alter table public.notifications
  add column if not exists push_tentatives integer not null default 0,
  add column if not exists push_verrou_jusqu_a timestamptz;
create index if not exists idx_notifications_push_a_envoyer
  on public.notifications (created_at) where canal = 'push' and statut = 'en_attente';

-- ---------------------------------------------------------------------------
-- 6. Fonctions d'aide
-- ---------------------------------------------------------------------------
create or replace function public.gere_presences(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.est_direction(p_etablissement)
      or public.a_permission(p_etablissement, 'scolarite.presence.gerer');
$$;

create or replace function public.fuseau_etablissement(p_etablissement uuid)
returns text
language sql stable security definer set search_path = public
as $$
  select coalesce(nullif(fuseau_horaire, ''), 'Africa/Conakry') from public.etablissements where id = p_etablissement;
$$;

-- Numéro de téléphone d'un compte, chiffres seuls (format international).
create or replace function public.telephone_profil(p_profile uuid)
returns text
language sql stable security definer set search_path = public, auth
as $$
  select nullif(regexp_replace(coalesce(
           nullif(u.phone, ''),
           case when p.identifiant_canonique ~ '^\+?[0-9]{8,15}$' then p.identifiant_canonique end, ''), '[^0-9]', '', 'g'), '')
  from public.profiles p
  left join auth.users u on u.id = p.id
  where p.id = p_profile;
$$;

-- Texte SMS en alphabet GSM 7 bits (160 caractères par SMS au lieu de 70) :
-- les accents absents de cet alphabet sont remplacés.
create or replace function public.texte_sms(p_texte text)
returns text
language sql immutable
as $$
  select translate(
    replace(replace(replace(coalesce(p_texte, ''), 'œ', 'oe'), 'Œ', 'OE'), '…', '...'),
    'âêîôûçëïÂÊÎÔÛËÏ’‘“”«»–—',
    'aeioucei' || 'AEIOUEI' || '''''""""--');
$$;

create or replace function public.segments_sms(p_texte text)
returns integer
language sql immutable
as $$
  select case when length(p_texte) <= 160 then 1 else ceil(length(p_texte) / 153.0)::int end;
$$;

-- Destinataires des avis concernant un élève : les parents confirmés ; à
-- défaut, l'élève lui-même s'il a un compte (élève autonome).
create or replace function public.destinataires_eleve(p_fiche uuid)
returns setof uuid
language sql stable security definer set search_path = public
as $$
  with parents as (
    select r.parent_profile_id as id
    from public.relations_parent_eleve r
    where r.fiche_eleve_id = p_fiche and r.statut = 'confirmee' and r.autorise and r.deleted_at is null
  )
  select id from parents
  union
  select f.profile_id from public.fiches_eleves f
  where f.id = p_fiche and f.profile_id is not null and not exists (select 1 from parents);
$$;

-- Payeur(s) de la scolarité : l'élève s'il est à sa charge, sinon les parents.
create or replace function public.payeurs_eleve(p_fiche uuid)
returns setof uuid
language sql stable security definer set search_path = public
as $$
  select f.profile_id from public.fiches_eleves f
  where f.id = p_fiche and f.responsable_financier = 'eleve' and f.profile_id is not null
  union
  select d from public.destinataires_eleve(p_fiche) d
  where not exists (select 1 from public.fiches_eleves f
                    where f.id = p_fiche and f.responsable_financier = 'eleve' and f.profile_id is not null);
$$;

-- Notification push (boîte de l'application + envoi push).
create or replace function public.notifier_push(
  p_etablissement uuid, p_destinataire uuid, p_type text, p_contenu text, p_variables jsonb default '{}'::jsonb)
returns void
language sql volatile security definer set search_path = public
as $$
  insert into public.notifications (etablissement_id, destinataire, type, canal, contenu, variables, statut)
  values (p_etablissement, p_destinataire, p_type, 'push'::public.canal_notification, p_contenu,
          coalesce(p_variables, '{}'::jsonb), 'en_attente'::public.statut_notification);
$$;

-- SMS payé sur le crédit de l'établissement. Renvoie vrai si le SMS est
-- parti en file ; faux sans crédit suffisant ou sans numéro.
create or replace function public.envoyer_sms_etablissement(
  p_etablissement uuid, p_destinataire uuid, p_texte text, p_cle text)
returns boolean
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_telephone text := public.telephone_profil(p_destinataire);
  v_texte text := public.texte_sms(p_texte);
  v_segments integer;
  v_notification uuid;
begin
  if v_telephone is null then
    return false;
  end if;
  if exists (select 1 from public.notifications_sortantes where cle_idempotence = p_cle) then
    return true;
  end if;
  v_segments := public.segments_sms(v_texte);

  update public.credits_sms set solde = solde - v_segments, updated_at = now()
   where etablissement_id = p_etablissement and solde >= v_segments;
  if not found then
    return false;
  end if;

  v_notification := public.mettre_notification_en_file(
    'sms_etablissement', p_cle,
    jsonb_build_object('message', v_texte, 'etablissement_id', p_etablissement, 'segments', v_segments),
    v_telephone, null, 'sms');
  insert into public.mouvements_credits_sms (etablissement_id, quantite, motif, reference, notification_id)
  values (p_etablissement, -v_segments, 'envoi', p_cle, v_notification);
  return true;
end;
$$;

-- SMS en échec définitif : le crédit est rendu à l'établissement.
create or replace function public.rembourser_sms_echoue()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_etab uuid := (new.donnees->>'etablissement_id')::uuid;
  v_segments integer := coalesce((new.donnees->>'segments')::int, 1);
begin
  if new.canal = 'sms' and new.statut = 'echec_definitif' and old.statut <> 'echec_definitif' and v_etab is not null then
    update public.credits_sms set solde = solde + v_segments, updated_at = now() where etablissement_id = v_etab;
    insert into public.mouvements_credits_sms (etablissement_id, quantite, motif, reference, notification_id)
    values (v_etab, v_segments, 'remboursement', new.cle_idempotence, new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists notifications_sortantes_remboursement_sms on public.notifications_sortantes;
create trigger notifications_sortantes_remboursement_sms
  after update of statut on public.notifications_sortantes
  for each row execute function public.rembourser_sms_echoue();

create or replace function public.crediter_sms_interne(
  p_etablissement uuid, p_quantite integer, p_motif text, p_reference text, p_par uuid)
returns integer
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_solde integer;
begin
  insert into public.credits_sms (etablissement_id, solde) values (p_etablissement, 0)
  on conflict (etablissement_id) do nothing;
  update public.credits_sms set solde = solde + p_quantite, updated_at = now()
   where etablissement_id = p_etablissement
  returning solde into v_solde;
  insert into public.mouvements_credits_sms (etablissement_id, quantite, motif, reference, cree_par)
  values (p_etablissement, p_quantite, p_motif, p_reference, p_par);
  return v_solde;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Direction : paramètres, cartes, autorisations
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_parametres_pointage(
  p_etablissement uuid,
  p_actif boolean,
  p_heure_limite_arrivee time,
  p_heure_fin_cours time,
  p_jours_classe smallint[] default '{1,2,3,4,5}',
  p_notifier_arrivee_sortie boolean default true,
  p_sms_absence boolean default true,
  p_sms_sortie_anticipee boolean default true
)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if not public.gere_presences(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_heure_limite_arrivee >= p_heure_fin_cours then
    raise exception 'HEURES_INCOHERENTES' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(coalesce(p_jours_classe, '{}')) j where j not between 1 and 7) then
    raise exception 'JOURS_INVALIDES' using errcode = '22023';
  end if;
  insert into public.parametres_pointage (etablissement_id, actif, heure_limite_arrivee, heure_fin_cours, jours_classe,
    notifier_arrivee_sortie, sms_absence, sms_sortie_anticipee)
  values (p_etablissement, p_actif, p_heure_limite_arrivee, p_heure_fin_cours, coalesce(p_jours_classe, '{1,2,3,4,5}'),
    p_notifier_arrivee_sortie, p_sms_absence, p_sms_sortie_anticipee)
  on conflict (etablissement_id) do update set
    actif = excluded.actif, heure_limite_arrivee = excluded.heure_limite_arrivee,
    heure_fin_cours = excluded.heure_fin_cours, jours_classe = excluded.jours_classe,
    notifier_arrivee_sortie = excluded.notifier_arrivee_sortie, sms_absence = excluded.sms_absence,
    sms_sortie_anticipee = excluded.sms_sortie_anticipee, updated_at = now();
end;
$$;

-- Cartes d'une classe (émises au besoin) pour l'impression.
create or replace function public.cartes_classe(p_classe uuid, p_regenerer boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_etab uuid;
  v_annee uuid;
begin
  select etablissement_id, annee_scolaire_id into v_etab, v_annee from public.classes where id = p_classe;
  if v_etab is null or not public.gere_presences(v_etab) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  insert into public.cartes_eleves (fiche_eleve_id, etablissement_id, jeton)
  select i.fiche_eleve_id, v_etab, public.nouveau_jeton_carte()
  from public.inscriptions i
  where i.classe_id = p_classe and i.deleted_at is null and i.statut in ('active', 'redoublante')
  on conflict (fiche_eleve_id) do update
    set jeton = case when p_regenerer then public.nouveau_jeton_carte() else public.cartes_eleves.jeton end,
        version = case when p_regenerer then public.cartes_eleves.version + 1 else public.cartes_eleves.version end,
        emise_le = case when p_regenerer then now() else public.cartes_eleves.emise_le end;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'fiche_eleve_id', f.id, 'matricule', f.matricule, 'nom', f.nom, 'prenom', f.prenom,
      'date_naissance', f.date_naissance, 'classe', c.nom, 'jeton', k.jeton, 'version', k.version)
      order by f.nom, f.prenom)
    from public.inscriptions i
    join public.fiches_eleves f on f.id = i.fiche_eleve_id
    join public.classes c on c.id = i.classe_id
    join public.cartes_eleves k on k.fiche_eleve_id = f.id
    where i.classe_id = p_classe and i.deleted_at is null and i.statut in ('active', 'redoublante')), '[]'::jsonb);
end;
$$;

-- Une carte perdue : nouvelle carte, l'ancienne ne passe plus.
create or replace function public.remplacer_carte(p_fiche uuid)
returns text
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_etab uuid;
  v_jeton text := public.nouveau_jeton_carte();
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = p_fiche;
  if v_etab is null or not public.gere_presences(v_etab) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  insert into public.cartes_eleves (fiche_eleve_id, etablissement_id, jeton)
  values (p_fiche, v_etab, v_jeton)
  on conflict (fiche_eleve_id) do update
    set jeton = v_jeton, version = public.cartes_eleves.version + 1, emise_le = now();
  return v_jeton;
end;
$$;

-- Liste des cartes valides, gardée sur le téléphone du portail (nom affiché
-- au scan, même sans réseau).
create or replace function public.cartes_portail(p_etablissement uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.gere_presences(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'parametres', (select to_jsonb(p) from public.parametres_pointage p where p.etablissement_id = p_etablissement),
    'fuseau', public.fuseau_etablissement(p_etablissement),
    'cartes', coalesce((
      select jsonb_agg(jsonb_build_object('jeton', k.jeton, 'fiche_eleve_id', f.id, 'nom', f.nom, 'prenom', f.prenom,
                                          'classe', c.nom))
      from public.cartes_eleves k
      join public.fiches_eleves f on f.id = k.fiche_eleve_id and f.deleted_at is null
      join public.inscriptions i on i.fiche_eleve_id = f.id and i.deleted_at is null and i.statut in ('active', 'redoublante')
      join public.annees_scolaires a on a.id = i.annee_scolaire_id and a.courante
      join public.classes c on c.id = i.classe_id
      where k.etablissement_id = p_etablissement), '[]'::jsonb));
end;
$$;

create or replace function public.autoriser_sortie(p_fiche uuid, p_jour date, p_motif text)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_etab uuid;
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = p_fiche;
  if v_etab is null or not public.gere_presences(v_etab) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if coalesce(trim(p_motif), '') = '' then
    raise exception 'MOTIF_OBLIGATOIRE' using errcode = '22023';
  end if;
  insert into public.autorisations_sortie (etablissement_id, fiche_eleve_id, jour, motif, accordee_par)
  values (v_etab, p_fiche, p_jour, trim(p_motif), auth.uid())
  on conflict (fiche_eleve_id, jour) do update set motif = excluded.motif, accordee_par = excluded.accordee_par;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Le portail : scans (idempotents) et signal de synchronisation
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_pointage(
  p_id uuid,
  p_etablissement uuid,
  p_jeton text,
  p_sens text,
  p_scanne_le timestamptz,
  p_appareil text default null
)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_tz text := public.fuseau_etablissement(p_etablissement);
  v_scanne timestamptz := least(coalesce(p_scanne_le, now()), now());
  v_jour date;
  v_heure time;
  k public.cartes_eleves;
  f public.fiches_eleves;
  v_classe text;
  par public.parametres_pointage;
  v_retard boolean := false;
  v_premier boolean;
  v_dest uuid;
  v_texte text;
  v_transmis text := '';
  v_sms integer := 0;
begin
  if not public.gere_presences(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_sens not in ('arrivee', 'sortie') then
    raise exception 'SENS_INVALIDE' using errcode = '22023';
  end if;

  if exists (select 1 from public.pointages_portail where id = p_id) then
    return jsonb_build_object('statut', 'deja_recu');
  end if;

  select * into k from public.cartes_eleves
   where jeton = regexp_replace(coalesce(p_jeton, ''), '^ECO1\.', '') and etablissement_id = p_etablissement;
  if k.fiche_eleve_id is null then
    return jsonb_build_object('statut', 'carte_inconnue');
  end if;
  select * into f from public.fiches_eleves where id = k.fiche_eleve_id;
  select c.nom into v_classe from public.inscriptions i join public.classes c on c.id = i.classe_id
   join public.annees_scolaires a on a.id = i.annee_scolaire_id and a.courante
   where i.fiche_eleve_id = f.id and i.deleted_at is null limit 1;

  v_jour := (v_scanne at time zone v_tz)::date;
  v_heure := (v_scanne at time zone v_tz)::time;
  select * into par from public.parametres_pointage where etablissement_id = p_etablissement;

  -- Même élève, même sens, moins de 2 minutes : double passage de la carte.
  if exists (select 1 from public.pointages_portail
             where fiche_eleve_id = f.id and sens = p_sens and abs(extract(epoch from scanne_le - v_scanne)) < 120) then
    return jsonb_build_object('statut', 'doublon', 'nom', f.nom, 'prenom', f.prenom, 'classe', v_classe);
  end if;

  v_premier := not exists (select 1 from public.pointages_portail
                           where fiche_eleve_id = f.id and jour = v_jour and sens = p_sens);
  if p_sens = 'arrivee' and par.etablissement_id is not null then
    v_retard := v_heure > par.heure_limite_arrivee;
  end if;

  insert into public.pointages_portail (id, etablissement_id, fiche_eleve_id, sens, jour, scanne_le, en_retard,
                                        appareil_id, saisi_par)
  values (p_id, p_etablissement, f.id, p_sens, v_jour, v_scanne, v_retard, p_appareil, auth.uid());

  if p_appareil is not null then
    insert into public.etats_portail (etablissement_id, appareil_id, derniere_synchro)
    values (p_etablissement, p_appareil, now())
    on conflict (etablissement_id, appareil_id) do update set derniere_synchro = greatest(public.etats_portail.derniere_synchro, now());
  end if;

  -- Avis aux familles : seulement pour un scan du jour (un scan resté
  -- plusieurs jours sur un téléphone sans réseau ne réveille personne).
  if par.etablissement_id is not null and par.actif and v_jour = (now() at time zone v_tz)::date and v_premier then
    if now() - v_scanne > interval '10 minutes' then
      v_transmis := format(' (transmis à %s)', to_char(now() at time zone v_tz, 'HH24"h"MI'));
    end if;

    if p_sens = 'arrivee' and par.notifier_arrivee_sortie then
      v_texte := format('%s est arrivé(e) à l''école à %s%s%s.', f.prenom, to_char(v_heure, 'HH24"h"MI'),
                        case when v_retard then ', en retard' else '' end, v_transmis);
      for v_dest in select d from public.destinataires_eleve(f.id) d loop
        if coalesce((select arrivee_sortie from public.preferences_pointage where profile_id = v_dest), true) then
          perform public.notifier_push(p_etablissement, v_dest, 'pointage_arrivee', v_texte,
            jsonb_build_object('fiche_eleve_id', f.id, 'jour', v_jour, 'retard', v_retard));
        end if;
      end loop;
    elsif p_sens = 'sortie' then
      if v_heure < par.heure_fin_cours
         and not exists (select 1 from public.autorisations_sortie where fiche_eleve_id = f.id and jour = v_jour) then
        -- Sortie anticipée sans autorisation : alerte (push, et SMS si choisi).
        insert into public.alertes_presence (etablissement_id, fiche_eleve_id, jour, type)
        values (p_etablissement, f.id, v_jour, 'sortie_anticipee')
        on conflict (fiche_eleve_id, jour, type) do nothing;
        if found then
          v_texte := format('Attention : %s est sorti(e) de l''école à %s, avant la fin des cours, sans autorisation%s.',
                            f.prenom, to_char(v_heure, 'HH24"h"MI'), v_transmis);
          for v_dest in select d from public.destinataires_eleve(f.id) d loop
            perform public.notifier_push(p_etablissement, v_dest, 'alerte_sortie_anticipee', v_texte,
              jsonb_build_object('fiche_eleve_id', f.id, 'jour', v_jour));
            if par.sms_sortie_anticipee
               and public.envoyer_sms_etablissement(p_etablissement, v_dest, v_texte,
                     format('sortie:%s:%s:%s', f.id, v_jour, v_dest)) then
              v_sms := v_sms + 1;
            end if;
          end loop;
          update public.alertes_presence set sms_envoyes = v_sms
           where fiche_eleve_id = f.id and jour = v_jour and type = 'sortie_anticipee';
        end if;
      elsif par.notifier_arrivee_sortie then
        v_texte := format('%s est sorti(e) de l''école à %s%s.', f.prenom, to_char(v_heure, 'HH24"h"MI'), v_transmis);
        for v_dest in select d from public.destinataires_eleve(f.id) d loop
          if coalesce((select arrivee_sortie from public.preferences_pointage where profile_id = v_dest), true) then
            perform public.notifier_push(p_etablissement, v_dest, 'pointage_sortie', v_texte,
              jsonb_build_object('fiche_eleve_id', f.id, 'jour', v_jour));
          end if;
        end loop;
      end if;
    end if;
  end if;

  return jsonb_build_object('statut', 'enregistre', 'nom', f.nom, 'prenom', f.prenom, 'classe', v_classe,
                            'en_retard', v_retard, 'heure', to_char(v_heure, 'HH24:MI'));
end;
$$;

-- Le téléphone du portail signale qu'il n'a plus rien en attente : ses
-- scans sont arrivés (condition des alertes d'absence).
create or replace function public.signaler_portail(p_etablissement uuid, p_appareil text, p_en_attente integer default 0)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if not public.gere_presences(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if coalesce(p_en_attente, 0) > 0 then
    return;
  end if;
  insert into public.etats_portail (etablissement_id, appareil_id, derniere_synchro)
  values (p_etablissement, p_appareil, now())
  on conflict (etablissement_id, appareil_id) do update set derniere_synchro = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Détection des absences (tâche planifiée)
-- ---------------------------------------------------------------------------
-- Pour chaque établissement actif, un jour de classe, après l'heure limite :
-- si le portail a transmis ses scans postérieurs à l'heure limite, chaque
-- élève inscrit ni pointé à l'arrivée ni absent justifié à l'appel reçoit
-- une alerte (push, SMS si choisi et crédit disponible). Une fois par jour.
create or replace function public.detecter_absences_portail(p_etablissement uuid default null)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  par public.parametres_pointage;
  v_tz text;
  v_local timestamp;
  v_jour date;
  v_limite timestamptz;
  r record;
  v_dest uuid;
  v_texte text;
  v_sms integer;
  v_n integer;
  v_bilan jsonb := '[]'::jsonb;
begin
  for par in
    select * from public.parametres_pointage where actif and (p_etablissement is null or etablissement_id = p_etablissement)
  loop
    v_tz := public.fuseau_etablissement(par.etablissement_id);
    v_local := now() at time zone v_tz;
    v_jour := v_local::date;
    if not (extract(isodow from v_local)::smallint = any (par.jours_classe)) or v_local::time < par.heure_limite_arrivee then
      continue;
    end if;
    if exists (select 1 from public.traitements_absences where etablissement_id = par.etablissement_id and jour = v_jour) then
      continue;
    end if;
    v_limite := (v_jour + par.heure_limite_arrivee) at time zone v_tz;
    if not exists (select 1 from public.etats_portail
                   where etablissement_id = par.etablissement_id and derniere_synchro >= v_limite) then
      v_bilan := v_bilan || jsonb_build_object('etablissement_id', par.etablissement_id, 'etat', 'portail_non_synchronise');
      continue;
    end if;
    -- Aucun scan du jour : sans doute pas de classe (fête, grève) ; on ne
    -- prévient personne.
    if not exists (select 1 from public.pointages_portail where etablissement_id = par.etablissement_id and jour = v_jour) then
      insert into public.traitements_absences (etablissement_id, jour, alertes) values (par.etablissement_id, v_jour, 0);
      v_bilan := v_bilan || jsonb_build_object('etablissement_id', par.etablissement_id, 'etat', 'aucun_scan');
      continue;
    end if;

    v_n := 0;
    for r in
      select f.id, f.prenom
      from public.inscriptions i
      join public.annees_scolaires a on a.id = i.annee_scolaire_id and a.courante
      join public.fiches_eleves f on f.id = i.fiche_eleve_id and f.deleted_at is null
      where i.etablissement_id = par.etablissement_id and i.deleted_at is null and i.statut in ('active', 'redoublante')
        and not exists (select 1 from public.pointages_portail p
                        where p.fiche_eleve_id = f.id and p.jour = v_jour and p.sens = 'arrivee')
        and not exists (select 1 from public.presences pr
                        where pr.fiche_eleve_id = f.id and pr.date_presence = v_jour and pr.deleted_at is null
                          and pr.statut in ('absent', 'dispense') and pr.justifie)
    loop
      insert into public.alertes_presence (etablissement_id, fiche_eleve_id, jour, type)
      values (par.etablissement_id, r.id, v_jour, 'absence')
      on conflict (fiche_eleve_id, jour, type) do nothing;
      continue when not found;
      v_n := v_n + 1;
      v_sms := 0;
      v_texte := format('%s n''est pas arrivé(e) à l''école ce matin (%s). Si c''est normal, prévenez l''école.',
                        r.prenom, to_char(v_jour, 'DD/MM'));
      for v_dest in select d from public.destinataires_eleve(r.id) d loop
        perform public.notifier_push(par.etablissement_id, v_dest, 'alerte_absence', v_texte,
          jsonb_build_object('fiche_eleve_id', r.id, 'jour', v_jour));
        if par.sms_absence and public.envoyer_sms_etablissement(par.etablissement_id, v_dest, v_texte,
             format('absence:%s:%s:%s', r.id, v_jour, v_dest)) then
          v_sms := v_sms + 1;
        end if;
      end loop;
      update public.alertes_presence set sms_envoyes = v_sms
       where fiche_eleve_id = r.id and jour = v_jour and type = 'absence';
    end loop;

    insert into public.traitements_absences (etablissement_id, jour, alertes) values (par.etablissement_id, v_jour, v_n);
    v_bilan := v_bilan || jsonb_build_object('etablissement_id', par.etablissement_id, 'etat', 'traite', 'alertes', v_n);
  end loop;
  return v_bilan;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Tableau de présence du jour (Direction)
-- ---------------------------------------------------------------------------
create or replace function public.presence_du_jour(p_etablissement uuid, p_jour date default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_tz text := public.fuseau_etablissement(p_etablissement);
  v_jour date := coalesce(p_jour, (now() at time zone v_tz)::date);
  par public.parametres_pointage;
begin
  if not public.gere_presences(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select * into par from public.parametres_pointage where etablissement_id = p_etablissement;

  return (
    with eleves as (
      select f.id, f.nom, f.prenom, f.matricule, c.nom as classe, c.id as classe_id
      from public.inscriptions i
      join public.annees_scolaires a on a.id = i.annee_scolaire_id and a.courante
      join public.fiches_eleves f on f.id = i.fiche_eleve_id and f.deleted_at is null
      join public.classes c on c.id = i.classe_id
      where i.etablissement_id = p_etablissement and i.deleted_at is null and i.statut in ('active', 'redoublante')
    ),
    arr as (
      select distinct on (fiche_eleve_id) fiche_eleve_id, scanne_le, en_retard
      from public.pointages_portail where etablissement_id = p_etablissement and jour = v_jour and sens = 'arrivee'
      order by fiche_eleve_id, scanne_le
    ),
    sor as (
      select distinct on (fiche_eleve_id) fiche_eleve_id, scanne_le
      from public.pointages_portail where etablissement_id = p_etablissement and jour = v_jour and sens = 'sortie'
      order by fiche_eleve_id, scanne_le desc
    ),
    appel as (
      select fiche_eleve_id, bool_or(statut = 'absent') as absent_appel, bool_or(justifie) as justifie
      from public.presences
      where etablissement_id = p_etablissement and date_presence = v_jour and deleted_at is null
      group by fiche_eleve_id
    ),
    lignes as (
      select e.*, arr.scanne_le as arrivee, coalesce(arr.en_retard, false) as en_retard, sor.scanne_le as sortie,
             coalesce(ap.absent_appel, false) as absent_appel, coalesce(ap.justifie, false) as justifie,
             exists (select 1 from public.autorisations_sortie au where au.fiche_eleve_id = e.id and au.jour = v_jour) as sortie_autorisee,
             (select array_agg(type) from public.alertes_presence al where al.fiche_eleve_id = e.id and al.jour = v_jour) as alertes
      from eleves e
      left join arr on arr.fiche_eleve_id = e.id
      left join sor on sor.fiche_eleve_id = e.id
      left join appel ap on ap.fiche_eleve_id = e.id
    )
    select jsonb_build_object(
      'jour', v_jour,
      'actif', coalesce(par.actif, false),
      'heure_limite_arrivee', par.heure_limite_arrivee,
      'effectif', (select count(*) from lignes),
      'arrives', (select count(*) from lignes where arrivee is not null),
      'en_retard', (select count(*) from lignes where en_retard),
      'sortis', (select count(*) from lignes where sortie is not null),
      'traite', (select jsonb_build_object('traite_le', t.traite_le, 'alertes', t.alertes)
                 from public.traitements_absences t where t.etablissement_id = p_etablissement and t.jour = v_jour),
      'portails', coalesce((select jsonb_agg(jsonb_build_object('appareil_id', ep.appareil_id, 'derniere_synchro', ep.derniere_synchro)
                                             order by ep.derniere_synchro desc)
                            from public.etats_portail ep where ep.etablissement_id = p_etablissement), '[]'::jsonb),
      'eleves', coalesce((select jsonb_agg(jsonb_build_object(
          'fiche_eleve_id', l.id, 'nom', l.nom, 'prenom', l.prenom, 'matricule', l.matricule, 'classe', l.classe,
          'arrivee', l.arrivee, 'en_retard', l.en_retard, 'sortie', l.sortie,
          'absent_appel', l.absent_appel, 'justifie', l.justifie, 'sortie_autorisee', l.sortie_autorisee,
          'alertes', coalesce(to_jsonb(l.alertes), '[]'::jsonb),
          -- Écart : entré au portail mais absent à l'appel en classe.
          'ecart', l.arrivee is not null and l.absent_appel)
          order by l.classe, l.nom, l.prenom) from lignes l), '[]'::jsonb),
      'credits_sms', coalesce((select solde from public.credits_sms where etablissement_id = p_etablissement), 0)
    ) from (select 1) x
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Relances des familles en retard de paiement
-- ---------------------------------------------------------------------------
-- Retard = part annuelle exigible à ce jour (paliers dont la date limite est
-- passée) − payé. Sans palier daté : rien n'est exigible avant la fin.
create or replace function public.retards_paiement(p_etablissement uuid)
returns table (inscription_id uuid, fiche_eleve_id uuid, nom text, prenom text, classe text,
               exigible numeric, paye numeric, en_retard numeric, derniere_relance timestamptz)
language sql stable security definer set search_path = public
as $$
  with insc as (
    select i.id, i.fiche_eleve_id, i.annee_scolaire_id, f.nom, f.prenom, c.nom as classe
    from public.inscriptions i
    join public.annees_scolaires a on a.id = i.annee_scolaire_id and a.courante
    join public.fiches_eleves f on f.id = i.fiche_eleve_id and f.deleted_at is null
    join public.classes c on c.id = i.classe_id
    where i.etablissement_id = p_etablissement and i.deleted_at is null and i.statut in ('active', 'redoublante')
      and not coalesce(i.boursier, false)
  ),
  calc as (
    select insc.*, s.montant_du, s.montant_paye,
           round(s.montant_du * coalesce((
             select sum(p.pourcentage) from public.paliers_paiement_config p
             where p.etablissement_id = p_etablissement and p.annee_scolaire_id = insc.annee_scolaire_id
               and p.deleted_at is null and p.date_limite is not null and p.date_limite < current_date), 0) / 100) as exigible
    from insc, lateral public.solde_scolarite(insc.id) s
  )
  select id, fiche_eleve_id, nom, prenom, classe, exigible, montant_paye, exigible - montant_paye,
         (select max(r.created_at) from public.relances_impayes r where r.inscription_id = calc.id)
  from calc
  where exigible - montant_paye > 0
  order by classe, nom, prenom;
$$;

create or replace function public.apercu_relances_impayes(p_etablissement uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.gere_inscriptions(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'credits_sms', coalesce((select solde from public.credits_sms where etablissement_id = p_etablissement), 0),
    'familles', coalesce((select jsonb_agg(to_jsonb(r)) from public.retards_paiement(p_etablissement) r), '[]'::jsonb));
end;
$$;

-- Relance (push toujours ; SMS si demandé et crédit disponible) ; une même
-- famille n'est pas relancée deux fois en 7 jours.
create or replace function public.relancer_impayes(
  p_etablissement uuid, p_sms boolean default false, p_inscriptions uuid[] default null)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  r record;
  v_dest uuid;
  v_devise text;
  v_texte text;
  v_familles integer := 0;
  v_push integer := 0;
  v_sms integer := 0;
  v_sans_credit integer := 0;
  v_recentes integer := 0;
  v_avec_sms boolean;
  v_etab_nom text;
begin
  if not public.gere_inscriptions(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select devise_code, nom into v_devise, v_etab_nom from public.etablissements where id = p_etablissement;

  for r in select * from public.retards_paiement(p_etablissement)
           where p_inscriptions is null or inscription_id = any (p_inscriptions) loop
    if r.derniere_relance is not null and r.derniere_relance > now() - interval '7 days' then
      v_recentes := v_recentes + 1;
      continue;
    end if;
    v_familles := v_familles + 1;
    v_avec_sms := false;
    v_texte := format('%s : la scolarité de %s présente un retard de %s %s. Merci de régulariser (Orange Money dans l''application, ou à l''école).',
                      v_etab_nom, r.prenom, to_char(r.en_retard, 'FM999G999G999G990'), v_devise);
    for v_dest in select d from public.payeurs_eleve(r.fiche_eleve_id) d loop
      perform public.notifier_push(p_etablissement, v_dest, 'relance_impaye', v_texte,
        jsonb_build_object('inscription_id', r.inscription_id, 'montant', r.en_retard));
      v_push := v_push + 1;
      if p_sms then
        if public.envoyer_sms_etablissement(p_etablissement, v_dest, v_texte,
             format('relance:%s:%s:%s', r.inscription_id, current_date, v_dest)) then
          v_sms := v_sms + 1;
          v_avec_sms := true;
        else
          v_sans_credit := v_sans_credit + 1;
        end if;
      end if;
    end loop;
    insert into public.relances_impayes (etablissement_id, inscription_id, montant_en_retard, sms, envoyee_par)
    values (p_etablissement, r.inscription_id, r.en_retard, v_avec_sms, auth.uid());
  end loop;

  return jsonb_build_object('familles', v_familles, 'push', v_push, 'sms', v_sms,
                            'sms_non_envoyes', v_sans_credit, 'deja_relancees', v_recentes,
                            'credits_sms', coalesce((select solde from public.credits_sms where etablissement_id = p_etablissement), 0));
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. Achat de crédits SMS (circuit GSG)
-- ---------------------------------------------------------------------------
create or replace function public.definir_pack_sms(p_code text, p_libelle text, p_quantite integer, p_prix numeric, p_actif boolean)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if not public.est_admin_gsg() then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_actif and coalesce(p_prix, 0) <= 0 then
    raise exception 'PRIX_REQUIS' using errcode = '22023';
  end if;
  insert into public.packs_sms (code, libelle, quantite, prix, actif)
  values (p_code, p_libelle, p_quantite, p_prix, p_actif)
  on conflict (code) do update set libelle = excluded.libelle, quantite = excluded.quantite,
    prix = excluded.prix, actif = excluded.actif;
end;
$$;

-- Crédit direct par GSG (paiement reçu hors application, geste commercial).
create or replace function public.crediter_sms(p_etablissement uuid, p_quantite integer, p_reference text)
returns integer
language plpgsql volatile security definer set search_path = public
as $$
begin
  if not public.est_admin_gsg() then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_quantite = 0 then
    raise exception 'QUANTITE_INVALIDE' using errcode = '22023';
  end if;
  if coalesce(trim(p_reference), '') = '' then
    raise exception 'REFERENCE_OBLIGATOIRE' using errcode = '22023';
  end if;
  if p_quantite < 0 and coalesce((select solde from public.credits_sms where etablissement_id = p_etablissement), 0) < -p_quantite then
    raise exception 'SOLDE_INSUFFISANT' using errcode = '22023';
  end if;
  return public.crediter_sms_interne(p_etablissement, p_quantite,
    case when p_quantite > 0 then 'achat' else 'ajustement' end, trim(p_reference), auth.uid());
end;
$$;

create or replace function public.initier_achat_credits_sms(p_etablissement uuid, p_pack text)
returns public.transactions_cinetpay
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_pack public.packs_sms;
  v_row public.transactions_cinetpay;
begin
  if not (public.est_direction(p_etablissement) or public.est_admin_gsg()) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  select * into v_pack from public.packs_sms where code = p_pack and actif;
  if v_pack.code is null then
    raise exception 'PACK_INDISPONIBLE' using errcode = '22023';
  end if;
  insert into public.transactions_cinetpay (type_objet_paye, etablissement_id, initiateur_id, contexte, montant_attendu)
  values ('pack_sms_etablissement', p_etablissement, auth.uid(),
          jsonb_build_object('pack', v_pack.code, 'quantite', v_pack.quantite), v_pack.prix)
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function public.traiter_webhook_cinetpay(p_transaction_id uuid, p_signature text, p_montant numeric, p_moyen text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS transactions_cinetpay
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_secret text;
  v_message text;
  v_signature_attendue text;
  v_transaction public.transactions_cinetpay;
  v_annee uuid;
  v_effectif int;
begin
  select valeur ->> 'secret_verification_webhook' into v_secret
  from public.parametres_secrets_integration
  where cle = 'cinetpay_config';

  if v_secret is null or v_secret = '' then
    raise exception 'CINETPAY_NON_CONFIGURE' using errcode = '55000';
  end if;

  v_message := p_transaction_id::text || ':' || p_montant::text || ':' || coalesce(p_moyen, '');
  v_signature_attendue := encode(extensions.hmac(v_message::bytea, v_secret::bytea, 'sha256'), 'hex');

  if p_signature is null or p_signature <> v_signature_attendue then
    raise exception 'SIGNATURE_INVALIDE' using errcode = '42501';
  end if;

  select * into v_transaction
  from public.transactions_cinetpay
  where id = p_transaction_id
  for update;

  if v_transaction is null then
    raise exception 'TRANSACTION_INTROUVABLE' using errcode = '23514';
  end if;

  -- Idempotence : déjà traitée (rejeu CinetPay) -> no-op, jamais un second crédit.
  if v_transaction.statut <> 'initie' then
    return v_transaction;
  end if;

  if p_montant is distinct from v_transaction.montant_attendu then
    update public.transactions_cinetpay
    set statut = 'echoue', montant_confirme = p_montant, moyen_paiement = p_moyen,
        payload_webhook = p_payload, updated_at = now()
    where id = p_transaction_id
    returning * into v_transaction;

    return v_transaction;
  end if;

  update public.transactions_cinetpay
  set statut = 'reussi', montant_confirme = p_montant, moyen_paiement = p_moyen,
      payload_webhook = p_payload, updated_at = now()
  where id = p_transaction_id
  returning * into v_transaction;

  v_annee := (v_transaction.contexte ->> 'annee_scolaire_id')::uuid;

  case v_transaction.type_objet_paye
    when 'licence_pro_etablissement' then
      -- Recompte EN DIRECT, jamais effectif_a_l_initiation (peut être
      -- périmé si le webhook arrive après un délai) -- correction actée.
      v_effectif := public.compter_effectif_actif(v_transaction.etablissement_id, v_annee);
      perform public.appliquer_paiement_licence_pro(
        v_transaction.etablissement_id, v_annee, v_effectif, v_transaction.montant_confirme
      );
    when 'frais_ia_admin_etablissement' then
      perform public.appliquer_paiement_frais_ia_admin(
        v_transaction.etablissement_id, v_annee, v_transaction.montant_confirme
      );
    when 'abonnement_premium_eleve' then
      perform public.appliquer_paiement_abonnement_premium_eleve(
        v_transaction.beneficiaire_fiche_eleve_id, v_transaction.formule, v_transaction.montant_confirme
      );
    when 'pack_sms_etablissement' then
      -- REG-09 : crédits SMS achetés à GSG.
      perform public.crediter_sms_interne(
        v_transaction.etablissement_id, (v_transaction.contexte ->> 'quantite')::int, 'achat',
        'CINETPAY:' || coalesce(v_transaction.reference_cinetpay, v_transaction.id::text), v_transaction.initiateur_id
      );
  end case;

  return v_transaction;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 13. Push : jetons des téléphones, envoi (Edge Function `envoyer_push`)
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_jeton_push(p_jeton text, p_plateforme text default 'android')
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '42501';
  end if;
  if length(coalesce(p_jeton, '')) < 20 then
    raise exception 'JETON_INVALIDE' using errcode = '22023';
  end if;
  -- Un téléphone change de compte : le jeton suit le dernier compte connecté.
  insert into public.jetons_push (jeton, profile_id, plateforme)
  values (p_jeton, auth.uid(), coalesce(p_plateforme, 'android'))
  on conflict (jeton) do update set profile_id = excluded.profile_id, plateforme = excluded.plateforme, updated_at = now();
end;
$$;

create or replace function public.retirer_jeton_push(p_jeton text)
returns void
language sql volatile security definer set search_path = public
as $$
  delete from public.jetons_push where jeton = p_jeton and profile_id = auth.uid();
$$;

-- Réserve un lot de notifications push (bail de 5 minutes).
create or replace function public.reserver_notifications_push(p_limite integer default 100)
returns table (id uuid, destinataire uuid, type text, contenu text, variables jsonb, jetons text[])
language plpgsql volatile security definer set search_path = public
as $$
#variable_conflict use_column
begin
  return query
  with lot as (
    select n.id from public.notifications n
    where n.canal = 'push' and n.statut = 'en_attente' and n.deleted_at is null
      and (n.push_verrou_jusqu_a is null or n.push_verrou_jusqu_a < now())
      and n.created_at > now() - interval '2 days'
    order by n.created_at
    limit greatest(1, least(coalesce(p_limite, 100), 500))
    for update skip locked
  )
  update public.notifications n
     set push_verrou_jusqu_a = now() + interval '5 minutes', push_tentatives = n.push_tentatives + 1
    from lot
   where n.id = lot.id
  returning n.id, n.destinataire, n.type, n.contenu, n.variables,
            array(select j.jeton from public.jetons_push j where j.profile_id = n.destinataire);
end;
$$;

-- Résultat de l'envoi ; les jetons refusés par le service push sont oubliés.
create or replace function public.marquer_notification_push(p_id uuid, p_envoyee boolean, p_jetons_invalides text[] default '{}')
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  delete from public.jetons_push where jeton = any (coalesce(p_jetons_invalides, '{}'));
  update public.notifications
     set statut = case when p_envoyee then 'envoyee'::public.statut_notification
                       when push_tentatives >= 5 then 'echouee'::public.statut_notification
                       else statut end,
         date_envoi = case when p_envoyee then now() else date_envoi end,
         push_verrou_jusqu_a = case when p_envoyee then null else now() + make_interval(mins => 5 * push_tentatives) end
   where id = p_id and statut = 'en_attente';
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. RLS (lecture ; toute écriture passe par les fonctions)
-- ---------------------------------------------------------------------------
alter table public.parametres_pointage enable row level security;
alter table public.preferences_pointage enable row level security;
alter table public.cartes_eleves enable row level security;
alter table public.pointages_portail enable row level security;
alter table public.etats_portail enable row level security;
alter table public.autorisations_sortie enable row level security;
alter table public.alertes_presence enable row level security;
alter table public.traitements_absences enable row level security;
alter table public.packs_sms enable row level security;
alter table public.credits_sms enable row level security;
alter table public.mouvements_credits_sms enable row level security;
alter table public.relances_impayes enable row level security;
alter table public.jetons_push enable row level security;

revoke insert, update, delete on public.parametres_pointage, public.cartes_eleves, public.pointages_portail,
  public.etats_portail, public.autorisations_sortie, public.alertes_presence, public.traitements_absences,
  public.packs_sms, public.credits_sms, public.mouvements_credits_sms, public.relances_impayes, public.jetons_push
  from anon, authenticated;
revoke all on public.cartes_eleves, public.jetons_push from anon, authenticated;

drop policy if exists parametres_pointage_select on public.parametres_pointage;
create policy parametres_pointage_select on public.parametres_pointage
  for select to authenticated using (public.est_personnel(etablissement_id) or public.est_admin_gsg());

-- Préférence : chacun la sienne.
drop policy if exists preferences_pointage_proprio on public.preferences_pointage;
create policy preferences_pointage_proprio on public.preferences_pointage
  for all to authenticated using (profile_id = auth.uid()) with check (profile_id = auth.uid());
grant select, insert, update on public.preferences_pointage to authenticated;

-- Pointages : le personnel habilité ; les parents et l'élève pour l'élève.
drop policy if exists pointages_portail_select on public.pointages_portail;
create policy pointages_portail_select on public.pointages_portail
  for select to authenticated using (
    public.gere_presences(etablissement_id) or public.est_parent_confirme(fiche_eleve_id)
    or exists (select 1 from public.fiches_eleves f where f.id = fiche_eleve_id and f.profile_id = auth.uid()));

drop policy if exists etats_portail_select on public.etats_portail;
create policy etats_portail_select on public.etats_portail
  for select to authenticated using (public.gere_presences(etablissement_id));

drop policy if exists autorisations_sortie_select on public.autorisations_sortie;
create policy autorisations_sortie_select on public.autorisations_sortie
  for select to authenticated using (public.gere_presences(etablissement_id) or public.est_parent_confirme(fiche_eleve_id));

drop policy if exists alertes_presence_select on public.alertes_presence;
create policy alertes_presence_select on public.alertes_presence
  for select to authenticated using (public.gere_presences(etablissement_id) or public.est_parent_confirme(fiche_eleve_id));

drop policy if exists traitements_absences_select on public.traitements_absences;
create policy traitements_absences_select on public.traitements_absences
  for select to authenticated using (public.gere_presences(etablissement_id));

drop policy if exists packs_sms_select on public.packs_sms;
create policy packs_sms_select on public.packs_sms
  for select to authenticated using (actif or public.est_admin_gsg());

drop policy if exists credits_sms_select on public.credits_sms;
create policy credits_sms_select on public.credits_sms
  for select to authenticated using (public.est_personnel(etablissement_id) or public.est_admin_gsg());

drop policy if exists mouvements_credits_sms_select on public.mouvements_credits_sms;
create policy mouvements_credits_sms_select on public.mouvements_credits_sms
  for select to authenticated using (public.est_direction(etablissement_id) or public.est_admin_gsg());

drop policy if exists relances_impayes_select on public.relances_impayes;
create policy relances_impayes_select on public.relances_impayes
  for select to authenticated using (public.gere_inscriptions(etablissement_id));

-- ---------------------------------------------------------------------------
-- 15. Droits d'exécution
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  -- Mécanique interne et tâches serveur : jamais appelables par un client.
  foreach f in array array[
    'public.nouveau_jeton_carte()',
    'public.telephone_profil(uuid)',
    'public.destinataires_eleve(uuid)',
    'public.payeurs_eleve(uuid)',
    'public.notifier_push(uuid, uuid, text, text, jsonb)',
    'public.envoyer_sms_etablissement(uuid, uuid, text, text)',
    'public.crediter_sms_interne(uuid, integer, text, text, uuid)',
    'public.retards_paiement(uuid)',
    'public.detecter_absences_portail(uuid)',
    'public.reserver_notifications_push(integer)',
    'public.marquer_notification_push(uuid, boolean, text[])',
    'public.rembourser_sms_echoue()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  foreach f in array array[
    'public.detecter_absences_portail(uuid)',
    'public.reserver_notifications_push(integer)',
    'public.marquer_notification_push(uuid, boolean, text[])'
  ] loop
    execute format('grant execute on function %s to service_role', f);
  end loop;

  foreach f in array array[
    'public.gere_presences(uuid)',
    'public.fuseau_etablissement(uuid)',
    'public.texte_sms(text)',
    'public.segments_sms(text)',
    'public.enregistrer_parametres_pointage(uuid, boolean, time, time, smallint[], boolean, boolean, boolean)',
    'public.cartes_classe(uuid, boolean)',
    'public.remplacer_carte(uuid)',
    'public.cartes_portail(uuid)',
    'public.autoriser_sortie(uuid, date, text)',
    'public.enregistrer_pointage(uuid, uuid, text, text, timestamptz, text)',
    'public.signaler_portail(uuid, text, integer)',
    'public.presence_du_jour(uuid, date)',
    'public.apercu_relances_impayes(uuid)',
    'public.relancer_impayes(uuid, boolean, uuid[])',
    'public.definir_pack_sms(text, text, integer, numeric, boolean)',
    'public.crediter_sms(uuid, integer, text)',
    'public.initier_achat_credits_sms(uuid, text)',
    'public.enregistrer_jeton_push(text, text)',
    'public.retirer_jeton_push(text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

revoke all on function public.traiter_webhook_cinetpay(uuid, text, numeric, text, jsonb) from public, anon, authenticated;
grant execute on function public.traiter_webhook_cinetpay(uuid, text, numeric, text, jsonb) to service_role;
