-- ============================================================================
-- EcoShop — REG-37 lot R2 : quiz et entraînement hors connexion (cahier 11.1)
-- ============================================================================
-- Recherche et choix : document repère, « Moteur de révision — synthèse de
-- recherche pour le lot R2 ».
--
-- 1. Paquet de révision par niveau : matières du programme officiel,
--    chapitres, compétences et questions publiées (version diffusée), avec
--    une empreinte ; le téléphone ne retélécharge que si elle a changé.
-- 2. Tentatives : chaque quiz, terminé ou abandonné, est enregistré avec ses
--    réponses (identifiant tiré sur l'appareil : jamais en double). Un quiz
--    abandonné compte dans le temps de travail, pas dans la réussite (11.1).
-- 3. Résumé pour l'élève et le parent : temps, quiz, réussite par matière,
--    compétences à revoir.
--
-- Qui révise pour une fiche : l'élève lui-même ou un parent confirmé (« Réviser
-- avec mon enfant » sur le téléphone du parent). Résultats formatifs : jamais
-- dans la moyenne ni le bulletin (12.6).
-- ============================================================================

create or replace function public.peut_reviser_pour(p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.fiches_eleves f where f.id = p_fiche and f.profile_id = auth.uid())
      or coalesce(public.est_parent_confirme(p_fiche), false);
$$;

-- Niveau (et série) de l'élève : classe de son inscription la plus récente.
create or replace function public.niveau_revision_fiche(p_fiche uuid)
returns table (niveau_id uuid, filiere_id uuid, niveau_nom text, pays_code text, grade int)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return query
    select c.niveau_id, c.filiere_id, n.nom, n.pays_code, n.grade_level_normalise
      from public.inscriptions i
      join public.classes c on c.id = i.classe_id
      join public.annees_scolaires a on a.id = i.annee_scolaire_id
      join public.niveaux_educatifs n on n.id = c.niveau_id
     where i.fiche_eleve_id = p_fiche and i.deleted_at is null and i.statut = 'active'
     order by a.date_debut desc
     limit 1;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Paquet de révision d'un niveau
-- ---------------------------------------------------------------------------
create or replace function public.paquet_revision(
  p_niveau uuid,
  p_filiere uuid default null,
  p_empreinte text default null
)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_matieres uuid[];
  v_empreinte text;
begin
  if auth.uid() is null then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;

  -- Matières du programme officiel du niveau (tronc commun et série).
  select array_agg(m.id) into v_matieres
    from public.programmes_matieres m
    join public.programmes_officiels p on p.id = m.programme_id
   where p.niveau_id = p_niveau and p.etablissement_id is null and p.statut = 'publie'
     and (p.filiere_id is null or p.filiere_id = p_filiere);

  select md5(coalesce(string_agg(q.id::text || ':' || q.version_publiee, ',' order by q.id), '')
             || coalesce((select string_agg(c.id::text || c.titre, ',' order by c.id)
                            from public.chapitres_matiere c where c.matiere_id = any (v_matieres)), '')
             || coalesce((select string_agg(k.id::text || k.libelle, ',' order by k.id)
                            from public.competences_matiere k where k.matiere_id = any (v_matieres)), ''))
    into v_empreinte
    from public.questions q
   where q.matiere_id = any (v_matieres) and q.version_publiee is not null and q.suspendue_le is null;

  if p_empreinte is not null and p_empreinte = v_empreinte then
    return jsonb_build_object('empreinte', v_empreinte, 'inchange', true);
  end if;

  return jsonb_build_object(
    'empreinte', v_empreinte,
    'inchange', false,
    'matieres', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'code', m.code, 'nom', m.nom) order by m.ordre, m.nom)
        from public.programmes_matieres m where m.id = any (v_matieres)), '[]'::jsonb),
    'chapitres', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'matiere_id', c.matiere_id, 'titre', c.titre, 'ordre', c.ordre)
                       order by c.ordre)
        from public.chapitres_matiere c where c.matiere_id = any (v_matieres)), '[]'::jsonb),
    'competences', coalesce((
      select jsonb_agg(jsonb_build_object('id', k.id, 'matiere_id', k.matiere_id, 'code', k.code, 'libelle', k.libelle))
        from public.competences_matiere k where k.matiere_id = any (v_matieres)), '[]'::jsonb),
    'questions', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', q.id, 'matiere_id', q.matiere_id, 'version', v.version, 'type', v.type,
               'difficulte', v.difficulte, 'chapitre_id', v.chapitre_id, 'lecon_id', v.lecon_id,
               'competence_id', v.competence_id, 'enonce', v.enonce, 'contenu', v.contenu,
               'reponse', v.reponse, 'explication', v.explication,
               'temps_recommande_s', v.temps_recommande_s, 'media_chemin', v.media_chemin,
               'media_type', v.media_type))
        from public.questions q
        join public.questions_versions v on v.question_id = q.id and v.version = q.version_publiee
       where q.matiere_id = any (v_matieres) and q.suspendue_le is null), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Tentatives et réponses
-- ---------------------------------------------------------------------------
create table if not exists public.tentatives_revision (
  id uuid primary key,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  joue_par uuid references public.profiles (id) on delete set null,
  mode text not null check (mode in ('rapide', 'standard', 'intensif', 'chapitre', 'matiere', 'melange', 'personnalise', 'erreurs')),
  matiere_id uuid references public.programmes_matieres (id) on delete set null,
  chapitre_id uuid references public.chapitres_matiere (id) on delete set null,
  nb_questions int not null check (nb_questions between 1 and 50),
  nb_repondues int not null check (nb_repondues between 0 and 50),
  points numeric(6, 3) not null default 0 check (points >= 0),
  duree_s int not null default 0 check (duree_s between 0 and 86400),
  termine boolean not null,
  commence_le timestamptz not null,
  termine_le timestamptz,
  recu_le timestamptz not null default now()
);
create index if not exists idx_tentatives_revision_fiche on public.tentatives_revision (fiche_eleve_id, commence_le desc);

create table if not exists public.reponses_revision (
  tentative_id uuid not null references public.tentatives_revision (id) on delete cascade,
  question_id uuid not null references public.questions (id) on delete cascade,
  version int not null,
  ordre int not null,
  score numeric(4, 3) not null check (score between 0 and 1),
  duree_s int not null default 0,
  reponse jsonb,
  primary key (tentative_id, question_id)
);
create index if not exists idx_reponses_revision_question on public.reponses_revision (question_id);

alter table public.tentatives_revision enable row level security;
alter table public.reponses_revision enable row level security;
revoke insert, update, delete on public.tentatives_revision, public.reponses_revision from anon, authenticated;

drop policy if exists tentatives_revision_select on public.tentatives_revision;
create policy tentatives_revision_select on public.tentatives_revision for select to authenticated
  using (public.peut_reviser_pour(fiche_eleve_id));
drop policy if exists reponses_revision_select on public.reponses_revision;
create policy reponses_revision_select on public.reponses_revision for select to authenticated
  using (exists (select 1 from public.tentatives_revision t
                  where t.id = tentative_id and public.peut_reviser_pour(t.fiche_eleve_id)));

-- p_tentative : {id, fiche_eleve_id, mode, matiere_id, chapitre_id,
--   nb_questions, duree_s, termine, commence_le, termine_le,
--   reponses: [{question_id, version, ordre, score, duree_s, reponse}]}
create or replace function public.enregistrer_tentative_revision(p_tentative jsonb)
returns boolean   -- vrai si nouvelle, faux si déjà reçue
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid := (p_tentative ->> 'id')::uuid;
  v_fiche uuid := (p_tentative ->> 'fiche_eleve_id')::uuid;
  v_reponses jsonb := coalesce(p_tentative -> 'reponses', '[]'::jsonb);
begin
  if v_id is null or v_fiche is null then
    raise exception 'TENTATIVE_INVALIDE' using errcode = '22023';
  end if;
  if not public.peut_reviser_pour(v_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if exists (select 1 from public.tentatives_revision where id = v_id) then
    return false;                                   -- rejeu après une coupure
  end if;
  if jsonb_typeof(v_reponses) <> 'array' or jsonb_array_length(v_reponses) > 50 then
    raise exception 'TENTATIVE_INVALIDE' using errcode = '22023';
  end if;

  insert into public.tentatives_revision (
    id, fiche_eleve_id, joue_par, mode, matiere_id, chapitre_id, nb_questions, nb_repondues, points,
    duree_s, termine, commence_le, termine_le
  ) values (
    v_id, v_fiche, auth.uid(), p_tentative ->> 'mode',
    (select m.id from public.programmes_matieres m where m.id = (p_tentative ->> 'matiere_id')::uuid),
    (select c.id from public.chapitres_matiere c where c.id = (p_tentative ->> 'chapitre_id')::uuid),
    greatest(1, least(50, coalesce((p_tentative ->> 'nb_questions')::int, jsonb_array_length(v_reponses)))),
    jsonb_array_length(v_reponses),
    coalesce((select sum(least(1, greatest(0, (r ->> 'score')::numeric))) from jsonb_array_elements(v_reponses) r), 0),
    least(86400, greatest(0, coalesce((p_tentative ->> 'duree_s')::int, 0))),
    coalesce((p_tentative ->> 'termine')::boolean, false),
    coalesce((p_tentative ->> 'commence_le')::timestamptz, now()),
    (p_tentative ->> 'termine_le')::timestamptz
  );

  -- Réponses aux questions qui existent encore (une question retirée entre
  -- le quiz et l'envoi est ignorée sans bloquer la tentative).
  insert into public.reponses_revision (tentative_id, question_id, version, ordre, score, duree_s, reponse)
  select v_id, (r ->> 'question_id')::uuid, coalesce((r ->> 'version')::int, 1), coalesce((r ->> 'ordre')::int, 0),
         least(1, greatest(0, coalesce((r ->> 'score')::numeric, 0))),
         least(3600, greatest(0, coalesce((r ->> 'duree_s')::int, 0))), r -> 'reponse'
    from jsonb_array_elements(v_reponses) r
   where exists (select 1 from public.questions q where q.id = (r ->> 'question_id')::uuid)
  on conflict do nothing;
  return true;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Résumé pour l'élève et le parent
-- ---------------------------------------------------------------------------
create or replace function public.resume_revision(p_fiche uuid, p_jours int default 30)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_depuis timestamptz := now() - make_interval(days => greatest(1, least(365, coalesce(p_jours, 30))));
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'jours', greatest(1, least(365, coalesce(p_jours, 30))),
    'temps_s', coalesce((select sum(duree_s) from public.tentatives_revision
                          where fiche_eleve_id = p_fiche and commence_le >= v_depuis), 0),
    'quiz_termines', (select count(*) from public.tentatives_revision
                       where fiche_eleve_id = p_fiche and termine and commence_le >= v_depuis),
    'questions', coalesce((select sum(nb_repondues) from public.tentatives_revision
                            where fiche_eleve_id = p_fiche and termine and commence_le >= v_depuis), 0),
    'points', coalesce((select sum(points) from public.tentatives_revision
                         where fiche_eleve_id = p_fiche and termine and commence_le >= v_depuis), 0),
    'derniere_activite', (select max(commence_le) from public.tentatives_revision where fiche_eleve_id = p_fiche),
    'par_matiere', coalesce((
      select jsonb_agg(jsonb_build_object('matiere_id', x.matiere_id, 'reponses', x.n, 'points', x.p))
        from (select q.matiere_id, count(*) as n, sum(r.score) as p
                from public.reponses_revision r
                join public.tentatives_revision t on t.id = r.tentative_id
                join public.questions q on q.id = r.question_id
               where t.fiche_eleve_id = p_fiche and t.termine and t.commence_le >= v_depuis
               group by q.matiere_id) x), '[]'::jsonb),
    -- Cinq dernières réponses par compétence (étiquette « à revoir », « en
    -- progrès », « solide » calculée par l'application, comme Kolibri).
    'competences', coalesce((
      select jsonb_agg(jsonb_build_object('competence_id', y.competence_id, 'scores', y.scores))
        from (select z.competence_id, jsonb_agg(z.score order by z.quand desc) as scores
                from (select v.competence_id, r.score, t.commence_le + make_interval(secs => r.ordre) as quand,
                             row_number() over (partition by v.competence_id
                                                order by t.commence_le desc, r.ordre desc) as rang
                        from public.reponses_revision r
                        join public.tentatives_revision t on t.id = r.tentative_id
                        join public.questions_versions v on v.question_id = r.question_id and v.version = r.version
                       where t.fiche_eleve_id = p_fiche and t.termine) z
               where z.rang <= 5
               group by z.competence_id) y), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.peut_reviser_pour(uuid) from public, anon;
revoke all on function public.niveau_revision_fiche(uuid) from public, anon;
revoke all on function public.paquet_revision(uuid, uuid, text) from public, anon;
revoke all on function public.enregistrer_tentative_revision(jsonb) from public, anon;
revoke all on function public.resume_revision(uuid, int) from public, anon;
grant execute on function public.peut_reviser_pour(uuid) to authenticated;
grant execute on function public.niveau_revision_fiche(uuid) to authenticated;
grant execute on function public.paquet_revision(uuid, uuid, text) to authenticated;
grant execute on function public.enregistrer_tentative_revision(jsonb) to authenticated;
grant execute on function public.resume_revision(uuid, int) to authenticated;
