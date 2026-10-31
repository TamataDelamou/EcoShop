-- ============================================================================
-- EcoShop — REG-40 : cahier de texte numérique, travail à faire et devoirs
-- numériques (cahier de conception 9.2, 10.1, 14.1).
--
-- Recherche et choix : docs/propositions/REG-40_CAHIER_TEXTE_DEVOIRS.md
-- (Pronote, Google Classroom, Khan Academy, Quizizz, Kolibri ; travaux de
-- l'EEF et de l'Université de Limerick sur les devoirs).
--
-- 1. cahier_texte : une ligne par séance (ce qui a été fait), rattachée à la
--    matière et au chapitre du programme officiel, pièces jointes possibles.
-- 2. travaux : le travail à faire, pour une classe ou un groupe, avec une
--    échéance, un temps estimé et un type ; un « devoir numérique » porte des
--    questions publiées de la banque (REG-37), corrigées par le serveur.
-- 3. travaux_eleves : suivi de chaque élève (fait, commencé, remis, note,
--    en retard), écrit par l'élève ou un parent confirmé — même sans réseau
--    (la file d'envoi rejoue les fonctions ci-dessous).
-- 4. Notifications (aux heures de messagerie de l'école) aux élèves et aux
--    parents quand un travail est donné, et sur relance de l'enseignant.
-- 5. Suivi pour l'enseignant (statuts, questions difficiles), avancement
--    du cahier pour la direction, badge « travail à faire » de l'accueil.
--
-- Résultats formatifs : un devoir numérique n'entre jamais dans la moyenne
-- ni dans le bulletin (cahier 12.6) ; il alimente le profil de maîtrise.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Droits
-- ---------------------------------------------------------------------------
-- Écrire le cahier d'une classe : enseignant de la classe (cours ou
-- professeur principal) ou direction.
create or replace function public.ecrit_cahier_classe(p_classe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.enseigne_classe(p_classe), false)
      or exists (select 1 from public.classes c
                  where c.id = p_classe and coalesce(public.est_direction(c.etablissement_id), false));
$$;

-- Fiches qui suivent une classe et dont l'appelant est l'élève ou un parent
-- confirmé.
create or replace function public.fiches_famille_classe(p_classe uuid)
returns setof uuid
language sql stable security definer set search_path = public
as $$
  select i.fiche_eleve_id
    from public.inscriptions i
    join public.fiches_eleves f on f.id = i.fiche_eleve_id and f.deleted_at is null
   where i.classe_id = p_classe and i.deleted_at is null and i.statut in ('active', 'redoublante')
     and (f.profile_id = auth.uid() or coalesce(public.est_parent_confirme(f.id), false));
$$;

-- Lire le cahier d'une classe : qui l'écrit, la vie scolaire de l'école
-- (personnel), ses élèves et leurs parents confirmés.
create or replace function public.lit_cahier_classe(p_classe uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.ecrit_cahier_classe(p_classe)
      or exists (select 1 from public.classes c
                  where c.id = p_classe and coalesce(public.est_personnel(c.etablissement_id), false))
      or exists (select 1 from public.fiches_famille_classe(p_classe));
$$;

grant execute on function public.ecrit_cahier_classe(uuid), public.lit_cahier_classe(uuid) to authenticated;
revoke execute on function public.fiches_famille_classe(uuid) from public, anon;
grant execute on function public.fiches_famille_classe(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 1. Cahier de texte
-- ---------------------------------------------------------------------------
create table if not exists public.cahier_texte (
  id uuid primary key,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  classe_id uuid not null references public.classes (id) on delete cascade,
  groupe_id uuid references public.groupes_pedagogiques (id) on delete set null,
  programme_matiere_id uuid references public.programmes_matieres (id) on delete set null,
  chapitre_id uuid references public.chapitres_matiere (id) on delete set null,
  enseignant_profile_id uuid not null default auth.uid() references public.profiles (id),
  date_seance date not null,
  heure_debut time,
  titre text not null check (char_length(btrim(titre)) between 1 and 200),
  contenu text check (contenu is null or char_length(contenu) <= 4000),
  pieces_jointes jsonb not null default '[]'::jsonb check (jsonb_typeof(pieces_jointes) = 'array'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists idx_cahier_texte_classe on public.cahier_texte (classe_id, date_seance desc) where deleted_at is null;

drop trigger if exists cahier_texte_set_updated_at on public.cahier_texte;
create trigger cahier_texte_set_updated_at before update on public.cahier_texte
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 2. Travail à faire
-- ---------------------------------------------------------------------------
create table if not exists public.travaux (
  id uuid primary key,
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  classe_id uuid not null references public.classes (id) on delete cascade,
  groupe_id uuid references public.groupes_pedagogiques (id) on delete set null,
  programme_matiere_id uuid references public.programmes_matieres (id) on delete set null,
  chapitre_id uuid references public.chapitres_matiere (id) on delete set null,
  seance_id uuid references public.cahier_texte (id) on delete set null,
  enseignant_profile_id uuid not null default auth.uid() references public.profiles (id),
  type text not null default 'exercices'
    check (type in ('lecon', 'exercices', 'redaction', 'expose', 'revision', 'devoir_numerique', 'evaluation')),
  titre text not null check (char_length(btrim(titre)) between 1 and 200),
  consigne text check (consigne is null or char_length(consigne) <= 4000),
  donne_le date not null default current_date,
  pour_le date not null,
  temps_estime_min int not null default 20 check (temps_estime_min between 5 and 240),
  pieces_jointes jsonb not null default '[]'::jsonb check (jsonb_typeof(pieces_jointes) = 'array'),
  -- Devoir numérique : questions publiées de la banque, durée facultative
  -- (sans durée : à faire à son rythme, même sans réseau).
  questions uuid[] not null default '{}',
  duree_min int check (duree_min is null or duree_min between 5 and 180),
  correction_apres_echeance boolean not null default false,
  notifie_le timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint travaux_dates check (pour_le >= donne_le),
  constraint travaux_devoir_questions check (
    (type = 'devoir_numerique') = (cardinality(questions) > 0)),
  constraint travaux_devoir_taille check (cardinality(questions) <= 40)
);
create index if not exists idx_travaux_classe on public.travaux (classe_id, pour_le) where deleted_at is null;

drop trigger if exists travaux_set_updated_at on public.travaux;
create trigger travaux_set_updated_at before update on public.travaux
  for each row execute procedure public.set_updated_at();

-- Suivi par élève.
create table if not exists public.travaux_eleves (
  travail_id uuid not null references public.travaux (id) on delete cascade,
  fiche_eleve_id uuid not null references public.fiches_eleves (id) on delete cascade,
  fait_le timestamptz,
  commence_le timestamptz,
  remis_le timestamptz,
  reponses jsonb,
  score numeric(6, 3),
  nb_questions int,
  duree_s int check (duree_s is null or duree_s between 0 and 86400),
  en_retard boolean not null default false,
  ecrit_par uuid references public.profiles (id) on delete set null,
  primary key (travail_id, fiche_eleve_id)
);
create index if not exists idx_travaux_eleves_fiche on public.travaux_eleves (fiche_eleve_id);

-- Le devoir numérique alimente le profil de maîtrise.
alter table public.tentatives_revision drop constraint if exists tentatives_revision_mode_check;
alter table public.tentatives_revision add constraint tentatives_revision_mode_check
  check (mode in ('rapide', 'standard', 'intensif', 'chapitre', 'matiere', 'melange', 'personnalise', 'erreurs',
                  'examen', 'repetition', 'competence', 'plan', 'concours', 'devoir'));

-- Un travail concerne-t-il cette fiche ? (classe, et groupe s'il y en a un)
create or replace function public.travail_concerne_fiche(p_travail uuid, p_fiche uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.travaux t
      join public.inscriptions i on i.classe_id = t.classe_id and i.fiche_eleve_id = p_fiche
                                 and i.deleted_at is null and i.statut in ('active', 'redoublante')
     where t.id = p_travail and t.deleted_at is null
       and (t.groupe_id is null or exists (select 1 from public.groupes_membres g
                                            where g.groupe_id = t.groupe_id and g.fiche_eleve_id = p_fiche)));
$$;

-- ---------------------------------------------------------------------------
-- 3. Sécurité des lignes
-- ---------------------------------------------------------------------------
alter table public.cahier_texte enable row level security;
alter table public.travaux enable row level security;
alter table public.travaux_eleves enable row level security;

drop policy if exists cahier_texte_select on public.cahier_texte;
create policy cahier_texte_select on public.cahier_texte for select to authenticated
  using (deleted_at is null and public.lit_cahier_classe(classe_id));

drop policy if exists cahier_texte_insert on public.cahier_texte;
create policy cahier_texte_insert on public.cahier_texte for insert to authenticated
  with check (public.ecrit_cahier_classe(classe_id)
              and exists (select 1 from public.classes c where c.id = classe_id
                            and c.etablissement_id = cahier_texte.etablissement_id));

drop policy if exists cahier_texte_update on public.cahier_texte;
create policy cahier_texte_update on public.cahier_texte for update to authenticated
  using (public.ecrit_cahier_classe(classe_id))
  with check (public.ecrit_cahier_classe(classe_id));

-- Travaux : la famille ne voit que ceux de sa classe (et de son groupe).
drop policy if exists travaux_select on public.travaux;
create policy travaux_select on public.travaux for select to authenticated
  using (deleted_at is null and (
           public.ecrit_cahier_classe(classe_id)
           or exists (select 1 from public.classes c where c.id = classe_id
                        and coalesce(public.est_personnel(c.etablissement_id), false))
           or exists (select 1 from public.fiches_famille_classe(travaux.classe_id) as f(fiche)
                       where public.travail_concerne_fiche(travaux.id, f.fiche))));

drop policy if exists travaux_insert on public.travaux;
create policy travaux_insert on public.travaux for insert to authenticated
  with check (public.ecrit_cahier_classe(classe_id)
              and exists (select 1 from public.classes c where c.id = classe_id
                            and c.etablissement_id = travaux.etablissement_id));

drop policy if exists travaux_update on public.travaux;
create policy travaux_update on public.travaux for update to authenticated
  using (public.ecrit_cahier_classe(classe_id))
  with check (public.ecrit_cahier_classe(classe_id));

-- Suivi : lu par la famille de la fiche et par qui écrit le cahier de la
-- classe ; écrit seulement par les fonctions ci-dessous.
drop policy if exists travaux_eleves_select on public.travaux_eleves;
create policy travaux_eleves_select on public.travaux_eleves for select to authenticated
  using (public.peut_reviser_pour(fiche_eleve_id)
         or exists (select 1 from public.travaux t where t.id = travail_id and public.ecrit_cahier_classe(t.classe_id)));
revoke insert, update, delete on public.travaux_eleves from anon, authenticated;

-- Un devoir numérique ne porte que des questions publiées.
create or replace function public.tg_travaux_verifier()
returns trigger
language plpgsql set search_path = public
as $$
begin
  if cardinality(new.questions) > 0 and exists (
       select 1 from unnest(new.questions) q(id)
         left join public.questions x on x.id = q.id
        where x.id is null or x.version_publiee is null) then
    raise exception 'QUESTION_NON_PUBLIEE' using errcode = '22023';
  end if;
  -- Un devoir déjà commencé par un élève ne change plus de questions.
  if tg_op = 'UPDATE' and new.questions is distinct from old.questions
     and exists (select 1 from public.travaux_eleves e where e.travail_id = new.id and e.commence_le is not null) then
    raise exception 'DEVOIR_DEJA_COMMENCE' using errcode = '22023';
  end if;
  return new;
end;
$$;

drop trigger if exists travaux_verifier on public.travaux;
create trigger travaux_verifier before insert or update on public.travaux
  for each row execute function public.tg_travaux_verifier();

-- ---------------------------------------------------------------------------
-- 4. Notifications
-- ---------------------------------------------------------------------------
-- Élèves concernés et leurs parents confirmés, une seule fois chacun.
create or replace function public.destinataires_travail(p_travail uuid, p_seulement_non_faits boolean default false)
returns setof uuid
language sql stable security definer set search_path = public
as $$
  with fiches as (
    select i.fiche_eleve_id as fiche
      from public.travaux t
      join public.inscriptions i on i.classe_id = t.classe_id and i.deleted_at is null
                                 and i.statut in ('active', 'redoublante')
     where t.id = p_travail
       and public.travail_concerne_fiche(t.id, i.fiche_eleve_id)
       and (not p_seulement_non_faits or not exists (
             select 1 from public.travaux_eleves e
              where e.travail_id = t.id and e.fiche_eleve_id = i.fiche_eleve_id
                and (e.fait_le is not null or e.remis_le is not null)))
  )
  select distinct p from (
    select f.profile_id as p from fiches x join public.fiches_eleves f on f.id = x.fiche where f.profile_id is not null
    union
    select r.parent_profile_id from fiches x join public.relations_parent_eleve r on r.fiche_eleve_id = x.fiche
     where r.statut = 'confirmee' and r.autorise and r.deleted_at is null
  ) d where p is not null;
$$;
revoke execute on function public.destinataires_travail(uuid, boolean) from public, anon, authenticated;

create or replace function public.texte_travail(t public.travaux)
returns text
language sql stable set search_path = public
as $$
  select coalesce((select m.nom || ' : ' from public.programmes_matieres m where m.id = t.programme_matiere_id), '')
      || btrim(t.titre) || ' — pour le ' || to_char(t.pour_le, 'DD/MM')
      || case when t.type = 'devoir_numerique' then ' (devoir à faire dans EcoShop)' else '' end;
$$;

-- À la publication d'un travail (pas d'un brouillon) : prévenir la classe.
create or replace function public.tg_travaux_notifier()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_dest uuid;
begin
  if new.notifie_le is not null or new.deleted_at is not null then
    return new;
  end if;
  for v_dest in select * from public.destinataires_travail(new.id) loop
    perform public.notifier_push_calme(new.etablissement_id, v_dest, 'travail_a_faire',
                                       'Nouveau travail — ' || public.texte_travail(new),
                                       jsonb_build_object('travail_id', new.id, 'classe_id', new.classe_id));
  end loop;
  update public.travaux set notifie_le = now() where id = new.id;
  return new;
end;
$$;

drop trigger if exists travaux_notifier on public.travaux;
create trigger travaux_notifier after insert on public.travaux
  for each row execute function public.tg_travaux_notifier();

-- Relance : élèves (et parents) qui n'ont ni fait ni remis.
create or replace function public.relancer_travail(p_travail uuid)
returns integer
language plpgsql volatile security definer set search_path = public
as $$
declare
  t public.travaux;
  v_dest uuid;
  v_n integer := 0;
begin
  select * into t from public.travaux where id = p_travail and deleted_at is null;
  if not found or not public.ecrit_cahier_classe(t.classe_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  for v_dest in select * from public.destinataires_travail(p_travail, true) loop
    perform public.notifier_push_calme(t.etablissement_id, v_dest, 'travail_relance',
                                       'Rappel — ' || public.texte_travail(t),
                                       jsonb_build_object('travail_id', t.id, 'classe_id', t.classe_id));
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Côté élève et parent
-- ---------------------------------------------------------------------------
-- Travail d'une fiche depuis une date : tout ce qu'il faut pour la liste,
-- avec le suivi de l'élève. Lu par l'élève ou un parent confirmé.
create or replace function public.travaux_fiche(p_fiche uuid, p_depuis date default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', t.id, 'classe_id', t.classe_id, 'type', t.type, 'titre', t.titre, 'consigne', t.consigne,
             'matiere', m.nom, 'matiere_id', t.programme_matiere_id, 'chapitre', ch.titre,
             'donne_le', t.donne_le, 'pour_le', t.pour_le, 'temps_estime_min', t.temps_estime_min,
             'pieces_jointes', t.pieces_jointes, 'nb_questions', cardinality(t.questions), 'duree_min', t.duree_min,
             'enseignant', trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')),
             'fait_le', e.fait_le, 'commence_le', e.commence_le, 'remis_le', e.remis_le,
             'score', e.score, 'en_retard', coalesce(e.en_retard, false))
           order by t.pour_le, m.nom)
      from public.travaux t
      left join public.programmes_matieres m on m.id = t.programme_matiere_id
      left join public.chapitres_matiere ch on ch.id = t.chapitre_id
      left join public.profiles p on p.id = t.enseignant_profile_id
      left join public.travaux_eleves e on e.travail_id = t.id and e.fiche_eleve_id = p_fiche
     where t.deleted_at is null
       and t.pour_le >= coalesce(p_depuis, current_date - 30)
       and public.travail_concerne_fiche(t.id, p_fiche)), '[]'::jsonb);
end;
$$;

-- Cahier de texte de la classe d'une fiche (séances depuis une date).
create or replace function public.cahier_fiche(p_fiche uuid, p_depuis date default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', s.id, 'date_seance', s.date_seance, 'heure_debut', s.heure_debut, 'titre', s.titre,
             'contenu', s.contenu, 'matiere', m.nom, 'matiere_id', s.programme_matiere_id, 'chapitre', ch.titre,
             'pieces_jointes', s.pieces_jointes,
             'enseignant', trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')))
           order by s.date_seance desc, s.heure_debut desc nulls last)
      from public.cahier_texte s
      join public.inscriptions i on i.classe_id = s.classe_id and i.fiche_eleve_id = p_fiche
                                 and i.deleted_at is null and i.statut in ('active', 'redoublante')
      left join public.programmes_matieres m on m.id = s.programme_matiere_id
      left join public.chapitres_matiere ch on ch.id = s.chapitre_id
      left join public.profiles p on p.id = s.enseignant_profile_id
     where s.deleted_at is null
       and s.date_seance >= coalesce(p_depuis, current_date - 45)
       and (s.groupe_id is null or exists (select 1 from public.groupes_membres g
                                            where g.groupe_id = s.groupe_id and g.fiche_eleve_id = p_fiche))), '[]'::jsonb);
end;
$$;

-- « Fait » (ou « pas fait ») coché par l'élève ou un parent.
create or replace function public.marquer_travail_fait(p_travail uuid, p_fiche uuid, p_fait boolean, p_quand timestamptz default null)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  t public.travaux;
  v_quand timestamptz := least(coalesce(p_quand, now()), now());
begin
  if not public.peut_reviser_pour(p_fiche) or not public.travail_concerne_fiche(p_travail, p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select * into t from public.travaux where id = p_travail;
  if t.type = 'devoir_numerique' then
    raise exception 'DEVOIR_A_REMETTRE' using errcode = '22023';
  end if;
  insert into public.travaux_eleves (travail_id, fiche_eleve_id, fait_le, en_retard, ecrit_par)
  values (p_travail, p_fiche, case when p_fait then v_quand end,
          p_fait and v_quand::date > t.pour_le, auth.uid())
  on conflict (travail_id, fiche_eleve_id) do update
    set fait_le = excluded.fait_le, en_retard = excluded.en_retard, ecrit_par = excluded.ecrit_par;
end;
$$;

-- Sujet d'un devoir numérique, sans les réponses. Sans durée, il peut être
-- gardé sur le téléphone et fait sans réseau ; avec une durée, le
-- chronomètre part à l'ouverture (p_commencer).
create or replace function public.sujet_devoir(p_travail uuid, p_fiche uuid, p_commencer boolean default true)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  t public.travaux;
  e public.travaux_eleves;
begin
  if not public.peut_reviser_pour(p_fiche) or not public.travail_concerne_fiche(p_travail, p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select * into t from public.travaux where id = p_travail;
  if t.type <> 'devoir_numerique' then
    raise exception 'PAS_UN_DEVOIR' using errcode = '22023';
  end if;
  select * into e from public.travaux_eleves where travail_id = p_travail and fiche_eleve_id = p_fiche;
  if e.remis_le is not null then
    raise exception 'DEJA_REMIS' using errcode = '22023';
  end if;
  if p_commencer and e.commence_le is null then
    insert into public.travaux_eleves (travail_id, fiche_eleve_id, commence_le, ecrit_par)
    values (p_travail, p_fiche, now(), auth.uid())
    on conflict (travail_id, fiche_eleve_id) do update set commence_le = coalesce(travaux_eleves.commence_le, now())
    returning * into e;
  end if;
  return jsonb_build_object(
    'commence_le', coalesce(e.commence_le, now()),
    'limite', case when t.duree_min is null then null
                   else coalesce(e.commence_le, now()) + make_interval(mins => t.duree_min) end,
    'questions', (
      select jsonb_agg(jsonb_build_object(
               'id', q.id, 'matiere_id', q.matiere_id, 'version', v.version, 'type', v.type, 'difficulte', v.difficulte,
               'competence_id', v.competence_id, 'enonce', v.enonce, 'contenu', v.contenu,
               'explication', '', 'reponse', '{}'::jsonb, 'media_chemin', v.media_chemin, 'media_type', v.media_type)
             order by x.i)
        from unnest(t.questions) with ordinality x(id, i)
        join public.questions q on q.id = x.id
        join public.questions_versions v on v.question_id = q.id and v.version = q.version_publiee));
end;
$$;

-- Remise : correction par le serveur, suivi de l'élève, tentative de
-- révision (profil de maîtrise). La correction détaillée est renvoyée tout
-- de suite, ou après la date limite si l'enseignant l'a choisi.
create or replace function public.remettre_devoir(p_travail uuid, p_fiche uuid, p_reponses jsonb, p_duree_s int default null,
                                                  p_remis_le timestamptz default null)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  t public.travaux;
  e public.travaux_eleves;
  v_detail jsonb;
  v_score numeric;
  v_n int;
  v_quand timestamptz := least(coalesce(p_remis_le, now()), now());
  v_debut timestamptz;
  v_duree int;
  v_tentative uuid := gen_random_uuid();
  v_voir boolean;
begin
  if not public.peut_reviser_pour(p_fiche) or not public.travail_concerne_fiche(p_travail, p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select * into t from public.travaux where id = p_travail;
  if t.type <> 'devoir_numerique' then
    raise exception 'PAS_UN_DEVOIR' using errcode = '22023';
  end if;
  select * into e from public.travaux_eleves where travail_id = p_travail and fiche_eleve_id = p_fiche for update;
  v_voir := not t.correction_apres_echeance or current_date > t.pour_le;
  if e.remis_le is not null then
    return jsonb_build_object('score', e.score, 'questions', e.nb_questions, 'deja_remis', true,
                              'correction_visible', v_voir);
  end if;

  v_n := cardinality(t.questions);
  select coalesce(jsonb_agg(jsonb_build_object(
           'question_id', q.id, 'version', v.version, 'ordre', x.i - 1,
           'score', public.corriger_reponse(v.type, v.contenu, v.reponse, p_reponses -> q.id::text),
           'reponse', p_reponses -> q.id::text) order by x.i), '[]'::jsonb)
    into v_detail
    from unnest(t.questions) with ordinality x(id, i)
    join public.questions q on q.id = x.id
    join public.questions_versions v on v.question_id = q.id and v.version = q.version_publiee;
  select coalesce(sum((d ->> 'score')::numeric), 0) into v_score from jsonb_array_elements(v_detail) d;

  v_debut := coalesce(e.commence_le, v_quand - make_interval(secs => greatest(0, coalesce(p_duree_s, 0))));
  v_duree := least(86400, greatest(0, coalesce(p_duree_s, extract(epoch from (v_quand - v_debut))::int)));

  insert into public.travaux_eleves (travail_id, fiche_eleve_id, commence_le, remis_le, reponses, score,
                                     nb_questions, duree_s, en_retard, ecrit_par)
  values (p_travail, p_fiche, v_debut, v_quand, p_reponses, v_score, v_n, v_duree, v_quand::date > t.pour_le, auth.uid())
  on conflict (travail_id, fiche_eleve_id) do update
    set commence_le = coalesce(travaux_eleves.commence_le, excluded.commence_le), remis_le = excluded.remis_le,
        reponses = excluded.reponses, score = excluded.score, nb_questions = excluded.nb_questions,
        duree_s = excluded.duree_s, en_retard = excluded.en_retard, ecrit_par = excluded.ecrit_par;

  insert into public.tentatives_revision (id, fiche_eleve_id, joue_par, mode, matiere_id, chapitre_id, nb_questions,
                                          nb_repondues, points, duree_s, termine, commence_le, termine_le)
  values (v_tentative, p_fiche, auth.uid(), 'devoir', t.programme_matiere_id, t.chapitre_id, greatest(1, least(50, v_n)),
          least(50, (select count(*) from jsonb_object_keys(coalesce(p_reponses, '{}'::jsonb)))::int), v_score,
          v_duree, true, v_debut, v_quand);
  insert into public.reponses_revision (tentative_id, question_id, version, ordre, score, reponse)
  select v_tentative, (d ->> 'question_id')::uuid, (d ->> 'version')::int, (d ->> 'ordre')::int,
         (d ->> 'score')::numeric, d -> 'reponse'
    from jsonb_array_elements(v_detail) d
  on conflict do nothing;

  return jsonb_build_object(
    'score', v_score, 'questions', v_n, 'duree_s', v_duree, 'hors_delai', v_quand::date > t.pour_le,
    'correction_visible', v_voir,
    'correction', case when v_voir then (
      select jsonb_agg(jsonb_build_object(
               'question_id', d ->> 'question_id', 'score', (d ->> 'score')::numeric,
               'reponse', v.reponse, 'explication', v.explication) order by (d ->> 'ordre')::int)
        from jsonb_array_elements(v_detail) d
        join public.questions_versions v on v.question_id = (d ->> 'question_id')::uuid and v.version = (d ->> 'version')::int)
      else '[]'::jsonb end);
end;
$$;

-- Correction d'un devoir déjà remis (après la date limite, ou pour la revoir).
create or replace function public.correction_devoir(p_travail uuid, p_fiche uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  t public.travaux;
  e public.travaux_eleves;
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select * into t from public.travaux where id = p_travail;
  select * into e from public.travaux_eleves where travail_id = p_travail and fiche_eleve_id = p_fiche;
  if e.remis_le is null then
    raise exception 'NON_REMIS' using errcode = '22023';
  end if;
  if t.correction_apres_echeance and current_date <= t.pour_le then
    return jsonb_build_object('score', e.score, 'questions', e.nb_questions, 'correction_visible', false);
  end if;
  return jsonb_build_object(
    'score', e.score, 'questions', e.nb_questions, 'duree_s', e.duree_s, 'hors_delai', e.en_retard,
    'correction_visible', true,
    'correction', (
      select jsonb_agg(jsonb_build_object(
               'question_id', q.id, 'reponse_eleve', e.reponses -> q.id::text,
               'score', public.corriger_reponse(v.type, v.contenu, v.reponse, e.reponses -> q.id::text),
               'reponse', v.reponse, 'explication', v.explication, 'enonce', v.enonce, 'type', v.type,
               'contenu', v.contenu) order by x.i)
        from unnest(t.questions) with ordinality x(id, i)
        join public.questions q on q.id = x.id
        join public.questions_versions v on v.question_id = q.id and v.version = q.version_publiee));
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Côté enseignant et direction
-- ---------------------------------------------------------------------------
-- Suivi d'un travail : chaque élève, statistiques, questions difficiles.
create or replace function public.suivi_travail(p_travail uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  t public.travaux;
begin
  select * into t from public.travaux where id = p_travail and deleted_at is null;
  if not found or not public.ecrit_cahier_classe(t.classe_id) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'eleves', coalesce((
      select jsonb_agg(jsonb_build_object(
               'fiche_id', f.id, 'nom', trim(f.prenom || ' ' || f.nom),
               'fait_le', e.fait_le, 'commence_le', e.commence_le, 'remis_le', e.remis_le,
               'score', e.score, 'nb_questions', e.nb_questions, 'duree_s', e.duree_s,
               'en_retard', coalesce(e.en_retard, false))
             order by f.nom, f.prenom)
        from public.inscriptions i
        join public.fiches_eleves f on f.id = i.fiche_eleve_id and f.deleted_at is null
        left join public.travaux_eleves e on e.travail_id = t.id and e.fiche_eleve_id = f.id
       where i.classe_id = t.classe_id and i.deleted_at is null and i.statut in ('active', 'redoublante')
         and public.travail_concerne_fiche(t.id, f.id)), '[]'::jsonb),
    -- Questions de la moins réussie à la mieux réussie (Kolibri, Quizizz).
    'questions', coalesce((
      select jsonb_agg(jsonb_build_object(
               'question_id', q.id, 'ordre', x.i, 'enonce', left(v.enonce, 300), 'type', v.type,
               'competence', k.libelle,
               'reponses', r.n, 'reussite', r.moyenne, 'a_aider', r.noms)
             order by r.moyenne nulls last, x.i)
        from unnest(t.questions) with ordinality x(id, i)
        join public.questions q on q.id = x.id
        join public.questions_versions v on v.question_id = q.id and v.version = q.version_publiee
        left join public.competences_matiere k on k.id = v.competence_id
        left join lateral (
          select count(*) as n,
                 round(avg(public.corriger_reponse(v.type, v.contenu, v.reponse, e.reponses -> q.id::text)), 3) as moyenne,
                 coalesce(jsonb_agg(trim(f.prenom || ' ' || f.nom))
                            filter (where public.corriger_reponse(v.type, v.contenu, v.reponse, e.reponses -> q.id::text) < 1),
                          '[]'::jsonb) as noms
            from public.travaux_eleves e
            join public.fiches_eleves f on f.id = e.fiche_eleve_id
           where e.travail_id = t.id and e.remis_le is not null) r on true), '[]'::jsonb));
end;
$$;

-- Questions publiées utilisables pour un devoir dans une matière (et un
-- chapitre) : pour composer le devoir.
create or replace function public.questions_pour_devoir(p_matiere uuid, p_chapitre uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUISE' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', q.id, 'enonce', left(v.enonce, 200), 'type', v.type, 'difficulte', v.difficulte,
             'chapitre_id', v.chapitre_id, 'chapitre', ch.titre, 'competence', k.libelle,
             'temps_s', v.temps_recommande_s)
           order by ch.ordre nulls last, v.difficulte, v.enonce)
      from public.questions q
      join public.questions_versions v on v.question_id = q.id and v.version = q.version_publiee
      left join public.chapitres_matiere ch on ch.id = v.chapitre_id
      left join public.competences_matiere k on k.id = v.competence_id
     where q.matiere_id = p_matiere and q.version_publiee is not null and q.suspendue_le is null
       and (p_chapitre is null or v.chapitre_id = p_chapitre)
     limit 400), '[]'::jsonb);
end;
$$;

-- Avancement du cahier (direction) : par classe et matière, séances
-- renseignées sur les 14 derniers jours, comparées aux cours prévus à
-- l'emploi du temps sur la même période.
create or replace function public.avancement_cahier(p_etablissement uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_annee uuid;
begin
  if not coalesce(public.est_direction(p_etablissement), false) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select id into v_annee from public.annees_scolaires where etablissement_id = p_etablissement and courante limit 1;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'classe_id', x.classe_id, 'classe', c.nom, 'matiere_id', x.matiere_id, 'matiere', m.nom,
             'enseignant', trim(coalesce(p.prenom, '') || ' ' || coalesce(p.nom, '')),
             'prevues', x.prevues, 'renseignees', x.renseignees, 'derniere', x.derniere,
             'travaux', x.travaux)
           order by c.nom, m.nom)
      from (
        select e.classe_id, e.programme_matiere_id as matiere_id, max(e.enseignant_profile_id::text)::uuid as enseignant,
               -- Cours par semaine × 2 semaines.
               count(*) * 2 as prevues,
               (select count(*) from public.cahier_texte s
                 where s.classe_id = e.classe_id and s.programme_matiere_id = e.programme_matiere_id
                   and s.deleted_at is null and s.date_seance > current_date - 14) as renseignees,
               (select max(s.date_seance) from public.cahier_texte s
                 where s.classe_id = e.classe_id and s.programme_matiere_id = e.programme_matiere_id
                   and s.deleted_at is null) as derniere,
               (select count(*) from public.travaux w
                 where w.classe_id = e.classe_id and w.programme_matiere_id = e.programme_matiere_id
                   and w.deleted_at is null and w.donne_le > current_date - 14) as travaux
          from public.emplois_du_temps e
         where e.etablissement_id = p_etablissement and e.annee_scolaire_id = v_annee and e.deleted_at is null
           and e.type = 'cours' and e.programme_matiere_id is not null
         group by e.classe_id, e.programme_matiere_id) x
      join public.classes c on c.id = x.classe_id
      join public.programmes_matieres m on m.id = x.matiere_id
      left join public.profiles p on p.id = x.enseignant), '[]'::jsonb);
end;
$$;

revoke all on function public.relancer_travail(uuid), public.travaux_fiche(uuid, date), public.cahier_fiche(uuid, date),
  public.marquer_travail_fait(uuid, uuid, boolean, timestamptz), public.sujet_devoir(uuid, uuid, boolean),
  public.remettre_devoir(uuid, uuid, jsonb, int, timestamptz), public.correction_devoir(uuid, uuid),
  public.suivi_travail(uuid), public.questions_pour_devoir(uuid, uuid), public.avancement_cahier(uuid)
  from public, anon;
grant execute on function public.relancer_travail(uuid), public.travaux_fiche(uuid, date), public.cahier_fiche(uuid, date),
  public.marquer_travail_fait(uuid, uuid, boolean, timestamptz), public.sujet_devoir(uuid, uuid, boolean),
  public.remettre_devoir(uuid, uuid, jsonb, int, timestamptz), public.correction_devoir(uuid, uuid),
  public.suivi_travail(uuid), public.questions_pour_devoir(uuid, uuid), public.avancement_cahier(uuid),
  public.travail_concerne_fiche(uuid, uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Pièces jointes : <etablissement>/<classe>/<fichier>
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('cahier-texte', 'cahier-texte', false, 5242880)
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit;

create or replace function public.classe_du_chemin(p_nom_objet text)
returns uuid
language plpgsql immutable
as $$
begin
  return split_part(p_nom_objet, '/', 2)::uuid;
exception when others then
  return null;
end;
$$;

drop policy if exists cahier_texte_objets_select on storage.objects;
create policy cahier_texte_objets_select on storage.objects for select to authenticated
  using (bucket_id = 'cahier-texte' and public.lit_cahier_classe(public.classe_du_chemin(name)));

drop policy if exists cahier_texte_objets_insert on storage.objects;
create policy cahier_texte_objets_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'cahier-texte' and public.ecrit_cahier_classe(public.classe_du_chemin(name)));

drop policy if exists cahier_texte_objets_delete on storage.objects;
create policy cahier_texte_objets_delete on storage.objects for delete to authenticated
  using (bucket_id = 'cahier-texte' and public.ecrit_cahier_classe(public.classe_du_chemin(name)));

-- ---------------------------------------------------------------------------
-- 8. Badge de l'accueil : travail à faire d'ici après-demain
-- ---------------------------------------------------------------------------
do $$
declare
  v_def text := pg_get_functiondef('public.accueil_resume(uuid, uuid)'::regprocedure);
  v_ancre text := 'v_res := v_res || jsonb_build_object(''livres_a_rendre'', v_n);';
begin
  if position('travaux_a_faire' in v_def) > 0 then
    return;
  end if;
  if position(v_ancre in v_def) = 0 then
    raise exception 'accueil_resume : texte attendu introuvable';
  end if;
  v_def := replace(v_def, v_ancre, v_ancre || $r$
    select count(*) into v_n from public.travaux t
     where t.etablissement_id = p_etablissement and t.deleted_at is null
       and t.pour_le between current_date and current_date + 2
       and public.travail_concerne_fiche(t.id, v_fiche)
       and not exists (select 1 from public.travaux_eleves e
                        where e.travail_id = t.id and e.fiche_eleve_id = v_fiche
                          and (e.fait_le is not null or e.remis_le is not null));
    v_res := v_res || jsonb_build_object('travaux_a_faire', v_n);$r$);
  execute v_def;
end $$;
