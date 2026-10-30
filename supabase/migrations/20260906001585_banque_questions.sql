-- ============================================================================
-- EcoShop — REG-37 lot R1 : banque de questions (cahier ch. 10, 30.5)
-- ============================================================================
-- Actif central du volet révision : quiz, examens blancs, recommandation et
-- statistiques (ch. 11, 13, 14) en dépendent.
--
-- Structure : chaque matière d'un programme officiel (programmes_matieres)
-- reçoit ses chapitres, leçons et compétences ; chaque question est
-- rattachée à une matière, une compétence (obligatoire) et, si possible, à
-- un chapitre et une leçon. Pays, programme et classe s'en déduisent.
--
-- Versions (modèle de Moodle) : chaque modification d'une question publiée
-- crée une nouvelle version de travail ; les élèves continuent de recevoir
-- la version publiée jusqu'à la publication de la suivante. Les tentatives
-- (lot R2) noteront la version jouée.
--
-- Circuit unique du contenu pédagogique (30.5) : brouillon → révision →
-- validée → publiée. La validation est faite par un profil habilité
-- distinct de l'auteur, sauf si l'auteur est lui-même Administrateur de
-- contenu pédagogique.
--
-- Qualité (10.3) : pas d'enregistrement sans compétence, difficulté et
-- explication ; forme des choix et de la bonne réponse vérifiée selon le
-- type ; CP1 à CE2 : types adaptés seulement (9.6, 10.2). Une question
-- signalée par trois personnes distinctes est suspendue de la diffusion
-- jusqu'à vérification.
--
-- Types (corrigés automatiquement, inspirés des interactions QTI) :
--   qcm_simple, qcm_multiple, vrai_faux, reponse_courte, texte_a_trous,
--   association, classement, calcul. Image, audio ou document : pièce
--   jointe possible sur tout type.
--
-- La bonne réponse est lisible par l'élève avec la question : la correction
-- immédiate doit fonctionner sans réseau (choix de Kolibri). Ces résultats
-- restent formatifs, jamais dans la moyenne officielle (12.6).
-- ============================================================================

do $$ begin
  create type public.statut_contenu_pedagogique as enum ('brouillon', 'revision', 'validee', 'publiee');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.type_question as enum (
    'qcm_simple', 'qcm_multiple', 'vrai_faux', 'reponse_courte',
    'texte_a_trous', 'association', 'classement', 'calcul'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.difficulte_question as enum ('facile', 'moyen', 'difficile', 'expert');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 0. Rôle : Administrateur de contenu pédagogique (4.4)
-- ---------------------------------------------------------------------------
create or replace function public.est_admin_contenu()
returns boolean
language sql stable set search_path = public
as $$
  select coalesce(public.mon_role_racine() = 'admin_contenu', false);
$$;
grant execute on function public.est_admin_contenu() to authenticated;

-- ---------------------------------------------------------------------------
-- 1. Chapitres, leçons, compétences d'une matière du programme officiel
-- ---------------------------------------------------------------------------
create table if not exists public.chapitres_matiere (
  id uuid primary key default gen_random_uuid(),
  matiere_id uuid not null references public.programmes_matieres (id) on delete cascade,
  titre text not null check (char_length(btrim(titre)) between 1 and 200),
  ordre int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists idx_chapitres_matiere on public.chapitres_matiere (matiere_id, ordre);

create table if not exists public.lecons_chapitre (
  id uuid primary key default gen_random_uuid(),
  chapitre_id uuid not null references public.chapitres_matiere (id) on delete cascade,
  titre text not null check (char_length(btrim(titre)) between 1 and 200),
  ordre int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists idx_lecons_chapitre on public.lecons_chapitre (chapitre_id, ordre);

create table if not exists public.competences_matiere (
  id uuid primary key default gen_random_uuid(),
  matiere_id uuid not null references public.programmes_matieres (id) on delete cascade,
  code text not null check (char_length(btrim(code)) between 1 and 40),
  libelle text not null check (char_length(btrim(libelle)) between 1 and 300),
  created_at timestamptz not null default now(),
  constraint competences_matiere_code_unique unique (matiere_id, code)
);

alter table public.chapitres_matiere enable row level security;
alter table public.lecons_chapitre enable row level security;
alter table public.competences_matiere enable row level security;

-- Lecture : tout compte connecté (le volet révision est ouvert à tous, 2.5).
-- Écriture : Administrateur de contenu pédagogique seulement.
drop policy if exists chapitres_select on public.chapitres_matiere;
create policy chapitres_select on public.chapitres_matiere for select to authenticated using (true);
drop policy if exists chapitres_ecrire on public.chapitres_matiere;
create policy chapitres_ecrire on public.chapitres_matiere for all to authenticated
  using (public.est_admin_contenu()) with check (public.est_admin_contenu());

drop policy if exists lecons_select on public.lecons_chapitre;
create policy lecons_select on public.lecons_chapitre for select to authenticated using (true);
drop policy if exists lecons_ecrire on public.lecons_chapitre;
create policy lecons_ecrire on public.lecons_chapitre for all to authenticated
  using (public.est_admin_contenu()) with check (public.est_admin_contenu());

drop policy if exists competences_select on public.competences_matiere;
create policy competences_select on public.competences_matiere for select to authenticated using (true);
drop policy if exists competences_ecrire on public.competences_matiere;
create policy competences_ecrire on public.competences_matiere for all to authenticated
  using (public.est_admin_contenu()) with check (public.est_admin_contenu());

-- ---------------------------------------------------------------------------
-- 2. Questions et leurs versions
-- ---------------------------------------------------------------------------
create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  matiere_id uuid not null references public.programmes_matieres (id) on delete cascade,
  statut public.statut_contenu_pedagogique not null default 'brouillon',
  version_travail int not null default 1,
  version_publiee int,
  auteur_id uuid references public.profiles (id) on delete set null,
  validateur_id uuid references public.profiles (id) on delete set null,
  valide_le timestamptz,
  publie_le timestamptz,
  remarque_revision text,
  suspendue_le timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_questions_matiere on public.questions (matiere_id, statut);
create index if not exists idx_questions_diffusees on public.questions (matiere_id)
  where version_publiee is not null and suspendue_le is null;

drop trigger if exists questions_set_updated_at on public.questions;
create trigger questions_set_updated_at before update on public.questions
  for each row execute function public.set_updated_at();

create table if not exists public.questions_versions (
  question_id uuid not null references public.questions (id) on delete cascade,
  version int not null check (version > 0),
  type public.type_question not null,
  difficulte public.difficulte_question not null,
  chapitre_id uuid references public.chapitres_matiere (id) on delete set null,
  lecon_id uuid references public.lecons_chapitre (id) on delete set null,
  competence_id uuid not null references public.competences_matiere (id) on delete restrict,
  enonce text not null check (char_length(btrim(enonce)) between 1 and 4000),
  contenu jsonb not null default '{}'::jsonb,
  reponse jsonb not null,
  explication text not null check (char_length(btrim(explication)) between 1 and 4000),
  temps_recommande_s int not null default 60 check (temps_recommande_s between 5 and 3600),
  source text check (source is null or char_length(source) <= 300),
  tags text[] not null default '{}',
  media_chemin text,
  media_type text check (media_type is null or media_type in ('image', 'audio', 'document')),
  cree_par uuid references public.profiles (id) on delete set null,
  cree_le timestamptz not null default now(),
  modifie_le timestamptz not null default now(),
  primary key (question_id, version)
);
create index if not exists idx_questions_versions_competence on public.questions_versions (competence_id);
create index if not exists idx_questions_versions_chapitre on public.questions_versions (chapitre_id);

alter table public.questions enable row level security;
alter table public.questions_versions enable row level security;
revoke insert, update, delete on public.questions, public.questions_versions from anon, authenticated;

-- Diffusée : publiée et non suspendue.
drop policy if exists questions_select on public.questions;
create policy questions_select on public.questions for select to authenticated
  using (public.est_admin_contenu() or (version_publiee is not null and suspendue_le is null));

drop policy if exists questions_versions_select on public.questions_versions;
create policy questions_versions_select on public.questions_versions for select to authenticated
  using (
    public.est_admin_contenu()
    or exists (
      select 1 from public.questions q
      where q.id = question_id and q.version_publiee = version and q.suspendue_le is null
    )
  );

-- Type JSON jamais nul (« absent » quand la clé manque) : une clé oubliée
-- ne passe pas les contrôles.
create or replace function public.type_json(p jsonb)
returns text
language sql immutable set search_path = public
as $$ select coalesce(jsonb_typeof(p), 'absent'); $$;

-- ---------------------------------------------------------------------------
-- 3. Vérification de la forme d'une question (10.2, 10.3)
--    Renvoie null si elle est correcte, sinon un code d'erreur lisible.
-- ---------------------------------------------------------------------------
create or replace function public.erreur_forme_question(
  p_type public.type_question,
  p_enonce text,
  p_contenu jsonb,
  p_reponse jsonb
)
returns text
language plpgsql immutable set search_path = public
as $$
declare
  v_ids text[];
  v_ids_droite text[];
  v_cle text;
  v_valeur jsonb;
  v_n int;
begin
  p_contenu := coalesce(p_contenu, '{}'::jsonb);
  if p_reponse is null or public.type_json(p_reponse) <> 'object' then
    return 'REPONSE_INVALIDE';
  end if;

  if p_type in ('qcm_simple', 'qcm_multiple') then
    if public.type_json(p_contenu -> 'choix') <> 'array'
       or jsonb_array_length(p_contenu -> 'choix') not between 2 and 6 then
      return 'CHOIX_INVALIDES';
    end if;
    select array_agg(c ->> 'id') into v_ids
      from jsonb_array_elements(p_contenu -> 'choix') c
     where coalesce(btrim(c ->> 'id'), '') <> '' and coalesce(btrim(c ->> 'texte'), '') <> '';
    if coalesce(array_length(v_ids, 1), 0) <> jsonb_array_length(p_contenu -> 'choix')
       or (select count(distinct x) from unnest(v_ids) x) <> array_length(v_ids, 1) then
      return 'CHOIX_INVALIDES';
    end if;
    if public.type_json(p_reponse -> 'bonnes') <> 'array' then return 'REPONSE_INVALIDE'; end if;
    v_n := jsonb_array_length(p_reponse -> 'bonnes');
    if v_n = 0 or (p_type = 'qcm_simple' and v_n <> 1) or v_n > array_length(v_ids, 1)
       or (select count(distinct b) from jsonb_array_elements_text(p_reponse -> 'bonnes') b) <> v_n then
      return 'REPONSE_INVALIDE';
    end if;
    if exists (select 1 from jsonb_array_elements_text(p_reponse -> 'bonnes') b where not (b = any (v_ids))) then
      return 'REPONSE_INVALIDE';
    end if;

  elsif p_type = 'vrai_faux' then
    if public.type_json(p_reponse -> 'valeur') <> 'boolean' then return 'REPONSE_INVALIDE'; end if;

  elsif p_type = 'reponse_courte' then
    if public.type_json(p_reponse -> 'acceptees') <> 'array' or jsonb_array_length(p_reponse -> 'acceptees') = 0
       or exists (select 1 from jsonb_array_elements(p_reponse -> 'acceptees') a
                  where jsonb_typeof(a) <> 'string' or btrim(a #>> '{}') = '') then
      return 'REPONSE_INVALIDE';
    end if;

  elsif p_type = 'texte_a_trous' then
    if public.type_json(p_reponse -> 'trous') <> 'object' or p_reponse -> 'trous' = '{}'::jsonb then
      return 'REPONSE_INVALIDE';
    end if;
    for v_cle, v_valeur in select key, value from jsonb_each(p_reponse -> 'trous') loop
      if position('[[' || v_cle || ']]' in p_enonce) = 0 then return 'TROU_ABSENT_ENONCE'; end if;
      if jsonb_typeof(v_valeur) <> 'array' or jsonb_array_length(v_valeur) = 0
         or exists (select 1 from jsonb_array_elements(v_valeur) a
                    where jsonb_typeof(a) <> 'string' or btrim(a #>> '{}') = '') then
        return 'REPONSE_INVALIDE';
      end if;
    end loop;

  elsif p_type = 'association' then
    if public.type_json(p_contenu -> 'gauche') <> 'array' or public.type_json(p_contenu -> 'droite') <> 'array'
       or jsonb_array_length(p_contenu -> 'gauche') not between 2 and 8
       or jsonb_array_length(p_contenu -> 'droite') not between 2 and 8 then
      return 'CHOIX_INVALIDES';
    end if;
    select array_agg(c ->> 'id') into v_ids from jsonb_array_elements(p_contenu -> 'gauche') c
     where coalesce(btrim(c ->> 'id'), '') <> '' and coalesce(btrim(c ->> 'texte'), '') <> '';
    select array_agg(c ->> 'id') into v_ids_droite from jsonb_array_elements(p_contenu -> 'droite') c
     where coalesce(btrim(c ->> 'id'), '') <> '' and coalesce(btrim(c ->> 'texte'), '') <> '';
    if coalesce(array_length(v_ids, 1), 0) <> jsonb_array_length(p_contenu -> 'gauche')
       or coalesce(array_length(v_ids_droite, 1), 0) <> jsonb_array_length(p_contenu -> 'droite') then
      return 'CHOIX_INVALIDES';
    end if;
    if public.type_json(p_reponse -> 'paires') <> 'object' then return 'REPONSE_INVALIDE'; end if;
    if exists (select 1 from unnest(v_ids) g where not (p_reponse -> 'paires') ? g)
       or exists (select 1 from jsonb_each_text(p_reponse -> 'paires') p
                  where not (p.key = any (v_ids)) or not (p.value = any (v_ids_droite))) then
      return 'REPONSE_INVALIDE';
    end if;

  elsif p_type = 'classement' then
    if public.type_json(p_contenu -> 'elements') <> 'array'
       or jsonb_array_length(p_contenu -> 'elements') not between 2 and 8 then
      return 'CHOIX_INVALIDES';
    end if;
    select array_agg(c ->> 'id' order by c ->> 'id') into v_ids from jsonb_array_elements(p_contenu -> 'elements') c
     where coalesce(btrim(c ->> 'id'), '') <> '' and coalesce(btrim(c ->> 'texte'), '') <> '';
    if coalesce(array_length(v_ids, 1), 0) <> jsonb_array_length(p_contenu -> 'elements') then
      return 'CHOIX_INVALIDES';
    end if;
    if public.type_json(p_reponse -> 'ordre') <> 'array'
       or (select array_agg(o order by o) from jsonb_array_elements_text(p_reponse -> 'ordre') o) is distinct from v_ids then
      return 'REPONSE_INVALIDE';
    end if;

  elsif p_type = 'calcul' then
    if public.type_json(p_reponse -> 'valeur') <> 'number' then return 'REPONSE_INVALIDE'; end if;
    if p_reponse ? 'tolerance' and (public.type_json(p_reponse -> 'tolerance') <> 'number'
                                    or (p_reponse ->> 'tolerance')::numeric < 0) then
      return 'REPONSE_INVALIDE';
    end if;
  end if;

  return null;
end;
$$;
grant execute on function public.erreur_forme_question(public.type_question, text, jsonb, jsonb) to authenticated;

-- Premières classes du primaire (CP1 à CE2) et préscolaire : types adaptés
-- seulement, trois choix au plus (9.6, 10.2).
create or replace function public.matiere_petites_classes(p_matiere uuid)
returns boolean
language sql stable set search_path = public
as $$
  select coalesce((
    select n.grade_level_normalise <= 4
      from public.programmes_matieres m
      join public.programmes_officiels p on p.id = m.programme_id
      join public.niveaux_educatifs n on n.id = p.niveau_id
     where m.id = p_matiere
  ), false);
$$;

-- ---------------------------------------------------------------------------
-- 4. Enregistrer (créer ou modifier) une question
--    Identifiant tiré par l'appareil : un brouillon gardé sans réseau n'est
--    jamais créé deux fois (REG-35).
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_question(
  p_id uuid,
  p_matiere uuid,
  p_type public.type_question,
  p_difficulte public.difficulte_question,
  p_competence uuid,
  p_enonce text,
  p_contenu jsonb,
  p_reponse jsonb,
  p_explication text,
  p_chapitre uuid default null,
  p_lecon uuid default null,
  p_temps_recommande_s int default 60,
  p_source text default null,
  p_tags text[] default '{}',
  p_media_chemin text default null,
  p_media_type text default null
)
returns public.questions
language plpgsql security definer set search_path = public
as $$
declare
  v_q public.questions;
  v_erreur text;
  v_version int;
begin
  if not public.est_admin_contenu() then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_id is null then raise exception 'IDENTIFIANT_REQUIS' using errcode = '22023'; end if;
  if p_competence is null then raise exception 'COMPETENCE_REQUISE' using errcode = '22023'; end if;
  if p_difficulte is null then raise exception 'DIFFICULTE_REQUISE' using errcode = '22023'; end if;
  if coalesce(btrim(p_explication), '') = '' then raise exception 'EXPLICATION_REQUISE' using errcode = '22023'; end if;
  if coalesce(btrim(p_enonce), '') = '' then raise exception 'ENONCE_REQUIS' using errcode = '22023'; end if;

  if not exists (select 1 from public.competences_matiere where id = p_competence and matiere_id = p_matiere) then
    raise exception 'COMPETENCE_HORS_MATIERE' using errcode = '22023';
  end if;
  if p_chapitre is not null and not exists (
    select 1 from public.chapitres_matiere where id = p_chapitre and matiere_id = p_matiere
  ) then
    raise exception 'CHAPITRE_HORS_MATIERE' using errcode = '22023';
  end if;
  if p_lecon is not null and not exists (
    select 1 from public.lecons_chapitre where id = p_lecon and chapitre_id = p_chapitre
  ) then
    raise exception 'LECON_HORS_CHAPITRE' using errcode = '22023';
  end if;

  v_erreur := public.erreur_forme_question(p_type, p_enonce, p_contenu, p_reponse);
  if v_erreur is not null then raise exception '%', v_erreur using errcode = '22023'; end if;

  if public.matiere_petites_classes(p_matiere) then
    if p_type not in ('qcm_simple', 'vrai_faux', 'association', 'classement') then
      raise exception 'TYPE_NON_ADAPTE_PETITES_CLASSES' using errcode = '22023';
    end if;
    if p_type = 'qcm_simple' and jsonb_array_length(p_contenu -> 'choix') > 3 then
      raise exception 'TROP_DE_CHOIX_PETITES_CLASSES' using errcode = '22023';
    end if;
  end if;

  select * into v_q from public.questions where id = p_id for update;

  if not found then
    insert into public.questions (id, matiere_id, statut, version_travail, auteur_id)
    values (p_id, p_matiere, 'brouillon', 1, auth.uid())
    returning * into v_q;
    v_version := 1;
    insert into public.questions_versions (
      question_id, version, type, difficulte, chapitre_id, lecon_id, competence_id, enonce, contenu,
      reponse, explication, temps_recommande_s, source, tags, media_chemin, media_type, cree_par
    ) values (
      p_id, 1, p_type, p_difficulte, p_chapitre, p_lecon, p_competence, btrim(p_enonce), coalesce(p_contenu, '{}'),
      p_reponse, btrim(p_explication), p_temps_recommande_s, nullif(btrim(p_source), ''), coalesce(p_tags, '{}'),
      p_media_chemin, p_media_type, auth.uid()
    );
    return v_q;
  end if;

  if v_q.matiere_id <> p_matiere then
    raise exception 'MATIERE_NON_MODIFIABLE' using errcode = '22023';
  end if;

  if v_q.statut = 'publiee' then
    -- Publiée : nouvelle version de travail ; la version publiée reste servie.
    v_version := v_q.version_travail + 1;
    insert into public.questions_versions (
      question_id, version, type, difficulte, chapitre_id, lecon_id, competence_id, enonce, contenu,
      reponse, explication, temps_recommande_s, source, tags, media_chemin, media_type, cree_par
    ) values (
      p_id, v_version, p_type, p_difficulte, p_chapitre, p_lecon, p_competence, btrim(p_enonce), coalesce(p_contenu, '{}'),
      p_reponse, btrim(p_explication), p_temps_recommande_s, nullif(btrim(p_source), ''), coalesce(p_tags, '{}'),
      p_media_chemin, p_media_type, auth.uid()
    );
  else
    -- Brouillon, en révision ou validée : la version de travail est
    -- corrigée en place ; une validation déjà donnée est à refaire.
    v_version := v_q.version_travail;
    update public.questions_versions
       set type = p_type, difficulte = p_difficulte, chapitre_id = p_chapitre, lecon_id = p_lecon,
           competence_id = p_competence, enonce = btrim(p_enonce), contenu = coalesce(p_contenu, '{}'),
           reponse = p_reponse, explication = btrim(p_explication), temps_recommande_s = p_temps_recommande_s,
           source = nullif(btrim(p_source), ''), tags = coalesce(p_tags, '{}'), media_chemin = p_media_chemin,
           media_type = p_media_type, cree_par = auth.uid(), modifie_le = now()
     where question_id = p_id and version = v_version;
  end if;

  update public.questions
     set statut = 'brouillon', version_travail = v_version, validateur_id = null, valide_le = null
   where id = p_id
  returning * into v_q;
  return v_q;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Circuit : soumettre, renvoyer, valider, publier
-- ---------------------------------------------------------------------------
create or replace function public.changer_statut_question(
  p_id uuid,
  p_action text,
  p_remarque text default null
)
returns public.questions
language plpgsql security definer set search_path = public
as $$
declare
  v_q public.questions;
  v_auteur uuid;
  v_auteur_admin boolean;
begin
  if not public.est_admin_contenu() then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select * into v_q from public.questions where id = p_id for update;
  if not found then raise exception 'QUESTION_INTROUVABLE' using errcode = '22023'; end if;

  if p_action = 'soumettre' then
    if v_q.statut = 'revision' then return v_q; end if;          -- rejeu
    if v_q.statut <> 'brouillon' then raise exception 'STATUT_INATTENDU' using errcode = '22023'; end if;
    update public.questions set statut = 'revision', remarque_revision = null where id = p_id returning * into v_q;

  elsif p_action = 'renvoyer' then
    if v_q.statut not in ('revision', 'validee') then raise exception 'STATUT_INATTENDU' using errcode = '22023'; end if;
    if coalesce(btrim(p_remarque), '') = '' then raise exception 'REMARQUE_REQUISE' using errcode = '22023'; end if;
    update public.questions
       set statut = 'brouillon', remarque_revision = btrim(p_remarque), validateur_id = null, valide_le = null
     where id = p_id returning * into v_q;

  elsif p_action = 'valider' then
    if v_q.statut = 'validee' then return v_q; end if;
    if v_q.statut <> 'revision' then raise exception 'STATUT_INATTENDU' using errcode = '22023'; end if;
    select cree_par into v_auteur from public.questions_versions where question_id = p_id and version = v_q.version_travail;
    select coalesce(role_racine = 'admin_contenu', false) into v_auteur_admin from public.profiles where id = v_auteur;
    if v_auteur = auth.uid() and not coalesce(v_auteur_admin, false) then
      raise exception 'VALIDATEUR_DISTINCT_REQUIS' using errcode = '42501';
    end if;
    update public.questions set statut = 'validee', validateur_id = auth.uid(), valide_le = now()
     where id = p_id returning * into v_q;

  elsif p_action = 'publier' then
    if v_q.statut = 'publiee' then return v_q; end if;
    if v_q.statut <> 'validee' then raise exception 'VALIDATION_REQUISE' using errcode = '22023'; end if;
    update public.questions
       set statut = 'publiee', version_publiee = version_travail, publie_le = now()
     where id = p_id returning * into v_q;

  else
    raise exception 'ACTION_INCONNUE' using errcode = '22023';
  end if;
  return v_q;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Signalements (10.3) : trois personnes distinctes → suspension
-- ---------------------------------------------------------------------------
create table if not exists public.signalements_questions (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.questions (id) on delete cascade,
  version int not null,
  signale_par uuid not null references public.profiles (id) on delete cascade,
  motif text not null check (motif in ('reponse_fausse', 'enonce_confus', 'hors_programme', 'faute', 'autre')),
  commentaire text check (commentaire is null or char_length(commentaire) <= 500),
  traite boolean not null default false,
  cree_le timestamptz not null default now(),
  constraint signalements_un_par_personne unique (question_id, version, signale_par)
);
create index if not exists idx_signalements_ouverts on public.signalements_questions (question_id) where not traite;

alter table public.signalements_questions enable row level security;
revoke insert, update, delete on public.signalements_questions from anon, authenticated;
drop policy if exists signalements_select on public.signalements_questions;
create policy signalements_select on public.signalements_questions for select to authenticated
  using (public.est_admin_contenu() or signale_par = auth.uid());

-- Seuil lisible dans les paramètres de la plateforme.
insert into public.parametres_globaux (cle, valeur, description) values
  ('seuil_signalements_question', '{"valeur": 3}'::jsonb,
   'Nombre de personnes distinctes qui signalent une question avant sa suspension automatique (cahier 10.3).')
on conflict (cle) do nothing;

create or replace function public.signaler_question(
  p_question uuid,
  p_motif text,
  p_commentaire text default null
)
returns boolean   -- vrai si la question vient d'être suspendue
language plpgsql security definer set search_path = public
as $$
declare
  v_q public.questions;
  v_seuil int;
  v_n int;
begin
  if auth.uid() is null then raise exception 'PERMISSION_REFUSEE' using errcode = '42501'; end if;
  select * into v_q from public.questions where id = p_question for update;
  if not found or v_q.version_publiee is null then
    raise exception 'QUESTION_INTROUVABLE' using errcode = '22023';
  end if;

  insert into public.signalements_questions (question_id, version, signale_par, motif, commentaire)
  values (p_question, v_q.version_publiee, auth.uid(), p_motif, nullif(btrim(p_commentaire), ''))
  on conflict (question_id, version, signale_par) do nothing;   -- rejeu ou second signalement

  if v_q.suspendue_le is not null then return false; end if;
  select coalesce((valeur ->> 'valeur')::int, 3) into v_seuil
    from public.parametres_globaux where cle = 'seuil_signalements_question';
  select count(distinct signale_par) into v_n
    from public.signalements_questions where question_id = p_question and not traite;
  if v_n >= coalesce(v_seuil, 3) then
    update public.questions set suspendue_le = now() where id = p_question;
    return true;
  end if;
  return false;
end;
$$;

-- Après vérification : rétablir la question (signalements traités) ; si
-- elle était fausse, l'administrateur en publie d'abord une version corrigée.
create or replace function public.retablir_question(p_question uuid)
returns public.questions
language plpgsql security definer set search_path = public
as $$
declare
  v_q public.questions;
begin
  if not public.est_admin_contenu() then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  update public.signalements_questions set traite = true where question_id = p_question and not traite;
  update public.questions set suspendue_le = null where id = p_question returning * into v_q;
  if not found then raise exception 'QUESTION_INTROUVABLE' using errcode = '22023'; end if;
  return v_q;
end;
$$;

revoke all on function public.enregistrer_question(uuid, uuid, public.type_question, public.difficulte_question, uuid, text, jsonb, jsonb, text, uuid, uuid, int, text, text[], text, text) from public, anon;
revoke all on function public.changer_statut_question(uuid, text, text) from public, anon;
revoke all on function public.signaler_question(uuid, text, text) from public, anon;
revoke all on function public.retablir_question(uuid) from public, anon;
revoke all on function public.matiere_petites_classes(uuid) from public, anon;
grant execute on function public.enregistrer_question(uuid, uuid, public.type_question, public.difficulte_question, uuid, text, jsonb, jsonb, text, uuid, uuid, int, text, text[], text, text) to authenticated;
grant execute on function public.changer_statut_question(uuid, text, text) to authenticated;
grant execute on function public.signaler_question(uuid, text, text) to authenticated;
grant execute on function public.retablir_question(uuid) to authenticated;
grant execute on function public.matiere_petites_classes(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Images, sons et documents des questions
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('questions-medias', 'questions-medias', false, 3145728,
        array['image/jpeg', 'image/png', 'image/webp', 'audio/mpeg', 'audio/mp4', 'application/pdf'])
on conflict (id) do nothing;

drop policy if exists questions_medias_lire on storage.objects;
create policy questions_medias_lire on storage.objects for select to authenticated
  using (bucket_id = 'questions-medias');
drop policy if exists questions_medias_ecrire on storage.objects;
create policy questions_medias_ecrire on storage.objects for insert to authenticated
  with check (bucket_id = 'questions-medias' and public.est_admin_contenu());
drop policy if exists questions_medias_modifier on storage.objects;
create policy questions_medias_modifier on storage.objects for update to authenticated
  using (bucket_id = 'questions-medias' and public.est_admin_contenu());
