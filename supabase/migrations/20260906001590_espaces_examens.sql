-- ============================================================================
-- EcoShop — REG-38 lot E1 : espaces de préparation aux examens nationaux
-- (cahier ch. 13), pour tous les pays du référentiel
-- ============================================================================
-- Recherche et choix : document repère, « Préparation aux examens
-- nationaux — synthèse de recherche ».
--
-- Un espace par examen déclaré au référentiel (examens_nationaux), visible
-- d'un élève dont la classe est d'un niveau examinateur du même cycle et du
-- même pays (13.1, 6.6) : rien n'est codé en dur, un nouveau pays de la
-- CEDEAO s'ajoute par les données.
--   • sessions_examen : date de la session (compte à rebours, plan) ;
--   • epreuves_examen : épreuves (matière, durée, coefficient, série) ;
--   • annales : sujets et corrigés des sessions passées, publiés seulement
--     si leur droit de diffusion est validé (RG-013-01) et après le circuit
--     de validation du contenu (30.5) ; version interactive possible avec
--     des questions de la banque ;
--   • tentatives marquées par examen et épreuve : statistiques propres à
--     l'examen (RG-013-02), sans rien retirer au profil de maîtrise ;
--   • fin de primaire : chronomètre indicatif par défaut, remise
--     automatique activable par le parent (13.3, RG-013-03).
-- Résultats d'entraînement : jamais dans la moyenne ni le bulletin (12.6).
-- ============================================================================

do $$ begin
  create type public.droit_diffusion as enum ('a_verifier', 'source_officielle', 'licence', 'domaine_public');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 1. Sessions et épreuves
-- ---------------------------------------------------------------------------
create table if not exists public.sessions_examen (
  id uuid primary key default gen_random_uuid(),
  examen_id uuid not null references public.examens_nationaux (id) on delete cascade,
  annee int not null check (annee between 2000 and 2100),
  date_debut date not null,
  libelle text,
  constraint sessions_examen_unique unique (examen_id, annee)
);

create table if not exists public.epreuves_examen (
  id uuid primary key default gen_random_uuid(),
  examen_id uuid not null references public.examens_nationaux (id) on delete cascade,
  filiere_id uuid references public.filieres_educatives (id) on delete cascade,
  -- Code de la matière dans le programme officiel du niveau d'examen
  -- (programmes_matieres.code), pour relier questions et maîtrise.
  matiere_code text not null check (char_length(btrim(matiere_code)) between 1 and 40),
  libelle text not null check (char_length(btrim(libelle)) between 1 and 120),
  duree_min int not null check (duree_min between 10 and 480),
  coefficient numeric(4, 1) not null default 1 check (coefficient > 0),
  questions_blanc int not null default 20 check (questions_blanc between 5 and 50),
  ordre int not null default 0
);
create index if not exists idx_epreuves_examen on public.epreuves_examen (examen_id, ordre);

alter table public.sessions_examen enable row level security;
alter table public.epreuves_examen enable row level security;
drop policy if exists sessions_examen_select on public.sessions_examen;
create policy sessions_examen_select on public.sessions_examen for select to authenticated using (true);
drop policy if exists sessions_examen_ecrire on public.sessions_examen;
create policy sessions_examen_ecrire on public.sessions_examen for all to authenticated
  using (public.est_admin_contenu()) with check (public.est_admin_contenu());
drop policy if exists epreuves_examen_select on public.epreuves_examen;
create policy epreuves_examen_select on public.epreuves_examen for select to authenticated using (true);
drop policy if exists epreuves_examen_ecrire on public.epreuves_examen;
create policy epreuves_examen_ecrire on public.epreuves_examen for all to authenticated
  using (public.est_admin_contenu()) with check (public.est_admin_contenu());

-- ---------------------------------------------------------------------------
-- 2. Annales
-- ---------------------------------------------------------------------------
create table if not exists public.annales (
  id uuid primary key default gen_random_uuid(),
  examen_id uuid not null references public.examens_nationaux (id) on delete cascade,
  epreuve_id uuid references public.epreuves_examen (id) on delete set null,
  filiere_id uuid references public.filieres_educatives (id) on delete set null,
  annee int not null check (annee between 1960 and 2100),
  session text not null default 'normale' check (session in ('normale', 'remplacement', 'blanc_officiel')),
  titre text not null check (char_length(btrim(titre)) between 1 and 160),
  source text not null check (char_length(btrim(source)) between 1 and 300),
  droit public.droit_diffusion not null default 'a_verifier',
  statut public.statut_contenu_pedagogique not null default 'brouillon',
  sujet_chemin text,
  corrige_chemin text,
  auteur_id uuid references public.profiles (id) on delete set null,
  validateur_id uuid references public.profiles (id) on delete set null,
  publie_le timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_annales_examen on public.annales (examen_id, annee desc);
drop trigger if exists annales_set_updated_at on public.annales;
create trigger annales_set_updated_at before update on public.annales
  for each row execute function public.set_updated_at();

create table if not exists public.annales_questions (
  annale_id uuid not null references public.annales (id) on delete cascade,
  question_id uuid not null references public.questions (id) on delete cascade,
  ordre int not null default 0,
  primary key (annale_id, question_id)
);

alter table public.annales enable row level security;
alter table public.annales_questions enable row level security;
revoke insert, update, delete on public.annales from anon, authenticated;
drop policy if exists annales_select on public.annales;
create policy annales_select on public.annales for select to authenticated
  using (public.est_admin_contenu() or (statut = 'publiee' and droit <> 'a_verifier'));
drop policy if exists annales_questions_select on public.annales_questions;
create policy annales_questions_select on public.annales_questions for select to authenticated
  using (exists (select 1 from public.annales a where a.id = annale_id
                  and (public.est_admin_contenu() or (a.statut = 'publiee' and a.droit <> 'a_verifier'))));
drop policy if exists annales_questions_ecrire on public.annales_questions;
create policy annales_questions_ecrire on public.annales_questions for all to authenticated
  using (public.est_admin_contenu()) with check (public.est_admin_contenu());

create or replace function public.enregistrer_annale(
  p_id uuid,
  p_examen uuid,
  p_annee int,
  p_titre text,
  p_source text,
  p_droit public.droit_diffusion,
  p_session text default 'normale',
  p_epreuve uuid default null,
  p_filiere uuid default null,
  p_sujet_chemin text default null,
  p_corrige_chemin text default null
)
returns public.annales
language plpgsql security definer set search_path = public
as $$
declare
  v public.annales;
begin
  if not public.est_admin_contenu() then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  if coalesce(btrim(p_source), '') = '' then
    raise exception 'SOURCE_REQUISE' using errcode = '22023';
  end if;
  if p_epreuve is not null and not exists (select 1 from public.epreuves_examen where id = p_epreuve and examen_id = p_examen) then
    raise exception 'EPREUVE_HORS_EXAMEN' using errcode = '22023';
  end if;
  insert into public.annales (id, examen_id, epreuve_id, filiere_id, annee, session, titre, source, droit,
                              sujet_chemin, corrige_chemin, auteur_id)
  values (p_id, p_examen, p_epreuve, p_filiere, p_annee, coalesce(p_session, 'normale'), btrim(p_titre), btrim(p_source),
          coalesce(p_droit, 'a_verifier'), p_sujet_chemin, p_corrige_chemin, auth.uid())
  on conflict (id) do update
    set epreuve_id = excluded.epreuve_id, filiere_id = excluded.filiere_id, annee = excluded.annee,
        session = excluded.session, titre = excluded.titre, source = excluded.source, droit = excluded.droit,
        sujet_chemin = excluded.sujet_chemin, corrige_chemin = excluded.corrige_chemin,
        -- Une modification remet l'annale au brouillon (validation à refaire).
        statut = 'brouillon', validateur_id = null
  returning * into v;
  return v;
end;
$$;

-- Circuit 30.5 : soumettre, valider (autre personne sauf Administrateur de
-- contenu), publier (seulement si le droit de diffusion est établi).
create or replace function public.changer_statut_annale(p_id uuid, p_action text)
returns public.annales
language plpgsql security definer set search_path = public
as $$
declare
  v public.annales;
begin
  if not public.est_admin_contenu() then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select * into v from public.annales where id = p_id for update;
  if not found then raise exception 'ANNALE_INTROUVABLE' using errcode = '22023'; end if;
  if p_action = 'soumettre' and v.statut = 'brouillon' then
    update public.annales set statut = 'revision' where id = p_id returning * into v;
  elsif p_action = 'valider' and v.statut = 'revision' then
    update public.annales set statut = 'validee', validateur_id = auth.uid() where id = p_id returning * into v;
  elsif p_action = 'publier' and v.statut = 'validee' then
    if v.droit = 'a_verifier' then
      raise exception 'DROIT_DIFFUSION_A_VERIFIER' using errcode = '22023';
    end if;
    if v.sujet_chemin is null and not exists (select 1 from public.annales_questions where annale_id = p_id) then
      raise exception 'ANNALE_VIDE' using errcode = '22023';
    end if;
    update public.annales set statut = 'publiee', publie_le = now() where id = p_id returning * into v;
  elsif p_action = 'retirer' then
    update public.annales set statut = 'brouillon', publie_le = null where id = p_id returning * into v;
  elsif not (p_action = 'soumettre' and v.statut = 'revision')
        and not (p_action = 'valider' and v.statut = 'validee')
        and not (p_action = 'publier' and v.statut = 'publiee') then
    raise exception 'STATUT_INATTENDU' using errcode = '22023';
  end if;
  return v;
end;
$$;

-- Sujets et corrigés (PDF ou images) : lisibles par les comptes connectés
-- pour les annales publiées ; écrits par l'Administrateur de contenu.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('annales', 'annales', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

drop policy if exists annales_fichiers_lire on storage.objects;
create policy annales_fichiers_lire on storage.objects for select to authenticated
  using (bucket_id = 'annales' and (
    public.est_admin_contenu()
    or exists (select 1 from public.annales a
                where (a.sujet_chemin = name or a.corrige_chemin = name)
                  and a.statut = 'publiee' and a.droit <> 'a_verifier')));
drop policy if exists annales_fichiers_ecrire on storage.objects;
create policy annales_fichiers_ecrire on storage.objects for insert to authenticated
  with check (bucket_id = 'annales' and public.est_admin_contenu());
drop policy if exists annales_fichiers_modifier on storage.objects;
create policy annales_fichiers_modifier on storage.objects for update to authenticated
  using (bucket_id = 'annales' and public.est_admin_contenu());

-- ---------------------------------------------------------------------------
-- 3. Tentatives marquées par examen et épreuve
-- ---------------------------------------------------------------------------
alter table public.tentatives_revision
  add column if not exists examen_id uuid references public.examens_nationaux (id) on delete set null,
  add column if not exists epreuve_id uuid references public.epreuves_examen (id) on delete set null;
create index if not exists idx_tentatives_revision_examen on public.tentatives_revision (fiche_eleve_id, examen_id)
  where examen_id is not null;

alter table public.preferences_revision
  add column if not exists chrono_strict_primaire boolean not null default false;

create or replace function public.definir_chrono_strict(p_fiche uuid, p_strict boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  insert into public.preferences_revision (fiche_eleve_id, chrono_strict_primaire, modifie_par)
  values (p_fiche, coalesce(p_strict, false), auth.uid())
  on conflict (fiche_eleve_id) do update
    set chrono_strict_primaire = excluded.chrono_strict_primaire, modifie_par = auth.uid(), modifie_le = now();
end;
$$;

-- Tentatives : examen et épreuve en plus (REG-38).
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
    duree_s, termine, commence_le, termine_le, examen_id, epreuve_id
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
    (p_tentative ->> 'termine_le')::timestamptz,
    (select x.id from public.examens_nationaux x where x.id = (p_tentative ->> 'examen_id')::uuid),
    (select e.id from public.epreuves_examen e where e.id = (p_tentative ->> 'epreuve_id')::uuid)
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
-- 4. Espaces de préparation d'un élève
-- ---------------------------------------------------------------------------
create or replace function public.espaces_preparation(p_fiche uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_niveau uuid;
  v_filiere uuid;
  v_examinateur boolean;
  v_cycle uuid;
  v_pays text;
begin
  if not public.peut_reviser_pour(p_fiche) then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
  select c.niveau_id, c.filiere_id, n.est_niveau_examinateur, n.cycle_id, n.pays_code
    into v_niveau, v_filiere, v_examinateur, v_cycle, v_pays
    from public.inscriptions i
    join public.classes c on c.id = i.classe_id
    join public.annees_scolaires a on a.id = i.annee_scolaire_id
    join public.niveaux_educatifs n on n.id = c.niveau_id
   where i.fiche_eleve_id = p_fiche and i.deleted_at is null and i.statut = 'active'
   order by a.date_debut desc
   limit 1;
  -- Classe intermédiaire : aucun espace (13.1).
  if v_niveau is null or not coalesce(v_examinateur, false) then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', x.id, 'code', x.code, 'nom', x.nom, 'organisme', x.organisme, 'pays_code', x.pays_code,
      'fin_primaire', cy.code in ('primaire', 'primary'),
      'mois_session', x.mois_session,
      'session', (select jsonb_build_object('annee', s.annee, 'date_debut', s.date_debut, 'libelle', s.libelle)
                    from public.sessions_examen s where s.examen_id = x.id and s.date_debut >= current_date
                   order by s.date_debut limit 1),
      'epreuves', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', e.id, 'matiere_code', e.matiere_code, 'libelle', e.libelle, 'duree_min', e.duree_min,
                 'coefficient', e.coefficient, 'questions_blanc', e.questions_blanc,
                 'matiere_id', (select m.id from public.programmes_matieres m
                                  join public.programmes_officiels p on p.id = m.programme_id
                                 where p.niveau_id = v_niveau and p.etablissement_id is null and p.statut = 'publie'
                                   and (p.filiere_id is null or p.filiere_id = v_filiere)
                                   and upper(m.code) = upper(e.matiere_code)
                                 order by p.filiere_id nulls last limit 1))
               order by e.ordre, e.libelle)
          from public.epreuves_examen e
         where e.examen_id = x.id and (e.filiere_id is null or e.filiere_id = v_filiere)), '[]'::jsonb),
      'annales', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', a.id, 'annee', a.annee, 'session', a.session, 'titre', a.titre, 'source', a.source,
                 'epreuve_id', a.epreuve_id, 'sujet_chemin', a.sujet_chemin, 'corrige_chemin', a.corrige_chemin,
                 'questions', (select coalesce(jsonb_agg(aq.question_id order by aq.ordre), '[]'::jsonb)
                                 from public.annales_questions aq
                                 join public.questions q on q.id = aq.question_id
                                where aq.annale_id = a.id and q.version_publiee is not null and q.suspendue_le is null))
               order by a.annee desc, a.titre)
          from public.annales a
         where a.examen_id = x.id and a.statut = 'publiee' and a.droit <> 'a_verifier'
           and (a.filiere_id is null or a.filiere_id = v_filiere)), '[]'::jsonb),
      -- Statistiques propres à l'examen (RG-013-02).
      'blancs', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'epreuve_id', t.epreuve_id, 'nombre', t.n, 'derniere_note', t.derniere, 'meilleure_note', t.meilleure))
          from (select tr.epreuve_id, count(*) as n,
                       round(20 * (array_agg(tr.points / greatest(tr.nb_questions, 1) order by tr.commence_le desc))[1], 2) as derniere,
                       round(20 * max(tr.points / greatest(tr.nb_questions, 1)), 2) as meilleure
                  from public.tentatives_revision tr
                 where tr.fiche_eleve_id = p_fiche and tr.examen_id = x.id and tr.termine and tr.mode = 'examen'
                 group by tr.epreuve_id) t), '[]'::jsonb),
      'chrono_strict', coalesce((select pr.chrono_strict_primaire from public.preferences_revision pr
                                  where pr.fiche_eleve_id = p_fiche), false)
    ) order by x.code)
      from public.examens_nationaux x
      join public.cycles_educatifs cy on cy.id = x.cycle_id
     where x.pays_code = v_pays and x.cycle_id = v_cycle and x.statut = 'publie'), '[]'::jsonb);
end;
$$;

revoke all on function public.enregistrer_annale(uuid, uuid, int, text, text, public.droit_diffusion, text, uuid, uuid, text, text) from public, anon;
revoke all on function public.changer_statut_annale(uuid, text) from public, anon;
revoke all on function public.definir_chrono_strict(uuid, boolean) from public, anon;
revoke all on function public.espaces_preparation(uuid) from public, anon;
grant execute on function public.enregistrer_annale(uuid, uuid, int, text, text, public.droit_diffusion, text, uuid, uuid, text, text) to authenticated;
grant execute on function public.changer_statut_annale(uuid, text) to authenticated;
grant execute on function public.definir_chrono_strict(uuid, boolean) to authenticated;
grant execute on function public.espaces_preparation(uuid) to authenticated;
