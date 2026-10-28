-- ============================================================================
-- EcoShop — REG-23 : mise en route d'un établissement en un seul parcours
-- (retour du porteur de projet, 2026-10-28 : « regrouper les activités
-- primordiales pour la configuration d'un établissement : année scolaire,
-- classes, groupes pédagogiques, frais de scolarité… »)
--
--   • classes.filiere_id : série du lycée (SM, SE, SS…), qui choisit le
--     programme officiel de la classe parmi ceux du niveau.
--   • groupes_pedagogiques / groupes_membres : parties de classe (demi-
--     classe de TP, langue vivante, option, soutien) ou groupes de
--     plusieurs classes. Utilisés par l'emploi du temps : deux groupes
--     d'une même classe peuvent avoir cours en même temps.
--   • creer_annee_scolaire() : année + découpage (trimestres ou semestres)
--     + reprise facultative des classes et des frais de l'année précédente,
--     en une seule action.
--   • definir_annee_courante() : bascule de l'année courante.
--   • etat_configuration_etablissement() : où en est la mise en route
--     (liste des étapes de l'écran « Configurer mon établissement »).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Série (filière) de la classe
-- ---------------------------------------------------------------------------
alter table public.classes
  add column if not exists filiere_id uuid references public.filieres_educatives (id) on delete set null;

-- ---------------------------------------------------------------------------
-- 2. Groupes pédagogiques
-- ---------------------------------------------------------------------------
create table if not exists public.groupes_pedagogiques (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  -- Null : groupe de plusieurs classes (option commune à un niveau…).
  classe_id uuid references public.classes (id) on delete cascade,
  nom text not null check (char_length(trim(nom)) between 1 and 60),
  type text not null default 'demi_classe'
    check (type in ('demi_classe', 'langue', 'option', 'soutien', 'autre')),
  capacite int check (capacite is null or capacite > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists idx_groupes_nom_unique
  on public.groupes_pedagogiques (
    annee_scolaire_id,
    coalesce(classe_id, '00000000-0000-0000-0000-000000000000'::uuid),
    lower(trim(nom))
  )
  where deleted_at is null;
create index if not exists idx_groupes_classe on public.groupes_pedagogiques (classe_id);
create index if not exists idx_groupes_etablissement on public.groupes_pedagogiques (etablissement_id, annee_scolaire_id);

drop trigger if exists groupes_set_updated_at on public.groupes_pedagogiques;
create trigger groupes_set_updated_at
  before update on public.groupes_pedagogiques
  for each row execute procedure public.set_updated_at();

create table if not exists public.groupes_membres (
  groupe_id uuid not null references public.groupes_pedagogiques (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (groupe_id, fiche_eleve_id)
);
create index if not exists idx_groupes_membres_fiche on public.groupes_membres (fiche_eleve_id);

create or replace function public.groupes_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
begin
  if not exists (select 1 from public.annees_scolaires a
                  where a.id = new.annee_scolaire_id and a.etablissement_id = new.etablissement_id) then
    raise exception 'GROUPE_ANNEE_HORS_ETABLISSEMENT' using errcode = '22023';
  end if;
  if new.classe_id is not null and not exists (
       select 1 from public.classes c
        where c.id = new.classe_id and c.etablissement_id = new.etablissement_id
          and c.annee_scolaire_id = new.annee_scolaire_id) then
    raise exception 'GROUPE_CLASSE_HORS_ANNEE' using errcode = '22023';
  end if;
  return new;
end $$;
drop trigger if exists groupes_verifie_tenant_trg on public.groupes_pedagogiques;
create trigger groupes_verifie_tenant_trg
  before insert or update on public.groupes_pedagogiques
  for each row execute procedure public.groupes_verifie_tenant();

create or replace function public.groupes_membres_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
begin
  if not exists (select 1 from public.groupes_pedagogiques g
                  where g.id = new.groupe_id and g.etablissement_id = new.etablissement_id) then
    raise exception 'GROUPE_HORS_ETABLISSEMENT' using errcode = '22023';
  end if;
  if not exists (select 1 from public.fiches_eleves f
                  where f.id = new.fiche_eleve_id and f.etablissement_id = new.etablissement_id) then
    raise exception 'ELEVE_HORS_ETABLISSEMENT' using errcode = '22023';
  end if;
  return new;
end $$;
drop trigger if exists groupes_membres_verifie_tenant_trg on public.groupes_membres;
create trigger groupes_membres_verifie_tenant_trg
  before insert or update on public.groupes_membres
  for each row execute procedure public.groupes_membres_verifie_tenant();

alter table public.groupes_pedagogiques enable row level security;
alter table public.groupes_membres enable row level security;

-- Lecture : le personnel de l'école (organisation, comme les classes) ;
-- l'élève et ses parents voient les groupes de l'élève.
drop policy if exists groupes_select on public.groupes_pedagogiques;
create policy groupes_select on public.groupes_pedagogiques for select to authenticated
  using (deleted_at is null and (
    public.est_personnel(etablissement_id)
    or exists (select 1 from public.groupes_membres gm
                where gm.groupe_id = groupes_pedagogiques.id and public.fiche_famille(gm.fiche_eleve_id))
  ));

drop policy if exists groupes_ecriture on public.groupes_pedagogiques;
create policy groupes_ecriture on public.groupes_pedagogiques for all to authenticated
  using (public.a_permission(etablissement_id, 'scolarite.classe.gerer'))
  with check (public.a_permission(etablissement_id, 'scolarite.classe.gerer'));

drop policy if exists groupes_membres_select on public.groupes_membres;
create policy groupes_membres_select on public.groupes_membres for select to authenticated
  using (public.est_personnel(etablissement_id) or public.fiche_famille(fiche_eleve_id));

drop policy if exists groupes_membres_ecriture on public.groupes_membres;
create policy groupes_membres_ecriture on public.groupes_membres for all to authenticated
  using (public.a_permission(etablissement_id, 'scolarite.classe.gerer'))
  with check (public.a_permission(etablissement_id, 'scolarite.classe.gerer'));

grant select, insert, update, delete on public.groupes_pedagogiques, public.groupes_membres to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Création d'une année scolaire en une action
-- ---------------------------------------------------------------------------
create or replace function public.creer_annee_scolaire(
  p_etablissement uuid,
  p_libelle text,
  p_debut date,
  p_fin date,
  p_decoupage text default 'trimestre',
  p_courante boolean default true,
  p_reprendre_de uuid default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_annee uuid;
  v_libelle text := nullif(trim(p_libelle), '');
  v_nb int;
  v_jours int;
  v_debut date;
  v_fin date;
  i int;
begin
  if not public.a_permission(p_etablissement, 'etablissement.annee.gerer') then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  if v_libelle is null then
    raise exception 'LIBELLE_REQUIS' using errcode = '22023';
  end if;
  if p_debut is null or p_fin is null or p_fin <= p_debut then
    raise exception 'DATES_INVALIDES' using errcode = '22023';
  end if;
  if p_fin - p_debut > 400 then
    raise exception 'ANNEE_TROP_LONGUE' using errcode = '22023';
  end if;
  if p_decoupage not in ('trimestre', 'semestre') then
    raise exception 'DECOUPAGE_INVALIDE' using errcode = '22023';
  end if;
  if exists (select 1 from public.annees_scolaires
              where etablissement_id = p_etablissement and lower(libelle) = lower(v_libelle)) then
    raise exception 'ANNEE_EXISTE_DEJA' using errcode = '23505';
  end if;
  if p_reprendre_de is not null and not exists (
       select 1 from public.annees_scolaires where id = p_reprendre_de and etablissement_id = p_etablissement) then
    raise exception 'ANNEE_SOURCE_INTROUVABLE' using errcode = '22023';
  end if;

  if p_courante then
    update public.annees_scolaires set courante = false
     where etablissement_id = p_etablissement and courante;
  end if;

  insert into public.annees_scolaires (etablissement_id, libelle, date_debut, date_fin, courante)
  values (p_etablissement, v_libelle, p_debut, p_fin, p_courante)
  returning id into v_annee;

  -- Découpage en parts égales (modifiable ensuite période par période).
  v_nb := case p_decoupage when 'semestre' then 2 else 3 end;
  v_jours := (p_fin - p_debut + 1) / v_nb;
  for i in 1..v_nb loop
    v_debut := p_debut + (i - 1) * v_jours;
    v_fin := case when i = v_nb then p_fin else p_debut + i * v_jours - 1 end;
    insert into public.periodes_scolaires
      (etablissement_id, annee_scolaire_id, code, libelle, type, ordre, date_debut, date_fin)
    values (
      p_etablissement, v_annee,
      case p_decoupage when 'semestre' then 'S' else 'T' end || i,
      case when i = 1 then '1er ' else i || 'e ' end
        || case p_decoupage when 'semestre' then 'semestre' else 'trimestre' end,
      p_decoupage::public.type_periode, i, v_debut, v_fin
    );
  end loop;

  -- Reprise de l'année précédente : classes (sans élèves) et frais.
  if p_reprendre_de is not null then
    insert into public.classes
      (etablissement_id, annee_scolaire_id, unite_id, niveau_id, filiere_id, code, nom, capacite, enseignant_principal_id)
    select etablissement_id, v_annee, unite_id, niveau_id, filiere_id, code, nom, capacite, enseignant_principal_id
      from public.classes
     where annee_scolaire_id = p_reprendre_de and deleted_at is null and actif;

    insert into public.frais_scolarite_config
      (etablissement_id, annee_scolaire_id, niveau_id, montant_annuel, frais_inscription)
    select etablissement_id, v_annee, niveau_id, montant_annuel, frais_inscription
      from public.frais_scolarite_config
     where annee_scolaire_id = p_reprendre_de and deleted_at is null;
  end if;

  return v_annee;
end;
$$;
revoke all on function public.creer_annee_scolaire(uuid, text, date, date, text, boolean, uuid) from public, anon;
grant execute on function public.creer_annee_scolaire(uuid, text, date, date, text, boolean, uuid) to authenticated;

create or replace function public.definir_annee_courante(p_annee uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_etab uuid;
begin
  select etablissement_id into v_etab from public.annees_scolaires where id = p_annee;
  if v_etab is null then
    raise exception 'ANNEE_INTROUVABLE' using errcode = '22023';
  end if;
  if not public.a_permission(v_etab, 'etablissement.annee.gerer') then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  update public.annees_scolaires set courante = false where etablissement_id = v_etab and courante and id <> p_annee;
  update public.annees_scolaires set courante = true where id = p_annee;
end;
$$;
revoke all on function public.definir_annee_courante(uuid) from public, anon;
grant execute on function public.definir_annee_courante(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. État de la mise en route
-- ---------------------------------------------------------------------------
create or replace function public.etat_configuration_etablissement(p_etablissement uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_annee public.annees_scolaires;
  v_etab public.etablissements;
  v_resultat jsonb;
begin
  if not (coalesce(public.est_direction(p_etablissement), false)
          or public.a_permission(p_etablissement, 'scolarite.classe.gerer')
          or public.a_permission(p_etablissement, 'etablissement.annee.gerer')) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  select * into v_etab from public.etablissements where id = p_etablissement;
  select * into v_annee from public.annees_scolaires
   where etablissement_id = p_etablissement
   order by courante desc, date_debut desc
   limit 1;

  select jsonb_build_object(
    'annee', case when v_annee.id is null then null else jsonb_build_object(
               'id', v_annee.id, 'libelle', v_annee.libelle, 'courante', v_annee.courante,
               'date_debut', v_annee.date_debut, 'date_fin', v_annee.date_fin) end,
    'periodes', (select count(*) from public.periodes_scolaires
                  where annee_scolaire_id = v_annee.id and deleted_at is null),
    'classes', (select count(*) from public.classes
                 where annee_scolaire_id = v_annee.id and deleted_at is null and actif),
    'classes_sans_niveau', (select count(*) from public.classes
                 where annee_scolaire_id = v_annee.id and deleted_at is null and actif and niveau_id is null),
    'groupes', (select count(*) from public.groupes_pedagogiques
                 where annee_scolaire_id = v_annee.id and deleted_at is null),
    'salles', (select count(*) from public.salles
                where etablissement_id = p_etablissement and deleted_at is null and actif),
    'frais', (select count(*) from public.frais_scolarite_config
               where annee_scolaire_id = v_annee.id and deleted_at is null),
    'personnel', (select count(*) from public.etablissements_membres
                   where etablissement_id = p_etablissement and actif and deleted_at is null
                     and role_dans_etablissement not in ('eleve', 'parent')),
    'enseignants', (select count(*) from public.etablissements_membres
                   where etablissement_id = p_etablissement and actif and deleted_at is null
                     and role_dans_etablissement = 'enseignant'),
    'affectations', (select count(*) from public.affectations_enseignants
                      where annee_scolaire_id = v_annee.id and deleted_at is null),
    'classes_sans_affectation', (select count(*) from public.classes c
                      where c.annee_scolaire_id = v_annee.id and c.deleted_at is null and c.actif
                        and not exists (select 1 from public.affectations_enseignants a
                                         where a.classe_id = c.id and a.deleted_at is null)),
    'grille_horaire', exists (select 1 from public.grilles_horaires where annee_scolaire_id = v_annee.id),
    'seances', (select count(*) from public.emplois_du_temps
                 where annee_scolaire_id = v_annee.id and deleted_at is null),
    'eleves_inscrits', (select count(*) from public.inscriptions
                         where annee_scolaire_id = v_annee.id and deleted_at is null
                           and statut in ('active', 'redoublante')),
    'campagne_inscription', exists (select 1 from public.campagnes_inscription
                                     where annee_scolaire_id = v_annee.id),
    'identite_visuelle', (v_etab.couleur_identite is not null or v_etab.logo_chemin is not null),
    'slogan', v_etab.slogan is not null,
    'paiement_mobile', exists (select 1 from public.sous_comptes_marchands
                                where etablissement_id = p_etablissement and actif and deleted_at is null)
  ) into v_resultat;

  return v_resultat;
end;
$$;
revoke all on function public.etat_configuration_etablissement(uuid) from public, anon;
grant execute on function public.etat_configuration_etablissement(uuid) to authenticated;
