-- ============================================================================
-- EcoShop — M5 — Administration & Scolarité
--
-- Périmètre (ANALYSE_GLOBALE.md §4.3, cahier v4.1) :
--   • Structures : campus/annexes (déjà en M1), périodes scolaires
--     (trimestres/semestres/termes), classes (« structures d'accueil »).
--   • Inscriptions & fiches : enrichissement des fiches élèves, inscriptions
--     aux années scolaires, liaison parent ↔ élève (sélecteur d'enfant).
--   • Personnel & rôles dynamiques : affectation des enseignants aux classes
--     et matières.
--
-- Principes (cohérents avec M1/M2) :
--   • Chaque table porte `etablissement_id` (dénormalisation de tenant) pour
--     une RLS simple et un garde-fou multi-tenant par trigger, sur le modèle
--     de membres_verifie_tenant (M1).
--   • Visibilité fine : le personnel lit les structures et l'annuaire ; un
--     élève ne voit que sa fiche ; un parent ne voit que ses enfants liés.
--   • Les écritures métier passent par RPC (security definer) quand elles
--     touchent plusieurs tenants ou des facteurs d'authentification
--     (liaison parent ↔ fiche).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Types énumérés
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.type_periode as enum ('trimestre', 'semestre', 'terme');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.statut_inscription as enum ('active', 'retiree', 'redoublante', 'en_attente');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.type_relation_parentale as enum ('tuteur_legal', 'parent', 'autre');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.statut_relation as enum ('en_attente', 'confirmee', 'refusee');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.role_affectation as enum ('titulaire', 'enseignant', 'suppleant');
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Périodes scolaires (trimestres / semestres / termes)
--    Le découpage est libre par établissement et par année : il suffit de
--    créer les périodes souhaitées (2 semestres ou 3 trimestres, ou 3 termes
--    pour les établissements anglophones).
-- ---------------------------------------------------------------------------
create table if not exists public.periodes_scolaires (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  code text not null,
  libelle text not null,
  type public.type_periode not null default 'trimestre',
  ordre int not null check (ordre > 0),
  date_debut date not null,
  date_fin date not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint periodes_code_unique unique (annee_scolaire_id, code),
  constraint periodes_ordre_unique unique (annee_scolaire_id, ordre),
  constraint periodes_dates_coherentes check (date_fin > date_debut)
);

-- ---------------------------------------------------------------------------
-- 2. Classes — « structures d'accueil » des élèves, définies au sein d'une
--    année scolaire (ex. « 6e A 2026-2027 »). Le niveau (M4) qualifie la
--    classe pour l'alignement sur le référentiel pédagogique.
-- ---------------------------------------------------------------------------
create table if not exists public.classes (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  unite_id uuid references public.unites_operationnelles (id) on delete set null,
  niveau_id uuid references public.niveaux_educatifs (id) on delete set null,
  code text not null,
  nom text not null,
  capacite int check (capacite > 0),
  enseignant_principal_id uuid references public.profiles (id) on delete set null,
  actif boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint classes_code_unique unique (annee_scolaire_id, code)
);

-- ---------------------------------------------------------------------------
-- 3. Inscriptions — rattachement d'une fiche élève à une classe pour une
--    année scolaire. Une fiche ne peut être inscrite qu'une fois par année.
-- ---------------------------------------------------------------------------
create table if not exists public.inscriptions (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  classe_id uuid not null references public.classes (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  statut public.statut_inscription not null default 'active',
  date_inscription date not null default current_date,
  date_retrait date,
  motif_retrait text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint inscriptions_fiche_annee_unique unique (fiche_eleve_id, annee_scolaire_id)
);

-- ---------------------------------------------------------------------------
-- 4. Relations parent ↔ élève — support du sélecteur d'enfant (reporté de
--    Phase A). Le parent lié (statut « confirmee ») peut consulter la fiche
--    et la classe de l'enfant, sans jamais devenir membre de l'établissement.
-- ---------------------------------------------------------------------------
create table if not exists public.relations_parent_eleve (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  parent_profile_id uuid not null references public.profiles (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  type_relation public.type_relation_parentale not null default 'parent',
  statut public.statut_relation not null default 'confirmee',
  autorise boolean not null default true,   -- droit de consulter les données de l'élève
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint relations_parent_fiche_unique unique (parent_profile_id, fiche_eleve_id)
);

-- ---------------------------------------------------------------------------
-- 5. Affectations des enseignants — qui enseigne quelle matière dans quelle
--    classe. La matière référence le référentiel M4 (programmes_matieres),
--    optionnelle tant que l'établissement n'est pas aligné sur M4.
-- ---------------------------------------------------------------------------
create table if not exists public.affectations_enseignants (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  enseignant_profile_id uuid not null references public.profiles (id) on delete cascade,
  classe_id uuid not null references public.classes (id) on delete cascade,
  programme_matiere_id uuid references public.programmes_matieres (id) on delete set null,
  role_affectation public.role_affectation not null default 'enseignant',
  volume_horaire_hebdo int check (volume_horaire_hebdo > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint affectations_unique unique (
    annee_scolaire_id, enseignant_profile_id, classe_id, programme_matiere_id
  )
);

-- ---------------------------------------------------------------------------
-- 6. Enrichissement des fiches élèves (état civil + supervision)
-- ---------------------------------------------------------------------------
alter table public.fiches_eleves
  add column if not exists sexe text check (sexe in ('M', 'F'));
alter table public.fiches_eleves
  add column if not exists lieu_naissance text;
alter table public.fiches_eleves
  add column if not exists nationalite text;
alter table public.fiches_eleves
  add column if not exists statut text not null default 'actif' check (statut in ('actif', 'retire'));
alter table public.fiches_eleves
  add column if not exists est_supervise boolean not null default false;

-- ---------------------------------------------------------------------------
-- 7. Garde-fous multi-tenant (pattern membres_verifie_tenant, M1)
-- ---------------------------------------------------------------------------
create or replace function public.periodes_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists periodes_verifie_tenant_trg on public.periodes_scolaires;
create trigger periodes_verifie_tenant_trg
  before insert or update on public.periodes_scolaires
  for each row execute procedure public.periodes_verifie_tenant();

create or replace function public.classes_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  if new.unite_id is not null then
    select etablissement_id into v_etab from public.unites_operationnelles where id = new.unite_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'UNITE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists classes_verifie_tenant_trg on public.classes;
create trigger classes_verifie_tenant_trg
  before insert or update on public.classes
  for each row execute procedure public.classes_verifie_tenant();

create or replace function public.inscriptions_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = new.fiche_eleve_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'FICHE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  select etablissement_id into v_etab from public.classes where id = new.classe_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'CLASSE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  return new;
end $$;

drop trigger if exists inscriptions_verifie_tenant_trg on public.inscriptions;
create trigger inscriptions_verifie_tenant_trg
  before insert or update on public.inscriptions
  for each row execute procedure public.inscriptions_verifie_tenant();

create or replace function public.relations_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = new.fiche_eleve_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'FICHE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists relations_verifie_tenant_trg on public.relations_parent_eleve;
create trigger relations_verifie_tenant_trg
  before insert or update on public.relations_parent_eleve
  for each row execute procedure public.relations_verifie_tenant();

create or replace function public.affectations_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  select etablissement_id into v_etab from public.classes where id = new.classe_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'CLASSE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  -- L'enseignant affecté doit être un membre actif de l'établissement.
  if not exists (
    select 1 from public.etablissements_membres m
    where m.profile_id = new.enseignant_profile_id
      and m.etablissement_id = new.etablissement_id
      and m.actif and m.deleted_at is null
      and (m.date_fin is null or m.date_fin >= current_date)
  ) then
    raise exception 'ENSEIGNANT_NON_MEMBRE' using errcode = '23514';
  end if;

  return new;
end $$;

drop trigger if exists affectations_verifie_tenant_trg on public.affectations_enseignants;
create trigger affectations_verifie_tenant_trg
  before insert or update on public.affectations_enseignants
  for each row execute procedure public.affectations_verifie_tenant();

-- ---------------------------------------------------------------------------
-- 8. Helpers de visibilité (SECURITY DEFINER — jamais de récursion RLS)
-- ---------------------------------------------------------------------------

-- Vrai si l'appelant est personnel de l'établissement (pas élève ni parent).
create or replace function public.est_personnel(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.etablissements_membres m
    join public.profiles p on p.id = m.profile_id
    where m.profile_id = auth.uid()
      and m.etablissement_id = p_etablissement
      and m.actif and m.deleted_at is null
      and (m.date_fin is null or m.date_fin >= current_date)
      and m.role_dans_etablissement not in ('eleve', 'parent')
      and p.statut_compte = 'actif' and p.deleted_at is null
  );
$$;

-- Vrai si l'appelant est parent confirmé (et autorisé) de la fiche.
create or replace function public.est_parent_confirme(p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.relations_parent_eleve r
    where r.fiche_eleve_id = p_fiche
      and r.parent_profile_id = auth.uid()
      and r.statut = 'confirmee' and r.autorise and r.deleted_at is null
  );
$$;

-- Visibilité d'une fiche : personnel de l'établissement, l'élève lié, ou un
-- parent confirmé. Sert aussi de brique pour la visibilité des inscriptions.
create or replace function public.fiche_visible(p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.fiches_eleves f
    where f.id = p_fiche and f.deleted_at is null
      and (
        public.est_personnel(f.etablissement_id)
        or f.profile_id = auth.uid()
        or public.est_parent_confirme(f.id)
      )
  );
$$;

-- Visibilité d'une classe : personnel, ou élève/parent d'un inscrit.
create or replace function public.classe_visible(p_classe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.classes c
    where c.id = p_classe and c.deleted_at is null
      and (
        public.est_personnel(c.etablissement_id)
        or exists (
          select 1 from public.inscriptions i
          where i.classe_id = c.id and i.deleted_at is null
            and public.fiche_visible(i.fiche_eleve_id)
        )
      )
  );
$$;

grant execute on function public.est_personnel(uuid) to authenticated;
grant execute on function public.est_parent_confirme(uuid) to authenticated;
grant execute on function public.fiche_visible(uuid) to authenticated;
grant execute on function public.classe_visible(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Liaison parent ↔ fiche (double facteur + anti-brute-force, ch. 5.8)
--    Le parent ne devient PAS membre de l'établissement : sa visibilité reste
--    strictement limitée aux fiches/enfants liés.
-- ---------------------------------------------------------------------------
create or replace function public.lier_parent_a_fiche(
  p_matricule text,
  p_date_naissance date,
  p_type public.type_relation_parentale default 'parent'
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
  v_fiche_id uuid;
  v_relation_id uuid;
  v_echecs int;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '28000';
  end if;

  if (select role_racine from public.profiles where id = auth.uid()) is distinct from 'parent' then
    raise exception 'ROLE_PARENT_REQUIS' using errcode = '42501';
  end if;

  select count(*) into v_echecs
  from public.tentatives_liaison
  where profile_id = auth.uid() and not reussie
    and created_at > now() - interval '1 hour';

  if v_echecs >= 5 then
    raise exception 'TROP_DE_TENTATIVES' using errcode = '54000';
  end if;

  select id into v_fiche_id
  from public.fiches_eleves
  where matricule = trim(p_matricule)
    and date_naissance = p_date_naissance
    and deleted_at is null
  limit 1;

  if v_fiche_id is null then
    insert into public.tentatives_liaison (profile_id, matricule_essaye, reussie)
    values (auth.uid(), trim(p_matricule), false);
    raise exception 'LIAISON_IMPOSSIBLE' using errcode = '42501';
  end if;

  insert into public.relations_parent_eleve
    (etablissement_id, parent_profile_id, fiche_eleve_id, type_relation, statut)
  select f.etablissement_id, auth.uid(), v_fiche_id, p_type, 'confirmee'
  from public.fiches_eleves f where f.id = v_fiche_id
  on conflict (parent_profile_id, fiche_eleve_id) do update
    set statut = 'confirmee', autorise = true, deleted_at = null
  returning id into v_relation_id;

  insert into public.tentatives_liaison (profile_id, matricule_essaye, reussie)
  values (auth.uid(), trim(p_matricule), true);

  return v_relation_id;
end $$;

revoke execute on function public.lier_parent_a_fiche(text, date, public.type_relation_parentale) from public, anon;
grant execute on function public.lier_parent_a_fiche(text, date, public.type_relation_parentale) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. Row Level Security
-- ---------------------------------------------------------------------------
alter table public.periodes_scolaires enable row level security;
alter table public.classes enable row level security;
alter table public.inscriptions enable row level security;
alter table public.relations_parent_eleve enable row level security;
alter table public.affectations_enseignants enable row level security;

-- Périodes : lecture par le personnel, écriture par la scolarité.
drop policy if exists "periodes_select_personnel" on public.periodes_scolaires;
create policy "periodes_select_personnel" on public.periodes_scolaires
  for select using (
    deleted_at is null and public.est_personnel(etablissement_id)
  );

drop policy if exists "periodes_ecriture_scolarite" on public.periodes_scolaires;
create policy "periodes_ecriture_scolarite" on public.periodes_scolaires
  for all
  using (public.a_permission(etablissement_id, 'scolarite.periode.gerer'))
  with check (public.a_permission(etablissement_id, 'scolarite.periode.gerer'));

-- Classes : lecture par qui a le droit de voir (personnel, élève/parent d'un
-- inscrit), écriture par la scolarité.
drop policy if exists "classes_select_visible" on public.classes;
create policy "classes_select_visible" on public.classes
  for select using (public.classe_visible(id));

drop policy if exists "classes_ecriture_scolarite" on public.classes;
create policy "classes_ecriture_scolarite" on public.classes
  for all
  using (public.a_permission(etablissement_id, 'scolarite.classe.gerer'))
  with check (public.a_permission(etablissement_id, 'scolarite.classe.gerer'));

-- Inscriptions : visibles via la fiche ; écrites par la scolarité.
drop policy if exists "inscriptions_select_visible" on public.inscriptions;
create policy "inscriptions_select_visible" on public.inscriptions
  for select using (public.fiche_visible(fiche_eleve_id));

drop policy if exists "inscriptions_ecriture_scolarite" on public.inscriptions;
create policy "inscriptions_ecriture_scolarite" on public.inscriptions
  for all
  using (public.a_permission(etablissement_id, 'scolarite.inscription.gerer'))
  with check (public.a_permission(etablissement_id, 'scolarite.inscription.gerer'));

-- Relations parent ↔ élève : le parent voit les siennes ; la scolarité gère
-- celles de son établissement. La création par le parent passe par la RPC
-- lier_parent_a_fiche (aucune policy INSERT directe côté parent).
drop policy if exists "relations_select_parent" on public.relations_parent_eleve;
create policy "relations_select_parent" on public.relations_parent_eleve
  for select using (parent_profile_id = auth.uid() and deleted_at is null);

drop policy if exists "relations_scolarite" on public.relations_parent_eleve;
create policy "relations_scolarite" on public.relations_parent_eleve
  for all
  using (public.a_permission(etablissement_id, 'scolarite.relation.gerer'))
  with check (public.a_permission(etablissement_id, 'scolarite.relation.gerer'));

-- Affectations : visibles par le personnel et par l'enseignant concerné ;
-- écrites par qui gère les affectations.
drop policy if exists "affectations_select_personnel" on public.affectations_enseignants;
create policy "affectations_select_personnel" on public.affectations_enseignants
  for select using (
    deleted_at is null
    and (
      public.est_personnel(etablissement_id)
      or enseignant_profile_id = auth.uid()
    )
  );

drop policy if exists "affectations_ecriture" on public.affectations_enseignants;
create policy "affectations_ecriture" on public.affectations_enseignants
  for all
  using (public.a_permission(etablissement_id, 'rh.enseignant.affecter'))
  with check (public.a_permission(etablissement_id, 'rh.enseignant.affecter'));

-- Fiches élèves : la visibilité parent s'ajoute à l'existant (M2). On remplace
-- la policy « élève uniquement » par une policy unifiée qui couvre personnel +
-- élève + parent, sans toucher à la policy d'écriture « fiches_scolarite ».
drop policy if exists "fiches_select_propre" on public.fiches_eleves;
create policy "fiches_select_visible" on public.fiches_eleves
  for select using (public.fiche_visible(id));

-- ---------------------------------------------------------------------------
-- 11. Index
-- ---------------------------------------------------------------------------
create index if not exists idx_periodes_annee on public.periodes_scolaires (annee_scolaire_id);
create index if not exists idx_periodes_etablissement on public.periodes_scolaires (etablissement_id);
create index if not exists idx_classes_annee on public.classes (annee_scolaire_id);
create index if not exists idx_classes_etablissement on public.classes (etablissement_id);
create index if not exists idx_classes_niveau on public.classes (niveau_id);
create index if not exists idx_inscriptions_fiche on public.inscriptions (fiche_eleve_id);
create index if not exists idx_inscriptions_classe on public.inscriptions (classe_id);
create index if not exists idx_inscriptions_etablissement on public.inscriptions (etablissement_id);
create index if not exists idx_relations_parent on public.relations_parent_eleve (parent_profile_id);
create index if not exists idx_relations_fiche on public.relations_parent_eleve (fiche_eleve_id);
create index if not exists idx_affectations_enseignant on public.affectations_enseignants (enseignant_profile_id);
create index if not exists idx_affectations_classe on public.affectations_enseignants (classe_id);

-- ---------------------------------------------------------------------------
-- 12. Permissions introduites par M5
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domaine, libelle, description) values
  ('scolarite.classe.gerer',      'scolarite', 'Gérer les classes',       'Créer et modifier les classes d''une année scolaire.'),
  ('scolarite.inscription.gerer', 'scolarite', 'Gérer les inscriptions',  'Inscrire, muter et retirer des élèves.'),
  ('scolarite.periode.gerer',     'scolarite', 'Gérer les périodes',      'Créer et modifier trimestres, semestres et termes.'),
  ('scolarite.relation.gerer',    'scolarite', 'Gérer les liens parentaux','Confirmer, révoquer et délier les relations parent ↔ élève.'),
  ('rh.enseignant.affecter',      'rh',        'Affecter les enseignants', 'Attribuer des enseignants aux classes et matières.')
on conflict (code) do nothing;

-- ============================================================================
-- Fin M5.
-- ============================================================================
