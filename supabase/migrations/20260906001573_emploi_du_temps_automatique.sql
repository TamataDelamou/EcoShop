-- ============================================================================
-- EcoShop — REG-24 : emploi du temps dynamique et automatisé
-- (retour du porteur de projet, 2026-10-28 : « un emploi du temps très
-- puissant basé sur les modèles de Pronote/EDT et Horarium »)
--
-- Le calcul se fait SUR L'APPAREIL (hors connexion d'abord) : l'application
-- lit les cours à placer (affectations), la grille horaire, les salles, les
-- indisponibilités et les séances verrouillées, calcule une proposition,
-- la montre avec son diagnostic ; la Direction la valide. Le serveur
-- n'enregistre que le résultat, en une seule transaction.
--
--   • grilles_horaires : jours ouvrés, créneaux de la journée (cours,
--     récréation, pause de midi) et règles de qualité pondérées, par année.
--   • affectations_enseignants : + groupe (partie de classe), durée d'une
--     séance (1 h, 2 h…), salle souhaitée. L'unicité tient compte du groupe.
--   • emplois_du_temps : + groupe, verrou (séance gardée telle quelle par
--     le calcul), origine (manuelle / automatique), affectation d'origine.
--     L'unicité d'un créneau tient compte du groupe et ignore les séances
--     retirées.
--   • contraintes_emploi : correction du type par défaut (« indisponibilite »
--     n'était pas une valeur permise).
--   • enregistrer_emploi_genere() : remplace les séances non verrouillées de
--     l'année par la proposition validée.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Grille horaire de l'année
-- ---------------------------------------------------------------------------
create table if not exists public.grilles_horaires (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  -- 1 = lundi … 7 = dimanche.
  jours int[] not null default '{1,2,3,4,5}',
  -- [{"debut": "08:00", "fin": "09:00", "type": "cours"},
  --  {"debut": "10:00", "fin": "10:15", "type": "pause", "libelle": "Récréation"}]
  creneaux jsonb not null default '[]'::jsonb check (jsonb_typeof(creneaux) = 'array'),
  -- Demi-journées libérées : {"3": "apres_midi", "6": "apres_midi"}.
  demi_journees_libres jsonb not null default '{}'::jsonb check (jsonb_typeof(demi_journees_libres) = 'object'),
  -- Poids des règles de qualité (0 = ignorée, 10 = très importante).
  regles jsonb not null default '{}'::jsonb check (jsonb_typeof(regles) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint grilles_horaires_annee_unique unique (annee_scolaire_id)
);

drop trigger if exists grilles_horaires_set_updated_at on public.grilles_horaires;
create trigger grilles_horaires_set_updated_at
  before update on public.grilles_horaires
  for each row execute procedure public.set_updated_at();

create or replace function public.grilles_horaires_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
begin
  if not exists (select 1 from public.annees_scolaires a
                  where a.id = new.annee_scolaire_id and a.etablissement_id = new.etablissement_id) then
    raise exception 'GRILLE_ANNEE_HORS_ETABLISSEMENT' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(new.jours) j where j not between 1 and 7) then
    raise exception 'GRILLE_JOUR_INVALIDE' using errcode = '22023';
  end if;
  return new;
end $$;
drop trigger if exists grilles_horaires_verifie_tenant_trg on public.grilles_horaires;
create trigger grilles_horaires_verifie_tenant_trg
  before insert or update on public.grilles_horaires
  for each row execute procedure public.grilles_horaires_verifie_tenant();

alter table public.grilles_horaires enable row level security;

drop policy if exists grilles_horaires_select on public.grilles_horaires;
create policy grilles_horaires_select on public.grilles_horaires for select to authenticated
  using (public.est_personnel(etablissement_id)
         or exists (select 1 from public.classes c
                     where c.annee_scolaire_id = grilles_horaires.annee_scolaire_id
                       and public.classe_visible(c.id)));

drop policy if exists grilles_horaires_ecriture on public.grilles_horaires;
create policy grilles_horaires_ecriture on public.grilles_horaires for all to authenticated
  using (public.a_permission(etablissement_id, 'planification.administrer'))
  with check (public.a_permission(etablissement_id, 'planification.administrer'));

grant select, insert, update, delete on public.grilles_horaires to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Cours à placer : groupe, durée de séance, salle souhaitée
-- ---------------------------------------------------------------------------
alter table public.affectations_enseignants
  add column if not exists groupe_id uuid references public.groupes_pedagogiques (id) on delete set null,
  add column if not exists duree_seance int not null default 60,
  add column if not exists salle_id uuid references public.salles (id) on delete set null;

do $$ begin
  alter table public.affectations_enseignants
    add constraint affectations_duree_seance check (duree_seance between 30 and 240);
exception when duplicate_object then null; end $$;

alter table public.affectations_enseignants drop constraint if exists affectations_unique;
create unique index if not exists idx_affectations_unique
  on public.affectations_enseignants (
    annee_scolaire_id, enseignant_profile_id, classe_id,
    coalesce(programme_matiere_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(groupe_id, '00000000-0000-0000-0000-000000000000'::uuid)
  )
  where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 3. Séances : groupe, verrou, origine
-- ---------------------------------------------------------------------------
alter table public.emplois_du_temps
  add column if not exists groupe_id uuid references public.groupes_pedagogiques (id) on delete set null,
  add column if not exists verrouille boolean not null default false,
  add column if not exists origine text not null default 'manuelle',
  add column if not exists affectation_id uuid references public.affectations_enseignants (id) on delete set null;

do $$ begin
  alter table public.emplois_du_temps
    add constraint emplois_origine_valide check (origine in ('manuelle', 'automatique'));
exception when duplicate_object then null; end $$;

drop index if exists public.idx_emplois_creneau_unique;
create unique index if not exists idx_emplois_creneau_unique
  on public.emplois_du_temps (
    etablissement_id, annee_scolaire_id, classe_id,
    coalesce(groupe_id, '00000000-0000-0000-0000-000000000000'::uuid),
    jour_semaine, heure_debut
  )
  where deleted_at is null;
create index if not exists idx_emplois_enseignant
  on public.emplois_du_temps (enseignant_profile_id, annee_scolaire_id) where deleted_at is null;

-- ---------------------------------------------------------------------------
-- 4. Indisponibilités : valeur par défaut permise
-- ---------------------------------------------------------------------------
alter table public.contraintes_emploi alter column type set default 'indisponibilite_enseignant';

-- ---------------------------------------------------------------------------
-- 5. Enregistrement d'une proposition validée
-- ---------------------------------------------------------------------------
-- p_seances : [{"classe_id", "groupe_id", "enseignant_profile_id",
--   "programme_matiere_id", "salle_id", "affectation_id", "jour_semaine",
--   "heure_debut", "heure_fin"}]
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

  -- Les séances verrouillées restent ; toutes les autres sont retirées
  -- (retrait logique : l'historique reste consultable).
  update public.emplois_du_temps
     set deleted_at = now(), modifie_le = now(), device_id = p_device_id
   where etablissement_id = p_etablissement
     and annee_scolaire_id = p_annee
     and deleted_at is null
     and not verrouille;

  insert into public.emplois_du_temps (
    etablissement_id, annee_scolaire_id, classe_id, groupe_id, enseignant_profile_id,
    programme_matiere_id, salle_id, affectation_id, jour_semaine, heure_debut, heure_fin,
    type, origine, modifie_le, device_id)
  select p_etablissement, p_annee, s.classe_id, s.groupe_id, s.enseignant_profile_id,
         s.programme_matiere_id, s.salle_id, s.affectation_id, s.jour_semaine, s.heure_debut, s.heure_fin,
         'cours', 'automatique', now(), p_device_id
    from jsonb_to_recordset(p_seances) as s(
      classe_id uuid, groupe_id uuid, enseignant_profile_id uuid, programme_matiere_id uuid,
      salle_id uuid, affectation_id uuid, jour_semaine int, heure_debut time, heure_fin time);
  get diagnostics v_n = row_count;
  return v_n;
exception
  when unique_violation then
    raise exception 'CRENEAU_DEJA_OCCUPE' using errcode = '23505';
end;
$$;
revoke all on function public.enregistrer_emploi_genere(uuid, uuid, jsonb, text) from public, anon;
grant execute on function public.enregistrer_emploi_genere(uuid, uuid, jsonb, text) to authenticated;
