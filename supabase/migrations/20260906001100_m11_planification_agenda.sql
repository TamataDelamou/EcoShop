-- ===========================================================================
-- M11 — Planification & Agenda
-- Emplois du temps, événements d'agenda, progression pédagogique, contraintes
-- de planification. IA : placement de séances (CSP glouton), détection de
-- conflits, prédiction de charge, recommandation de séances de rattrapage.
-- Hors-ligne : cache + synchronisation LWW (modifie_le + device_id).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Permissions fines
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domaine, libelle, description) values
  ('planification.consulter',   'planification', 'Consulter la planification',  'Lire les emplois du temps, agendas et progressions de son établissement'),
  ('planification.generer',     'planification', 'Générer la planification',    'Créer et modifier les emplois du temps, événements et séances'),
  ('planification.administrer', 'planification', 'Administrer la planification','Gérer les contraintes et valider les propositions IA')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Salles — ressources physiques de l'établissement
-- ---------------------------------------------------------------------------
create table if not exists public.salles (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  code text not null,
  nom text not null default '',
  capacite int check (capacite > 0),
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint salles_code_unique unique (etablissement_id, code)
);

drop trigger if exists salles_set_updated_at on public.salles;
create trigger salles_set_updated_at
  before update on public.salles
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3. Emplois du temps — créneau hebdomadaire récurrent (jour + heure)
-- ---------------------------------------------------------------------------
create table if not exists public.emplois_du_temps (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  classe_id uuid not null references public.classes (id) on delete cascade,
  enseignant_profile_id uuid references public.profiles (id) on delete set null,
  programme_matiere_id uuid references public.programmes_matieres (id) on delete set null,
  salle_id uuid references public.salles (id) on delete set null,
  jour_semaine int not null check (jour_semaine between 1 and 7),
  heure_debut time not null,
  heure_fin time not null,
  type text not null default 'cours' check (type in ('cours','pause','activite','etude','examen')),
  modifie_le timestamptz not null default now(),   -- LWW : dernière écriture gagne
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint emplois_creneau_coherent check (heure_fin > heure_debut)
);

create unique index if not exists idx_emplois_creneau_unique
  on public.emplois_du_temps (etablissement_id, annee_scolaire_id, classe_id, jour_semaine, heure_debut, heure_fin);

drop trigger if exists emplois_set_updated_at on public.emplois_du_temps;
create trigger emplois_set_updated_at
  before update on public.emplois_du_temps
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 4. Événements d'agenda — réunions, conseils, examens, sorties, rappels
--    (complémentaire de evenements_scolaires M7, qui porte l'impact présences)
-- ---------------------------------------------------------------------------
create table if not exists public.evenements_agenda (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  classe_id uuid references public.classes (id) on delete cascade,
  titre text not null,
  type text not null default 'reunion'
    check (type in ('examen','reunion','conseil_classe','sortie','fete','rappel','autre')),
  date_debut date not null,
  date_fin date not null,
  heure_debut time,
  heure_fin time,
  lieu text,
  participants jsonb not null default '{}'::jsonb,
  rappel boolean not null default false,          -- rappel via M9
  modifie_le timestamptz not null default now(),   -- LWW
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint evenements_agenda_periode_coherente check (date_fin >= date_debut)
);

drop trigger if exists evenements_agenda_set_updated_at on public.evenements_agenda;
create trigger evenements_agenda_set_updated_at
  before update on public.evenements_agenda
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 5. Progression pédagogique — séances liées au programme M4 et aux évaluations M6
-- ---------------------------------------------------------------------------
create table if not exists public.progression_pedagogique (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  classe_id uuid not null references public.classes (id) on delete cascade,
  programme_matiere_id uuid references public.programmes_matieres (id) on delete set null,
  enseignant_profile_id uuid not null references public.profiles (id) on delete cascade,
  seance text not null,
  objectifs text,
  contenu text,
  evaluation_id uuid references public.evaluations (id) on delete set null,
  statut text not null default 'planifiee'
    check (statut in ('planifiee','realisee','reportee','annulee','proposee')),
  date_prevue date,
  date_realisee date,
  modifie_le timestamptz not null default now(),   -- LWW
  device_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint progression_dates_coherentes
    check (date_realisee is null or date_prevue is null or date_realisee >= date_prevue)
);

create unique index if not exists idx_progression_rattrapage_unique
  on public.progression_pedagogique (etablissement_id, annee_scolaire_id, classe_id)
  where statut = 'proposee';

drop trigger if exists progression_set_updated_at on public.progression_pedagogique;
create trigger progression_set_updated_at
  before update on public.progression_pedagogique
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 6. Contraintes de planification — indisponibilités, préférences, vacances
-- ---------------------------------------------------------------------------
create table if not exists public.contraintes_emploi (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  enseignant_profile_id uuid references public.profiles (id) on delete cascade,
  salle_id uuid references public.salles (id) on delete cascade,
  classe_id uuid references public.classes (id) on delete cascade,
  jour_semaine int check (jour_semaine between 1 and 7),
  heure_debut time,
  heure_fin time,
  type text not null default 'indisponibilite'
    check (type in ('indisponibilite_enseignant','indisponibilite_salle','indisponibilite_classe','preference','vacance')),
  raison text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint contraintes_coherentes
    check (heure_fin is null or heure_debut is null or heure_fin > heure_debut)
);

drop trigger if exists contraintes_set_updated_at on public.contraintes_emploi;
create trigger contraintes_set_updated_at
  before update on public.contraintes_emploi
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 7. Garde-fous multi-tenant
-- ---------------------------------------------------------------------------
create or replace function public.salles_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.etablissement_id is null then
    raise exception 'SALLE_SANS_ETABLISSEMENT' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists salles_verifie_tenant_trg on public.salles;
create trigger salles_verifie_tenant_trg
  before insert or update on public.salles
  for each row execute procedure public.salles_verifie_tenant();

create or replace function public.emplois_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid; v_annee uuid;
begin
  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'EMPLOI_ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  select etablissement_id, annee_scolaire_id into v_etab, v_annee from public.classes where id = new.classe_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'EMPLOI_CLASSE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  if v_annee is distinct from new.annee_scolaire_id then
    raise exception 'EMPLOI_CLASSE_AUTRE_ANNEE' using errcode = '23514';
  end if;

  if new.salle_id is not null then
    select etablissement_id into v_etab from public.salles where id = new.salle_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'EMPLOI_SALLE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;

  if new.enseignant_profile_id is not null and not exists (
    select 1 from public.etablissements_membres m
    where m.profile_id = new.enseignant_profile_id and m.etablissement_id = new.etablissement_id
      and m.actif and m.deleted_at is null
  ) then
    raise exception 'EMPLOI_ENSEIGNANT_NON_MEMBRE' using errcode = '23514';
  end if;

  return new;
end $$;

drop trigger if exists emplois_verifie_tenant_trg on public.emplois_du_temps;
create trigger emplois_verifie_tenant_trg
  before insert or update on public.emplois_du_temps
  for each row execute procedure public.emplois_verifie_tenant();

create or replace function public.evenements_agenda_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid; v_annee uuid;
begin
  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'EVENEMENT_ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  if new.classe_id is not null then
    select etablissement_id, annee_scolaire_id into v_etab, v_annee from public.classes where id = new.classe_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'EVENEMENT_CLASSE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
    if v_annee is distinct from new.annee_scolaire_id then
      raise exception 'EVENEMENT_CLASSE_AUTRE_ANNEE' using errcode = '23514';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists evenements_agenda_verifie_tenant_trg on public.evenements_agenda;
create trigger evenements_agenda_verifie_tenant_trg
  before insert or update on public.evenements_agenda
  for each row execute procedure public.evenements_agenda_verifie_tenant();

create or replace function public.progression_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid; v_annee uuid;
begin
  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'PROGRESSION_ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  select etablissement_id, annee_scolaire_id into v_etab, v_annee from public.classes where id = new.classe_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'PROGRESSION_CLASSE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  if v_annee is distinct from new.annee_scolaire_id then
    raise exception 'PROGRESSION_CLASSE_AUTRE_ANNEE' using errcode = '23514';
  end if;

  if new.evaluation_id is not null then
    select etablissement_id into v_etab from public.evaluations where id = new.evaluation_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'PROGRESSION_EVALUATION_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists progression_verifie_tenant_trg on public.progression_pedagogique;
create trigger progression_verifie_tenant_trg
  before insert or update on public.progression_pedagogique
  for each row execute procedure public.progression_verifie_tenant();

create or replace function public.contraintes_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'CONTRAINTE_ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  if new.salle_id is not null then
    select etablissement_id into v_etab from public.salles where id = new.salle_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'CONTRAINTE_SALLE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;

  if new.classe_id is not null then
    select etablissement_id into v_etab from public.classes where id = new.classe_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'CONTRAINTE_CLASSE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists contraintes_verifie_tenant_trg on public.contraintes_emploi;
create trigger contraintes_verifie_tenant_trg
  before insert or update on public.contraintes_emploi
  for each row execute procedure public.contraintes_verifie_tenant();

-- ---------------------------------------------------------------------------
-- 8. Fonctions IA (SECURITY DEFINER)
-- ---------------------------------------------------------------------------

-- 8.1 Optimisation (CSP glouton) : premier créneau libre commun (enseignant +
--     classe + salle), en respectant les contraintes d'indisponibilité.
create or replace function public.suggerer_placement_seance(
  p_etab uuid, p_annee uuid, p_enseignant uuid, p_classe uuid, p_salle uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_j int; v_h int; v_debut time; v_fin time;
begin
  if not public.est_personnel(p_etab) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  for v_j in 1..7 loop
    for v_h in 8..16 loop
      v_debut := make_time(v_h, 0, 0);
      v_fin := make_time(v_h + 1, 0, 0);

      if not exists (
        select 1 from public.emplois_du_temps e
        where e.etablissement_id = p_etab and e.annee_scolaire_id = p_annee
          and e.jour_semaine = v_j and e.deleted_at is null
          and e.heure_debut < v_fin and v_debut < e.heure_fin
          and (e.classe_id = p_classe or e.enseignant_profile_id = p_enseignant or e.salle_id = p_salle)
      ) and not exists (
        select 1 from public.contraintes_emploi c
        where c.etablissement_id = p_etab and c.annee_scolaire_id = p_annee
          and c.deleted_at is null
          and (c.jour_semaine is null or c.jour_semaine = v_j)
          and (c.heure_debut is null or c.heure_fin is null or (c.heure_debut < v_fin and v_debut < c.heure_fin))
          and (c.enseignant_profile_id = p_enseignant or c.salle_id = p_salle or c.classe_id = p_classe)
      ) then
        return jsonb_build_object('jour_semaine', v_j, 'heure_debut', v_debut::text, 'heure_fin', v_fin::text);
      end if;
    end loop;
  end loop;

  return null;
end $$;

-- 8.2 Détection de conflits (chevauchements horaires) avec type de ressource.
create or replace function public.detecter_conflits_emploi(p_etab uuid, p_annee uuid)
returns setof jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.est_personnel(p_etab) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  return query
  select jsonb_build_object('type','salle','a',a.id,'b',b.id,'jour_semaine',a.jour_semaine,
                            'heure_debut',a.heure_debut::text,'heure_fin',a.heure_fin::text)
  from public.emplois_du_temps a
  join public.emplois_du_temps b on b.salle_id = a.salle_id and b.id > a.id
  where a.etablissement_id = p_etab and a.annee_scolaire_id = p_annee
    and b.etablissement_id = p_etab and b.annee_scolaire_id = p_annee
    and a.deleted_at is null and b.deleted_at is null
    and a.salle_id is not null and b.salle_id is not null
    and a.jour_semaine = b.jour_semaine
    and a.heure_debut < b.heure_fin and b.heure_debut < a.heure_fin

  union all

  select jsonb_build_object('type','enseignant','a',a.id,'b',b.id,'jour_semaine',a.jour_semaine,
                            'heure_debut',a.heure_debut::text,'heure_fin',a.heure_fin::text)
  from public.emplois_du_temps a
  join public.emplois_du_temps b on b.enseignant_profile_id = a.enseignant_profile_id and b.id > a.id
  where a.etablissement_id = p_etab and a.annee_scolaire_id = p_annee
    and b.etablissement_id = p_etab and b.annee_scolaire_id = p_annee
    and a.deleted_at is null and b.deleted_at is null
    and a.enseignant_profile_id is not null and b.enseignant_profile_id is not null
    and a.jour_semaine = b.jour_semaine
    and a.heure_debut < b.heure_fin and b.heure_debut < a.heure_fin

  union all

  select jsonb_build_object('type','classe','a',a.id,'b',b.id,'jour_semaine',a.jour_semaine,
                            'heure_debut',a.heure_debut::text,'heure_fin',a.heure_fin::text)
  from public.emplois_du_temps a
  join public.emplois_du_temps b on b.classe_id = a.classe_id and b.id > a.id
  where a.etablissement_id = p_etab and a.annee_scolaire_id = p_annee
    and b.etablissement_id = p_etab and b.annee_scolaire_id = p_annee
    and a.deleted_at is null and b.deleted_at is null
    and a.jour_semaine = b.jour_semaine
    and a.heure_debut < b.heure_fin and b.heure_debut < a.heure_fin;
end $$;

-- 8.3 Prédiction de charge — enseignant (heures hebdo vs volume contractuel).
create or replace function public.charger_travail_enseignant(p_etab uuid, p_annee uuid, p_enseignant uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_heures numeric; v_nb int; v_volume int;
begin
  if not public.est_personnel(p_etab) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  select coalesce(sum(extract(epoch from (e.heure_fin - e.heure_debut)) / 3600.0), 0)::numeric,
         count(*)
  into v_heures, v_nb
  from public.emplois_du_temps e
  where e.etablissement_id = p_etab and e.annee_scolaire_id = p_annee
    and e.enseignant_profile_id = p_enseignant and e.deleted_at is null;

  select coalesce(sum(volume_horaire_hebdo), 0)::int into v_volume
  from public.affectations_enseignants
  where etablissement_id = p_etab and annee_scolaire_id = p_annee
    and enseignant_profile_id = p_enseignant and deleted_at is null;

  return jsonb_build_object(
    'enseignant', p_enseignant,
    'heures_hebdo', round(v_heures, 2),
    'nb_seances', v_nb,
    'volume_contractuel_hebdo', v_volume,
    'surcharge', (v_volume > 0 and v_heures > v_volume)
  );
end $$;

-- 8.4 Prédiction de charge — élève/classe (heures hebdo, seuil 35 h).
create or replace function public.charger_travail_eleve(p_classe uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_heures numeric; v_nb int; v_jours int;
begin
  if not public.classe_visible(p_classe) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  select coalesce(sum(extract(epoch from (heure_fin - heure_debut)) / 3600.0), 0)::numeric,
         count(*),
         count(distinct jour_semaine)
  into v_heures, v_nb, v_jours
  from public.emplois_du_temps
  where classe_id = p_classe and deleted_at is null;

  return jsonb_build_object(
    'classe', p_classe,
    'heures_hebdo', round(v_heures, 2),
    'nb_seances', v_nb,
    'jours_occupes', v_jours,
    'surcharge', (v_heures > 35)
  );
end $$;

-- 8.5 Recommandation de séances de rattrapage (croise M6 réussite × M7 assiduité).
create or replace function public.recommander_seances(p_etab uuid, p_annee uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  r record; v_reussite numeric; v_absenteisme numeric;
begin
  if not public.est_personnel(p_etab) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  for r in
    select c.id as classe, c.enseignant_principal_id as prof
    from public.classes c
    where c.etablissement_id = p_etab and c.annee_scolaire_id = p_annee
      and c.actif and c.deleted_at is null and c.enseignant_principal_id is not null
  loop
    select case when count(*) = 0 then 0
                else count(*) filter (where n.valeur / e.bareme >= 0.5)::numeric / count(*)::numeric end
    into v_reussite
    from public.notes n
    join public.evaluations e on e.id = n.evaluation_id
    where e.classe_id = r.classe and n.deleted_at is null and e.deleted_at is null and n.absent = false;

    select case when count(*) = 0 then 0
                else count(*) filter (where p.statut <> 'present')::numeric / count(*)::numeric end
    into v_absenteisme
    from public.presences p
    where p.classe_id = r.classe and p.deleted_at is null;

    if v_absenteisme > 0.2 or v_reussite < 0.6 then
      insert into public.progression_pedagogique
        (etablissement_id, annee_scolaire_id, classe_id, enseignant_profile_id, seance, objectifs, statut, date_prevue)
      values (p_etab, p_annee, r.classe, r.prof, 'Séance de rattrapage',
              'Consolider les acquis (difficultés détectées en M6/M7)', 'proposee', current_date + 7)
      on conflict (etablissement_id, annee_scolaire_id, classe_id)
        where statut = 'proposee' do nothing;
    end if;
  end loop;

  return (select count(*) from public.progression_pedagogique
          where etablissement_id = p_etab and annee_scolaire_id = p_annee and statut = 'proposee');
end $$;

-- ---------------------------------------------------------------------------
-- 9. RLS — isolation par établissement, visibilité par rôle
-- ---------------------------------------------------------------------------
alter table public.salles enable row level security;
alter table public.emplois_du_temps enable row level security;
alter table public.evenements_agenda enable row level security;
alter table public.progression_pedagogique enable row level security;
alter table public.contraintes_emploi enable row level security;

-- Salles : lecture personnel, écriture administration.
create policy salles_select on public.salles for select to authenticated
  using (public.est_personnel(etablissement_id));
create policy salles_insert on public.salles for insert to authenticated
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'planification.administrer'));
create policy salles_update on public.salles for update to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'planification.administrer'))
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'planification.administrer'));
create policy salles_delete on public.salles for delete to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'planification.administrer'));

-- Emplois du temps : personnel + élèves/parents de la classe (lecture).
create policy emplois_select on public.emplois_du_temps for select to authenticated
  using (public.est_personnel(etablissement_id) or public.classe_visible(classe_id));
create policy emplois_insert on public.emplois_du_temps for insert to authenticated
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'planification.generer'));
create policy emplois_update on public.emplois_du_temps for update to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'planification.generer'))
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'planification.generer'));
create policy emplois_delete on public.emplois_du_temps for delete to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'planification.generer'));

-- Événements d'agenda : personnel + élèves/parents de la classe concernée.
create policy evenements_select on public.evenements_agenda for select to authenticated
  using (public.est_personnel(etablissement_id)
         or (classe_id is not null and public.classe_visible(classe_id)));
create policy evenements_insert on public.evenements_agenda for insert to authenticated
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'planification.generer'));
create policy evenements_update on public.evenements_agenda for update to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'planification.generer'))
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'planification.generer'));
create policy evenements_delete on public.evenements_agenda for delete to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'planification.generer'));

-- Progression pédagogique : réservée au personnel.
create policy progression_select on public.progression_pedagogique for select to authenticated
  using (public.est_personnel(etablissement_id));
create policy progression_insert on public.progression_pedagogique for insert to authenticated
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'planification.generer'));
create policy progression_update on public.progression_pedagogique for update to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'planification.generer'))
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'planification.generer'));
create policy progression_delete on public.progression_pedagogique for delete to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'planification.administrer'));

-- Contraintes : lecture personnel, écriture administration.
create policy contraintes_select on public.contraintes_emploi for select to authenticated
  using (public.est_personnel(etablissement_id));
create policy contraintes_insert on public.contraintes_emploi for insert to authenticated
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'planification.administrer'));
create policy contraintes_update on public.contraintes_emploi for update to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'planification.administrer'))
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'planification.administrer'));
create policy contraintes_delete on public.contraintes_emploi for delete to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'planification.administrer'));

-- ---------------------------------------------------------------------------
-- 10. Droits d'exécution
-- ---------------------------------------------------------------------------
grant select, insert, update, delete on public.salles to authenticated;
grant select, insert, update, delete on public.emplois_du_temps to authenticated;
grant select, insert, update, delete on public.evenements_agenda to authenticated;
grant select, insert, update, delete on public.progression_pedagogique to authenticated;
grant select, insert, update, delete on public.contraintes_emploi to authenticated;

grant execute on function public.suggerer_placement_seance(uuid, uuid, uuid, uuid, uuid) to authenticated;
grant execute on function public.detecter_conflits_emploi(uuid, uuid) to authenticated;
grant execute on function public.charger_travail_enseignant(uuid, uuid, uuid) to authenticated;
grant execute on function public.charger_travail_eleve(uuid) to authenticated;
grant execute on function public.recommander_seances(uuid, uuid) to authenticated;
