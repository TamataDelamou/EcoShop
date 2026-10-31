-- ============================================================================
-- EcoShop — REG-38 lot E2a : concours, olympiades et certificats de
-- maîtrise (cahier 13.2, 23.1 à 23.4)
-- ============================================================================
-- • Concours internes (Direction d'une école) et événements de la
--   plateforme (GSG : concours inter-écoles, olympiades, tournois), pour un
--   pays ou au-delà (pays_code nul : international). Public visé par
--   niveau normalisé (grade 1 à 13), comparable d'un pays à l'autre.
-- • Manches à fenêtre horaire commune ; chaque emplacement de question peut
--   avoir 3 ou 4 variantes équivalentes, tirées par élève : la fuite d'un
--   sujet ne sert plus (Univ. de l'Illinois : avantage de 12 points annulé
--   avec 3 à 4 variantes). Ordre mélangé par élève.
-- • Correction faite par le serveur (même règles que l'application) : un
--   score de concours ne vient jamais du téléphone.
-- • Classement : général, filtrable par pays ou par école ; un classement
--   national ne mélange jamais deux pays (23.1). Copie trop rapide et
--   parfaite : écartée en attente de vérification par l'organisateur
--   (23.4), sans rien retirer à l'élève.
-- • Certificat de maîtrise (23.3) : identifiant unique, vérifiable par un
--   tiers sans compte (fonction publique verifier_certificat) ; jamais un
--   résultat officiel de scolarité (12.6).
-- ============================================================================

alter table public.tentatives_revision drop constraint if exists tentatives_revision_mode_check;
alter table public.tentatives_revision add constraint tentatives_revision_mode_check
  check (mode in ('rapide', 'standard', 'intensif', 'chapitre', 'matiere', 'melange', 'personnalise', 'erreurs',
                  'examen', 'repetition', 'competence', 'plan', 'concours'));

do $$ begin
  create type public.type_concours as enum (
    'concours_interne', 'concours_inter_ecoles', 'olympiade', 'tournoi', 'championnat', 'concours_entree');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.statut_concours as enum ('brouillon', 'ouvert', 'termine', 'annule');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 1. Concours et manches
-- ---------------------------------------------------------------------------
create table if not exists public.concours (
  id uuid primary key default gen_random_uuid(),
  titre text not null check (char_length(btrim(titre)) between 3 and 120),
  description text check (description is null or char_length(description) <= 2000),
  type public.type_concours not null default 'concours_interne',
  -- Nul : événement de la plateforme (GSG).
  etablissement_id uuid references public.etablissements (id) on delete cascade,
  -- Nul : ouvert à tous les pays (international).
  pays_code text references public.pays_pedagogiques (code_iso) on delete set null,
  grade_min int not null default 1 check (grade_min between -2 and 13),
  grade_max int not null default 13 check (grade_max between -2 and 13),
  recompenses text check (recompenses is null or char_length(recompenses) <= 1000),
  inscription_jusquau timestamptz,
  seuil_certificat int not null default 50 check (seuil_certificat between 0 and 100),
  statut public.statut_concours not null default 'brouillon',
  cree_par uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint concours_grades check (grade_min <= grade_max)
);
drop trigger if exists concours_set_updated_at on public.concours;
create trigger concours_set_updated_at before update on public.concours
  for each row execute function public.set_updated_at();

create table if not exists public.manches_concours (
  id uuid primary key default gen_random_uuid(),
  concours_id uuid not null references public.concours (id) on delete cascade,
  ordre int not null default 1,
  titre text not null check (char_length(btrim(titre)) between 1 and 120),
  ouverture timestamptz not null,
  fermeture timestamptz not null,
  duree_min int not null check (duree_min between 5 and 240),
  constraint manches_fenetre check (fermeture > ouverture)
);
create index if not exists idx_manches_concours on public.manches_concours (concours_id, ordre);

create table if not exists public.manches_questions (
  manche_id uuid not null references public.manches_concours (id) on delete cascade,
  emplacement int not null check (emplacement between 1 and 50),
  question_id uuid not null references public.questions (id) on delete cascade,
  primary key (manche_id, emplacement, question_id)
);

create table if not exists public.inscriptions_concours (
  concours_id uuid not null references public.concours (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  etablissement_id uuid references public.etablissements (id) on delete set null,
  pays_code text,
  inscrit_par uuid references public.profiles (id) on delete set null,
  inscrit_le timestamptz not null default now(),
  primary key (concours_id, fiche_eleve_id)
);

create table if not exists public.participations_manche (
  manche_id uuid not null references public.manches_concours (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  questions uuid[] not null,
  commence_le timestamptz not null default now(),
  remis_le timestamptz,
  reponses jsonb,
  score numeric(6, 3),
  duree_s int,
  hors_delai boolean not null default false,
  suspect boolean not null default false,
  rehabilite boolean not null default false,
  primary key (manche_id, fiche_eleve_id)
);

alter table public.concours enable row level security;
alter table public.manches_concours enable row level security;
alter table public.manches_questions enable row level security;
alter table public.inscriptions_concours enable row level security;
alter table public.participations_manche enable row level security;
revoke insert, update, delete on public.concours, public.manches_concours, public.manches_questions,
  public.inscriptions_concours, public.participations_manche from anon, authenticated;
-- Lecture des sujets (manches_questions) : jamais directe, seulement par
-- commencer_manche (sinon un élève lirait les questions avant l'heure).
revoke select on public.manches_questions from anon, authenticated;

-- Qui organise : la Direction de l'école (concours interne), GSG sinon.
create or replace function public.organise_concours(p_etablissement uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select case when p_etablissement is null
              then coalesce(public.est_admin_gsg(), false) or public.est_admin_contenu()
              else coalesce(public.est_direction(p_etablissement), false) end;
$$;

-- Fiche de l'élève : école, pays et niveau de sa classe actuelle.
create or replace function public.situation_eleve(p_fiche uuid)
returns table (etablissement_id uuid, pays_code text, grade int)
language sql stable security definer set search_path = public
as $$
  select i.etablissement_id, n.pays_code, n.grade_level_normalise
    from public.inscriptions i
    join public.classes c on c.id = i.classe_id
    join public.annees_scolaires a on a.id = i.annee_scolaire_id
    join public.niveaux_educatifs n on n.id = c.niveau_id
   where i.fiche_eleve_id = p_fiche and i.deleted_at is null and i.statut = 'active'
   order by a.date_debut desc
   limit 1;
$$;
revoke all on function public.situation_eleve(uuid) from public, anon, authenticated;

drop policy if exists concours_select on public.concours;
create policy concours_select on public.concours for select to authenticated
  using (statut <> 'brouillon' or public.organise_concours(etablissement_id));
drop policy if exists manches_select on public.manches_concours;
create policy manches_select on public.manches_concours for select to authenticated
  using (exists (select 1 from public.concours c where c.id = concours_id
                  and (c.statut <> 'brouillon' or public.organise_concours(c.etablissement_id))));
drop policy if exists inscriptions_concours_select on public.inscriptions_concours;
create policy inscriptions_concours_select on public.inscriptions_concours for select to authenticated
  using (public.peut_reviser_pour(fiche_eleve_id)
         or exists (select 1 from public.concours c where c.id = concours_id and public.organise_concours(c.etablissement_id)));
drop policy if exists participations_select on public.participations_manche;
create policy participations_select on public.participations_manche for select to authenticated
  using (public.peut_reviser_pour(fiche_eleve_id)
         or exists (select 1 from public.manches_concours m join public.concours c on c.id = m.concours_id
                     where m.id = manche_id and public.organise_concours(c.etablissement_id)));

-- Enregistrer (créer ou modifier) un concours.
create or replace function public.enregistrer_concours(
  p_id uuid,
  p_titre text,
  p_type public.type_concours,
  p_etablissement uuid,
  p_pays text,
  p_grade_min int,
  p_grade_max int,
  p_description text default null,
  p_recompenses text default null,
  p_inscription_jusquau timestamptz default null,
  p_seuil_certificat int default 50
)
returns public.concours
language plpgsql security definer set search_path = public
as $$
declare
  v public.concours;
begin
  if not public.organise_concours(p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_etablissement is not null and p_type <> 'concours_interne' then
    raise exception 'TYPE_RESERVE_PLATEFORME' using errcode = '22023';
  end if;
  select * into v from public.concours where id = p_id for update;
  if found and (v.etablissement_id is distinct from p_etablissement) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if found and v.statut <> 'brouillon' then
    raise exception 'CONCOURS_DEJA_OUVERT' using errcode = '22023';
  end if;
  insert into public.concours (id, titre, description, type, etablissement_id, pays_code, grade_min, grade_max,
                               recompenses, inscription_jusquau, seuil_certificat, cree_par)
  values (p_id, btrim(p_titre), p_description, p_type, p_etablissement,
          -- Concours d'une école : le pays de l'école.
          coalesce(p_pays, (select e.pays_code from public.etablissements e where e.id = p_etablissement)),
          p_grade_min, p_grade_max, p_recompenses, p_inscription_jusquau, coalesce(p_seuil_certificat, 50), auth.uid())
  on conflict (id) do update
    set titre = excluded.titre, description = excluded.description, type = excluded.type,
        pays_code = excluded.pays_code, grade_min = excluded.grade_min, grade_max = excluded.grade_max,
        recompenses = excluded.recompenses, inscription_jusquau = excluded.inscription_jusquau,
        seuil_certificat = excluded.seuil_certificat
  returning * into v;
  return v;
end;
$$;

create or replace function public.enregistrer_manche(
  p_id uuid,
  p_concours uuid,
  p_ordre int,
  p_titre text,
  p_ouverture timestamptz,
  p_fermeture timestamptz,
  p_duree_min int,
  -- [{emplacement, question_id}] : plusieurs questions par emplacement =
  -- variantes équivalentes.
  p_questions jsonb
)
returns public.manches_concours
language plpgsql security definer set search_path = public
as $$
declare
  v_c public.concours;
  v public.manches_concours;
begin
  select * into v_c from public.concours where id = p_concours;
  if not found or not public.organise_concours(v_c.etablissement_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if v_c.statut <> 'brouillon' and exists (select 1 from public.participations_manche where manche_id = p_id) then
    raise exception 'MANCHE_DEJA_COMMENCEE' using errcode = '22023';
  end if;
  if jsonb_typeof(p_questions) <> 'array' or jsonb_array_length(p_questions) = 0 then
    raise exception 'QUESTIONS_REQUISES' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(p_questions) x
              left join public.questions q on q.id = (x ->> 'question_id')::uuid
             where q.id is null or q.version_publiee is null) then
    raise exception 'QUESTION_NON_PUBLIEE' using errcode = '22023';
  end if;
  insert into public.manches_concours (id, concours_id, ordre, titre, ouverture, fermeture, duree_min)
  values (p_id, p_concours, p_ordre, btrim(p_titre), p_ouverture, p_fermeture, p_duree_min)
  on conflict (id) do update
    set ordre = excluded.ordre, titre = excluded.titre, ouverture = excluded.ouverture,
        fermeture = excluded.fermeture, duree_min = excluded.duree_min
  returning * into v;
  delete from public.manches_questions where manche_id = p_id;
  insert into public.manches_questions (manche_id, emplacement, question_id)
  select p_id, (x ->> 'emplacement')::int, (x ->> 'question_id')::uuid
    from jsonb_array_elements(p_questions) x
  on conflict do nothing;
  return v;
end;
$$;

-- Questions publiées utilisables dans un concours : niveaux de sa tranche,
-- de son pays (tous les pays si international). Pour composer les manches.
create or replace function public.questions_pour_concours(p_concours uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v public.concours;
begin
  select * into v from public.concours where id = p_concours;
  if not found or not public.organise_concours(v.etablissement_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(x order by x ->> 'pays', (x ->> 'grade')::int, x ->> 'matiere', x ->> 'enonce')
      from (
        select jsonb_build_object(
                 'id', q.id, 'pays', n.pays_code, 'grade', n.grade_level_normalise, 'niveau', n.nom,
                 'matiere', m.nom, 'enonce', left(qv.enonce, 200), 'type', qv.type, 'difficulte', qv.difficulte) as x
          from public.questions q
          join public.questions_versions qv on qv.question_id = q.id and qv.version = q.version_publiee
          join public.programmes_matieres m on m.id = q.matiere_id
          join public.programmes_officiels po on po.id = m.programme_id
          join public.niveaux_educatifs n on n.id = po.niveau_id
         where q.version_publiee is not null and q.suspendue_le is null
           and n.grade_level_normalise between v.grade_min and v.grade_max
           and (v.pays_code is null or n.pays_code = v.pays_code)
         limit 800) t), '[]'::jsonb);
end;
$$;

create or replace function public.changer_statut_concours(p_concours uuid, p_statut public.statut_concours)
returns public.concours
language plpgsql security definer set search_path = public
as $$
declare
  v public.concours;
begin
  select * into v from public.concours where id = p_concours for update;
  if not found or not public.organise_concours(v.etablissement_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_statut = 'ouvert' and not exists (select 1 from public.manches_concours where concours_id = p_concours) then
    raise exception 'MANCHE_REQUISE' using errcode = '22023';
  end if;
  update public.concours set statut = p_statut where id = p_concours returning * into v;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Concours d'un élève, inscription
-- ---------------------------------------------------------------------------
create or replace function public.concours_ouvert_a(p_concours public.concours, p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.situation_eleve(p_fiche) s
     where p_concours.statut in ('ouvert', 'termine')
       and s.grade between p_concours.grade_min and p_concours.grade_max
       and s.grade >= 1                                   -- jamais en maternelle (9.7.2)
       and (p_concours.pays_code is null or p_concours.pays_code = s.pays_code)
       and (p_concours.etablissement_id is null or p_concours.etablissement_id = s.etablissement_id)
  );
$$;
revoke all on function public.concours_ouvert_a(public.concours, uuid) from public, anon, authenticated;

create or replace function public.concours_eleve(p_fiche uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', c.id, 'titre', c.titre, 'description', c.description, 'type', c.type,
      'organisateur', coalesce((select e.nom from public.etablissements e where e.id = c.etablissement_id), 'Global Service Groupe'),
      'international', c.pays_code is null, 'pays_code', c.pays_code, 'recompenses', c.recompenses,
      'statut', c.statut, 'inscription_jusquau', c.inscription_jusquau,
      'inscrit', exists (select 1 from public.inscriptions_concours i where i.concours_id = c.id and i.fiche_eleve_id = p_fiche),
      'manches', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', m.id, 'ordre', m.ordre, 'titre', m.titre, 'ouverture', m.ouverture, 'fermeture', m.fermeture,
                 'duree_min', m.duree_min,
                 'questions', (select count(distinct mq.emplacement) from public.manches_questions mq where mq.manche_id = m.id),
                 'commencee', p.commence_le is not null, 'remise', p.remis_le is not null,
                 'score', p.score, 'hors_delai', p.hors_delai) order by m.ordre)
          from public.manches_concours m
          left join public.participations_manche p on p.manche_id = m.id and p.fiche_eleve_id = p_fiche
         where m.concours_id = c.id), '[]'::jsonb),
      'certificat', (select ce.code from public.certificats ce where ce.concours_id = c.id and ce.fiche_eleve_id = p_fiche
                       and not ce.revoque limit 1)
    ) order by c.statut, c.created_at desc)
      from public.concours c
     where public.concours_ouvert_a(c, p_fiche)
       and (c.statut = 'ouvert' or c.updated_at > now() - interval '120 days')), '[]'::jsonb);
end;
$$;

create or replace function public.inscrire_concours(p_concours uuid, p_fiche uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v public.concours;
  s record;
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select * into v from public.concours where id = p_concours;
  if not found or v.statut <> 'ouvert' or not public.concours_ouvert_a(v, p_fiche) then
    raise exception 'CONCOURS_FERME' using errcode = '22023';
  end if;
  if v.inscription_jusquau is not null and now() > v.inscription_jusquau then
    raise exception 'INSCRIPTIONS_CLOSES' using errcode = '22023';
  end if;
  select * into s from public.situation_eleve(p_fiche);
  insert into public.inscriptions_concours (concours_id, fiche_eleve_id, etablissement_id, pays_code, inscrit_par)
  values (p_concours, p_fiche, s.etablissement_id, s.pays_code, auth.uid())
  on conflict do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Correction par le serveur (mêmes règles que l'application)
-- ---------------------------------------------------------------------------
create or replace function public.normaliser_reponse(p text)
returns text
language sql immutable set search_path = public
as $$
  select btrim(regexp_replace(regexp_replace(
           translate(replace(replace(lower(coalesce(p, '')), 'œ', 'oe'), 'æ', 'ae'),
                     'àâäáéèêëîïíôöóùûüúçÿ', 'aaaaeeeeiiiooouuuucy'),
           '\s+', ' ', 'g'), '[.!?;:]+$', ''));
$$;

create or replace function public.corriger_reponse(
  p_type public.type_question,
  p_contenu jsonb,
  p_reponse jsonb,
  p_donnee jsonb
)
returns numeric
language plpgsql immutable set search_path = public
as $$
declare
  v_n int;
  v_justes int := 0;
  v_cle text;
  v_val jsonb;
  v_saisi numeric;
begin
  if p_donnee is null or jsonb_typeof(p_donnee) = 'null' then
    return 0;
  end if;
  case p_type
    when 'qcm_simple', 'qcm_multiple' then
      if jsonb_typeof(p_donnee) <> 'array' then return 0; end if;
      return case when (select coalesce(array_agg(distinct x order by x), '{}') from jsonb_array_elements_text(p_donnee) x)
                     = (select coalesce(array_agg(distinct x order by x), '{}') from jsonb_array_elements_text(p_reponse -> 'bonnes') x)
                  then 1 else 0 end;
    when 'vrai_faux' then
      return case when p_donnee = p_reponse -> 'valeur' then 1 else 0 end;
    when 'reponse_courte' then
      if jsonb_typeof(p_donnee) <> 'string' or public.normaliser_reponse(p_donnee #>> '{}') = '' then return 0; end if;
      return case when exists (select 1 from jsonb_array_elements_text(p_reponse -> 'acceptees') a
                                where public.normaliser_reponse(a) = public.normaliser_reponse(p_donnee #>> '{}'))
                  then 1 else 0 end;
    when 'texte_a_trous' then
      if jsonb_typeof(p_donnee) <> 'object' then return 0; end if;
      select count(*) into v_n from jsonb_object_keys(p_reponse -> 'trous');
      if v_n = 0 then return 0; end if;
      for v_cle, v_val in select key, value from jsonb_each(p_reponse -> 'trous') loop
        if public.normaliser_reponse(p_donnee ->> v_cle) <> '' and exists (
             select 1 from jsonb_array_elements_text(v_val) a
              where public.normaliser_reponse(a) = public.normaliser_reponse(p_donnee ->> v_cle)) then
          v_justes := v_justes + 1;
        end if;
      end loop;
      return round(v_justes::numeric / v_n, 3);
    when 'association' then
      if jsonb_typeof(p_donnee) <> 'object' then return 0; end if;
      select count(*), count(*) filter (where p_donnee ->> p.key = p.value)
        into v_n, v_justes from jsonb_each_text(p_reponse -> 'paires') p;
      return case when v_n = 0 then 0 else round(v_justes::numeric / v_n, 3) end;
    when 'classement' then
      if jsonb_typeof(p_donnee) <> 'array'
         or jsonb_array_length(p_donnee) <> jsonb_array_length(p_reponse -> 'ordre') then return 0; end if;
      select count(*), count(*) filter (where o.val = d.val)
        into v_n, v_justes
        from jsonb_array_elements_text(p_reponse -> 'ordre') with ordinality o(val, i)
        join jsonb_array_elements_text(p_donnee) with ordinality d(val, j) on d.j = o.i;
      return case when v_n = 0 then 0 else round(v_justes::numeric / v_n, 3) end;
    when 'calcul' then
      begin
        v_saisi := replace(regexp_replace(p_donnee #>> '{}', '[\s  ]', '', 'g'), ',', '.')::numeric;
      exception when others then
        return 0;
      end;
      return case when abs(v_saisi - (p_reponse ->> 'valeur')::numeric)
                       <= coalesce((p_reponse ->> 'tolerance')::numeric, 0) + 0.000000001 then 1 else 0 end;
  end case;
  return 0;
end;
$$;
grant execute on function public.normaliser_reponse(text) to authenticated;
grant execute on function public.corriger_reponse(public.type_question, jsonb, jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Participer à une manche
-- ---------------------------------------------------------------------------
-- Commence (ou reprend) la manche : une variante tirée par emplacement,
-- ordre mélangé, tirage stable pour cet élève. Renvoie les questions sans la
-- bonne réponse.
create or replace function public.commencer_manche(p_manche uuid, p_fiche uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_m public.manches_concours;
  v_c public.concours;
  v_p public.participations_manche;
  v_questions uuid[];
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select * into v_m from public.manches_concours where id = p_manche;
  select * into v_c from public.concours where id = v_m.concours_id;
  if v_m.id is null or v_c.statut <> 'ouvert' then
    raise exception 'CONCOURS_FERME' using errcode = '22023';
  end if;
  if not exists (select 1 from public.inscriptions_concours where concours_id = v_c.id and fiche_eleve_id = p_fiche) then
    raise exception 'NON_INSCRIT' using errcode = '22023';
  end if;
  select * into v_p from public.participations_manche where manche_id = p_manche and fiche_eleve_id = p_fiche;
  if found then
    if v_p.remis_le is not null then
      raise exception 'DEJA_REMIS' using errcode = '22023';
    end if;
    v_questions := v_p.questions;
  else
    if now() < v_m.ouverture then raise exception 'PAS_ENCORE_OUVERTE' using errcode = '22023'; end if;
    if now() > v_m.fermeture then raise exception 'MANCHE_FERMEE' using errcode = '22023'; end if;
    select array_agg(x.question_id order by md5(p_fiche::text || p_manche::text || 'ordre' || x.emplacement))
      into v_questions
      from (select distinct on (mq.emplacement) mq.emplacement, mq.question_id
              from public.manches_questions mq
              join public.questions q on q.id = mq.question_id and q.version_publiee is not null
             where mq.manche_id = p_manche
             order by mq.emplacement, md5(p_fiche::text || p_manche::text || mq.question_id::text)) x;
    if v_questions is null then raise exception 'QUESTIONS_REQUISES' using errcode = '22023'; end if;
    insert into public.participations_manche (manche_id, fiche_eleve_id, questions)
    values (p_manche, p_fiche, v_questions)
    returning * into v_p;
  end if;

  return jsonb_build_object(
    'commence_le', v_p.commence_le,
    'limite', least(v_p.commence_le + make_interval(mins => v_m.duree_min), v_m.fermeture),
    'questions', (
      select jsonb_agg(jsonb_build_object(
               'id', q.id, 'matiere_id', q.matiere_id, 'version', v.version, 'type', v.type, 'difficulte', v.difficulte,
               'competence_id', v.competence_id, 'enonce', v.enonce, 'contenu', v.contenu,
               'explication', '', 'reponse', '{}'::jsonb, 'media_chemin', v.media_chemin, 'media_type', v.media_type)
             order by t.i)
        from unnest(v_questions) with ordinality t(id, i)
        join public.questions q on q.id = t.id
        join public.questions_versions v on v.question_id = q.id and v.version = q.version_publiee)
  );
end;
$$;

-- Remet la copie : correction par le serveur, tentative de révision pour le
-- profil de maîtrise, puis correction détaillée renvoyée à l'élève.
create or replace function public.remettre_manche(p_manche uuid, p_fiche uuid, p_reponses jsonb)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_m public.manches_concours;
  v_p public.participations_manche;
  v_limite timestamptz;
  v_score numeric := 0;
  v_n int;
  v_duree int;
  v_t uuid := gen_random_uuid();
  v_detail jsonb;
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select * into v_m from public.manches_concours where id = p_manche;
  select * into v_p from public.participations_manche where manche_id = p_manche and fiche_eleve_id = p_fiche for update;
  if not found then raise exception 'NON_COMMENCEE' using errcode = '22023'; end if;
  if v_p.remis_le is not null then
    return jsonb_build_object('score', v_p.score, 'questions', array_length(v_p.questions, 1), 'deja_remis', true);
  end if;

  v_limite := least(v_p.commence_le + make_interval(mins => v_m.duree_min), v_m.fermeture);
  v_n := array_length(v_p.questions, 1);
  v_duree := greatest(0, extract(epoch from (least(now(), v_limite) - v_p.commence_le))::int);

  select coalesce(jsonb_agg(jsonb_build_object(
           'question_id', q.id, 'version', v.version, 'ordre', t.i - 1,
           'score', public.corriger_reponse(v.type, v.contenu, v.reponse, p_reponses -> q.id::text),
           'reponse', p_reponses -> q.id::text) order by t.i), '[]'::jsonb)
    into v_detail
    from unnest(v_p.questions) with ordinality t(id, i)
    join public.questions q on q.id = t.id
    join public.questions_versions v on v.question_id = q.id and v.version = q.version_publiee;
  select coalesce(sum((d ->> 'score')::numeric), 0) into v_score from jsonb_array_elements(v_detail) d;

  update public.participations_manche
     set remis_le = now(), reponses = p_reponses, score = v_score, duree_s = v_duree,
         -- 5 minutes de grâce (réseau) au-delà de la limite.
         hors_delai = now() > v_limite + interval '5 minutes',
         suspect = v_n >= 5 and v_duree < 2 * v_n and v_score >= 0.9 * v_n
   where manche_id = p_manche and fiche_eleve_id = p_fiche;

  -- Le profil de maîtrise et la répétition espacée en profitent aussi.
  insert into public.tentatives_revision (id, fiche_eleve_id, joue_par, mode, nb_questions, nb_repondues, points,
                                          duree_s, termine, commence_le, termine_le)
  values (v_t, p_fiche, auth.uid(), 'concours', greatest(1, least(50, v_n)), least(50, v_n), v_score,
          v_duree, true, v_p.commence_le, now());
  insert into public.reponses_revision (tentative_id, question_id, version, ordre, score, reponse)
  select v_t, (d ->> 'question_id')::uuid, (d ->> 'version')::int, (d ->> 'ordre')::int,
         (d ->> 'score')::numeric, d -> 'reponse'
    from jsonb_array_elements(v_detail) d
  on conflict do nothing;

  return jsonb_build_object(
    'score', v_score, 'questions', v_n, 'duree_s', v_duree,
    'hors_delai', now() > v_limite + interval '5 minutes',
    'correction', (
      select jsonb_agg(jsonb_build_object(
               'question_id', d ->> 'question_id', 'score', (d ->> 'score')::numeric,
               'reponse', v.reponse, 'explication', v.explication) order by (d ->> 'ordre')::int)
        from jsonb_array_elements(v_detail) d
        join public.questions_versions v on v.question_id = (d ->> 'question_id')::uuid and v.version = (d ->> 'version')::int)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Classement (23.1, 23.4)
-- ---------------------------------------------------------------------------
create or replace function public.classement_concours(
  p_concours uuid,
  p_fiche uuid default null,
  p_pays text default null,
  p_etablissement uuid default null
)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_c public.concours;
  v_organisateur boolean;
begin
  select * into v_c from public.concours where id = p_concours;
  if not found then raise exception 'CONCOURS_INTROUVABLE' using errcode = '22023'; end if;
  v_organisateur := public.organise_concours(v_c.etablissement_id);
  if not v_organisateur and not (p_fiche is not null and public.peut_reviser_pour(p_fiche)
         and exists (select 1 from public.inscriptions_concours i where i.concours_id = p_concours and i.fiche_eleve_id = p_fiche)) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  return (
    with totaux as (
      select i.fiche_eleve_id, i.pays_code, i.etablissement_id,
             sum(p.score) as score, sum(p.duree_s) as duree, count(p.remis_le) as manches,
             bool_or(p.suspect and not p.rehabilite) as en_verification,
             bool_or(p.hors_delai) as hors_delai
        from public.inscriptions_concours i
        join public.participations_manche p on p.fiche_eleve_id = i.fiche_eleve_id
        join public.manches_concours m on m.id = p.manche_id and m.concours_id = p_concours
       where i.concours_id = p_concours and p.remis_le is not null
         and (p_pays is null or i.pays_code = p_pays)
         and (p_etablissement is null or i.etablissement_id = p_etablissement)
       group by i.fiche_eleve_id, i.pays_code, i.etablissement_id
    ),
    publics as (
      select t.*, rank() over (order by t.score desc, t.duree asc) as rang
        from totaux t where not t.en_verification and not t.hors_delai
    )
    select jsonb_build_object(
      'concours', v_c.titre,
      'participants', (select count(*) from publics),
      -- Situation de l'élève, pour filtrer « mon pays », « mon école ».
      'mon_pays', (select i.pays_code from public.inscriptions_concours i
                    where i.concours_id = p_concours and i.fiche_eleve_id = p_fiche),
      'mon_etablissement', (select i.etablissement_id from public.inscriptions_concours i
                             where i.concours_id = p_concours and i.fiche_eleve_id = p_fiche),
      'en_verification', case when v_organisateur
                              then (select count(*) from totaux where en_verification) else null end,
      'lignes', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'rang', p.rang,
                 'nom', case when coalesce(pr.classement_visible, true) or v_organisateur
                             then f.prenom || ' ' || left(coalesce(f.nom, ''), 1) || '.' else 'Participant' end,
                 'ecole', e.nom, 'pays', p.pays_code, 'score', round(p.score, 2), 'duree_s', p.duree,
                 'moi', p.fiche_eleve_id = p_fiche) order by p.rang)
          from publics p
          join public.fiches_eleves f on f.id = p.fiche_eleve_id
          left join public.etablissements e on e.id = p.etablissement_id
          left join public.preferences_revision pr on pr.fiche_eleve_id = p.fiche_eleve_id
         where p.rang <= 20 or p.fiche_eleve_id = p_fiche), '[]'::jsonb),
      'a_verifier', case when v_organisateur then coalesce((
        select jsonb_agg(jsonb_build_object('fiche_eleve_id', t.fiche_eleve_id, 'nom', f.prenom || ' ' || f.nom,
                                            'score', round(t.score, 2), 'duree_s', t.duree))
          from totaux t join public.fiches_eleves f on f.id = t.fiche_eleve_id
         where t.en_verification), '[]'::jsonb) else null end
    )
  );
end;
$$;

-- L'organisateur rétablit une copie écartée après vérification (23.4).
create or replace function public.rehabiliter_participation(p_concours uuid, p_fiche uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_c public.concours;
begin
  select * into v_c from public.concours where id = p_concours;
  if not found or not public.organise_concours(v_c.etablissement_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  update public.participations_manche p set rehabilite = true
    from public.manches_concours m
   where m.id = p.manche_id and m.concours_id = p_concours and p.fiche_eleve_id = p_fiche;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Certificats de maîtrise (23.3)
-- ---------------------------------------------------------------------------
create table if not exists public.certificats (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  concours_id uuid references public.concours (id) on delete set null,
  titre text not null,
  prenom text not null,
  initiale text not null,
  mention text not null,
  reussite int not null check (reussite between 0 and 100),
  rang int,
  participants int,
  delivre_par text not null,
  delivre_le timestamptz not null default now(),
  revoque boolean not null default false,
  constraint certificats_un_par_concours unique (concours_id, fiche_eleve_id)
);
alter table public.certificats enable row level security;
revoke insert, update, delete on public.certificats from anon, authenticated;
drop policy if exists certificats_select on public.certificats;
create policy certificats_select on public.certificats for select to authenticated
  using (public.peut_reviser_pour(fiche_eleve_id));

create or replace function public.code_certificat()
returns text
language sql volatile set search_path = public
as $$
  -- 12 caractères sans ambiguïté (pas de 0/O ni 1/I) : GSG-XXXX-XXXX-XXXX.
  select 'GSG-' || string_agg(substr('23456789ABCDEFGHJKLMNPQRSTUVWXYZ', 1 + floor(random() * 32)::int, 1)
                              || case when g in (4, 8) then '-' else '' end, '' order by g)
    from generate_series(1, 12) g;
$$;

create or replace function public.delivrer_certificats(p_concours uuid)
returns int
language plpgsql security definer set search_path = public
as $$
declare
  v_c public.concours;
  v_nb_manches int;
  r record;
  v_n int := 0;
  v_participants int;
begin
  select * into v_c from public.concours where id = p_concours for update;
  if not found or not public.organise_concours(v_c.etablissement_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if v_c.statut <> 'termine' then
    raise exception 'CONCOURS_NON_TERMINE' using errcode = '22023';
  end if;
  select count(*) into v_nb_manches from public.manches_concours where concours_id = p_concours;

  for r in
    with t as (
      select p.fiche_eleve_id, sum(p.score) as score, sum(p.duree_s) as duree, count(*) as manches,
             sum(array_length(p.questions, 1)) as questions,
             bool_or(p.suspect and not p.rehabilite) or bool_or(p.hors_delai) as ecarte
        from public.participations_manche p
        join public.manches_concours m on m.id = p.manche_id and m.concours_id = p_concours
       where p.remis_le is not null
       group by p.fiche_eleve_id
    )
    select t.*, rank() over (order by t.score desc, t.duree) as rang, count(*) over () as total,
           round(100 * t.score / greatest(t.questions, 1))::int as pct
      from t where not t.ecarte and t.manches = v_nb_manches
  loop
    v_participants := r.total;
    continue when r.pct < v_c.seuil_certificat;
    insert into public.certificats (code, fiche_eleve_id, concours_id, titre, prenom, initiale, mention, reussite,
                                    rang, participants, delivre_par)
    select public.code_certificat(), r.fiche_eleve_id, p_concours, v_c.titre, f.prenom, left(coalesce(f.nom, ''), 1),
           case when r.pct >= 90 then 'Excellence' when r.pct >= 75 then 'Très bien'
                when r.pct >= 60 then 'Bien' else 'Réussite' end,
           r.pct, r.rang, r.total,
           coalesce((select e.nom from public.etablissements e where e.id = v_c.etablissement_id), 'Global Service Groupe')
      from public.fiches_eleves f where f.id = r.fiche_eleve_id
    on conflict (concours_id, fiche_eleve_id) do nothing;
    if found then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end;
$$;

-- Vérification publique, sans compte (tiers : école, employeur,
-- organisateur). Ne révèle que ce qui figure sur le certificat.
create or replace function public.verifier_certificat(p_code text)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce((
    select jsonb_build_object(
      'valide', not c.revoque, 'revoque', c.revoque, 'code', c.code, 'titre', c.titre,
      'titulaire', c.prenom || ' ' || c.initiale || '.', 'mention', c.mention, 'reussite', c.reussite,
      'rang', c.rang, 'participants', c.participants, 'delivre_par', c.delivre_par, 'delivre_le', c.delivre_le)
      from public.certificats c
     where c.code = upper(btrim(p_code))), jsonb_build_object('valide', false, 'inconnu', true));
$$;

revoke all on function public.organise_concours(uuid) from public, anon;
revoke all on function public.enregistrer_concours(uuid, text, public.type_concours, uuid, text, int, int, text, text, timestamptz, int) from public, anon;
revoke all on function public.enregistrer_manche(uuid, uuid, int, text, timestamptz, timestamptz, int, jsonb) from public, anon;
revoke all on function public.changer_statut_concours(uuid, public.statut_concours) from public, anon;
revoke all on function public.questions_pour_concours(uuid) from public, anon;
revoke all on function public.concours_eleve(uuid) from public, anon;
revoke all on function public.inscrire_concours(uuid, uuid) from public, anon;
revoke all on function public.commencer_manche(uuid, uuid) from public, anon;
revoke all on function public.remettre_manche(uuid, uuid, jsonb) from public, anon;
revoke all on function public.classement_concours(uuid, uuid, text, uuid) from public, anon;
revoke all on function public.rehabiliter_participation(uuid, uuid) from public, anon;
revoke all on function public.delivrer_certificats(uuid) from public, anon;
revoke all on function public.code_certificat() from public, anon, authenticated;
grant execute on function public.organise_concours(uuid) to authenticated;
grant execute on function public.enregistrer_concours(uuid, text, public.type_concours, uuid, text, int, int, text, text, timestamptz, int) to authenticated;
grant execute on function public.enregistrer_manche(uuid, uuid, int, text, timestamptz, timestamptz, int, jsonb) to authenticated;
grant execute on function public.changer_statut_concours(uuid, public.statut_concours) to authenticated;
grant execute on function public.questions_pour_concours(uuid) to authenticated;
grant execute on function public.concours_eleve(uuid) to authenticated;
grant execute on function public.inscrire_concours(uuid, uuid) to authenticated;
grant execute on function public.commencer_manche(uuid, uuid) to authenticated;
grant execute on function public.remettre_manche(uuid, uuid, jsonb) to authenticated;
grant execute on function public.classement_concours(uuid, uuid, text, uuid) to authenticated;
grant execute on function public.rehabiliter_participation(uuid, uuid) to authenticated;
grant execute on function public.delivrer_certificats(uuid) to authenticated;
grant execute on function public.verifier_certificat(text) to anon, authenticated;
