-- ============================================================================
-- EcoShop — REG-08 : inscriptions et réinscriptions en ligne (lot I1, serveur)
--
-- Décisions du porteur de projet (2026-10-18) :
--   • la Direction déclare une CAMPAGNE par année scolaire : ouverture des
--     réinscriptions (anciens élèves, prioritaires), ouverture des nouvelles
--     demandes, date limite, places par niveau, pièces exigées, délai de
--     réservation d'une place ;
--   • en primaire, le parent seul agit ; DÈS LE COLLÈGE (CITE/ISCED ≥ 2),
--     l'élève comme le parent peuvent inscrire, réinscrire et payer — certains
--     élèves sont à leur propre charge : on enregistre qui paie
--     (fiches_eleves.responsable_financier) ;
--   • AUCUN BLOCAGE AUTOMATIQUE pour impayé ou sanction : la demande passe
--     « à examiner » et la Direction décide au cas par cas ;
--   • hors connexion d'abord : la demande porte la clé générée par
--     l'appareil (un second envoi renvoie le dossier déjà reçu), son numéro
--     provisoire et sa date de saisie ; une demande remplie avant la date
--     limite mais reçue après (retour du réseau) reste recevable 7 jours.
--
-- Circuit d'une demande :
--   réinscription : soumise → acceptee (place réservée N jours, frais
--     d'inscription à régler) → inscrite ; ou a_examiner (alertes) ;
--     liste_attente si le niveau est complet ; desistement (« ne revient
--     pas ») ;
--   nouvel élève : soumise → [incomplete | convoquee] → acceptee → inscrite ;
--     ou refusee (motif) / liste_attente (rang) ;
--   offre non réglée à l'échéance → expiree, la place passe au suivant de la
--   liste d'attente ; le demandeur peut retirer sa demande (retiree).
--
-- Paiement : Orange Money (nouvel objet « frais_inscription » visant la
-- demande ; le succès crée l'inscription puis l'encaissement) ou au guichet
-- (finaliser_inscription_guichet). Frais nuls : inscription immédiate.
--
-- Notifications : chaque changement d'étape est déposé dans la boîte de
-- notifications de l'application (canal push, M9) — l'envoi push lui-même
-- est livré par REG-09.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Types et colonnes
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.statut_demande_inscription as enum (
    'soumise', 'incomplete', 'convoquee', 'a_examiner', 'acceptee',
    'liste_attente', 'inscrite', 'refusee', 'expiree', 'desistement', 'retiree');
exception when duplicate_object then null;
end $$;

alter table public.fiches_eleves
  add column if not exists responsable_financier text not null default 'parent';
do $$ begin
  alter table public.fiches_eleves add constraint fiches_responsable_financier_valide
    check (responsable_financier in ('parent', 'eleve'));
exception when duplicate_object then null;
end $$;
comment on column public.fiches_eleves.responsable_financier is
  'REG-08 — qui paie la scolarité : le parent, ou l''élève lui-même (à sa charge, dès le collège).';

-- ---------------------------------------------------------------------------
-- 1. Campagnes et places
-- ---------------------------------------------------------------------------
create table if not exists public.campagnes_inscription (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  ouverture_reinscriptions date not null,
  ouverture_nouvelles date not null,
  date_limite date not null,
  delai_reservation_jours integer not null default 7 check (delai_reservation_jours between 1 and 60),
  -- [{ "code": "acte_naissance", "libelle": "Acte de naissance",
  --    "obligatoire": true, "isced_min": 0, "isced_max": 8 }]
  pieces_requises jsonb not null default '[]'::jsonb check (jsonb_typeof(pieces_requises) = 'array'),
  consignes text,
  publiee boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint campagnes_etab_annee_unique unique (etablissement_id, annee_scolaire_id),
  constraint campagnes_dates_coherentes check (
    ouverture_reinscriptions <= date_limite and ouverture_nouvelles <= date_limite)
);

drop trigger if exists campagnes_inscription_set_updated_at on public.campagnes_inscription;
create trigger campagnes_inscription_set_updated_at
  before update on public.campagnes_inscription
  for each row execute procedure public.set_updated_at();

-- Places par niveau. Sans ligne : capacité des classes du niveau (somme des
-- capacités renseignées), illimitée si une classe n'a pas de capacité.
create table if not exists public.places_inscription (
  campagne_id uuid not null references public.campagnes_inscription (id) on delete cascade,
  niveau_id uuid not null references public.niveaux_educatifs (id) on delete cascade,
  places integer not null check (places >= 0),
  primary key (campagne_id, niveau_id)
);

-- ---------------------------------------------------------------------------
-- 2. Demandes
-- ---------------------------------------------------------------------------
create table if not exists public.demandes_inscription (
  id uuid primary key,                         -- clé générée par l'appareil
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  campagne_id uuid not null references public.campagnes_inscription (id) on delete cascade,
  type text not null check (type in ('reinscription', 'nouvelle')),
  numero_dossier text not null,
  numero_provisoire text,
  saisi_le_client timestamptz,
  statut public.statut_demande_inscription not null default 'soumise',
  -- Élève
  fiche_eleve_id uuid references public.fiches_eleves (id) on delete set null,
  inscription_precedente_id uuid references public.inscriptions (id) on delete set null,
  nom text not null,
  prenom text not null,
  date_naissance date not null,
  sexe text check (sexe in ('M', 'F')),
  lieu_naissance text,
  ecole_precedente text,
  niveau_id uuid not null references public.niveaux_educatifs (id),
  intention text check (intention in ('revient', 'ne_revient_pas')),
  -- Demandeur et payeur
  demandeur_id uuid not null references public.profiles (id),
  demandeur_qualite text not null check (demandeur_qualite in ('parent', 'eleve')),
  responsable_financier text not null default 'parent' check (responsable_financier in ('parent', 'eleve')),
  telephone_contact text,
  commentaire text,
  -- Instruction
  alertes jsonb not null default '{}'::jsonb,
  motif text,
  rang_attente integer,
  offre_expire_le timestamptz,
  montant_a_regler numeric(12, 2) not null default 0 check (montant_a_regler >= 0),
  classe_id uuid references public.classes (id) on delete set null,
  inscription_id uuid references public.inscriptions (id) on delete set null,
  traite_par uuid references public.profiles (id),
  traite_le timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint demandes_numero_unique unique (etablissement_id, numero_dossier),
  constraint demandes_reinscription_fiche check (type = 'nouvelle' or fiche_eleve_id is not null)
);

-- Une seule demande vivante par élève et par campagne.
create unique index if not exists demandes_fiche_campagne_vivante
  on public.demandes_inscription (campagne_id, fiche_eleve_id)
  where fiche_eleve_id is not null and statut not in ('refusee', 'expiree', 'retiree', 'desistement');
create index if not exists idx_demandes_campagne_statut on public.demandes_inscription (campagne_id, statut);
create index if not exists idx_demandes_demandeur on public.demandes_inscription (demandeur_id);

drop trigger if exists demandes_inscription_set_updated_at on public.demandes_inscription;
create trigger demandes_inscription_set_updated_at
  before update on public.demandes_inscription
  for each row execute procedure public.set_updated_at();

create table if not exists public.pieces_demandes_inscription (
  id uuid primary key default gen_random_uuid(),
  demande_id uuid not null references public.demandes_inscription (id) on delete cascade,
  code text not null check (code ~ '^[a-z0-9_]{2,40}$'),
  chemin text not null,
  depose_le timestamptz not null default now(),
  constraint pieces_demande_code_unique unique (demande_id, code)
);

-- ---------------------------------------------------------------------------
-- 3. Fonctions d'aide
-- ---------------------------------------------------------------------------
create or replace function public.gere_inscriptions(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.est_direction(p_etablissement)
      or public.a_permission(p_etablissement, 'scolarite.inscription.gerer');
$$;

-- Le demandeur, un parent confirmé de l'élève, l'élève lui-même ou le
-- personnel chargé des inscriptions.
create or replace function public.demande_inscription_visible(p_demande uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.demandes_inscription d
    where d.id = p_demande
      and (d.demandeur_id = auth.uid()
           or public.gere_inscriptions(d.etablissement_id)
           or (d.fiche_eleve_id is not null and public.est_parent_confirme(d.fiche_eleve_id))
           or exists (select 1 from public.fiches_eleves f
                      where f.id = d.fiche_eleve_id and f.profile_id = auth.uid()))
  );
$$;

-- Niveau suivant dans le référentiel du pays (même grille normalisée).
create or replace function public.niveau_suivant(p_niveau uuid)
returns uuid
language sql stable security definer set search_path = public
as $$
  select n2.id
  from public.niveaux_educatifs n
  join public.niveaux_educatifs n2
    on n2.pays_code = n.pays_code and n2.grade_level_normalise = n.grade_level_normalise + 1
  where n.id = p_niveau;
$$;

-- Niveau proposé à un élève pour l'année de la campagne : le même s'il est
-- recalé à un examen, sinon le suivant.
create or replace function public.niveau_propose_reinscription(p_inscription uuid)
returns uuid
language sql stable security definer set search_path = public
as $$
  select case when i.mention_finale = 'recale' then c.niveau_id
              else public.niveau_suivant(c.niveau_id) end
  from public.inscriptions i
  join public.classes c on c.id = i.classe_id
  where i.id = p_inscription;
$$;

-- Le niveau est-il ouvert par l'établissement pour l'année de la campagne ?
create or replace function public.niveau_offert(p_campagne uuid, p_niveau uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.campagnes_inscription k
    join public.classes c on c.annee_scolaire_id = k.annee_scolaire_id and c.etablissement_id = k.etablissement_id
    where k.id = p_campagne and c.niveau_id = p_niveau and c.actif and c.deleted_at is null
  );
$$;

-- Places restantes (NULL = illimité).
create or replace function public.places_restantes_inscription(p_campagne uuid, p_niveau uuid)
returns integer
language plpgsql stable security definer set search_path = public
as $$
declare
  k public.campagnes_inscription;
  v_capacite integer;
  v_sans_capacite boolean;
  v_occupees integer;
begin
  select * into k from public.campagnes_inscription where id = p_campagne;
  if k.id is null then
    return 0;
  end if;

  select places into v_capacite from public.places_inscription
   where campagne_id = p_campagne and niveau_id = p_niveau;
  if v_capacite is null then
    select sum(c.capacite), bool_or(c.capacite is null) into v_capacite, v_sans_capacite
    from public.classes c
    where c.etablissement_id = k.etablissement_id and c.annee_scolaire_id = k.annee_scolaire_id
      and c.niveau_id = p_niveau and c.actif and c.deleted_at is null;
    if v_capacite is null or v_sans_capacite then
      return null;
    end if;
  end if;

  select
    (select count(*) from public.inscriptions i
       join public.classes c on c.id = i.classe_id
      where i.annee_scolaire_id = k.annee_scolaire_id and i.etablissement_id = k.etablissement_id
        and c.niveau_id = p_niveau and i.deleted_at is null and i.statut in ('active', 'redoublante'))
  + (select count(*) from public.demandes_inscription d
      where d.campagne_id = p_campagne and d.niveau_id = p_niveau
        and d.statut = 'acceptee' and d.offre_expire_le > now())
  into v_occupees;

  return greatest(v_capacite - v_occupees, 0);
end;
$$;

create or replace function public.frais_inscription_niveau(p_campagne uuid, p_niveau uuid)
returns numeric
language sql stable security definer set search_path = public
as $$
  select coalesce(
    (select f.frais_inscription from public.frais_scolarite_config f, public.campagnes_inscription k
      where k.id = p_campagne and f.etablissement_id = k.etablissement_id
        and f.annee_scolaire_id = k.annee_scolaire_id and f.niveau_id = p_niveau and f.deleted_at is null limit 1),
    (select f.frais_inscription from public.frais_scolarite_config f, public.campagnes_inscription k
      where k.id = p_campagne and f.etablissement_id = k.etablissement_id
        and f.annee_scolaire_id = k.annee_scolaire_id and f.niveau_id is null and f.deleted_at is null limit 1),
    0);
$$;

-- Dépôt d'une notification dans la boîte de l'application (canal push,
-- envoyée par REG-09) pour le demandeur, les parents confirmés et l'élève.
create or replace function public.notifier_demande_inscription(p_demande uuid, p_type text, p_contenu text)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  d public.demandes_inscription;
begin
  select * into d from public.demandes_inscription where id = p_demande;
  insert into public.notifications (etablissement_id, destinataire, type, canal, contenu, variables, statut)
  select distinct d.etablissement_id, x.profile_id, p_type, 'push'::public.canal_notification, p_contenu,
         jsonb_build_object('demande_id', d.id, 'numero_dossier', d.numero_dossier, 'statut', d.statut),
         'en_attente'::public.statut_notification
  from (
    select d.demandeur_id as profile_id
    union select r.parent_profile_id from public.relations_parent_eleve r
      where r.fiche_eleve_id = d.fiche_eleve_id and r.statut = 'confirmee' and r.autorise and r.deleted_at is null
    union select f.profile_id from public.fiches_eleves f
      where f.id = d.fiche_eleve_id and f.profile_id is not null
  ) x
  where x.profile_id is not null;
end;
$$;

-- Matricule : préfixe de l'établissement + compteur (verrouillé).
create or replace function public.generer_matricule(p_etablissement uuid)
returns text
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_slug text;
  v_prefixe text;
  v_n integer;
  v_matricule text;
begin
  perform pg_advisory_xact_lock(hashtext('matricule:' || p_etablissement::text));
  select slug into v_slug from public.etablissements where id = p_etablissement;
  v_prefixe := upper(left(regexp_replace(coalesce(v_slug, 'ecs'), '[^a-zA-Z0-9]', '', 'g'), 4));
  select count(*) into v_n from public.fiches_eleves where etablissement_id = p_etablissement;
  loop
    v_n := v_n + 1;
    v_matricule := v_prefixe || '-' || lpad(v_n::text, 5, '0');
    exit when not exists (select 1 from public.fiches_eleves
                          where etablissement_id = p_etablissement and matricule = v_matricule);
  end loop;
  return v_matricule;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Mécanique interne : offre de place, liste d'attente, finalisation
-- ---------------------------------------------------------------------------
create or replace function public.finaliser_demande_inscription(
  p_demande uuid,
  p_classe uuid,
  p_montant numeric,
  p_moyen public.moyen_paiement,
  p_reference text
)
returns uuid
language plpgsql volatile security definer set search_path = public
as $$
declare
  d public.demandes_inscription;
  k public.campagnes_inscription;
  v_classe uuid := p_classe;
  v_fiche uuid;
  v_inscription uuid;
begin
  select * into d from public.demandes_inscription where id = p_demande for update;
  if d.statut = 'inscrite' then
    return d.inscription_id;
  end if;
  if d.statut not in ('acceptee', 'a_examiner', 'soumise', 'convoquee', 'incomplete', 'liste_attente') then
    raise exception 'DEMANDE_NON_FINALISABLE' using errcode = '22023';
  end if;
  select * into k from public.campagnes_inscription where id = d.campagne_id;

  -- Classe : celle choisie (même niveau, même année), sinon la classe du
  -- niveau qui a le plus de places libres.
  if v_classe is not null then
    if not exists (select 1 from public.classes c
                   where c.id = v_classe and c.etablissement_id = d.etablissement_id
                     and c.annee_scolaire_id = k.annee_scolaire_id and c.deleted_at is null) then
      raise exception 'CLASSE_INVALIDE' using errcode = '22023';
    end if;
  else
    select c.id into v_classe
    from public.classes c
    where c.etablissement_id = d.etablissement_id and c.annee_scolaire_id = k.annee_scolaire_id
      and c.niveau_id = d.niveau_id and c.actif and c.deleted_at is null
    order by coalesce(c.capacite, 100000) - (select count(*) from public.inscriptions i
             where i.classe_id = c.id and i.deleted_at is null and i.statut in ('active', 'redoublante')) desc,
             c.code
    limit 1;
    if v_classe is null then
      raise exception 'AUCUNE_CLASSE_POUR_CE_NIVEAU' using errcode = '22023';
    end if;
  end if;

  -- Élève : fiche existante (réinscription) ou nouvelle fiche.
  v_fiche := d.fiche_eleve_id;
  if v_fiche is null then
    insert into public.fiches_eleves (etablissement_id, matricule, nom, prenom, date_naissance, sexe,
                                      lieu_naissance, responsable_financier)
    values (d.etablissement_id, public.generer_matricule(d.etablissement_id), d.nom, d.prenom,
            d.date_naissance, d.sexe, d.lieu_naissance, d.responsable_financier)
    returning id into v_fiche;

    if d.demandeur_qualite = 'parent' then
      insert into public.relations_parent_eleve (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut, autorise)
      values (d.etablissement_id, d.demandeur_id, v_fiche, 'parent', 'confirmee', true)
      on conflict (parent_profile_id, fiche_eleve_id) do nothing;
      insert into public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
      values (d.demandeur_id, d.etablissement_id, 'parent')
      on conflict (profile_id, etablissement_id) do nothing;
    else
      update public.fiches_eleves set profile_id = d.demandeur_id, lie_le = now() where id = v_fiche;
      insert into public.etablissements_membres (profile_id, etablissement_id, role_dans_etablissement)
      values (d.demandeur_id, d.etablissement_id, 'eleve')
      on conflict (profile_id, etablissement_id) do nothing;
    end if;
  else
    update public.fiches_eleves set responsable_financier = d.responsable_financier where id = v_fiche;
  end if;

  -- Inscription (réutilisée si le guichet l'a déjà faite entre-temps).
  select id into v_inscription from public.inscriptions
   where fiche_eleve_id = v_fiche and annee_scolaire_id = k.annee_scolaire_id and deleted_at is null;
  if v_inscription is null then
    insert into public.inscriptions (etablissement_id, fiche_eleve_id, classe_id, annee_scolaire_id, statut)
    values (d.etablissement_id, v_fiche, v_classe, k.annee_scolaire_id, 'active')
    returning id into v_inscription;
  end if;

  if coalesce(p_montant, 0) > 0 then
    insert into public.encaissements_scolarite (etablissement_id, fiche_eleve_id, inscription_id, type_frais,
                                                montant, moyen_paiement, reference_paiement, saisi_par)
    values (d.etablissement_id, v_fiche, v_inscription, 'inscription', p_montant, p_moyen,
            p_reference, coalesce(auth.uid(), d.demandeur_id));
  end if;

  update public.demandes_inscription
     set statut = 'inscrite', fiche_eleve_id = v_fiche, classe_id = v_classe,
         inscription_id = v_inscription, rang_attente = null,
         traite_le = now(), traite_par = coalesce(auth.uid(), traite_par)
   where id = p_demande;

  perform public.notifier_demande_inscription(p_demande, 'inscription_confirmee',
    format('Inscription confirmée : %s %s (dossier %s).', d.prenom, d.nom, d.numero_dossier));
  return v_inscription;
end;
$$;

-- Offre une place (ou met en liste d'attente) ; frais nuls → inscription.
create or replace function public.offrir_place_inscription(p_demande uuid, p_forcer boolean default false)
returns public.statut_demande_inscription
language plpgsql volatile security definer set search_path = public
as $$
declare
  d public.demandes_inscription;
  k public.campagnes_inscription;
  v_places integer;
  v_montant numeric;
begin
  select * into d from public.demandes_inscription where id = p_demande for update;
  select * into k from public.campagnes_inscription where id = d.campagne_id;
  v_places := public.places_restantes_inscription(d.campagne_id, d.niveau_id);

  if v_places is not null and v_places <= 0 and not p_forcer then
    update public.demandes_inscription
       set statut = 'liste_attente', offre_expire_le = null,
           rang_attente = coalesce(rang_attente, (select coalesce(max(rang_attente), 0) + 1
                                                  from public.demandes_inscription
                                                  where campagne_id = d.campagne_id and niveau_id = d.niveau_id))
     where id = p_demande;
    perform public.notifier_demande_inscription(p_demande, 'inscription_liste_attente',
      format('Dossier %s : le niveau demandé est complet, votre demande est en liste d''attente.', d.numero_dossier));
    return 'liste_attente';
  end if;

  v_montant := public.frais_inscription_niveau(d.campagne_id, d.niveau_id);
  update public.demandes_inscription
     set statut = 'acceptee', rang_attente = null, montant_a_regler = v_montant,
         offre_expire_le = now() + make_interval(days => k.delai_reservation_jours)
   where id = p_demande;

  if v_montant = 0 then
    perform public.finaliser_demande_inscription(p_demande, null, 0, 'especes', null);
    return 'inscrite';
  end if;

  perform public.notifier_demande_inscription(p_demande, 'inscription_acceptee',
    format('Dossier %s accepté : place réservée jusqu''au %s. Réglez %s pour confirmer l''inscription.',
           d.numero_dossier, to_char(now() + make_interval(days => k.delai_reservation_jours), 'DD/MM/YYYY'),
           v_montant::bigint));
  return 'acceptee';
end;
$$;

-- Fait passer les suivants de la liste d'attente tant qu'il reste des places.
create or replace function public.promouvoir_liste_attente(p_campagne uuid, p_niveau uuid)
returns integer
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_id uuid;
  v_n integer := 0;
  v_places integer;
begin
  loop
    v_places := public.places_restantes_inscription(p_campagne, p_niveau);
    exit when v_places is not null and v_places <= 0;
    select id into v_id from public.demandes_inscription
     where campagne_id = p_campagne and niveau_id = p_niveau and statut = 'liste_attente'
     order by rang_attente nulls last, created_at
     limit 1;
    exit when v_id is null;
    perform public.offrir_place_inscription(v_id);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- Offres échues → expiree, puis promotion de la liste d'attente.
create or replace function public.expirer_offres_inscription(p_campagne uuid default null)
returns integer
language plpgsql volatile security definer set search_path = public
as $$
declare
  r record;
  v_n integer := 0;
begin
  for r in
    update public.demandes_inscription
       set statut = 'expiree'
     where statut = 'acceptee' and offre_expire_le <= now()
       and (p_campagne is null or campagne_id = p_campagne)
    returning id, campagne_id, niveau_id, numero_dossier
  loop
    v_n := v_n + 1;
    perform public.notifier_demande_inscription(r.id, 'inscription_expiree',
      format('Dossier %s : le délai de réservation est dépassé, la place a été libérée.', r.numero_dossier));
    perform public.promouvoir_liste_attente(r.campagne_id, r.niveau_id);
  end loop;
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Direction : campagne
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_campagne_inscription(
  p_etablissement uuid,
  p_annee_scolaire uuid,
  p_ouverture_reinscriptions date,
  p_ouverture_nouvelles date,
  p_date_limite date,
  p_delai_reservation_jours integer default 7,
  p_pieces_requises jsonb default '[]'::jsonb,
  p_places jsonb default '{}'::jsonb,          -- { "<niveau_id>": 40, ... }
  p_consignes text default null,
  p_publiee boolean default false
)
returns uuid
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_id uuid;
  v_cle text;
  v_piece jsonb;
begin
  if not public.gere_inscriptions(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if not exists (select 1 from public.annees_scolaires
                 where id = p_annee_scolaire and etablissement_id = p_etablissement and not cloturee) then
    raise exception 'ANNEE_INVALIDE' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_pieces_requises, '[]'::jsonb)) <> 'array' then
    raise exception 'PIECES_INVALIDES' using errcode = '22023';
  end if;
  for v_piece in select * from jsonb_array_elements(coalesce(p_pieces_requises, '[]'::jsonb)) loop
    if coalesce(v_piece->>'code', '') !~ '^[a-z0-9_]{2,40}$' or coalesce(trim(v_piece->>'libelle'), '') = '' then
      raise exception 'PIECES_INVALIDES' using errcode = '22023';
    end if;
  end loop;

  insert into public.campagnes_inscription (etablissement_id, annee_scolaire_id, ouverture_reinscriptions,
    ouverture_nouvelles, date_limite, delai_reservation_jours, pieces_requises, consignes, publiee)
  values (p_etablissement, p_annee_scolaire, p_ouverture_reinscriptions, p_ouverture_nouvelles, p_date_limite,
    coalesce(p_delai_reservation_jours, 7), coalesce(p_pieces_requises, '[]'::jsonb), p_consignes, coalesce(p_publiee, false))
  on conflict (etablissement_id, annee_scolaire_id) do update
    set ouverture_reinscriptions = excluded.ouverture_reinscriptions,
        ouverture_nouvelles = excluded.ouverture_nouvelles,
        date_limite = excluded.date_limite,
        delai_reservation_jours = excluded.delai_reservation_jours,
        pieces_requises = excluded.pieces_requises,
        consignes = excluded.consignes,
        publiee = excluded.publiee
  returning id into v_id;

  delete from public.places_inscription where campagne_id = v_id;
  for v_cle in select jsonb_object_keys(coalesce(p_places, '{}'::jsonb)) loop
    insert into public.places_inscription (campagne_id, niveau_id, places)
    values (v_id, v_cle::uuid, (p_places->>v_cle)::integer);
  end loop;

  -- Des places ont pu s'ouvrir.
  perform public.promouvoir_liste_attente(v_id, n.niveau_id)
  from (select distinct niveau_id from public.demandes_inscription
        where campagne_id = v_id and statut = 'liste_attente') n;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Parent / élève : consulter, demander, déposer, payer, retirer
-- ---------------------------------------------------------------------------

-- Campagnes publiées en cours (recherche d'une école par un parent).
create or replace function public.campagnes_inscription_ouvertes(p_recherche text default null)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(x order by x->>'etablissement_nom'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'campagne_id', k.id,
      'etablissement_id', e.id,
      'etablissement_nom', e.nom,
      'ville', e.ville,
      'annee', a.libelle,
      'ouverture_reinscriptions', k.ouverture_reinscriptions,
      'ouverture_nouvelles', k.ouverture_nouvelles,
      'date_limite', k.date_limite,
      'nouvelles_ouvertes', current_date >= k.ouverture_nouvelles,
      'pieces_requises', k.pieces_requises,
      'consignes', k.consignes,
      'niveaux', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'niveau_id', n.id, 'nom', n.nom, 'isced', n.isced,
                 'places_restantes', public.places_restantes_inscription(k.id, n.id),
                 'frais_inscription', public.frais_inscription_niveau(k.id, n.id))
               order by n.grade_level_normalise)
        from public.niveaux_educatifs n
        where n.id in (select c.niveau_id from public.classes c
                       where c.etablissement_id = k.etablissement_id and c.annee_scolaire_id = k.annee_scolaire_id
                         and c.actif and c.deleted_at is null)), '[]'::jsonb)
    ) as x
    from public.campagnes_inscription k
    join public.etablissements e on e.id = k.etablissement_id and e.deleted_at is null
    join public.annees_scolaires a on a.id = k.annee_scolaire_id
    where k.publiee
      and current_date between least(k.ouverture_reinscriptions, k.ouverture_nouvelles) and k.date_limite
      and (p_recherche is null or trim(p_recherche) = ''
           or e.nom ilike '%' || trim(p_recherche) || '%' or e.ville ilike '%' || trim(p_recherche) || '%')
  ) s;
$$;

-- Élèves que l'utilisateur peut réinscrire (ses enfants ; lui-même dès le
-- collège) dans une campagne publiée en cours.
create or replace function public.reinscriptions_possibles()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(x), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'fiche_eleve_id', f.id,
      'nom', f.nom, 'prenom', f.prenom, 'date_naissance', f.date_naissance, 'sexe', f.sexe,
      'etablissement_id', e.id, 'etablissement_nom', e.nom,
      'campagne_id', k.id, 'annee', a.libelle, 'date_limite', k.date_limite,
      'ouverte', current_date >= k.ouverture_reinscriptions,
      'pieces_requises', k.pieces_requises,
      'inscription_precedente_id', i.id,
      'classe_actuelle', c.nom,
      'niveau_propose_id', np.id,
      'niveau_propose_nom', np.nom,
      'niveau_offert', np.id is not null and public.niveau_offert(k.id, np.id),
      'frais_inscription', case when np.id is null then 0 else public.frais_inscription_niveau(k.id, np.id) end,
      'solde_precedent', coalesce((select s.solde from public.solde_scolarite(i.id) s), 0),
      'qualite', case when f.profile_id = auth.uid() then 'eleve' else 'parent' end,
      'responsable_financier', f.responsable_financier,
      'demande', (select jsonb_build_object('id', d.id, 'statut', d.statut, 'numero_dossier', d.numero_dossier,
                                            'montant_a_regler', d.montant_a_regler, 'offre_expire_le', d.offre_expire_le)
                  from public.demandes_inscription d
                  where d.campagne_id = k.id and d.fiche_eleve_id = f.id
                  order by d.created_at desc limit 1)
    ) as x
    from public.fiches_eleves f
    join public.etablissements e on e.id = f.etablissement_id
    join public.campagnes_inscription k on k.etablissement_id = f.etablissement_id and k.publiee
      and current_date between k.ouverture_reinscriptions and k.date_limite
    join public.annees_scolaires a on a.id = k.annee_scolaire_id
    join lateral (
      select i.* from public.inscriptions i
      join public.annees_scolaires a2 on a2.id = i.annee_scolaire_id
      where i.fiche_eleve_id = f.id and i.deleted_at is null and i.annee_scolaire_id <> k.annee_scolaire_id
        and i.statut <> 'retiree' and a2.date_debut < a.date_debut
      order by a2.date_debut desc limit 1
    ) i on true
    join public.classes c on c.id = i.classe_id
    left join public.niveaux_educatifs np on np.id = public.niveau_propose_reinscription(i.id)
    where f.deleted_at is null and f.statut = 'actif'
      and not exists (select 1 from public.inscriptions i3
                      where i3.fiche_eleve_id = f.id and i3.annee_scolaire_id = k.annee_scolaire_id and i3.deleted_at is null)
      and (public.est_parent_confirme(f.id)
           or (f.profile_id = auth.uid() and coalesce(np.isced, 0) >= 2))
  ) s;
$$;

-- Dépôt d'une demande (réinscription ou nouvel élève). Idempotent par la
-- clé de l'appareil.
create or replace function public.soumettre_demande_inscription(
  p_id uuid,
  p_campagne uuid,
  p_donnees jsonb,
  p_numero_provisoire text default null,
  p_saisi_le timestamptz default null
)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  k public.campagnes_inscription;
  d public.demandes_inscription;
  v_type text := p_donnees->>'type';
  v_fiche public.fiches_eleves;
  v_prec public.inscriptions;
  v_niveau uuid;
  v_isced integer;
  v_qualite text;
  v_quand timestamptz;
  v_alertes jsonb := '{}'::jsonb;
  v_solde numeric;
  v_annee_debut date;
  v_numero text;
  v_statut public.statut_demande_inscription;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUISE' using errcode = '42501';
  end if;

  -- Second envoi de la même saisie : on renvoie le dossier déjà reçu.
  select * into d from public.demandes_inscription where id = p_id;
  if d.id is not null then
    if d.demandeur_id <> v_uid then
      raise exception 'CLE_DEJA_UTILISEE' using errcode = '23505';
    end if;
    return jsonb_build_object('id', d.id, 'numero_dossier', d.numero_dossier, 'statut', d.statut,
      'montant_a_regler', d.montant_a_regler, 'offre_expire_le', d.offre_expire_le, 'deja_recue', true);
  end if;

  select * into k from public.campagnes_inscription where id = p_campagne;
  if k.id is null or not k.publiee then
    raise exception 'CAMPAGNE_FERMEE' using errcode = '22023';
  end if;
  select date_debut into v_annee_debut from public.annees_scolaires where id = k.annee_scolaire_id;

  -- Fenêtre : la date de saisie sur l'appareil fait foi (jamais dans le
  -- futur), si la demande arrive au plus 7 jours après la date limite.
  v_quand := least(coalesce(p_saisi_le, now()), now());
  if now()::date > k.date_limite + 7 or v_quand::date > k.date_limite then
    raise exception 'CAMPAGNE_TERMINEE' using errcode = '22023';
  end if;

  if v_type = 'reinscription' then
    select * into v_fiche from public.fiches_eleves
     where id = (p_donnees->>'fiche_eleve_id')::uuid and etablissement_id = k.etablissement_id and deleted_at is null;
    if v_fiche.id is null then
      raise exception 'ELEVE_INTROUVABLE' using errcode = '22023';
    end if;
    if v_quand::date < k.ouverture_reinscriptions then
      raise exception 'REINSCRIPTIONS_PAS_ENCORE_OUVERTES' using errcode = '22023';
    end if;

    select i.* into v_prec from public.inscriptions i
      join public.annees_scolaires a2 on a2.id = i.annee_scolaire_id
     where i.fiche_eleve_id = v_fiche.id and i.deleted_at is null and i.statut <> 'retiree'
       and a2.date_debut < v_annee_debut
     order by a2.date_debut desc limit 1;
    if v_prec.id is null then
      raise exception 'AUCUNE_INSCRIPTION_PRECEDENTE' using errcode = '22023';
    end if;
    if exists (select 1 from public.inscriptions where fiche_eleve_id = v_fiche.id
               and annee_scolaire_id = k.annee_scolaire_id and deleted_at is null) then
      raise exception 'DEJA_INSCRIT' using errcode = '23505';
    end if;

    -- Le niveau est celui que l'école propose ; la Direction peut le changer.
    v_niveau := public.niveau_propose_reinscription(v_prec.id);
    select isced into v_isced from public.niveaux_educatifs where id = v_niveau;

    if public.est_parent_confirme(v_fiche.id) then
      v_qualite := 'parent';
    elsif v_fiche.profile_id = v_uid and coalesce(v_isced, 0) >= 2 then
      v_qualite := 'eleve';
    else
      raise exception 'ACCES_REFUSE' using errcode = '42501';
    end if;
    if v_niveau is null or not public.niveau_offert(k.id, v_niveau) then
      raise exception 'NIVEAU_NON_OUVERT' using errcode = '22023';
    end if;

    select s.solde into v_solde from public.solde_scolarite(v_prec.id) s;
    if coalesce(v_solde, 0) > 0 then
      v_alertes := v_alertes || jsonb_build_object('impaye', v_solde);
    end if;
    if exists (select 1 from public.sanctions s where s.fiche_eleve_id = v_fiche.id
               and s.deleted_at is null and s.statut in ('notifiee', 'executee')) then
      v_alertes := v_alertes || jsonb_build_object('sanction_active', true);
    end if;
  elsif v_type = 'nouvelle' then
    if v_quand::date < k.ouverture_nouvelles then
      raise exception 'NOUVELLES_DEMANDES_PAS_ENCORE_OUVERTES' using errcode = '22023';
    end if;
    v_niveau := (p_donnees->>'niveau_id')::uuid;
    select isced into v_isced from public.niveaux_educatifs where id = v_niveau;
    if v_niveau is null or not public.niveau_offert(k.id, v_niveau) then
      raise exception 'NIVEAU_NON_OUVERT' using errcode = '22023';
    end if;
    v_qualite := coalesce(p_donnees->>'demandeur_qualite', 'parent');
    if v_qualite not in ('parent', 'eleve') then
      raise exception 'QUALITE_INVALIDE' using errcode = '22023';
    end if;
    if v_qualite = 'eleve' and coalesce(v_isced, 0) < 2 then
      raise exception 'PARENT_REQUIS_AVANT_COLLEGE' using errcode = '42501';
    end if;
    if coalesce(trim(p_donnees->>'nom'), '') = '' or coalesce(trim(p_donnees->>'prenom'), '') = ''
       or (p_donnees->>'date_naissance') is null then
      raise exception 'IDENTITE_INCOMPLETE' using errcode = '22023';
    end if;
    if public.verifier_doublon_eleve(p_donnees->>'nom', p_donnees->>'prenom', (p_donnees->>'date_naissance')::date) then
      v_alertes := v_alertes || jsonb_build_object('doublon_possible', true);
    end if;
  else
    raise exception 'TYPE_INVALIDE' using errcode = '22023';
  end if;

  -- Avant le collège, c'est le parent qui paie.
  if coalesce(p_donnees->>'responsable_financier', 'parent') = 'eleve' and coalesce(v_isced, 0) < 2 then
    raise exception 'PARENT_REQUIS_AVANT_COLLEGE' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext('dossier:' || k.id::text));
  select 'INS-' || to_char(v_annee_debut, 'YYYY') || '-' || lpad((count(*) + 1)::text, 5, '0')
    into v_numero from public.demandes_inscription where campagne_id = k.id;

  v_statut := case
    when v_type = 'reinscription' and p_donnees->>'intention' = 'ne_revient_pas' then 'desistement'
    when v_type = 'reinscription' and v_alertes <> '{}'::jsonb then 'a_examiner'
    else 'soumise' end;

  insert into public.demandes_inscription (
    id, etablissement_id, campagne_id, type, numero_dossier, numero_provisoire, saisi_le_client, statut,
    fiche_eleve_id, inscription_precedente_id, nom, prenom, date_naissance, sexe, lieu_naissance,
    ecole_precedente, niveau_id, intention, demandeur_id, demandeur_qualite, responsable_financier,
    telephone_contact, commentaire, alertes)
  values (
    p_id, k.etablissement_id, k.id, v_type, v_numero, p_numero_provisoire, p_saisi_le, v_statut,
    v_fiche.id, v_prec.id,
    coalesce(v_fiche.nom, trim(p_donnees->>'nom')), coalesce(v_fiche.prenom, trim(p_donnees->>'prenom')),
    coalesce(v_fiche.date_naissance, (p_donnees->>'date_naissance')::date),
    coalesce(v_fiche.sexe, nullif(p_donnees->>'sexe', '')),
    coalesce(v_fiche.lieu_naissance, nullif(trim(p_donnees->>'lieu_naissance'), '')),
    nullif(trim(p_donnees->>'ecole_precedente'), ''),
    v_niveau,
    case when v_type = 'reinscription' then coalesce(p_donnees->>'intention', 'revient') end,
    v_uid, v_qualite, coalesce(p_donnees->>'responsable_financier', 'parent'),
    nullif(trim(p_donnees->>'telephone'), ''), nullif(trim(p_donnees->>'commentaire'), ''), v_alertes)
  returning * into d;

  -- Réinscription sans alerte : place offerte tout de suite.
  if v_statut = 'soumise' and v_type = 'reinscription' then
    v_statut := public.offrir_place_inscription(d.id);
  else
    perform public.notifier_demande_inscription(d.id, 'inscription_recue',
      case v_statut
        when 'desistement' then format('Merci : nous avons noté que %s ne reviendra pas l''an prochain.', d.prenom)
        when 'a_examiner' then format('Dossier %s reçu : il sera examiné par la direction.', v_numero)
        else format('Dossier %s reçu : l''école va l''examiner.', v_numero) end);
  end if;

  select * into d from public.demandes_inscription where id = p_id;
  return jsonb_build_object('id', d.id, 'numero_dossier', d.numero_dossier, 'statut', d.statut,
    'montant_a_regler', d.montant_a_regler, 'offre_expire_le', d.offre_expire_le, 'deja_recue', false);
end;
$$;

-- Enregistre une pièce déposée (le fichier est déjà dans le stockage).
create or replace function public.deposer_piece_inscription(p_demande uuid, p_code text, p_chemin text)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  d public.demandes_inscription;
  k public.campagnes_inscription;
  v_isced integer;
  v_manque boolean;
begin
  select * into d from public.demandes_inscription where id = p_demande;
  if d.id is null or d.demandeur_id <> auth.uid() then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if d.statut not in ('soumise', 'incomplete', 'convoquee', 'a_examiner', 'acceptee', 'liste_attente') then
    raise exception 'DEMANDE_CLOSE' using errcode = '22023';
  end if;
  if split_part(p_chemin, '/', 1) <> d.id::text then
    raise exception 'CHEMIN_INVALIDE' using errcode = '22023';
  end if;

  insert into public.pieces_demandes_inscription (demande_id, code, chemin)
  values (p_demande, p_code, p_chemin)
  on conflict (demande_id, code) do update set chemin = excluded.chemin, depose_le = now();

  -- Dossier incomplet : retour en examen dès que les pièces obligatoires y sont.
  if d.statut = 'incomplete' then
    select * into k from public.campagnes_inscription where id = d.campagne_id;
    select isced into v_isced from public.niveaux_educatifs where id = d.niveau_id;
    select exists (
      select 1 from jsonb_array_elements(k.pieces_requises) p
      where coalesce((p->>'obligatoire')::boolean, true)
        and coalesce(v_isced, 0) between coalesce((p->>'isced_min')::int, 0) and coalesce((p->>'isced_max')::int, 8)
        and not exists (select 1 from public.pieces_demandes_inscription x
                        where x.demande_id = d.id and x.code = p->>'code')
    ) into v_manque;
    if not v_manque then
      update public.demandes_inscription set statut = 'soumise', motif = null where id = d.id;
    end if;
  end if;
end;
$$;

-- Le demandeur retire sa demande (avant l'inscription) ; la place se libère.
create or replace function public.retirer_demande_inscription(p_demande uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  d public.demandes_inscription;
begin
  select * into d from public.demandes_inscription where id = p_demande for update;
  if d.id is null or d.demandeur_id <> auth.uid() then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if d.statut in ('inscrite', 'refusee', 'expiree', 'retiree', 'desistement') then
    raise exception 'DEMANDE_CLOSE' using errcode = '22023';
  end if;
  update public.demandes_inscription set statut = 'retiree', offre_expire_le = null, rang_attente = null
   where id = p_demande;
  perform public.promouvoir_liste_attente(d.campagne_id, d.niveau_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Direction : instruction des dossiers, guichet, tableau de bord
-- ---------------------------------------------------------------------------
create or replace function public.traiter_demande_inscription(
  p_demande uuid,
  p_decision text,                 -- accepter | refuser | incomplete | convoquer | liste_attente
  p_motif text default null,
  p_niveau uuid default null,
  p_forcer boolean default false   -- accepter au-delà des places
)
returns public.statut_demande_inscription
language plpgsql volatile security definer set search_path = public
as $$
declare
  d public.demandes_inscription;
  v_statut public.statut_demande_inscription;
begin
  select * into d from public.demandes_inscription where id = p_demande for update;
  if d.id is null or not public.gere_inscriptions(d.etablissement_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if d.statut in ('inscrite', 'refusee', 'expiree', 'retiree', 'desistement') then
    raise exception 'DEMANDE_CLOSE' using errcode = '22023';
  end if;

  if p_niveau is not null and p_niveau <> d.niveau_id then
    if not public.niveau_offert(d.campagne_id, p_niveau) then
      raise exception 'NIVEAU_NON_OUVERT' using errcode = '22023';
    end if;
    update public.demandes_inscription set niveau_id = p_niveau, rang_attente = null where id = p_demande;
  end if;

  update public.demandes_inscription set traite_par = auth.uid(), traite_le = now() where id = p_demande;

  if p_decision = 'accepter' then
    update public.demandes_inscription set motif = null where id = p_demande;
    v_statut := public.offrir_place_inscription(p_demande, coalesce(p_forcer, false));
  elsif p_decision = 'refuser' then
    if coalesce(trim(p_motif), '') = '' then
      raise exception 'MOTIF_OBLIGATOIRE' using errcode = '22023';
    end if;
    update public.demandes_inscription
       set statut = 'refusee', motif = trim(p_motif), offre_expire_le = null, rang_attente = null
     where id = p_demande;
    perform public.notifier_demande_inscription(p_demande, 'inscription_refusee',
      format('Dossier %s : demande non retenue. Motif : %s', d.numero_dossier, trim(p_motif)));
    perform public.promouvoir_liste_attente(d.campagne_id, d.niveau_id);
    v_statut := 'refusee';
  elsif p_decision in ('incomplete', 'convoquer') then
    if coalesce(trim(p_motif), '') = '' then
      raise exception 'MOTIF_OBLIGATOIRE' using errcode = '22023';
    end if;
    v_statut := case p_decision when 'incomplete' then 'incomplete' else 'convoquee' end;
    update public.demandes_inscription
       set statut = v_statut, motif = trim(p_motif), offre_expire_le = null
     where id = p_demande;
    perform public.notifier_demande_inscription(p_demande,
      case p_decision when 'incomplete' then 'inscription_pieces' else 'inscription_convocation' end,
      format('Dossier %s : %s', d.numero_dossier, trim(p_motif)));
    perform public.promouvoir_liste_attente(d.campagne_id, d.niveau_id);
  elsif p_decision = 'liste_attente' then
    update public.demandes_inscription
       set statut = 'liste_attente', offre_expire_le = null, motif = nullif(trim(p_motif), ''),
           rang_attente = (select coalesce(max(rang_attente), 0) + 1 from public.demandes_inscription
                           where campagne_id = d.campagne_id and niveau_id = coalesce(p_niveau, d.niveau_id))
     where id = p_demande;
    perform public.notifier_demande_inscription(p_demande, 'inscription_liste_attente',
      format('Dossier %s : votre demande est en liste d''attente.', d.numero_dossier));
    perform public.promouvoir_liste_attente(d.campagne_id, d.niveau_id);
    v_statut := 'liste_attente';
  else
    raise exception 'DECISION_INVALIDE' using errcode = '22023';
  end if;
  return v_statut;
end;
$$;

-- Paiement au guichet (espèces…) : inscription immédiate.
create or replace function public.finaliser_inscription_guichet(
  p_demande uuid,
  p_classe uuid default null,
  p_montant numeric default null,
  p_moyen public.moyen_paiement default 'especes',
  p_reference text default null
)
returns uuid
language plpgsql volatile security definer set search_path = public
as $$
declare
  d public.demandes_inscription;
begin
  select * into d from public.demandes_inscription where id = p_demande;
  if d.id is null or not public.gere_inscriptions(d.etablissement_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if coalesce(p_montant, d.montant_a_regler) < 0 then
    raise exception 'MONTANT_INVALIDE' using errcode = '22023';
  end if;
  return public.finaliser_demande_inscription(p_demande, p_classe, coalesce(p_montant, d.montant_a_regler),
                                              coalesce(p_moyen, 'especes'), p_reference);
end;
$$;

create or replace function public.tableau_campagne_inscription(p_campagne uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  k public.campagnes_inscription;
  v_eligibles integer;
  v_resultat jsonb;
begin
  select * into k from public.campagnes_inscription where id = p_campagne;
  if k.id is null or not public.gere_inscriptions(k.etablissement_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  perform public.expirer_offres_inscription(p_campagne);

  -- Élèves de l'année précédente susceptibles de revenir.
  select count(distinct i.fiche_eleve_id) into v_eligibles
  from public.inscriptions i
  join public.annees_scolaires a on a.id = i.annee_scolaire_id
  where i.etablissement_id = k.etablissement_id and i.deleted_at is null and i.statut in ('active', 'redoublante')
    and a.date_debut = (select max(a2.date_debut) from public.annees_scolaires a2
                        where a2.etablissement_id = k.etablissement_id
                          and a2.date_debut < (select date_debut from public.annees_scolaires where id = k.annee_scolaire_id));

  select jsonb_build_object(
    'eleves_eligibles', v_eligibles,
    'reinscrits', (select count(*) from public.demandes_inscription
                   where campagne_id = k.id and type = 'reinscription' and statut = 'inscrite'),
    'desistements', (select count(*) from public.demandes_inscription
                     where campagne_id = k.id and statut = 'desistement'),
    'par_statut', coalesce((select jsonb_object_agg(statut, n) from (
        select statut, count(*) as n from public.demandes_inscription where campagne_id = k.id group by statut) s),
        '{}'::jsonb),
    'frais_encaisses', coalesce((select sum(e.montant) from public.encaissements_scolarite e
        join public.demandes_inscription d on d.inscription_id = e.inscription_id
        where d.campagne_id = k.id and e.type_frais = 'inscription' and e.statut = 'valide'), 0),
    'niveaux', coalesce((select jsonb_agg(jsonb_build_object(
          'niveau_id', n.id, 'nom', n.nom,
          'places_restantes', public.places_restantes_inscription(k.id, n.id),
          'en_attente', (select count(*) from public.demandes_inscription d
                         where d.campagne_id = k.id and d.niveau_id = n.id and d.statut = 'liste_attente'))
          order by n.grade_level_normalise)
        from public.niveaux_educatifs n
        where n.id in (select c.niveau_id from public.classes c
                       where c.etablissement_id = k.etablissement_id and c.annee_scolaire_id = k.annee_scolaire_id
                         and c.actif and c.deleted_at is null)), '[]'::jsonb)
  ) into v_resultat;
  return v_resultat;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Orange Money : frais d'inscription d'une demande acceptée
-- ---------------------------------------------------------------------------
alter table public.transactions_mobile_money
  add column if not exists demande_inscription_id uuid references public.demandes_inscription (id) on delete restrict;
create index if not exists idx_transactions_mm_demande on public.transactions_mobile_money (demande_inscription_id)
  where demande_inscription_id is not null;

alter table public.transactions_mobile_money drop constraint if exists transactions_mobile_money_objet_check;
alter table public.transactions_mobile_money add constraint transactions_mobile_money_objet_check
  check (objet in ('scolarite', 'commande_marketplace', 'frais_inscription'));
alter table public.transactions_mobile_money drop constraint if exists transactions_mm_cible_coherente;
alter table public.transactions_mobile_money add constraint transactions_mm_cible_coherente check (
  (objet = 'scolarite' and inscription_id is not null and commande_id is null and demande_inscription_id is null)
  or (objet = 'commande_marketplace' and commande_id is not null and inscription_id is null and demande_inscription_id is null)
  or (objet = 'frais_inscription' and demande_inscription_id is not null and commande_id is null)
);

create or replace function public.initier_transaction_mobile_money(
  p_objet text,
  p_cible_id uuid,
  p_montant numeric default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_etab uuid;
  v_fiche uuid;
  v_montant numeric(12, 2);
  v_solde numeric;
  v_devise text;
  v_sous_compte uuid;
  v_commande public.commandes;
  v_demande public.demandes_inscription;
  v_tx public.transactions_mobile_money;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUISE' using errcode = '42501';
  end if;

  if p_objet = 'scolarite' then
    select i.etablissement_id, i.fiche_eleve_id into v_etab, v_fiche
    from public.inscriptions i
    where i.id = p_cible_id and i.deleted_at is null;
    if v_etab is null then
      raise exception 'INSCRIPTION_INTROUVABLE' using errcode = '22023';
    end if;
    -- Payeur : l'élève lui-même ou un parent confirmé et autorisé. Le
    -- personnel saisit les paiements au guichet (encaissement manuel).
    if not (exists (select 1 from public.fiches_eleves f where f.id = v_fiche and f.profile_id = v_uid)
            or public.est_parent_confirme(v_fiche)) then
      raise exception 'ACCES_REFUSE' using errcode = '42501';
    end if;

    select solde into v_solde from public.solde_scolarite(p_cible_id);
    v_montant := coalesce(p_montant, v_solde);
    if v_montant is null or v_montant <= 0 then
      raise exception 'RIEN_A_PAYER' using errcode = '22023';
    end if;
    if v_montant > v_solde then
      raise exception 'MONTANT_SUPERIEUR_AU_SOLDE' using errcode = '22023';
    end if;

  elsif p_objet = 'frais_inscription' then
    -- REG-08 : frais d'inscription d'une demande acceptée, montant fixé par
    -- l'école (jamais celui du client), place encore réservée.
    perform public.expirer_offres_inscription(
      (select campagne_id from public.demandes_inscription where id = p_cible_id));
    select * into v_demande from public.demandes_inscription where id = p_cible_id;
    if v_demande.id is null then
      raise exception 'DEMANDE_INTROUVABLE' using errcode = '22023';
    end if;
    if not (v_demande.demandeur_id = v_uid
            or (v_demande.fiche_eleve_id is not null and public.est_parent_confirme(v_demande.fiche_eleve_id))
            or exists (select 1 from public.fiches_eleves f
                       where f.id = v_demande.fiche_eleve_id and f.profile_id = v_uid)) then
      raise exception 'ACCES_REFUSE' using errcode = '42501';
    end if;
    if v_demande.statut <> 'acceptee' then
      raise exception 'DEMANDE_NON_PAYABLE' using errcode = '22023';
    end if;
    v_etab := v_demande.etablissement_id;
    v_montant := v_demande.montant_a_regler;
    if v_montant <= 0 then
      raise exception 'RIEN_A_PAYER' using errcode = '22023';
    end if;

  elsif p_objet = 'commande_marketplace' then
    select * into v_commande from public.commandes
    where id = p_cible_id and deleted_at is null;
    if v_commande.id is null then
      raise exception 'COMMANDE_INTROUVABLE' using errcode = '22023';
    end if;
    if v_commande.profile_id <> v_uid then
      raise exception 'ACCES_REFUSE' using errcode = '42501';
    end if;
    if v_commande.statut not in ('brouillon', 'confirmee') then
      raise exception 'COMMANDE_NON_PAYABLE' using errcode = '22023';
    end if;
    v_etab := v_commande.etablissement_id;
    -- Montant de la commande, jamais celui du client.
    v_montant := v_commande.montant_total + v_commande.montant_frais;
    if v_montant <= 0 then
      raise exception 'RIEN_A_PAYER' using errcode = '22023';
    end if;
  else
    raise exception 'OBJET_INCONNU' using errcode = '22023';
  end if;

  -- Une seule transaction en cours par cible : évite les doubles paiements.
  if exists (
    select 1 from public.transactions_mobile_money t
    where (t.inscription_id = p_cible_id or t.commande_id = p_cible_id or t.demande_inscription_id = p_cible_id)
      and t.statut in ('initie', 'en_attente')
      and t.created_at > now() - interval '30 minutes'
  ) then
    raise exception 'PAIEMENT_DEJA_EN_COURS' using errcode = '55000';
  end if;

  select s.id into v_sous_compte
  from public.sous_comptes_marchands s
  join public.secrets_sous_comptes_marchands sec on sec.sous_compte_id = s.id
  where s.etablissement_id = v_etab
    and s.fournisseur = 'orange_money_gn'
    and s.actif and s.deleted_at is null;
  if v_sous_compte is null then
    raise exception 'ORANGE_MONEY_NON_ACTIVE' using errcode = '55000';
  end if;

  select devise_code into v_devise from public.etablissements where id = v_etab;
  if v_devise = 'GNF' and v_montant <> trunc(v_montant) then
    raise exception 'MONTANT_GNF_ENTIER_REQUIS' using errcode = '22023';
  end if;

  insert into public.transactions_mobile_money (
    etablissement_id, sous_compte_id, fournisseur, objet,
    inscription_id, commande_id, demande_inscription_id, initiateur_id, montant, devise, reference_commande
  ) values (
    v_etab, v_sous_compte, 'orange_money_gn', p_objet,
    case when p_objet = 'scolarite' then p_cible_id end,
    case when p_objet = 'commande_marketplace' then p_cible_id end,
    case when p_objet = 'frais_inscription' then p_cible_id end,
    v_uid, v_montant, v_devise,
    'ECO' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 17))
  )
  returning * into v_tx;

  return jsonb_build_object(
    'transaction_id', v_tx.id,
    'reference_commande', v_tx.reference_commande,
    'montant', v_tx.montant,
    'devise', v_tx.devise,
    'sous_compte_id', v_tx.sous_compte_id
  );
end;
$$;

-- Seule autorité de crédit. Appelée par l'Edge Function APRÈS
-- reconfirmation du statut auprès de l'opérateur. Idempotente.
create or replace function public.traiter_resultat_mobile_money(
  p_transaction_id uuid,
  p_resultat text,               -- 'reussi' | 'echoue'
  p_montant_confirme numeric,
  p_reference_operateur text,
  p_message text default null
)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_tx public.transactions_mobile_money;
  v_fiche uuid;
  v_encaissement uuid;
  v_paiement uuid;
  v_inscription uuid;
  v_statut_demande public.statut_demande_inscription;
begin
  if p_resultat not in ('reussi', 'echoue') then
    raise exception 'RESULTAT_INVALIDE' using errcode = '22023';
  end if;

  select * into v_tx from public.transactions_mobile_money
  where id = p_transaction_id
  for update;

  if v_tx.id is null then
    raise exception 'TRANSACTION_INTROUVABLE' using errcode = '22023';
  end if;
  if v_tx.statut not in ('initie', 'en_attente') then
    return 'deja_traitee';
  end if;

  if p_resultat = 'echoue' then
    update public.transactions_mobile_money
       set statut = 'echoue', message = left(p_message, 500),
           reference_operateur = coalesce(p_reference_operateur, reference_operateur),
           traite_le = now()
     where id = v_tx.id;
    return 'echoue';
  end if;

  if p_montant_confirme is distinct from v_tx.montant then
    update public.transactions_mobile_money
       set statut = 'echoue', message = 'ECART_MONTANT',
           reference_operateur = p_reference_operateur, traite_le = now()
     where id = v_tx.id;
    return 'ecart_montant';
  end if;

  if v_tx.objet = 'scolarite' then
    select fiche_eleve_id into v_fiche from public.inscriptions where id = v_tx.inscription_id;
    insert into public.encaissements_scolarite (
      etablissement_id, fiche_eleve_id, inscription_id, type_frais, montant,
      moyen_paiement, reference_paiement, date_paiement, saisi_par
    ) values (
      v_tx.etablissement_id, v_fiche, v_tx.inscription_id, 'scolarite', v_tx.montant,
      'mobile_money', 'OM:' || coalesce(p_reference_operateur, v_tx.reference_commande),
      current_date, v_tx.initiateur_id
    )
    returning id into v_encaissement;
  elsif v_tx.objet = 'frais_inscription' then
    -- L'argent est encaissé : l'inscription est créée même si l'offre a
    -- expiré entre-temps (on ne garde jamais un paiement sans contrepartie).
    select statut into v_statut_demande from public.demandes_inscription where id = v_tx.demande_inscription_id;
    if v_statut_demande = 'expiree' then
      update public.demandes_inscription set statut = 'acceptee' where id = v_tx.demande_inscription_id;
    end if;
    v_inscription := public.finaliser_demande_inscription(
      v_tx.demande_inscription_id, null, v_tx.montant, 'mobile_money',
      'OM:' || coalesce(p_reference_operateur, v_tx.reference_commande));
    select id into v_encaissement from public.encaissements_scolarite
     where inscription_id = v_inscription and type_frais = 'inscription'
       and reference_paiement = 'OM:' || coalesce(p_reference_operateur, v_tx.reference_commande)
     order by created_at desc limit 1;
    update public.transactions_mobile_money set inscription_id = v_inscription where id = v_tx.id;
  else
    insert into public.paiements (
      etablissement_id, commande_id, sous_compte_id, fournisseur, montant,
      statut, reference_fournisseur, message
    ) values (
      v_tx.etablissement_id, v_tx.commande_id, v_tx.sous_compte_id, v_tx.fournisseur,
      v_tx.montant, 'reussi', p_reference_operateur, 'Orange Money'
    )
    returning id into v_paiement;

    update public.commandes set statut = 'payee' where id = v_tx.commande_id;
  end if;

  update public.transactions_mobile_money
     set statut = 'reussi', reference_operateur = p_reference_operateur,
         encaissement_id = v_encaissement, paiement_id = v_paiement,
         traite_le = now()
   where id = v_tx.id;

  return 'reussi';
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Stockage des pièces (privé : demandeur et personnel habilité)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pieces-inscription', 'pieces-inscription', false, 5242880,
        array['image/png', 'image/jpeg', 'image/webp', 'application/pdf'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Chemin : <demande_id>/<code>-<suffixe>.<ext>
create or replace function public.piece_inscription_deposable(p_chemin text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.demandes_inscription d
    where d.id::text = split_part(p_chemin, '/', 1)
      and d.demandeur_id = auth.uid()
      and d.statut in ('soumise', 'incomplete', 'convoquee', 'a_examiner', 'acceptee', 'liste_attente')
  );
$$;

create or replace function public.piece_inscription_lisible(p_chemin text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select case when split_part(p_chemin, '/', 1) ~ '^[0-9a-f-]{36}$'
              then public.demande_inscription_visible(split_part(p_chemin, '/', 1)::uuid)
              else false end;
$$;

drop policy if exists pieces_inscription_insert on storage.objects;
create policy pieces_inscription_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'pieces-inscription' and public.piece_inscription_deposable(name));

drop policy if exists pieces_inscription_update on storage.objects;
create policy pieces_inscription_update on storage.objects
  for update to authenticated
  using (bucket_id = 'pieces-inscription' and public.piece_inscription_deposable(name))
  with check (bucket_id = 'pieces-inscription' and public.piece_inscription_deposable(name));

drop policy if exists pieces_inscription_select on storage.objects;
create policy pieces_inscription_select on storage.objects
  for select to authenticated
  using (bucket_id = 'pieces-inscription' and public.piece_inscription_lisible(name));

-- ---------------------------------------------------------------------------
-- 10. RLS (lecture seule ; toute écriture passe par les fonctions)
-- ---------------------------------------------------------------------------
alter table public.campagnes_inscription enable row level security;
alter table public.places_inscription enable row level security;
alter table public.demandes_inscription enable row level security;
alter table public.pieces_demandes_inscription enable row level security;

revoke insert, update, delete on public.campagnes_inscription, public.places_inscription,
  public.demandes_inscription, public.pieces_demandes_inscription from anon, authenticated;

drop policy if exists campagnes_inscription_select on public.campagnes_inscription;
create policy campagnes_inscription_select on public.campagnes_inscription
  for select to authenticated
  using (publiee or public.est_personnel(etablissement_id) or public.est_admin_gsg());

drop policy if exists places_inscription_select on public.places_inscription;
create policy places_inscription_select on public.places_inscription
  for select to authenticated
  using (exists (select 1 from public.campagnes_inscription k
                 where k.id = campagne_id and (k.publiee or public.est_personnel(k.etablissement_id))));

drop policy if exists demandes_inscription_select on public.demandes_inscription;
create policy demandes_inscription_select on public.demandes_inscription
  for select to authenticated
  using (public.demande_inscription_visible(id) or public.est_admin_gsg());

drop policy if exists pieces_demandes_inscription_select on public.pieces_demandes_inscription;
create policy pieces_demandes_inscription_select on public.pieces_demandes_inscription
  for select to authenticated
  using (public.demande_inscription_visible(demande_id) or public.est_admin_gsg());

-- ---------------------------------------------------------------------------
-- 11. Droits d'exécution
-- ---------------------------------------------------------------------------
do $$
declare
  f text;
begin
  -- Mécanique interne : jamais appelable par un client.
  foreach f in array array[
    'public.finaliser_demande_inscription(uuid, uuid, numeric, public.moyen_paiement, text)',
    'public.offrir_place_inscription(uuid, boolean)',
    'public.promouvoir_liste_attente(uuid, uuid)',
    'public.notifier_demande_inscription(uuid, text, text)',
    'public.generer_matricule(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;

  foreach f in array array[
    'public.gere_inscriptions(uuid)',
    'public.demande_inscription_visible(uuid)',
    'public.niveau_suivant(uuid)',
    'public.niveau_propose_reinscription(uuid)',
    'public.niveau_offert(uuid, uuid)',
    'public.places_restantes_inscription(uuid, uuid)',
    'public.frais_inscription_niveau(uuid, uuid)',
    'public.enregistrer_campagne_inscription(uuid, uuid, date, date, date, integer, jsonb, jsonb, text, boolean)',
    'public.campagnes_inscription_ouvertes(text)',
    'public.reinscriptions_possibles()',
    'public.soumettre_demande_inscription(uuid, uuid, jsonb, text, timestamptz)',
    'public.deposer_piece_inscription(uuid, text, text)',
    'public.retirer_demande_inscription(uuid)',
    'public.traiter_demande_inscription(uuid, text, text, uuid, boolean)',
    'public.finaliser_inscription_guichet(uuid, uuid, numeric, public.moyen_paiement, text)',
    'public.tableau_campagne_inscription(uuid)',
    'public.piece_inscription_deposable(text)',
    'public.piece_inscription_lisible(text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

revoke all on function public.expirer_offres_inscription(uuid) from public, anon, authenticated;
grant execute on function public.expirer_offres_inscription(uuid) to service_role;

revoke all on function public.initier_transaction_mobile_money(text, uuid, numeric) from public, anon;
grant execute on function public.initier_transaction_mobile_money(text, uuid, numeric) to authenticated;
revoke all on function public.traiter_resultat_mobile_money(uuid, text, numeric, text, text) from public, anon, authenticated;
grant execute on function public.traiter_resultat_mobile_money(uuid, text, numeric, text, text) to service_role;
