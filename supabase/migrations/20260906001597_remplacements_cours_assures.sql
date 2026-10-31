-- ============================================================================
-- EcoShop — REG-41 : absences des enseignants, remplacements, cours assurés,
-- semaines A/B.
--
-- Recherche et choix : docs/propositions/REG-41_REMPLACEMENTS_COURS_ASSURES.md
-- (Untis, aSc Timetables, Pronote ; enquêtes SDI de la Banque mondiale : près
-- de la moitié du temps d'enseignement prévu est perdu, surtout par absence
-- de la classe). Décisions du porteur de projet (2026-10-31) :
--   1. la direction déclare les absences ; l'enseignant peut prévenir à
--      l'avance, la direction valide ;
--   2. compteur d'heures de remplacement, qui peut alimenter la paie au
--      choix de chaque école ;
--   3. parents prévenus quand un cours est annulé, en étude ou déplacé ; pour
--      un simple remplacement, les élèves seulement.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Réglages de l'école, semaines A/B
-- ---------------------------------------------------------------------------
alter table public.etablissements add column if not exists remplacements_payes boolean not null default false;
alter table public.etablissements add column if not exists tarif_heure_remplacement numeric(12, 2)
  check (tarif_heure_remplacement is null or tarif_heure_remplacement >= 0);
-- Un lundi d'une semaine A ; à défaut, le début de l'année scolaire.
alter table public.etablissements add column if not exists semaine_a_reference date;

alter table public.affectations_enseignants add column if not exists alternance text
  check (alternance is null or alternance in ('A', 'B'));
alter table public.emplois_du_temps add column if not exists semaine text
  check (semaine is null or semaine in ('A', 'B'));

comment on column public.affectations_enseignants.alternance is
  'REG-41 : cours une semaine sur deux (A ou B) ; nul = chaque semaine.';
comment on column public.emplois_du_temps.semaine is
  'REG-41 : séance des semaines A ou B seulement ; nulle = chaque semaine.';

-- Une séance A et une séance B peuvent partager le même créneau.
drop index if exists public.idx_emplois_creneau_unique;
create unique index if not exists idx_emplois_creneau_unique
  on public.emplois_du_temps (
    etablissement_id, annee_scolaire_id, classe_id,
    coalesce(groupe_id, '00000000-0000-0000-0000-000000000000'::uuid),
    jour_semaine, heure_debut, coalesce(semaine, '')
  )
  where deleted_at is null;

-- Semaine A ou B d'une date pour une école.
create or replace function public.semaine_ab(p_etablissement uuid, p_date date)
returns text
language sql stable security definer set search_path = public
as $$
  select case when ((p_date - (r.ref - (extract(isodow from r.ref)::int - 1))) / 7) % 2 = 0 then 'A' else 'B' end
    from (select coalesce(e.semaine_a_reference,
                          (select a.date_debut from public.annees_scolaires a
                            where a.etablissement_id = e.id and a.courante limit 1),
                          date '2026-09-07') as ref
            from public.etablissements e where e.id = p_etablissement) r;
$$;
grant execute on function public.semaine_ab(uuid, date) to authenticated;

-- La séance a-t-elle lieu cette semaine-là ?
create or replace function public.seance_a_lieu(p_semaine text, p_etablissement uuid, p_date date)
returns boolean
language sql stable set search_path = public
as $$
  select p_semaine is null or p_semaine = public.semaine_ab(p_etablissement, p_date);
$$;

-- Enregistrement de l'emploi du temps calculé : avec la semaine A/B.
create or replace function public.enregistrer_emploi_genere(
  p_etablissement uuid,
  p_annee uuid,
  p_seances jsonb,
  p_device_id text default null
)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_n integer;
begin
  if not public.a_permission(p_etablissement, 'planification.generer') then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if not exists (select 1 from public.annees_scolaires where id = p_annee and etablissement_id = p_etablissement) then
    raise exception 'ANNEE_HORS_ETABLISSEMENT' using errcode = '22023';
  end if;
  if jsonb_typeof(p_seances) <> 'array' then
    raise exception 'SEANCES_INVALIDES' using errcode = '22023';
  end if;

  update public.emplois_du_temps
     set deleted_at = now(), modifie_le = now(), device_id = p_device_id
   where etablissement_id = p_etablissement
     and annee_scolaire_id = p_annee
     and deleted_at is null
     and not verrouille;

  insert into public.emplois_du_temps (
    etablissement_id, annee_scolaire_id, classe_id, groupe_id, enseignant_profile_id,
    programme_matiere_id, salle_id, affectation_id, jour_semaine, heure_debut, heure_fin, semaine,
    type, origine, modifie_le, device_id)
  select p_etablissement, p_annee, s.classe_id, s.groupe_id, s.enseignant_profile_id,
         s.programme_matiere_id, s.salle_id, s.affectation_id, s.jour_semaine, s.heure_debut, s.heure_fin,
         nullif(s.semaine, ''),
         'cours', 'automatique', now(), p_device_id
    from jsonb_to_recordset(p_seances) as s(
      classe_id uuid, groupe_id uuid, enseignant_profile_id uuid, programme_matiere_id uuid,
      salle_id uuid, affectation_id uuid, jour_semaine int, heure_debut time, heure_fin time, semaine text);
  get diagnostics v_n = row_count;
  return v_n;
exception
  when unique_violation then
    raise exception 'CRENEAU_DEJA_OCCUPE' using errcode = '23505';
end;
$$;
revoke all on function public.enregistrer_emploi_genere(uuid, uuid, jsonb, text) from public, anon;
grant execute on function public.enregistrer_emploi_genere(uuid, uuid, jsonb, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 1. Droits
-- ---------------------------------------------------------------------------
create or replace function public.gere_remplacements(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.est_direction(p_etablissement), false)
      or coalesce(public.a_permission(p_etablissement, 'planification.generer'), false);
$$;
grant execute on function public.gere_remplacements(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Absences des enseignants
-- ---------------------------------------------------------------------------
create table if not exists public.absences_enseignants (
  id uuid primary key,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  enseignant_profile_id uuid not null references public.profiles (id) on delete cascade,
  date_debut date not null,
  date_fin date not null,
  heure_debut time,
  heure_fin time,
  motif text check (motif is null or char_length(motif) <= 300),
  statut text not null default 'validee' check (statut in ('signalee', 'validee', 'refusee')),
  declare_par uuid not null default auth.uid() references public.profiles (id),
  valide_par uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint absences_enseignants_dates check (date_fin >= date_debut and date_fin <= date_debut + 120),
  constraint absences_enseignants_heures check (heure_debut is null or heure_fin is null or heure_fin > heure_debut)
);
create index if not exists idx_absences_enseignants on public.absences_enseignants (etablissement_id, date_debut, date_fin)
  where deleted_at is null;

alter table public.absences_enseignants enable row level security;
revoke insert, update, delete on public.absences_enseignants from anon, authenticated;
drop policy if exists absences_enseignants_select on public.absences_enseignants;
create policy absences_enseignants_select on public.absences_enseignants for select to authenticated
  using (deleted_at is null and (public.gere_remplacements(etablissement_id) or enseignant_profile_id = auth.uid()));

-- Déclarer (ou modifier) une absence. La direction : validée d'office.
-- L'enseignant pour lui-même : signalée, à valider ; la direction est
-- prévenue.
create or replace function public.declarer_absence_enseignant(
  p_id uuid, p_etablissement uuid, p_enseignant uuid, p_du date, p_au date,
  p_heure_debut time default null, p_heure_fin time default null, p_motif text default null)
returns text
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_gere boolean := public.gere_remplacements(p_etablissement);
  v_statut text;
  v_dir uuid;
  v_nom text;
begin
  if not v_gere then
    if p_enseignant is distinct from auth.uid() or not exists (
         select 1 from public.etablissements_membres m
          where m.etablissement_id = p_etablissement and m.profile_id = auth.uid() and m.actif and m.deleted_at is null
            and m.role_dans_etablissement = 'enseignant') then
      raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
    end if;
    if p_du < current_date then
      raise exception 'ABSENCE_PASSEE' using errcode = '22023';
    end if;
  end if;
  if exists (select 1 from public.absences_enseignants where id = p_id and etablissement_id <> p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  v_statut := case when v_gere then 'validee' else 'signalee' end;
  insert into public.absences_enseignants (id, etablissement_id, enseignant_profile_id, date_debut, date_fin,
                                           heure_debut, heure_fin, motif, statut, declare_par, valide_par)
  values (p_id, p_etablissement, p_enseignant, p_du, coalesce(p_au, p_du), p_heure_debut, p_heure_fin,
          nullif(btrim(coalesce(p_motif, '')), ''), v_statut, auth.uid(), case when v_gere then auth.uid() end)
  on conflict (id) do update
    set date_debut = excluded.date_debut, date_fin = excluded.date_fin, heure_debut = excluded.heure_debut,
        heure_fin = excluded.heure_fin, motif = excluded.motif,
        statut = case when v_gere then 'validee' else absences_enseignants.statut end,
        valide_par = coalesce(absences_enseignants.valide_par, excluded.valide_par);

  if not v_gere then
    select trim(coalesce(prenom, '') || ' ' || coalesce(nom, '')) into v_nom from public.profiles where id = auth.uid();
    for v_dir in select m.profile_id from public.etablissements_membres m
                  where m.etablissement_id = p_etablissement and m.actif and m.deleted_at is null
                    and m.role_dans_etablissement = 'direction' loop
      perform public.notifier_push(p_etablissement, v_dir, 'absence_signalee',
        v_nom || ' prévient d''une absence le ' || to_char(p_du, 'DD/MM')
          || case when coalesce(p_au, p_du) > p_du then ' au ' || to_char(p_au, 'DD/MM') else '' end
          || ' : à valider, puis organiser les remplacements.',
        jsonb_build_object('absence_id', p_id));
    end loop;
  end if;
  return v_statut;
end;
$$;

create or replace function public.decider_absence_enseignant(p_id uuid, p_valider boolean)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  a public.absences_enseignants;
begin
  select * into a from public.absences_enseignants where id = p_id and deleted_at is null;
  if not found or not public.gere_remplacements(a.etablissement_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  update public.absences_enseignants
     set statut = case when p_valider then 'validee' else 'refusee' end, valide_par = auth.uid()
   where id = p_id;
end;
$$;

create or replace function public.retirer_absence_enseignant(p_id uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  a public.absences_enseignants;
begin
  select * into a from public.absences_enseignants where id = p_id and deleted_at is null;
  if not found or not (public.gere_remplacements(a.etablissement_id)
                       or (a.enseignant_profile_id = auth.uid() and a.statut = 'signalee')) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  update public.absences_enseignants set deleted_at = now() where id = p_id;
end;
$$;

-- Un enseignant est-il absent à ce créneau ?
create or replace function public.enseignant_absent(p_enseignant uuid, p_date date, p_debut time, p_fin time)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.absences_enseignants a
     where a.enseignant_profile_id = p_enseignant and a.deleted_at is null and a.statut = 'validee'
       and p_date between a.date_debut and a.date_fin
       and (a.heure_debut is null or a.heure_fin is null or (p_debut < a.heure_fin and p_fin > a.heure_debut)));
$$;

-- ---------------------------------------------------------------------------
-- 3. Séances modifiées (remplacement, étude, déplacement, annulation)
-- ---------------------------------------------------------------------------
create table if not exists public.seances_modifiees (
  id uuid primary key,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  emploi_id uuid not null references public.emplois_du_temps (id) on delete cascade,
  date_seance date not null,
  classe_id uuid not null references public.classes (id) on delete cascade,
  programme_matiere_id uuid references public.programmes_matieres (id) on delete set null,
  enseignant_absent_id uuid references public.profiles (id) on delete set null,
  heure_debut time not null,
  heure_fin time not null,
  solution text not null check (solution in ('remplacement', 'etude', 'deplace', 'annule')),
  remplacant_id uuid references public.profiles (id) on delete set null,
  salle_id uuid references public.salles (id) on delete set null,
  deplace_le date,
  deplace_heure_debut time,
  deplace_heure_fin time,
  note text check (note is null or char_length(note) <= 300),
  decide_par uuid not null default auth.uid() references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint seances_modifiees_remplacant check (solution not in ('remplacement', 'etude') or remplacant_id is not null),
  constraint seances_modifiees_deplace check (solution <> 'deplace'
    or (deplace_le is not null and deplace_heure_debut is not null and deplace_heure_fin > deplace_heure_debut))
);
create unique index if not exists idx_seances_modifiees_unique on public.seances_modifiees (emploi_id, date_seance)
  where deleted_at is null;
create index if not exists idx_seances_modifiees_date on public.seances_modifiees (etablissement_id, date_seance)
  where deleted_at is null;

drop trigger if exists seances_modifiees_set_updated_at on public.seances_modifiees;
create trigger seances_modifiees_set_updated_at before update on public.seances_modifiees
  for each row execute procedure public.set_updated_at();

alter table public.seances_modifiees enable row level security;
revoke insert, update, delete on public.seances_modifiees from anon, authenticated;
drop policy if exists seances_modifiees_select on public.seances_modifiees;
create policy seances_modifiees_select on public.seances_modifiees for select to authenticated
  using (deleted_at is null and (public.gere_remplacements(etablissement_id) or remplacant_id = auth.uid()
                                 or public.lit_cahier_classe(classe_id)));

-- Libellé d'une séance pour les notifications : « Maths 10h00 (6e A) ».
create or replace function public.libelle_seance(p_matiere uuid, p_classe uuid, p_date date, p_debut time)
returns text
language sql stable security definer set search_path = public
as $$
  select coalesce((select m.nom from public.programmes_matieres m where m.id = p_matiere), 'Cours')
      || ' du ' || to_char(p_date, 'DD/MM') || ' à ' || to_char(p_debut, 'HH24"h"MI')
      || coalesce(' (' || (select c.nom from public.classes c where c.id = p_classe) || ')', '');
$$;

-- Cours à remplacer un jour donné : séances des enseignants absents, avec la
-- décision déjà prise.
create or replace function public.cours_a_remplacer(p_etablissement uuid, p_date date)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_annee uuid;
begin
  if not public.gere_remplacements(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select id into v_annee from public.annees_scolaires where etablissement_id = p_etablissement and courante limit 1;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'emploi_id', e.id, 'date', p_date, 'classe_id', e.classe_id, 'classe', c.nom,
             'matiere_id', e.programme_matiere_id, 'matiere', m.nom,
             'heure_debut', e.heure_debut, 'heure_fin', e.heure_fin, 'salle', s.code,
             'enseignant_id', e.enseignant_profile_id,
             'enseignant', trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')),
             'modification', (select jsonb_build_object(
                                 'id', x.id, 'solution', x.solution, 'remplacant_id', x.remplacant_id,
                                 'remplacant', trim(coalesce(r.prenom, '') || ' ' || coalesce(r.nom, '')),
                                 'note', x.note, 'deplace_le', x.deplace_le,
                                 'deplace_heure_debut', x.deplace_heure_debut, 'deplace_heure_fin', x.deplace_heure_fin)
                                from public.seances_modifiees x
                                left join public.profiles r on r.id = x.remplacant_id
                               where x.emploi_id = e.id and x.date_seance = p_date and x.deleted_at is null))
           order by e.heure_debut, c.nom)
      from public.emplois_du_temps e
      join public.classes c on c.id = e.classe_id
      left join public.programmes_matieres m on m.id = e.programme_matiere_id
      left join public.salles s on s.id = e.salle_id
      left join public.profiles p on p.id = e.enseignant_profile_id
     where e.etablissement_id = p_etablissement and e.annee_scolaire_id = v_annee and e.deleted_at is null
       and e.type = 'cours' and e.jour_semaine = extract(isodow from p_date)::int
       and public.seance_a_lieu(e.semaine, p_etablissement, p_date)
       and (public.enseignant_absent(e.enseignant_profile_id, p_date, e.heure_debut, e.heure_fin)
            or exists (select 1 from public.seances_modifiees x
                        where x.emploi_id = e.id and x.date_seance = p_date and x.deleted_at is null))), '[]'::jsonb);
end;
$$;

-- Absences d'une période (validées et signalées), pour l'écran de la direction.
create or replace function public.absences_enseignants_periode(p_etablissement uuid, p_du date, p_au date)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.gere_remplacements(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', a.id, 'enseignant_id', a.enseignant_profile_id,
             'enseignant', trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')),
             'date_debut', a.date_debut, 'date_fin', a.date_fin, 'heure_debut', a.heure_debut, 'heure_fin', a.heure_fin,
             'motif', a.motif, 'statut', a.statut) order by a.statut desc, a.date_debut, p.nom)
      from public.absences_enseignants a
      join public.profiles p on p.id = a.enseignant_profile_id
     where a.etablissement_id = p_etablissement and a.deleted_at is null and a.statut <> 'refusee'
       and a.date_debut <= p_au and a.date_fin >= p_du), '[]'::jsonb);
end;
$$;

-- Remplaçants possibles pour une séance, du meilleur au moins bon :
-- libres à cette heure, même matière, connaissent la classe, moins
-- sollicités ce mois-ci (Untis). Le personnel (non enseignant) est proposé
-- pour une étude surveillée.
create or replace function public.remplacants_possibles(p_emploi uuid, p_date date)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  e public.emplois_du_temps;
begin
  select * into e from public.emplois_du_temps where id = p_emploi and deleted_at is null;
  if not found or not public.gere_remplacements(e.etablissement_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'profile_id', x.profile_id, 'nom', x.nom, 'role', x.role,
             'meme_matiere', x.meme_matiere, 'connait_classe', x.connait_classe, 'ce_mois', x.ce_mois)
           order by (x.role = 'enseignant') desc, x.meme_matiere desc, x.connait_classe desc, x.ce_mois, x.nom)
      from (
        select m.profile_id, m.role_dans_etablissement as role,
               trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')) as nom,
               exists (select 1 from public.affectations_enseignants a
                        join public.programmes_matieres pm on pm.id = a.programme_matiere_id
                        join public.programmes_matieres pe on pe.id = e.programme_matiere_id
                       where a.enseignant_profile_id = m.profile_id and a.deleted_at is null
                         and (a.programme_matiere_id = e.programme_matiere_id or lower(pm.nom) = lower(pe.nom))) as meme_matiere,
               exists (select 1 from public.affectations_enseignants a
                        where a.enseignant_profile_id = m.profile_id and a.classe_id = e.classe_id
                          and a.deleted_at is null) as connait_classe,
               (select count(*)::int from public.seances_modifiees s
                 where s.remplacant_id = m.profile_id and s.deleted_at is null
                   and s.date_seance >= date_trunc('month', p_date)::date) as ce_mois
          from public.etablissements_membres m
          join public.profiles p on p.id = m.profile_id
         where m.etablissement_id = e.etablissement_id and m.actif and m.deleted_at is null
           and m.role_dans_etablissement in ('enseignant', 'personnel', 'direction')
           and m.profile_id is distinct from e.enseignant_profile_id
           and not public.enseignant_absent(m.profile_id, p_date, e.heure_debut, e.heure_fin)
           -- Libre : pas de cours à cette heure ce jour-là (sauf cours annulé)…
           and not exists (
             select 1 from public.emplois_du_temps o
              where o.enseignant_profile_id = m.profile_id and o.deleted_at is null
                and o.annee_scolaire_id = e.annee_scolaire_id and o.jour_semaine = e.jour_semaine
                and o.heure_debut < e.heure_fin and o.heure_fin > e.heure_debut
                and public.seance_a_lieu(o.semaine, e.etablissement_id, p_date)
                and not exists (select 1 from public.seances_modifiees k
                                 where k.emploi_id = o.id and k.date_seance = p_date and k.deleted_at is null
                                   and k.solution in ('annule', 'deplace')))
           -- … et pas déjà un autre remplacement au même moment.
           and not exists (
             select 1 from public.seances_modifiees s
              where s.remplacant_id = m.profile_id and s.deleted_at is null and s.date_seance = p_date
                and s.emploi_id <> e.id and s.heure_debut < e.heure_fin and s.heure_fin > e.heure_debut)
      ) x), '[]'::jsonb);
end;
$$;

-- Décider pour une séance, puis prévenir : le remplaçant ou le surveillant,
-- les élèves de la classe ; les parents si le cours est annulé, en étude ou
-- déplacé (décision 3).
create or replace function public.decider_seance(
  p_id uuid, p_emploi uuid, p_date date, p_solution text,
  p_remplacant uuid default null, p_salle uuid default null,
  p_deplace_le date default null, p_deplace_debut time default null, p_deplace_fin time default null,
  p_note text default null)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  e public.emplois_du_temps;
  v_libelle text;
  v_texte text;
  v_nom text;
  v_dest uuid;
begin
  select * into e from public.emplois_du_temps where id = p_emploi and deleted_at is null;
  if not found or not public.gere_remplacements(e.etablissement_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_solution in ('remplacement', 'etude') and not exists (
       select 1 from public.etablissements_membres m
        where m.etablissement_id = e.etablissement_id and m.profile_id = p_remplacant and m.actif and m.deleted_at is null) then
    raise exception 'REMPLACANT_INCONNU' using errcode = '22023';
  end if;

  update public.seances_modifiees set deleted_at = now()
   where emploi_id = p_emploi and date_seance = p_date and deleted_at is null and id <> p_id;
  insert into public.seances_modifiees (id, etablissement_id, emploi_id, date_seance, classe_id, programme_matiere_id,
                                        enseignant_absent_id, heure_debut, heure_fin, solution, remplacant_id, salle_id,
                                        deplace_le, deplace_heure_debut, deplace_heure_fin, note)
  values (p_id, e.etablissement_id, e.id, p_date, e.classe_id, e.programme_matiere_id, e.enseignant_profile_id,
          e.heure_debut, e.heure_fin, p_solution,
          case when p_solution in ('remplacement', 'etude') then p_remplacant end, p_salle,
          case when p_solution = 'deplace' then p_deplace_le end,
          case when p_solution = 'deplace' then p_deplace_debut end,
          case when p_solution = 'deplace' then p_deplace_fin end,
          nullif(btrim(coalesce(p_note, '')), ''))
  on conflict (id) do update
    set solution = excluded.solution, remplacant_id = excluded.remplacant_id, salle_id = excluded.salle_id,
        deplace_le = excluded.deplace_le, deplace_heure_debut = excluded.deplace_heure_debut,
        deplace_heure_fin = excluded.deplace_heure_fin, note = excluded.note, deleted_at = null,
        decide_par = auth.uid();

  v_libelle := public.libelle_seance(e.programme_matiere_id, e.classe_id, p_date, e.heure_debut);
  select trim(coalesce(prenom, '') || ' ' || coalesce(nom, '')) into v_nom from public.profiles where id = p_remplacant;
  v_texte := v_libelle || case p_solution
    when 'remplacement' then ' : remplacé par ' || coalesce(v_nom, 'un autre enseignant')
    when 'etude' then ' : étude surveillée' || coalesce(' (' || v_nom || ')', '')
    when 'deplace' then ' : déplacé au ' || to_char(p_deplace_le, 'DD/MM') || ' à ' || to_char(p_deplace_debut, 'HH24"h"MI')
    else ' : annulé' end
    || coalesce(' — ' || nullif(btrim(coalesce(p_note, '')), ''), '');

  if p_solution in ('remplacement', 'etude') then
    perform public.notifier_push(e.etablissement_id, p_remplacant, 'remplacement_a_assurer',
      'À assurer — ' || v_libelle || case when p_solution = 'etude' then ' (étude surveillée)' else '' end,
      jsonb_build_object('seance_id', p_id));
  end if;
  for v_dest in
    select distinct d from (
      select f.profile_id as d
        from public.inscriptions i join public.fiches_eleves f on f.id = i.fiche_eleve_id and f.deleted_at is null
       where i.classe_id = e.classe_id and i.deleted_at is null and i.statut in ('active', 'redoublante')
         and (e.groupe_id is null or exists (select 1 from public.groupes_membres g
                                              where g.groupe_id = e.groupe_id and g.fiche_eleve_id = f.id))
      union
      select r.parent_profile_id
        from public.inscriptions i join public.relations_parent_eleve r on r.fiche_eleve_id = i.fiche_eleve_id
       where p_solution <> 'remplacement'
         and i.classe_id = e.classe_id and i.deleted_at is null and i.statut in ('active', 'redoublante')
         and r.statut = 'confirmee' and r.autorise and r.deleted_at is null
         and (e.groupe_id is null or exists (select 1 from public.groupes_membres g
                                              where g.groupe_id = e.groupe_id and g.fiche_eleve_id = i.fiche_eleve_id))
    ) x where d is not null
  loop
    perform public.notifier_push(e.etablissement_id, v_dest, 'cours_modifie', v_texte,
                                 jsonb_build_object('seance_id', p_id, 'classe_id', e.classe_id));
  end loop;
end;
$$;

create or replace function public.annuler_decision_seance(p_id uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  s public.seances_modifiees;
begin
  select * into s from public.seances_modifiees where id = p_id and deleted_at is null;
  if not found or not public.gere_remplacements(s.etablissement_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  update public.seances_modifiees set deleted_at = now() where id = p_id;
end;
$$;

-- Changements de l'emploi du temps d'une classe (élèves, parents, personnel).
create or replace function public.changements_classe(p_classe uuid, p_du date default null, p_au date default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.lit_cahier_classe(p_classe) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', s.id, 'date', s.date_seance, 'heure_debut', s.heure_debut, 'heure_fin', s.heure_fin,
             'matiere', m.nom, 'solution', s.solution,
             'remplacant', case when s.solution = 'remplacement'
                                then trim(coalesce(r.prenom, '') || ' ' || coalesce(r.nom, '')) end,
             'salle', sa.code, 'deplace_le', s.deplace_le, 'deplace_heure_debut', s.deplace_heure_debut,
             'deplace_heure_fin', s.deplace_heure_fin, 'note', s.note)
           order by s.date_seance, s.heure_debut)
      from public.seances_modifiees s
      left join public.programmes_matieres m on m.id = s.programme_matiere_id
      left join public.profiles r on r.id = s.remplacant_id
      left join public.salles sa on sa.id = s.salle_id
     where s.classe_id = p_classe and s.deleted_at is null
       and s.date_seance between coalesce(p_du, current_date) and coalesce(p_au, current_date + 14)), '[]'::jsonb);
end;
$$;

-- Changements de la classe d'une fiche (élève ou parent).
create or replace function public.changements_fiche(p_fiche uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_classe uuid;
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select i.classe_id into v_classe
    from public.inscriptions i join public.annees_scolaires a on a.id = i.annee_scolaire_id
   where i.fiche_eleve_id = p_fiche and i.deleted_at is null and i.statut in ('active', 'redoublante')
   order by a.date_debut desc limit 1;
  if v_classe is null then
    return '[]'::jsonb;
  end if;
  return public.changements_classe(v_classe);
end;
$$;

-- Ce que j'assure en remplacement, et mes absences.
create or replace function public.mes_remplacements(p_etablissement uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  return jsonb_build_object(
    'a_assurer', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id, 'date', s.date_seance, 'heure_debut', s.heure_debut, 'heure_fin', s.heure_fin,
               'classe', c.nom, 'matiere', m.nom, 'solution', s.solution, 'salle', sa.code, 'note', s.note,
               'absent', trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')))
             order by s.date_seance, s.heure_debut)
        from public.seances_modifiees s
        join public.classes c on c.id = s.classe_id
        left join public.programmes_matieres m on m.id = s.programme_matiere_id
        left join public.salles sa on sa.id = s.salle_id
        left join public.profiles p on p.id = s.enseignant_absent_id
       where s.etablissement_id = p_etablissement and s.remplacant_id = auth.uid() and s.deleted_at is null
         and s.date_seance >= current_date - 7), '[]'::jsonb),
    'absences', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', a.id, 'date_debut', a.date_debut, 'date_fin', a.date_fin, 'heure_debut', a.heure_debut,
               'heure_fin', a.heure_fin, 'motif', a.motif, 'statut', a.statut) order by a.date_debut desc)
        from public.absences_enseignants a
       where a.etablissement_id = p_etablissement and a.enseignant_profile_id = auth.uid() and a.deleted_at is null
         and a.date_fin >= current_date - 30), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Cours assurés (lot 2)
-- ---------------------------------------------------------------------------
-- Un cours prévu (emploi du temps, semaine A/B respectée, jours passés de
-- l'année) est assuré quand, ce jour-là, l'appel de la classe est fait pour
-- cette matière (ou à la demi-journée), qu'une séance du cahier de texte est
-- notée pour cette matière, ou qu'il a été remplacé. Annulé, en étude ou non
-- renseigné : perdu (une étude n'est pas un cours).
create or replace function public.cours_assures(p_etablissement uuid, p_du date, p_au date)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_annee public.annees_scolaires;
begin
  if not public.gere_remplacements(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_au - p_du > 120 then
    raise exception 'PERIODE_TROP_LONGUE' using errcode = '22023';
  end if;
  select * into v_annee from public.annees_scolaires where etablissement_id = p_etablissement and courante limit 1;
  return coalesce((
    with jours as (
      select d::date as jour
        from generate_series(greatest(p_du, v_annee.date_debut), least(p_au, current_date, v_annee.date_fin), interval '1 day') d
    ),
    prevus as (
      select e.id, e.classe_id, e.programme_matiere_id, e.enseignant_profile_id, j.jour,
             extract(epoch from (e.heure_fin - e.heure_debut))::int / 60 as minutes,
             (select x.solution from public.seances_modifiees x
               where x.emploi_id = e.id and x.date_seance = j.jour and x.deleted_at is null) as solution
        from public.emplois_du_temps e
        join jours j on extract(isodow from j.jour)::int = e.jour_semaine
       where e.etablissement_id = p_etablissement and e.annee_scolaire_id = v_annee.id and e.deleted_at is null
         and e.type = 'cours' and public.seance_a_lieu(e.semaine, p_etablissement, j.jour)
    ),
    statut as (
      select p.*,
             case
               when p.solution = 'remplacement' then true
               when p.solution in ('annule', 'etude') then false
               else exists (select 1 from public.presences pr
                             where pr.classe_id = p.classe_id and pr.date_presence = p.jour and pr.deleted_at is null
                               and (pr.programme_matiere_id is null or pr.programme_matiere_id = p.programme_matiere_id))
                 or exists (select 1 from public.cahier_texte ct
                             where ct.classe_id = p.classe_id and ct.date_seance = p.jour and ct.deleted_at is null
                               and ct.programme_matiere_id is not distinct from p.programme_matiere_id)
             end as assure
        from prevus p
    )
    select jsonb_build_object(
      'prevus', count(*), 'assures', count(*) filter (where assure),
      'minutes_perdues', coalesce(sum(minutes) filter (where not assure), 0),
      'lignes', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'classe_id', g.classe_id, 'classe', c.nom, 'matiere', m.nom,
                 'enseignant', trim(coalesce(pf.prenom, '') || ' ' || coalesce(pf.nom, '')),
                 'prevus', g.prevus, 'assures', g.assures, 'minutes_perdues', g.minutes_perdues,
                 'alerte', g.prevus > 0 and (g.prevus - g.assures)::numeric / g.prevus > 0.10)
               order by (g.prevus - g.assures)::numeric / greatest(g.prevus, 1) desc, c.nom, m.nom)
          from (select classe_id, programme_matiere_id, max(enseignant_profile_id::text)::uuid as enseignant,
                       count(*) as prevus, count(*) filter (where assure) as assures,
                       coalesce(sum(minutes) filter (where not assure), 0) as minutes_perdues
                  from statut group by classe_id, programme_matiere_id) g
          join public.classes c on c.id = g.classe_id
          left join public.programmes_matieres m on m.id = g.programme_matiere_id
          left join public.profiles pf on pf.id = g.enseignant), '[]'::jsonb),
      'enseignants', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'enseignant', trim(coalesce(pf.prenom, '') || ' ' || coalesce(pf.nom, '')),
                 'prevus', t.prevus, 'assures', t.assures) order by t.assures::numeric / greatest(t.prevus, 1))
          from (select enseignant_profile_id, count(*) as prevus, count(*) filter (where assure) as assures
                  from statut where enseignant_profile_id is not null group by enseignant_profile_id) t
          join public.profiles pf on pf.id = t.enseignant_profile_id), '[]'::jsonb))
    from statut), '{}'::jsonb);
end;
$$;

-- Compteur des remplacements (lot 2, décision 2) : heures faites en
-- remplacement ou en surveillance d'étude, cours manqués pour absence ; le
-- montant n'est calculé que si l'école paie les remplacements.
create or replace function public.compteur_remplacements(p_etablissement uuid, p_du date, p_au date)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_payes boolean;
  v_tarif numeric;
begin
  if not public.gere_remplacements(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select remplacements_payes, tarif_heure_remplacement into v_payes, v_tarif from public.etablissements where id = p_etablissement;
  return jsonb_build_object(
    'payes', coalesce(v_payes, false), 'tarif_heure', v_tarif,
    'lignes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'profile_id', x.pid, 'nom', trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')),
               'remplacements', x.remplacements, 'etudes', x.etudes, 'minutes_faites', x.minutes_faites,
               'cours_manques', x.manques,
               'montant', case when coalesce(v_payes, false) and v_tarif is not null
                               then round(x.minutes_faites / 60.0 * v_tarif, 0) end)
             order by x.minutes_faites desc, p.nom)
        from (
          select pid, sum(remplacements)::int as remplacements, sum(etudes)::int as etudes,
                 sum(minutes)::int as minutes_faites, sum(manques)::int as manques
            from (
              select s.remplacant_id as pid,
                     count(*) filter (where s.solution = 'remplacement') as remplacements,
                     count(*) filter (where s.solution = 'etude') as etudes,
                     sum(extract(epoch from (s.heure_fin - s.heure_debut)) / 60) as minutes, 0 as manques
                from public.seances_modifiees s
               where s.etablissement_id = p_etablissement and s.deleted_at is null and s.remplacant_id is not null
                 and s.date_seance between p_du and p_au
               group by s.remplacant_id
              union all
              select s.enseignant_absent_id, 0, 0, 0, count(*)
                from public.seances_modifiees s
               where s.etablissement_id = p_etablissement and s.deleted_at is null and s.enseignant_absent_id is not null
                 and s.date_seance between p_du and p_au
               group by s.enseignant_absent_id
            ) u group by pid
        ) x join public.profiles p on p.id = x.pid), '[]'::jsonb));
end;
$$;

create or replace function public.regler_remplacements(p_etablissement uuid, p_payes boolean, p_tarif numeric,
                                                       p_semaine_a date default null)
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if not coalesce(public.est_direction(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  update public.etablissements
     set remplacements_payes = coalesce(p_payes, false),
         tarif_heure_remplacement = p_tarif,
         semaine_a_reference = coalesce(p_semaine_a, semaine_a_reference)
   where id = p_etablissement;
end;
$$;

revoke all on function public.declarer_absence_enseignant(uuid, uuid, uuid, date, date, time, time, text),
  public.decider_absence_enseignant(uuid, boolean), public.retirer_absence_enseignant(uuid),
  public.cours_a_remplacer(uuid, date), public.absences_enseignants_periode(uuid, date, date),
  public.remplacants_possibles(uuid, date),
  public.decider_seance(uuid, uuid, date, text, uuid, uuid, date, time, time, text),
  public.annuler_decision_seance(uuid), public.changements_classe(uuid, date, date), public.changements_fiche(uuid),
  public.mes_remplacements(uuid), public.cours_assures(uuid, date, date), public.compteur_remplacements(uuid, date, date),
  public.regler_remplacements(uuid, boolean, numeric, date)
  from public, anon;
grant execute on function public.declarer_absence_enseignant(uuid, uuid, uuid, date, date, time, time, text),
  public.decider_absence_enseignant(uuid, boolean), public.retirer_absence_enseignant(uuid),
  public.cours_a_remplacer(uuid, date), public.absences_enseignants_periode(uuid, date, date),
  public.remplacants_possibles(uuid, date),
  public.decider_seance(uuid, uuid, date, text, uuid, uuid, date, time, time, text),
  public.annuler_decision_seance(uuid), public.changements_classe(uuid, date, date), public.changements_fiche(uuid),
  public.mes_remplacements(uuid), public.cours_assures(uuid, date, date), public.compteur_remplacements(uuid, date, date),
  public.regler_remplacements(uuid, boolean, numeric, date), public.enseignant_absent(uuid, date, time, time),
  public.seance_a_lieu(text, uuid, date), public.libelle_seance(uuid, uuid, date, time)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Badges de l'accueil
-- ---------------------------------------------------------------------------
-- Direction : cours d'aujourd'hui sans solution. Enseignant : remplacements
-- à assurer aujourd'hui et demain. Famille : cours changés d'ici demain.
do $$
declare
  v_def text := pg_get_functiondef('public.accueil_resume(uuid, uuid)'::regprocedure);
  v_ancre_dir text := 'v_res := v_res || jsonb_build_object(''alertes_ouvertes'', v_n);';
  v_ancre_ens text := 'v_res := v_res || jsonb_build_object(''notes_a_saisir'', v_n);';
  v_ancre_fam text := 'v_res := v_res || jsonb_build_object(''livres_a_rendre'', v_n);';
begin
  if position('cours_a_remplacer' in v_def) > 0 then
    return;
  end if;
  if position(v_ancre_dir in v_def) = 0 or position(v_ancre_ens in v_def) = 0 or position(v_ancre_fam in v_def) = 0 then
    raise exception 'accueil_resume : texte attendu introuvable';
  end if;
  v_def := replace(v_def, v_ancre_dir, v_ancre_dir || $r$
  end if;
  if coalesce(public.gere_remplacements(p_etablissement), false) then
    select count(*) into v_n
      from jsonb_array_elements(public.cours_a_remplacer(p_etablissement, current_date)) x
     where x -> 'modification' is null or jsonb_typeof(x -> 'modification') = 'null';
    v_res := v_res || jsonb_build_object('cours_a_remplacer', v_n);
    select count(*) into v_n from public.absences_enseignants
     where etablissement_id = p_etablissement and statut = 'signalee' and deleted_at is null and date_fin >= current_date;
    v_res := v_res || jsonb_build_object('absences_a_valider', v_n);$r$);
  v_def := replace(v_def, v_ancre_ens, v_ancre_ens || $r$
    select count(*) into v_n from public.seances_modifiees
     where etablissement_id = p_etablissement and remplacant_id = v_uid and deleted_at is null
       and date_seance between current_date and current_date + 1;
    v_res := v_res || jsonb_build_object('remplacements_a_assurer', v_n);$r$);
  v_def := replace(v_def, v_ancre_fam, v_ancre_fam || $r$
    select count(*) into v_n from public.seances_modifiees s
     where s.deleted_at is null and s.date_seance between current_date and current_date + 1
       and exists (select 1 from public.inscriptions i where i.fiche_eleve_id = v_fiche and i.classe_id = s.classe_id
                    and i.deleted_at is null and i.statut in ('active', 'redoublante'));
    v_res := v_res || jsonb_build_object('cours_modifies', v_n);$r$);
  execute v_def;
end $$;
