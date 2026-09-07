-- ============================================================================
-- EcoShop — M4 — Référentiel pédagogique multi-pays (CEDEAO)
--
-- Périmètre (ANALYSE_GLOBALE.md §4.3, cahier v4.1 ch. 6) : décrire 16 systèmes
-- éducatifs CEDEAO sous un modèle unique, inter-comparable, téléchargeable
-- hors-ligne. Domaines couverts : pays, système éducatif, cycles, niveaux
-- (grade_level_normalise), examens nationaux, filières, programmes officiels
-- et matières par programme.
--
-- Principes :
--   • type_systeme : 4 familles (francophone_cfa, anglophone_waec, lusophone,
--     arabophone_mixte) — un pays appartient à exactement une famille.
--   • grade_level_normalise : entier continu par pays, unique, jamais affiché
--     à l'utilisateur (seule l'appellation locale l'est) ; il permet la
--     comparaison inter-pays (ex. Terminale GN = Terminale SN = SHS3 GH).
--   • Lecture publique des données publiées ; écriture réservée au back-office
--     via service_role (aucune policy d'écriture client).
--   • Référentiel versionné + paquets de téléchargement hors-ligne par pays /
--     niveau (axe différenciant).
--
-- Migration idempotente.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Types énumérés
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.type_systeme_educatif as enum (
    'francophone_cfa', 'anglophone_waec', 'lusophone', 'arabophone_mixte'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.statut_referentiel as enum ('brouillon', 'publie', 'archive');
exception when duplicate_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Systèmes éducatifs (4 familles, invariant du modèle)
-- ---------------------------------------------------------------------------
create table if not exists public.systemes_educatifs (
  code text primary key,
  nom text not null,
  description text
);

-- ---------------------------------------------------------------------------
-- 2. Pays pédagogiques (16 pays CEDEAO)
-- ---------------------------------------------------------------------------
create table if not exists public.pays_pedagogiques (
  code_iso text primary key,                       -- ISO 3166-1 alpha-2
  nom text not null,
  type_systeme text not null
    references public.systemes_educatifs (code),
  langue_enseignement_principale text not null,
  organisme_examinateur text,                      -- ex. WAEC, ministère national
  devise_code text not null default 'XOF',
  statut_deploiement text not null default 'brouillon'
    check (statut_deploiement in ('brouillon', 'deploye')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 3. Cycles (pays_cycle) — ex. primaire / collège / lycée
-- ---------------------------------------------------------------------------
create table if not exists public.cycles_educatifs (
  id uuid primary key default gen_random_uuid(),
  pays_code text not null references public.pays_pedagogiques (code_iso) on delete cascade,
  code text not null,
  nom text not null,
  ordre int not null,
  age_min int,
  age_max int,
  duree_annees int,
  isced_min int not null check (isced_min between 0 and 8),
  isced_max int not null check (isced_max between 0 and 8),
  statut public.statut_referentiel not null default 'brouillon',
  constraint cycles_pays_code_unique unique (pays_code, code)
);

-- ---------------------------------------------------------------------------
-- 4. Niveaux (pays_niveau) — ex. CP1, 6e, JHS1…
-- grade_level_normalise : clé de comparaison inter-pays (contiguë, unique).
-- ---------------------------------------------------------------------------
create table if not exists public.niveaux_educatifs (
  id uuid primary key default gen_random_uuid(),
  cycle_id uuid not null references public.cycles_educatifs (id) on delete cascade,
  pays_code text not null references public.pays_pedagogiques (code_iso) on delete cascade,
  code text not null,
  nom text not null,
  grade_level_normalise int not null check (grade_level_normalise > 0),
  isced int not null check (isced between 0 and 8),
  ordre int not null,
  statut public.statut_referentiel not null default 'brouillon',
  constraint niveaux_pays_code_unique unique (pays_code, code),
  constraint niveaux_pays_grade_unique unique (pays_code, grade_level_normalise)
);

-- ---------------------------------------------------------------------------
-- 5. Examens nationaux (pays_examen) — ex. BEPC, BAC, BECE, WASSCE
-- ---------------------------------------------------------------------------
create table if not exists public.examens_nationaux (
  id uuid primary key default gen_random_uuid(),
  pays_code text not null references public.pays_pedagogiques (code_iso) on delete cascade,
  cycle_id uuid references public.cycles_educatifs (id) on delete set null,
  code text not null,
  nom text not null,
  organisme text,
  mois_session int check (mois_session between 1 and 12),
  periodicite text,
  statut public.statut_referentiel not null default 'brouillon',
  constraint examens_pays_code_unique unique (pays_code, code)
);

-- ---------------------------------------------------------------------------
-- 6. Filières (pays_filiere) — ex. séries du lycée (L, S, technique)
-- ---------------------------------------------------------------------------
create table if not exists public.filieres_educatives (
  id uuid primary key default gen_random_uuid(),
  pays_code text not null references public.pays_pedagogiques (code_iso) on delete cascade,
  niveau_id uuid references public.niveaux_educatifs (id) on delete cascade,
  code text not null,
  nom text not null,
  description text,
  statut public.statut_referentiel not null default 'brouillon',
  constraint filieres_pays_code_unique unique (pays_code, code)
);

-- ---------------------------------------------------------------------------
-- 7. Programmes officiels (programme_officiel) — curriculum versionné
-- ---------------------------------------------------------------------------
create table if not exists public.programmes_officiels (
  id uuid primary key default gen_random_uuid(),
  pays_code text not null references public.pays_pedagogiques (code_iso) on delete cascade,
  niveau_id uuid not null references public.niveaux_educatifs (id) on delete cascade,
  filiere_id uuid references public.filieres_educatives (id) on delete set null,
  code text not null,
  nom text not null,
  annee_scolaire text,                              -- ex. '2026-2027'
  version int not null default 1,
  statut public.statut_referentiel not null default 'brouillon',
  constraint programmes_pays_code_version_unique unique (pays_code, code, version)
);

-- ---------------------------------------------------------------------------
-- 8. Matières par programme (programme_matiere)
-- ---------------------------------------------------------------------------
create table if not exists public.programmes_matieres (
  id uuid primary key default gen_random_uuid(),
  programme_id uuid not null references public.programmes_officiels (id) on delete cascade,
  code text not null,
  nom text not null,
  coefficient int check (coefficient > 0),
  volume_horaire_annuel int,
  ordre int not null default 0,
  statut public.statut_referentiel not null default 'brouillon',
  constraint matieres_programme_code_unique unique (programme_id, code)
);

-- ---------------------------------------------------------------------------
-- 9. Paquets de téléchargement hors-ligne (axe différenciant : contenu par
--    pays/niveau, vérifié par empreinte SHA-256, versionné)
-- ---------------------------------------------------------------------------
create table if not exists public.paquets_referentiel (
  id uuid primary key default gen_random_uuid(),
  pays_code text not null references public.pays_pedagogiques (code_iso) on delete cascade,
  niveau_id uuid references public.niveaux_educatifs (id) on delete cascade,
  version int not null,
  empreinte_sha256 text not null,
  taille_octets bigint not null,
  url text,
  publie_le timestamptz,
  constraint paquets_pays_niveau_version_unique unique (pays_code, niveau_id, version)
);

-- ---------------------------------------------------------------------------
-- Trigger updated_at (réutilise le helper M0)
-- ---------------------------------------------------------------------------
drop trigger if exists pays_pedagogiques_set_updated_at on public.pays_pedagogiques;
create trigger pays_pedagogiques_set_updated_at
  before update on public.pays_pedagogiques
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- Lecture publique des données publiées ; écriture service_role uniquement.
-- ---------------------------------------------------------------------------
alter table public.systemes_educatifs enable row level security;
alter table public.pays_pedagogiques enable row level security;
alter table public.cycles_educatifs enable row level security;
alter table public.niveaux_educatifs enable row level security;
alter table public.examens_nationaux enable row level security;
alter table public.filieres_educatives enable row level security;
alter table public.programmes_officiels enable row level security;
alter table public.programmes_matieres enable row level security;
alter table public.paquets_referentiel enable row level security;

drop policy if exists "systemes_select" on public.systemes_educatifs;
create policy "systemes_select" on public.systemes_educatifs
  for select using (true);

drop policy if exists "pays_select_deploye" on public.pays_pedagogiques;
create policy "pays_select_deploye" on public.pays_pedagogiques
  for select using (statut_deploiement = 'deploye');

drop policy if exists "cycles_select_publie" on public.cycles_educatifs;
create policy "cycles_select_publie" on public.cycles_educatifs
  for select using (statut = 'publie');

drop policy if exists "niveaux_select_publie" on public.niveaux_educatifs;
create policy "niveaux_select_publie" on public.niveaux_educatifs
  for select using (statut = 'publie');

drop policy if exists "examens_select_publie" on public.examens_nationaux;
create policy "examens_select_publie" on public.examens_nationaux
  for select using (statut = 'publie');

drop policy if exists "filieres_select_publie" on public.filieres_educatives;
create policy "filieres_select_publie" on public.filieres_educatives
  for select using (statut = 'publie');

drop policy if exists "programmes_select_publie" on public.programmes_officiels;
create policy "programmes_select_publie" on public.programmes_officiels
  for select using (statut = 'publie');

drop policy if exists "matieres_select_publie" on public.programmes_matieres;
create policy "matieres_select_publie" on public.programmes_matieres
  for select using (statut = 'publie');

drop policy if exists "paquets_select_publie" on public.paquets_referentiel;
create policy "paquets_select_publie" on public.paquets_referentiel
  for select using (publie_le is not null);

-- ---------------------------------------------------------------------------
-- Index
-- ---------------------------------------------------------------------------
create index if not exists idx_cycles_pays on public.cycles_educatifs (pays_code);
create index if not exists idx_niveaux_cycle on public.niveaux_educatifs (cycle_id);
create index if not exists idx_niveaux_pays_grade on public.niveaux_educatifs (pays_code, grade_level_normalise);
create index if not exists idx_examens_pays on public.examens_nationaux (pays_code);
create index if not exists idx_programmes_niveau on public.programmes_officiels (niveau_id);
create index if not exists idx_matieres_programme on public.programmes_matieres (programme_id);

-- ============================================================================
-- NB : la continuité de grade_level_normalise au sein d'un pays (aucun trou)
-- est une règle d'intégrité maintenue par le CMS/back-office (ch. 6) ; le
-- schéma en garantit l'unicité et la positivité.
-- ============================================================================
