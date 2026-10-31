-- ============================================================================
-- EcoShop — REG-37 lot R4 : profil de maîtrise, recommandation, répétition
-- espacée et planificateur (cahier ch. 14 et 15)
-- ============================================================================
-- 1. Répétition espacée (15.1) : chaque question jouée entre dans un
--    calendrier aux paliers du cahier — J1 (apprentissage), J2, J4, J7, J14,
--    J30 ; réussite : palier suivant ; échec : palier précédent (pas retour à
--    zéro), revue le lendemain. Mis à jour par le serveur à chaque réponse
--    reçue, donc le même sur le téléphone de l'élève et sur celui du parent.
--    Paliers croissants : l'écart optimal entre révisions grandit avec la
--    durée à retenir (Cepeda et al. 2008).
-- 2. Profil de maîtrise par compétence (14.1) : moyenne des réponses, les
--    plus récentes pesant davantage, partant de 50 % (pas de 100 % après
--    une seule réponse) ; sous 50 % : point faible.
-- 3. Vue de l'enseignant par classe (14.1) : compétences le plus souvent
--    sous le seuil (rapports d'ASSISTments).
-- 4. Plan de révision (15.2) : échéance et matières déclarées par l'élève ou
--    son parent ; les missions du jour sont calculées sur l'appareil.
-- Résultats d'entraînement : jamais fusionnés avec le risque d'échec (12.7)
-- ni avec les notes officielles (12.6).
-- ============================================================================

alter table public.tentatives_revision drop constraint if exists tentatives_revision_mode_check;
alter table public.tentatives_revision add constraint tentatives_revision_mode_check
  check (mode in ('rapide', 'standard', 'intensif', 'chapitre', 'matiere', 'melange', 'personnalise', 'erreurs',
                  'examen', 'repetition', 'competence', 'plan'));

-- ---------------------------------------------------------------------------
-- 1. Répétition espacée
-- ---------------------------------------------------------------------------
create table if not exists public.cartes_revision (
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  question_id uuid not null references public.questions (id) on delete cascade,
  palier int not null default 0 check (palier between 0 and 6),   -- 6 : retenue (après J30)
  echeance date not null,
  derniere_revision timestamptz not null,
  revisions int not null default 0,
  echecs int not null default 0,
  primary key (fiche_eleve_id, question_id)
);
create index if not exists idx_cartes_revision_echeance on public.cartes_revision (fiche_eleve_id, echeance);

alter table public.cartes_revision enable row level security;
revoke insert, update, delete on public.cartes_revision from anon, authenticated;
drop policy if exists cartes_revision_select on public.cartes_revision;
create policy cartes_revision_select on public.cartes_revision for select to authenticated
  using (public.peut_reviser_pour(fiche_eleve_id));

-- Jours avant la prochaine révision quand on atteint un palier :
-- 1 → J2, 2 → J4, 3 → J7, 4 → J14, 5 → J30, 6 → contrôle à 60 jours.
create or replace function public.ecart_palier(p_palier int)
returns int
language sql immutable set search_path = public
as $$ select (array[1, 1, 2, 3, 7, 16, 60])[least(greatest(p_palier, 0), 6) + 1]; $$;

create or replace function public.tg_carte_revision()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_fiche uuid;
  v_quand timestamptz;
  v_carte public.cartes_revision;
  v_palier int;
begin
  select t.fiche_eleve_id, t.commence_le + make_interval(secs => new.ordre) into v_fiche, v_quand
    from public.tentatives_revision t where t.id = new.tentative_id;
  select * into v_carte from public.cartes_revision
   where fiche_eleve_id = v_fiche and question_id = new.question_id for update;

  if not found then
    v_palier := case when new.score >= 1 then 1 else 0 end;
    insert into public.cartes_revision (fiche_eleve_id, question_id, palier, echeance, derniere_revision, revisions, echecs)
    values (v_fiche, new.question_id, v_palier, (v_quand + make_interval(days => public.ecart_palier(v_palier)))::date,
            v_quand, 1, case when new.score >= 1 then 0 else 1 end);
    return new;
  end if;

  -- Une réponse plus ancienne arrivée en retard (envoi différé) ne recule
  -- pas le calendrier.
  if v_quand <= v_carte.derniere_revision then
    return new;
  end if;
  -- Revoir une carte avant son échéance ne fait pas monter d'un palier
  -- (sauf si elle est ratée : elle redescend).
  if new.score >= 1 and v_quand::date < v_carte.echeance then
    update public.cartes_revision set derniere_revision = v_quand, revisions = revisions + 1
     where fiche_eleve_id = v_fiche and question_id = new.question_id;
    return new;
  end if;
  v_palier := case when new.score >= 1 then least(v_carte.palier + 1, 6) else greatest(v_carte.palier - 1, 0) end;
  update public.cartes_revision
     set palier = v_palier,
         echeance = (v_quand + make_interval(days => case when new.score >= 1 then public.ecart_palier(v_palier) else 1 end))::date,
         derniere_revision = v_quand,
         revisions = revisions + 1,
         echecs = echecs + case when new.score >= 1 then 0 else 1 end
   where fiche_eleve_id = v_fiche and question_id = new.question_id;
  return new;
end;
$$;

drop trigger if exists trg_carte_revision on public.reponses_revision;
create trigger trg_carte_revision after insert on public.reponses_revision
  for each row execute function public.tg_carte_revision();

-- Cartes à revoir aujourd'hui, plafonnées (15.1) ; plus anciennes d'abord.
create or replace function public.revisions_du_jour(p_fiche uuid, p_limite int default 20)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'dues', (select count(*) from public.cartes_revision c
              join public.questions q on q.id = c.question_id
             where c.fiche_eleve_id = p_fiche and c.echeance <= current_date and c.palier < 6
               and q.version_publiee is not null and q.suspendue_le is null),
    'retenues', (select count(*) from public.cartes_revision where fiche_eleve_id = p_fiche and palier >= 5),
    'suivies', (select count(*) from public.cartes_revision where fiche_eleve_id = p_fiche),
    'cartes', coalesce((
      select jsonb_agg(jsonb_build_object('question_id', x.question_id, 'palier', x.palier, 'echeance', x.echeance))
        from (select c.question_id, c.palier, c.echeance
                from public.cartes_revision c
                join public.questions q on q.id = c.question_id
               where c.fiche_eleve_id = p_fiche and c.echeance <= current_date and c.palier < 6
                 and q.version_publiee is not null and q.suspendue_le is null
               order by c.echeance, c.palier
               limit greatest(1, least(50, coalesce(p_limite, 20)))) x), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Profil de maîtrise par compétence
-- ---------------------------------------------------------------------------
-- Les 20 dernières réponses de chaque compétence ; poids 0,85^rang (la plus
-- récente pèse 1) ; un « a priori » de 50 % pesant 1.
create or replace function public.maitrise_competences(p_fiches uuid[])
returns table (fiche_eleve_id uuid, competence_id uuid, maitrise numeric, reponses int, derniere timestamptz)
language sql stable security definer set search_path = public
as $$
  with r as (
    select t.fiche_eleve_id, v.competence_id, r.score,
           t.commence_le + make_interval(secs => r.ordre) as quand,
           row_number() over (partition by t.fiche_eleve_id, v.competence_id
                              order by t.commence_le desc, r.ordre desc) - 1 as rang
      from public.reponses_revision r
      join public.tentatives_revision t on t.id = r.tentative_id
      join public.questions_versions v on v.question_id = r.question_id and v.version = r.version
     where t.fiche_eleve_id = any (p_fiches) and t.termine
  )
  select r.fiche_eleve_id, r.competence_id,
         round((sum(r.score * power(0.85, r.rang)) + 0.5) / (sum(power(0.85, r.rang)) + 1), 3),
         count(*)::int, max(r.quand)
    from r where r.rang < 20
   group by r.fiche_eleve_id, r.competence_id;
$$;
revoke all on function public.maitrise_competences(uuid[]) from public, anon, authenticated;

create or replace function public.profil_maitrise(p_fiche uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'competence_id', m.competence_id, 'maitrise', m.maitrise, 'reponses', m.reponses, 'derniere', m.derniere,
             -- Échecs répétés : les trois dernières réponses ratées.
             'echecs_repetes', (select coalesce(bool_and(r.score < 1), false) and count(*) = 3
                                  from (select r.score
                                          from public.reponses_revision r
                                          join public.tentatives_revision t on t.id = r.tentative_id
                                          join public.questions_versions v on v.question_id = r.question_id and v.version = r.version
                                         where t.fiche_eleve_id = p_fiche and v.competence_id = m.competence_id and t.termine
                                         order by t.commence_le desc, r.ordre desc limit 3) r)))
      from public.maitrise_competences(array[p_fiche]) m), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Vue de l'enseignant (ou de la direction) par classe
-- ---------------------------------------------------------------------------
create or replace function public.maitrise_classe(p_classe uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_ecole uuid;
  v_annee uuid;
  v_fiches uuid[];
begin
  select c.etablissement_id, c.annee_scolaire_id into v_ecole, v_annee from public.classes c where c.id = p_classe;
  if v_ecole is null or not (coalesce(public.enseigne_classe(p_classe), false) or coalesce(public.est_direction(v_ecole), false)) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select array_agg(i.fiche_eleve_id) into v_fiches
    from public.inscriptions i
   where i.classe_id = p_classe and i.annee_scolaire_id = v_annee and i.deleted_at is null and i.statut = 'active';

  return jsonb_build_object(
    'eleves', coalesce(array_length(v_fiches, 1), 0),
    'eleves_actifs', (select count(distinct t.fiche_eleve_id) from public.tentatives_revision t
                       where t.fiche_eleve_id = any (v_fiches) and t.commence_le > now() - interval '30 days'),
    'competences', coalesce((
      select jsonb_agg(jsonb_build_object(
               'competence_id', k.id, 'libelle', k.libelle, 'matiere_id', k.matiere_id,
               'eleves', x.n, 'sous_seuil', x.faibles, 'maitrise_moyenne', x.moyenne,
               'eleves_sous_seuil', x.noms) order by x.faibles desc, x.moyenne)
        from (select m.competence_id, count(*) as n,
                     count(*) filter (where m.maitrise < 0.5) as faibles,
                     round(avg(m.maitrise), 3) as moyenne,
                     coalesce(jsonb_agg(f.prenom || ' ' || f.nom order by m.maitrise)
                                filter (where m.maitrise < 0.5), '[]'::jsonb) as noms
                from public.maitrise_competences(v_fiches) m
                join public.fiches_eleves f on f.id = m.fiche_eleve_id
               where m.reponses >= 3
               group by m.competence_id) x
        join public.competences_matiere k on k.id = x.competence_id), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Plan de révision vers une échéance
-- ---------------------------------------------------------------------------
create table if not exists public.plans_revision (
  fiche_eleve_id uuid primary key references public.fiches_eleves (id) on delete cascade,
  titre text not null default 'Mon examen' check (char_length(btrim(titre)) between 1 and 80),
  echeance date not null,
  matieres uuid[] not null default '{}',
  questions_par_jour int not null default 10 check (questions_par_jour between 3 and 50),
  cree_par uuid references public.profiles (id) on delete set null,
  cree_le timestamptz not null default now(),
  modifie_le timestamptz not null default now()
);
alter table public.plans_revision enable row level security;
revoke insert, update, delete on public.plans_revision from anon, authenticated;
drop policy if exists plans_revision_select on public.plans_revision;
create policy plans_revision_select on public.plans_revision for select to authenticated
  using (public.peut_reviser_pour(fiche_eleve_id));

create or replace function public.definir_plan_revision(
  p_fiche uuid,
  p_titre text,
  p_echeance date,
  p_matieres uuid[],
  p_questions_par_jour int default 10
)
returns public.plans_revision
language plpgsql security definer set search_path = public
as $$
declare
  v_plan public.plans_revision;
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if p_echeance is null or p_echeance <= current_date or p_echeance > current_date + 400 then
    raise exception 'ECHEANCE_INVALIDE' using errcode = '22023';
  end if;
  if coalesce(array_length(p_matieres, 1), 0) = 0 then
    raise exception 'MATIERES_REQUISES' using errcode = '22023';
  end if;
  insert into public.plans_revision (fiche_eleve_id, titre, echeance, matieres, questions_par_jour, cree_par)
  values (p_fiche, coalesce(nullif(btrim(p_titre), ''), 'Mon examen'), p_echeance, p_matieres,
          least(50, greatest(3, coalesce(p_questions_par_jour, 10))), auth.uid())
  on conflict (fiche_eleve_id) do update
    set titre = excluded.titre, echeance = excluded.echeance, matieres = excluded.matieres,
        questions_par_jour = excluded.questions_par_jour, modifie_le = now()
  returning * into v_plan;
  return v_plan;
end;
$$;

create or replace function public.supprimer_plan_revision(p_fiche uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  delete from public.plans_revision where fiche_eleve_id = p_fiche;
end;
$$;

-- Coefficients des matières pour le plan (15.2 : plus de temps aux
-- matières à fort coefficient), ajoutés au paquet de révision.
create or replace function public.coefficients_matieres(p_matieres uuid[])
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_object_agg(m.id, coalesce(m.coefficient, 1)), '{}'::jsonb)
    from public.programmes_matieres m where m.id = any (p_matieres);
$$;

revoke all on function public.revisions_du_jour(uuid, int) from public, anon;
revoke all on function public.profil_maitrise(uuid) from public, anon;
revoke all on function public.maitrise_classe(uuid) from public, anon;
revoke all on function public.definir_plan_revision(uuid, text, date, uuid[], int) from public, anon;
revoke all on function public.supprimer_plan_revision(uuid) from public, anon;
revoke all on function public.coefficients_matieres(uuid[]) from public, anon;
revoke all on function public.ecart_palier(int) from public, anon;
grant execute on function public.revisions_du_jour(uuid, int) to authenticated;
grant execute on function public.profil_maitrise(uuid) to authenticated;
grant execute on function public.maitrise_classe(uuid) to authenticated;
grant execute on function public.definir_plan_revision(uuid, text, date, uuid[], int) to authenticated;
grant execute on function public.supprimer_plan_revision(uuid) to authenticated;
grant execute on function public.coefficients_matieres(uuid[]) to authenticated;
grant execute on function public.ecart_palier(int) to authenticated;
