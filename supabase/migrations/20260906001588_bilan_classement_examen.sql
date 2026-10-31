-- ============================================================================
-- EcoShop — REG-37 : bilan hebdomadaire au parent (R2b), classement de la
-- semaine (cahier 22.1, 22.3, 23.1, 23.4) et mode examen (R3, cahier 11.2)
-- ============================================================================
-- 1. Bilan du dimanche soir au parent (notification de l'application) :
--    temps, quiz, réussite, une compétence à travailler et une action
--    concrète (J-PAL ; Côte d'Ivoire : les messages aux parents aident
--    surtout les élèves en difficulté).
-- 2. Classement de la semaine, par classe ou par école, sur des points
--    d'effort (barème du cahier 22.1 : +10 par bonne réponse, +50 par quiz
--    terminé, +100 par examen terminé), remis à zéro chaque lundi (ligues de
--    Duolingo). Vue relative : les 5 premiers, puis l'élève et ses voisins.
--    Garde-fous : prénom et initiale seulement ; l'élève ou son parent peut
--    se retirer ; désactivé du CP1 au CE2 et en maternelle (22.3) ; une
--    tentative trop rapide et trop parfaite est écartée du classement
--    public (23.4) sans rien retirer à l'élève.
-- 3. Mode examen : nouvelle valeur de mode des tentatives.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 3. Mode examen
-- ---------------------------------------------------------------------------
alter table public.tentatives_revision drop constraint if exists tentatives_revision_mode_check;
alter table public.tentatives_revision add constraint tentatives_revision_mode_check
  check (mode in ('rapide', 'standard', 'intensif', 'chapitre', 'matiere', 'melange', 'personnalise', 'erreurs', 'examen'));

-- ---------------------------------------------------------------------------
-- 2. Classement de la semaine
-- ---------------------------------------------------------------------------
create table if not exists public.preferences_revision (
  fiche_eleve_id uuid primary key references public.fiches_eleves (id) on delete cascade,
  classement_visible boolean not null default true,
  modifie_par uuid references public.profiles (id) on delete set null,
  modifie_le timestamptz not null default now()
);
alter table public.preferences_revision enable row level security;
revoke insert, update, delete on public.preferences_revision from anon, authenticated;
drop policy if exists preferences_revision_select on public.preferences_revision;
create policy preferences_revision_select on public.preferences_revision for select to authenticated
  using (public.peut_reviser_pour(fiche_eleve_id));

create or replace function public.definir_classement_visible(p_fiche uuid, p_visible boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  insert into public.preferences_revision (fiche_eleve_id, classement_visible, modifie_par)
  values (p_fiche, coalesce(p_visible, true), auth.uid())
  on conflict (fiche_eleve_id) do update
    set classement_visible = excluded.classement_visible, modifie_par = auth.uid(), modifie_le = now();
end;
$$;

-- Points d'effort d'une tentative (barème 22.1), 0 si elle est écartée du
-- classement public : en moyenne moins de 2 secondes par question avec 90 %
-- de réussite ou plus, sur au moins 5 réponses (23.4).
create or replace function public.points_effort(t public.tentatives_revision)
returns int
language sql stable set search_path = public
as $$
  select case
    when t.nb_repondues >= 5 and t.duree_s < 2 * t.nb_repondues and t.points >= 0.9 * t.nb_repondues then 0
    else (select count(*)::int * 10 from public.reponses_revision r where r.tentative_id = t.id and r.score >= 1)
         + case when t.termine and t.mode = 'examen' then 100 when t.termine then 50 else 0 end
  end;
$$;

-- Début de la semaine (lundi 00:00, heure de Conakry = UTC).
create or replace function public.debut_semaine_revision(p_quand timestamptz default now())
returns timestamptz
language sql immutable set search_path = public
as $$ select date_trunc('week', p_quand at time zone 'UTC') at time zone 'UTC'; $$;

create or replace function public.classement_revision(p_fiche uuid, p_echelle text default 'classe')
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_classe uuid;
  v_annee uuid;
  v_ecole uuid;
  v_grade int;
  v_debut timestamptz := public.debut_semaine_revision();
  v_lignes jsonb;
  v_moi boolean;
  v_rang int;
  v_total int;
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_echelle not in ('classe', 'etablissement') then
    raise exception 'ECHELLE_INCONNUE' using errcode = '22023';
  end if;

  select i.classe_id, i.annee_scolaire_id, i.etablissement_id, n.grade_level_normalise
    into v_classe, v_annee, v_ecole, v_grade
    from public.inscriptions i
    join public.classes c on c.id = i.classe_id
    join public.annees_scolaires a on a.id = i.annee_scolaire_id
    left join public.niveaux_educatifs n on n.id = c.niveau_id
   where i.fiche_eleve_id = p_fiche and i.deleted_at is null and i.statut = 'active'
   order by a.date_debut desc
   limit 1;
  if v_classe is null then
    return jsonb_build_object('actif', false, 'raison', 'SANS_CLASSE');
  end if;
  if coalesce(v_grade, 99) <= 4 then
    return jsonb_build_object('actif', false, 'raison', 'PETITES_CLASSES');
  end if;

  with eleves as (
    -- Élèves rattachés à la classe (ou à l'école) pour l'année en cours,
    -- du CM1 au moins (23.1, 22.3).
    select i.fiche_eleve_id
      from public.inscriptions i
      join public.classes c on c.id = i.classe_id
      left join public.niveaux_educatifs n on n.id = c.niveau_id
     where i.annee_scolaire_id = v_annee and i.deleted_at is null and i.statut = 'active'
       and (case when p_echelle = 'classe' then i.classe_id = v_classe else i.etablissement_id = v_ecole end)
       and coalesce(n.grade_level_normalise, 99) > 4
  ),
  points as (
    select e.fiche_eleve_id,
           coalesce(sum(public.points_effort(t)), 0)::int as points,
           count(t.id) filter (where t.termine) as quiz
      from eleves e
      left join public.tentatives_revision t on t.fiche_eleve_id = e.fiche_eleve_id and t.commence_le >= v_debut
     group by e.fiche_eleve_id
  ),
  visibles as (
    select p.*, f.prenom, left(coalesce(f.nom, ''), 1) as initiale
      from points p
      join public.fiches_eleves f on f.id = p.fiche_eleve_id
      left join public.preferences_revision pr on pr.fiche_eleve_id = p.fiche_eleve_id
     where coalesce(pr.classement_visible, true) and p.points > 0
  ),
  classes as (
    select v.*, rank() over (order by v.points desc) as rang from visibles v
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'rang', c.rang, 'nom', c.prenom || ' ' || c.initiale || '.', 'points', c.points, 'quiz', c.quiz,
           'moi', c.fiche_eleve_id = p_fiche) order by c.rang, c.prenom), '[]'::jsonb),
         max(c.rang) filter (where c.fiche_eleve_id = p_fiche),
         count(*)
    into v_lignes, v_rang, v_total
    from classes c;

  -- Les 5 premiers, puis l'élève et ses deux voisins de chaque côté.
  select coalesce(jsonb_agg(x order by (x ->> 'rang')::int, x ->> 'nom'), '[]'::jsonb) into v_lignes
    from jsonb_array_elements(v_lignes) with ordinality as l(x, i)
   where i <= 5
      or (v_rang is not null and exists (
            select 1 from jsonb_array_elements(v_lignes) with ordinality as m(y, j)
             where (y ->> 'moi')::boolean and abs(j - i) <= 2));

  select coalesce((select classement_visible from public.preferences_revision where fiche_eleve_id = p_fiche), true)
    into v_moi;
  return jsonb_build_object(
    'actif', true,
    'echelle', p_echelle,
    'debut', v_debut,
    'lignes', v_lignes,
    'mon_rang', v_rang,
    'participants', v_total,
    'visible', v_moi,
    'mes_points', coalesce((select sum(public.points_effort(t)) from public.tentatives_revision t
                             where t.fiche_eleve_id = p_fiche and t.commence_le >= v_debut), 0)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Bilan hebdomadaire au parent
-- ---------------------------------------------------------------------------
create or replace function public.texte_bilan_revision(p_fiche uuid, p_depuis timestamptz)
returns text
language plpgsql stable security definer set search_path = public
as $$
declare
  v_prenom text;
  v_temps int;
  v_quiz int;
  v_questions numeric;
  v_points numeric;
  v_faible text;
  v_minutes int;
begin
  select prenom into v_prenom from public.fiches_eleves where id = p_fiche;
  select coalesce(sum(duree_s), 0),
         count(*) filter (where termine),
         coalesce(sum(nb_repondues) filter (where termine), 0),
         coalesce(sum(points) filter (where termine), 0)
    into v_temps, v_quiz, v_questions, v_points
    from public.tentatives_revision
   where fiche_eleve_id = p_fiche and commence_le >= p_depuis;

  if v_temps = 0 then
    return format('%s n''a pas révisé cette semaine. Un quiz rapide de 5 questions ce soir, ensemble, suffit à reprendre : '
                  'ouvrez « Réviser » dans EcoShop.', v_prenom);
  end if;

  select k.libelle into v_faible
    from public.reponses_revision r
    join public.tentatives_revision t on t.id = r.tentative_id
    join public.questions_versions v on v.question_id = r.question_id and v.version = r.version
    join public.competences_matiere k on k.id = v.competence_id
   where t.fiche_eleve_id = p_fiche and t.termine and t.commence_le >= p_depuis
   group by k.libelle
  having count(*) >= 3 and avg(r.score) < 0.5
   order by avg(r.score), count(*) desc
   limit 1;

  v_minutes := greatest(1, round(v_temps / 60.0));
  return format('Cette semaine, %s a révisé %s min : %s quiz terminé%s%s.%s',
    v_prenom, v_minutes, v_quiz, case when v_quiz > 1 then 's' else '' end,
    case when v_questions > 0 then format(', %s %% de bonnes réponses', round(100 * v_points / v_questions)) else '' end,
    case
      when v_faible is not null then format(' À travailler : « %s ». Refaites le quiz avec %s et demandez-lui d''expliquer chaque réponse.', v_faible, v_prenom)
      else format(' Félicitez son travail régulier.', v_prenom)
    end);
end;
$$;

-- Appelé le dimanche à 18 h (tâche planifiée). Une seule fois par semaine
-- et par parent et enfant, même si la tâche est rejouée.
create or replace function public.envoyer_bilans_revision()
returns int
language plpgsql volatile security definer set search_path = public
as $$
declare
  r record;
  v_n int := 0;
  v_depuis timestamptz := now() - interval '7 days';
begin
  for r in
    select distinct rel.parent_profile_id, rel.fiche_eleve_id, f.etablissement_id
      from public.relations_parent_eleve rel
      join public.fiches_eleves f on f.id = rel.fiche_eleve_id
     where rel.statut = 'confirmee' and rel.autorise and rel.deleted_at is null
       -- Seulement si l'élève a un contenu de révision ou a déjà révisé.
       and (exists (select 1 from public.tentatives_revision t where t.fiche_eleve_id = rel.fiche_eleve_id)
            or exists (select 1 from public.inscriptions i join public.classes c on c.id = i.classe_id
                        join public.programmes_officiels p on p.niveau_id = c.niveau_id and p.etablissement_id is null
                        join public.programmes_matieres m on m.programme_id = p.id
                        join public.questions q on q.matiere_id = m.id and q.version_publiee is not null
                       where i.fiche_eleve_id = rel.fiche_eleve_id and i.deleted_at is null))
  loop
    if exists (select 1 from public.notifications n
                where n.destinataire = r.parent_profile_id and n.type = 'bilan_revision'
                  and n.variables ->> 'fiche_eleve_id' = r.fiche_eleve_id::text
                  and n.created_at > now() - interval '6 days') then
      continue;
    end if;
    insert into public.notifications (etablissement_id, destinataire, type, canal, contenu, variables)
    values (r.etablissement_id, r.parent_profile_id, 'bilan_revision', 'push',
            public.texte_bilan_revision(r.fiche_eleve_id, v_depuis),
            jsonb_build_object('fiche_eleve_id', r.fiche_eleve_id));
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- Le même bilan, lu dans l'application (écran du parent, bouton Écouter).
create or replace function public.bilan_revision(p_fiche uuid)
returns text
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return public.texte_bilan_revision(p_fiche, now() - interval '7 days');
end;
$$;

revoke all on function public.definir_classement_visible(uuid, boolean) from public, anon;
revoke all on function public.points_effort(public.tentatives_revision) from public, anon;
revoke all on function public.classement_revision(uuid, text) from public, anon;
revoke all on function public.texte_bilan_revision(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.envoyer_bilans_revision() from public, anon, authenticated;
revoke all on function public.bilan_revision(uuid) from public, anon;
grant execute on function public.definir_classement_visible(uuid, boolean) to authenticated;
grant execute on function public.points_effort(public.tentatives_revision) to authenticated;
grant execute on function public.classement_revision(uuid, text) to authenticated;
grant execute on function public.bilan_revision(uuid) to authenticated;
grant execute on function public.envoyer_bilans_revision() to service_role;
