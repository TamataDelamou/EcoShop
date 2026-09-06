-- ============================================================================
-- EcoShop — M6 — Notes & Évaluations
--
-- Périmètre (cahier v4.1, docs/RECHERCHE_COMPARATIVE.md) :
--   • Évaluations : devoirs, interrogations, contrôles, examens blancs,
--     compositions, TP — coefficient et barème propres.
--   • Notes : saisie par enseignant, avec ou sans connexion (hors-ligne).
--   • Appréciations : commentaires des bulletins, prêts pour l'analyse NLP.
--   • Bulletins : snapshots générés (individuels, par classe, par période),
--     signés par empreinte pour détecter toute altération.
--   • Statistiques & signaux IA : agrégats pré-calculés (moyennes, rangs,
--     risque de réussite, anomalies, recommandations).
--
-- Principes (cohérents avec M1/M4/M5) :
--   • Dénormalisation de tenant `etablissement_id` + garde-fou trigger
--     `*_verifie_tenant` (pattern M1/M5).
--   • Visibilité fine : personnel de l'établissement, élève/parent limité à
--     sa fiche, notes/evaluations visibles seulement une fois publiées.
--   • Hors-ligne : les notes portent `device_id` + `client_ts` (registre
--     Last-Write-Wins, cf. RECHERCHE_COMPARATIVE §6) ; la file `sync_queue`
--     (M0) rejoue les opérations ; les moyennes ne sont jamais synchronisées,
--     toujours recalculées côté serveur.
--   • Aucune décision automatique : les signaux IA sont des aides à la
--     décision, jamais des verdicts bloquants.
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Types énumérés
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.type_evaluation as enum
    ('devoir', 'interrogation', 'controle', 'examen_blanc', 'composition', 'tp', 'autre');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.statut_evaluation as enum ('brouillon', 'publiee', 'cloturee');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.type_bulletin as enum ('trimestriel', 'semestriel', 'annuel');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.statut_bulletin as enum ('brouillon', 'publie', 'archive');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.type_appreciation as enum ('generale', 'matiere', 'conseil');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.ton_appreciation as enum ('positif', 'neutre', 'negatif');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.type_agregat as enum
    ('moyenne_matiere', 'moyenne_classe', 'moyenne_generale', 'rang_eleve',
     'risque_reussite', 'anomalie_note', 'recommandation_contenu');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 1. Évaluations — l'unité de notation (devoir, contrôle, composition…)
-- ---------------------------------------------------------------------------
create table if not exists public.evaluations (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  periode_id uuid references public.periodes_scolaires (id) on delete set null,
  classe_id uuid not null references public.classes (id) on delete cascade,
  programme_matiere_id uuid references public.programmes_matieres (id) on delete set null,
  enseignant_profile_id uuid not null references public.profiles (id) on delete cascade,
  type public.type_evaluation not null default 'controle',
  libelle text not null,
  date_evaluation date not null default current_date,
  coefficient numeric(5,2) not null default 1 check (coefficient > 0),
  bareme numeric(5,2) not null default 20 check (bareme > 0),
  statut public.statut_evaluation not null default 'brouillon',
  publie_le timestamptz,
  cloture_le timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ---------------------------------------------------------------------------
-- 2. Notes — score d'un élève à une évaluation (absent ⟺ valeur nulle)
-- ---------------------------------------------------------------------------
create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  evaluation_id uuid not null references public.evaluations (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  valeur numeric(5,2) check (valeur >= 0),
  absent boolean not null default false,
  commentaire text,
  saisi_par uuid not null references public.profiles (id) on delete restrict,
  saisi_hors_ligne boolean not null default false,
  device_id text,
  client_ts timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint notes_evaluation_fiche_unique unique (evaluation_id, fiche_eleve_id),
  constraint notes_valeur_ou_absent check (
    (absent and valeur is null) or (not absent and valeur is not null)
  )
);

-- ---------------------------------------------------------------------------
-- 3. Appréciations — commentaires de bulletin, prêts pour l'analyse sémantique
-- ---------------------------------------------------------------------------
create table if not exists public.appreciations (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  periode_id uuid references public.periodes_scolaires (id) on delete set null,
  programme_matiere_id uuid references public.programmes_matieres (id) on delete set null,
  type public.type_appreciation not null default 'generale',
  texte text not null,
  ton public.ton_appreciation,
  points_forts text[],
  points_faibles text[],
  redige_par uuid not null references public.profiles (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ---------------------------------------------------------------------------
-- 4. Bulletins — snapshots signés des résultats d'un élève pour une période
-- ---------------------------------------------------------------------------
create table if not exists public.bulletins (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  periode_id uuid references public.periodes_scolaires (id) on delete set null,
  classe_id uuid not null references public.classes (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  type public.type_bulletin not null default 'trimestriel',
  statut public.statut_bulletin not null default 'brouillon',
  contenu jsonb not null default '{}'::jsonb,
  signature_sha256 text,
  genere_le timestamptz,
  publie_le timestamptz,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists idx_bulletins_fiche_periode_unique
  on public.bulletins (fiche_eleve_id, periode_id, type)
  where periode_id is not null;

create unique index if not exists idx_bulletins_fiche_type_unique
  on public.bulletins (fiche_eleve_id, type)
  where periode_id is null;

-- ---------------------------------------------------------------------------
-- 5. Statistiques & signaux IA — agrégats pré-calculés (dashboards + IA)
-- ---------------------------------------------------------------------------
create table if not exists public.statistiques_agregats (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  periode_id uuid references public.periodes_scolaires (id) on delete set null,
  classe_id uuid references public.classes (id) on delete cascade,
  programme_matiere_id uuid references public.programmes_matieres (id) on delete cascade,
  fiche_eleve_id uuid references public.fiches_eleves (id) on delete cascade,
  type_agregat public.type_agregat not null,
  valeur_numeric numeric(10,4),
  valeur_texte text,
  valeur_jsonb jsonb,
  calcule_le timestamptz not null default now(),
  version int not null default 1
);

-- ---------------------------------------------------------------------------
-- 6. Garde-fous multi-tenant
-- ---------------------------------------------------------------------------
create or replace function public.evaluations_verifie_tenant()
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

  if new.periode_id is not null then
    select etablissement_id into v_etab from public.periodes_scolaires where id = new.periode_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'PERIODE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;

  if not exists (
    select 1 from public.etablissements_membres m
    where m.profile_id = new.enseignant_profile_id
      and m.etablissement_id = new.etablissement_id
      and m.actif and m.deleted_at is null
  ) then
    raise exception 'ENSEIGNANT_NON_MEMBRE' using errcode = '23514';
  end if;

  return new;
end $$;

drop trigger if exists evaluations_verifie_tenant_trg on public.evaluations;
create trigger evaluations_verifie_tenant_trg
  before insert or update on public.evaluations
  for each row execute procedure public.evaluations_verifie_tenant();

create or replace function public.notes_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare
  v_eval record;
begin
  select etablissement_id, classe_id, annee_scolaire_id, bareme
    into v_eval
  from public.evaluations where id = new.evaluation_id;

  if not found then
    raise exception 'EVALUATION_INTROUVABLE' using errcode = '23514';
  end if;

  if v_eval.etablissement_id is distinct from new.etablissement_id then
    raise exception 'EVALUATION_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  if new.valeur is not null and new.valeur > v_eval.bareme then
    raise exception 'NOTE_SUP_BAREME' using errcode = '23514';
  end if;

  if not exists (
    select 1 from public.inscriptions i
    where i.fiche_eleve_id = new.fiche_eleve_id
      and i.classe_id = v_eval.classe_id
      and i.annee_scolaire_id = v_eval.annee_scolaire_id
      and i.deleted_at is null
  ) then
    raise exception 'ELEVE_NON_INSCRIT' using errcode = '23514';
  end if;

  return new;
end $$;

drop trigger if exists notes_verifie_tenant_trg on public.notes;
create trigger notes_verifie_tenant_trg
  before insert or update on public.notes
  for each row execute procedure public.notes_verifie_tenant();

create or replace function public.appreciations_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.fiches_eleves where id = new.fiche_eleve_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'FICHE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  if new.periode_id is not null then
    select etablissement_id into v_etab from public.periodes_scolaires where id = new.periode_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'PERIODE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists appreciations_verifie_tenant_trg on public.appreciations;
create trigger appreciations_verifie_tenant_trg
  before insert or update on public.appreciations
  for each row execute procedure public.appreciations_verifie_tenant();

create or replace function public.bulletins_verifie_tenant()
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

  if new.periode_id is not null then
    select etablissement_id into v_etab from public.periodes_scolaires where id = new.periode_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'PERIODE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists bulletins_verifie_tenant_trg on public.bulletins;
create trigger bulletins_verifie_tenant_trg
  before insert or update on public.bulletins
  for each row execute procedure public.bulletins_verifie_tenant();

create or replace function public.statistiques_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;

  if new.classe_id is not null then
    select etablissement_id into v_etab from public.classes where id = new.classe_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'CLASSE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;

  if new.fiche_eleve_id is not null then
    select etablissement_id into v_etab from public.fiches_eleves where id = new.fiche_eleve_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'FICHE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists statistiques_verifie_tenant_trg on public.statistiques_agregats;
create trigger statistiques_verifie_tenant_trg
  before insert or update on public.statistiques_agregats
  for each row execute procedure public.statistiques_verifie_tenant();

-- ---------------------------------------------------------------------------
-- 7. Helpers de visibilité et de droits (SECURITY DEFINER)
-- ---------------------------------------------------------------------------

-- Vrai si l'appelant est affecté à la classe (M5 affectations_enseignants).
create or replace function public.est_enseignant_affecte(p_classe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.affectations_enseignants a
    where a.classe_id = p_classe
      and a.enseignant_profile_id = auth.uid()
      and a.deleted_at is null
  );
$$;

-- Vrai si l'appelant peut gérer l'évaluation (auteur, ou permission scolarité).
create or replace function public.peut_gerer_evaluation(p_eval uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.evaluations e
    where e.id = p_eval and e.deleted_at is null
      and (
        public.a_permission(e.etablissement_id, 'scolarite.evaluation.gerer')
        or e.enseignant_profile_id = auth.uid()
      )
  );
$$;

-- Vrai si l'appelant peut saisir/corriger les notes de l'évaluation.
create or replace function public.peut_saisir_notes(p_eval uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.evaluations e
    where e.id = p_eval and e.deleted_at is null and e.statut <> 'cloturee'
      and (
        public.a_permission(e.etablissement_id, 'scolarite.note.gerer')
        or e.enseignant_profile_id = auth.uid()
      )
  );
$$;

-- Visibilité d'une évaluation : personnel, ou élève/parent de la classe une
-- fois l'évaluation publiée ou clôturée.
create or replace function public.evaluation_visible(p_eval uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.evaluations e
    where e.id = p_eval and e.deleted_at is null
      and (
        public.est_personnel(e.etablissement_id)
        or (e.statut in ('publiee', 'cloturee') and public.classe_visible(e.classe_id))
      )
  );
$$;

-- Visibilité d'une note : personnel, ou l'élève/parent une fois l'évaluation
-- publiée ou clôturée.
create or replace function public.note_visible(p_note uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.notes n
    join public.evaluations e on e.id = n.evaluation_id
    where n.id = p_note and n.deleted_at is null and e.deleted_at is null
      and (
        public.est_personnel(n.etablissement_id)
        or (e.statut in ('publiee', 'cloturee') and public.fiche_visible(n.fiche_eleve_id))
      )
  );
$$;

-- Visibilité d'une appréciation : personnel, ou l'élève/parent concerné.
create or replace function public.appreciation_visible(p_app uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.appreciations a
    where a.id = p_app and a.deleted_at is null
      and (
        public.est_personnel(a.etablissement_id)
        or public.fiche_visible(a.fiche_eleve_id)
      )
  );
$$;

-- Visibilité d'un bulletin : personnel, ou l'élève/parent une fois publié.
create or replace function public.bulletin_visible(p_bul uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.bulletins b
    where b.id = p_bul and b.deleted_at is null
      and (
        public.est_personnel(b.etablissement_id)
        or (b.statut = 'publie' and public.fiche_visible(b.fiche_eleve_id))
      )
  );
$$;

grant execute on function public.est_enseignant_affecte(uuid) to authenticated;
grant execute on function public.peut_gerer_evaluation(uuid) to authenticated;
grant execute on function public.peut_saisir_notes(uuid) to authenticated;
grant execute on function public.evaluation_visible(uuid) to authenticated;
grant execute on function public.note_visible(uuid) to authenticated;
grant execute on function public.appreciation_visible(uuid) to authenticated;
grant execute on function public.bulletin_visible(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Calculs (moyennes) — SECURITY DEFINER, jamais recalculés hors-ligne
-- ---------------------------------------------------------------------------

-- Moyenne pondérée (ramenée sur 20) d'un élève, filtrée par matière/période.
create or replace function public.calculer_moyenne_eleve(
  p_fiche uuid,
  p_matiere uuid default null,
  p_periode uuid default null
)
returns numeric
language sql stable security definer set search_path = public
as $$
  select case
    when sum(e.coefficient) is null or sum(e.coefficient) = 0 then null
    else round((sum(n.valeur / e.bareme * e.coefficient) / sum(e.coefficient)) * 20, 2)
  end
  from public.notes n
  join public.evaluations e on e.id = n.evaluation_id
  where n.fiche_eleve_id = p_fiche
    and n.deleted_at is null and e.deleted_at is null
    and not n.absent
    and e.statut <> 'brouillon'
    and (p_matiere is null or e.programme_matiere_id = p_matiere)
    and (p_periode is null or e.periode_id = p_periode);
$$;

-- Moyenne d'une classe (moyenne des moyennes élèves), par matière/période.
create or replace function public.calculer_moyenne_classe(
  p_classe uuid,
  p_matiere uuid default null,
  p_periode uuid default null
)
returns numeric
language sql stable security definer set search_path = public
as $$
  select round(avg(m), 2)
  from (
    select public.calculer_moyenne_eleve(f.id, p_matiere, p_periode) as m
    from public.fiches_eleves f
    where f.deleted_at is null
      and exists (
        select 1 from public.inscriptions i
        where i.fiche_eleve_id = f.id
          and i.classe_id = p_classe
          and i.deleted_at is null
      )
  ) s
  where s.m is not null;
$$;

grant execute on function public.calculer_moyenne_eleve(uuid, uuid, uuid) to authenticated;
grant execute on function public.calculer_moyenne_classe(uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Row Level Security
-- ---------------------------------------------------------------------------
alter table public.evaluations enable row level security;
alter table public.notes enable row level security;
alter table public.appreciations enable row level security;
alter table public.bulletins enable row level security;
alter table public.statistiques_agregats enable row level security;

-- Évaluations : lecture par visibilité ; écriture par l'auteur affecté ou la
-- scolarité.
drop policy if exists "evaluations_select_visible" on public.evaluations;
create policy "evaluations_select_visible" on public.evaluations
  for select using (public.evaluation_visible(id));

drop policy if exists "evaluations_insert_enseignant" on public.evaluations;
create policy "evaluations_insert_enseignant" on public.evaluations
  for insert to authenticated
  with check (
    public.a_permission(etablissement_id, 'scolarite.evaluation.gerer')
    or (enseignant_profile_id = auth.uid() and public.est_enseignant_affecte(classe_id))
  );

drop policy if exists "evaluations_update_gerant" on public.evaluations;
create policy "evaluations_update_gerant" on public.evaluations
  for update using (public.peut_gerer_evaluation(id))
  with check (public.peut_gerer_evaluation(id));

drop policy if exists "evaluations_delete_gerant" on public.evaluations;
create policy "evaluations_delete_gerant" on public.evaluations
  for delete using (public.peut_gerer_evaluation(id));

-- Notes : lecture par visibilité ; écriture par qui peut saisir l'évaluation.
drop policy if exists "notes_select_visible" on public.notes;
create policy "notes_select_visible" on public.notes
  for select using (public.note_visible(id));

drop policy if exists "notes_insert_saisie" on public.notes;
create policy "notes_insert_saisie" on public.notes
  for insert to authenticated
  with check (public.peut_saisir_notes(evaluation_id));

drop policy if exists "notes_update_saisie" on public.notes;
create policy "notes_update_saisie" on public.notes
  for update using (public.peut_saisir_notes(evaluation_id))
  with check (public.peut_saisir_notes(evaluation_id));

drop policy if exists "notes_delete_saisie" on public.notes;
create policy "notes_delete_saisie" on public.notes
  for delete using (public.peut_saisir_notes(evaluation_id));

-- Appréciations : lecture par visibilité ; écriture par scolarité ou auteur.
drop policy if exists "appreciations_select_visible" on public.appreciations;
create policy "appreciations_select_visible" on public.appreciations
  for select using (public.appreciation_visible(id));

drop policy if exists "appreciations_ecriture" on public.appreciations;
create policy "appreciations_ecriture" on public.appreciations
  for all
  using (
    public.a_permission(etablissement_id, 'scolarite.appreciation.gerer')
    or redige_par = auth.uid()
  )
  with check (
    public.a_permission(etablissement_id, 'scolarite.appreciation.gerer')
    or redige_par = auth.uid()
  );

-- Bulletins : lecture par visibilité ; écriture par la scolarité.
drop policy if exists "bulletins_select_visible" on public.bulletins;
create policy "bulletins_select_visible" on public.bulletins
  for select using (public.bulletin_visible(id));

drop policy if exists "bulletins_ecriture_scolarite" on public.bulletins;
create policy "bulletins_ecriture_scolarite" on public.bulletins
  for all
  using (public.a_permission(etablissement_id, 'scolarite.bulletin.gerer'))
  with check (public.a_permission(etablissement_id, 'scolarite.bulletin.gerer'));

-- Statistiques : lecture par le personnel, ou l'élève/parent pour ses signaux
-- (risque, recommandation). Aucune écriture client (calculs serveur).
drop policy if exists "statistiques_select" on public.statistiques_agregats;
create policy "statistiques_select" on public.statistiques_agregats
  for select using (
    public.est_personnel(etablissement_id)
    or public.fiche_visible(fiche_eleve_id)
  );

-- ---------------------------------------------------------------------------
-- 10. Index
-- ---------------------------------------------------------------------------
create index if not exists idx_evaluations_classe on public.evaluations (classe_id);
create index if not exists idx_evaluations_annee on public.evaluations (annee_scolaire_id);
create index if not exists idx_evaluations_matiere on public.evaluations (programme_matiere_id);
create index if not exists idx_notes_evaluation on public.notes (evaluation_id);
create index if not exists idx_notes_fiche on public.notes (fiche_eleve_id);
create index if not exists idx_notes_etablissement on public.notes (etablissement_id);
create index if not exists idx_appreciations_fiche on public.appreciations (fiche_eleve_id);
create index if not exists idx_bulletins_fiche on public.bulletins (fiche_eleve_id);
create index if not exists idx_bulletins_classe on public.bulletins (classe_id);
create index if not exists idx_statistiques_etablissement on public.statistiques_agregats (etablissement_id, annee_scolaire_id, type_agregat);
create index if not exists idx_statistiques_fiche on public.statistiques_agregats (fiche_eleve_id, type_agregat);

-- ---------------------------------------------------------------------------
-- 11. Permissions introduites par M6
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domaine, libelle, description) values
  ('scolarite.evaluation.gerer',  'scolarite', 'Gérer les évaluations',  'Créer et modifier devoirs, contrôles, compositions.'),
  ('scolarite.note.gerer',        'scolarite', 'Gérer les notes',        'Saisir et corriger les notes des élèves.'),
  ('scolarite.appreciation.gerer','scolarite', 'Gérer les appréciations','Rédiger les appréciations des bulletins.'),
  ('scolarite.bulletin.gerer',    'scolarite', 'Gérer les bulletins',    'Générer, publier et archiver les bulletins.')
on conflict (code) do nothing;

-- ============================================================================
-- Fin M6.
-- ============================================================================
