-- ============================================================================
-- EcoShop — REG-38 lot E2b : back-office du référentiel pédagogique, et pays
-- de la sous-région en brouillon.
--
-- Jusqu'ici, pays, cycles, niveaux, examens et programmes nationaux
-- n'étaient écrits que par migration (M4 : « écriture service_role »). Ce
-- lot donne à l'Administrateur de contenu pédagogique (et à l'Administrateur
-- GSG) un back-office :
--   1. pays, cycles, niveaux, examens nationaux : création, modification,
--      suppression tant que rien n'en dépend ;
--   2. programmes nationaux et leurs matières (sans coefficients : chaque
--      école fixe les siens), indispensables à la banque de questions —
--      la Guinée n'en avait aucun en production ;
--   3. contrôle avant publication : niveaux contigus, cycles non vides,
--      niveau d'examen présent, points à vérifier levés ;
--   4. publication d'un pays : tout ce qui est en brouillon devient visible.
--
-- Pays ajoutés EN BROUILLON (invisibles des écoles et des familles tant
-- qu'ils ne sont pas publiés), d'après la recherche du registre REG-38 :
--   CEDEAO : Côte d'Ivoire, Bénin, Togo, Nigeria, Sierra Leone, Liberia,
--            Gambie, Cap-Vert, Guinée-Bissau ;
--   AES (sortis de la CEDEAO en janvier 2025, mêmes écoles francophones) :
--            Mali, Burkina Faso, Niger.
-- Chaque pays porte ses « points à vérifier » : ce que la recherche n'a pas
-- pu confirmer sur un texte officiel. La publication est refusée tant
-- qu'ils ne sont pas levés. Le Cap-Vert et la Guinée-Bissau (lusophones)
-- n'ont que leur fiche : leurs niveaux sont à saisir d'après leur loi
-- d'orientation, rien n'est inventé.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Colonnes du back-office
-- ---------------------------------------------------------------------------
alter table public.pays_pedagogiques
  add column if not exists zone text not null default 'cedeao'
    check (zone in ('cedeao', 'aes', 'autre')),
  add column if not exists sources text check (sources is null or char_length(sources) <= 4000),
  add column if not exists points_a_verifier text
    check (points_a_verifier is null or char_length(points_a_verifier) <= 4000),
  add column if not exists publie_le timestamptz,
  add column if not exists publie_par uuid references public.profiles (id) on delete set null;

comment on column public.pays_pedagogiques.points_a_verifier is
  'REG-38 E2b : ce qui reste à confirmer sur un texte officiel ; la publication est refusée tant que ce champ n''est pas vide.';

-- Qui tient le référentiel : l'Administrateur de contenu, ou GSG.
create or replace function public.gere_referentiel()
returns boolean
language sql stable set search_path = public
as $$
  select coalesce(public.est_admin_contenu(), false) or coalesce(public.est_admin_gsg(), false);
$$;
grant execute on function public.gere_referentiel() to authenticated;

create or replace function public.exiger_gere_referentiel()
returns void
language plpgsql stable set search_path = public
as $$
begin
  if not public.gere_referentiel() then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Pays
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_pays_referentiel(
  p_code text,
  p_nom text,
  p_type_systeme text,
  p_langue text,
  p_organisme text default null,
  p_devise text default 'XOF',
  p_zone text default 'cedeao',
  p_sources text default null,
  p_points_a_verifier text default null
)
returns public.pays_pedagogiques
language plpgsql security definer set search_path = public
as $$
declare
  v public.pays_pedagogiques;
  v_code text := upper(btrim(coalesce(p_code, '')));
begin
  perform public.exiger_gere_referentiel();
  if v_code !~ '^[A-Z]{2}$' then raise exception 'CODE_PAYS_INVALIDE' using errcode = '22023'; end if;
  if char_length(btrim(coalesce(p_nom, ''))) < 2 then raise exception 'NOM_REQUIS' using errcode = '22023'; end if;
  if upper(coalesce(p_devise, '')) !~ '^[A-Z]{3}$' then raise exception 'DEVISE_INVALIDE' using errcode = '22023'; end if;
  insert into public.pays_pedagogiques
    (code_iso, nom, type_systeme, langue_enseignement_principale, organisme_examinateur, devise_code,
     zone, sources, points_a_verifier)
  values (v_code, btrim(p_nom), p_type_systeme, lower(btrim(p_langue)), nullif(btrim(p_organisme), ''),
          upper(p_devise), p_zone, nullif(btrim(p_sources), ''), nullif(btrim(p_points_a_verifier), ''))
  on conflict (code_iso) do update set
    nom = excluded.nom, type_systeme = excluded.type_systeme,
    langue_enseignement_principale = excluded.langue_enseignement_principale,
    organisme_examinateur = excluded.organisme_examinateur, devise_code = excluded.devise_code,
    zone = excluded.zone, sources = excluded.sources, points_a_verifier = excluded.points_a_verifier
  returning * into v;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Cycles, niveaux, examens
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_cycle_referentiel(
  p_id uuid,
  p_pays text,
  p_code text,
  p_nom text,
  p_ordre int,
  p_isced_min int,
  p_isced_max int,
  p_age_min int default null,
  p_age_max int default null,
  p_duree int default null
)
returns public.cycles_educatifs
language plpgsql security definer set search_path = public
as $$
declare
  v public.cycles_educatifs;
begin
  perform public.exiger_gere_referentiel();
  if btrim(coalesce(p_code, '')) = '' or btrim(coalesce(p_nom, '')) = '' then
    raise exception 'NOM_REQUIS' using errcode = '22023';
  end if;
  if p_isced_min > p_isced_max then raise exception 'ISCED_INVALIDE' using errcode = '22023'; end if;
  begin
    insert into public.cycles_educatifs
      (id, pays_code, code, nom, ordre, age_min, age_max, duree_annees, isced_min, isced_max)
    values (p_id, upper(p_pays), btrim(p_code), btrim(p_nom), p_ordre, p_age_min, p_age_max, p_duree, p_isced_min, p_isced_max)
    on conflict (id) do update set
      code = excluded.code, nom = excluded.nom, ordre = excluded.ordre, age_min = excluded.age_min,
      age_max = excluded.age_max, duree_annees = excluded.duree_annees,
      isced_min = excluded.isced_min, isced_max = excluded.isced_max
    returning * into v;
  exception when unique_violation then
    raise exception 'CODE_DEJA_UTILISE' using errcode = '22023';
  end;
  return v;
end;
$$;

create or replace function public.niveau_utilise(p_niveau uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.classes c where c.niveau_id = p_niveau);
$$;

create or replace function public.enregistrer_niveau_referentiel(
  p_id uuid,
  p_cycle uuid,
  p_code text,
  p_nom text,
  p_grade int,
  p_isced int,
  p_ordre int,
  p_examinateur boolean default false
)
returns public.niveaux_educatifs
language plpgsql security definer set search_path = public
as $$
declare
  v public.niveaux_educatifs;
  v_avant public.niveaux_educatifs;
  v_cycle public.cycles_educatifs;
begin
  perform public.exiger_gere_referentiel();
  select * into v_cycle from public.cycles_educatifs where id = p_cycle;
  if not found then raise exception 'CYCLE_INTROUVABLE' using errcode = '22023'; end if;
  if btrim(coalesce(p_code, '')) = '' or btrim(coalesce(p_nom, '')) = '' then
    raise exception 'NOM_REQUIS' using errcode = '22023';
  end if;
  select * into v_avant from public.niveaux_educatifs where id = p_id;
  -- La clé de comparaison d'un niveau qui a des classes ne bouge plus : elle
  -- porte la montée de classe et les statistiques entre pays.
  if found and (v_avant.grade_level_normalise <> p_grade or v_avant.cycle_id <> p_cycle)
     and public.niveau_utilise(p_id) then
    raise exception 'NIVEAU_UTILISE' using errcode = '22023';
  end if;
  begin
    insert into public.niveaux_educatifs
      (id, cycle_id, pays_code, code, nom, grade_level_normalise, isced, ordre, est_niveau_examinateur)
    values (p_id, p_cycle, v_cycle.pays_code, btrim(p_code), btrim(p_nom), p_grade, p_isced, p_ordre, coalesce(p_examinateur, false))
    on conflict (id) do update set
      cycle_id = excluded.cycle_id, code = excluded.code, nom = excluded.nom,
      grade_level_normalise = excluded.grade_level_normalise, isced = excluded.isced,
      ordre = excluded.ordre, est_niveau_examinateur = excluded.est_niveau_examinateur
    returning * into v;
  exception when unique_violation then
    raise exception 'CODE_OU_RANG_DEJA_UTILISE' using errcode = '22023';
  end;
  return v;
end;
$$;

create or replace function public.enregistrer_examen_referentiel(
  p_id uuid,
  p_pays text,
  p_cycle uuid,
  p_code text,
  p_nom text,
  p_organisme text default null,
  p_mois int default null
)
returns public.examens_nationaux
language plpgsql security definer set search_path = public
as $$
declare
  v public.examens_nationaux;
begin
  perform public.exiger_gere_referentiel();
  if btrim(coalesce(p_code, '')) = '' or btrim(coalesce(p_nom, '')) = '' then
    raise exception 'NOM_REQUIS' using errcode = '22023';
  end if;
  if p_cycle is not null and not exists (select 1 from public.cycles_educatifs c where c.id = p_cycle and c.pays_code = upper(p_pays)) then
    raise exception 'CYCLE_INTROUVABLE' using errcode = '22023';
  end if;
  begin
    insert into public.examens_nationaux (id, pays_code, cycle_id, code, nom, organisme, mois_session, periodicite)
    values (p_id, upper(p_pays), p_cycle, btrim(p_code), btrim(p_nom), nullif(btrim(p_organisme), ''), p_mois, 'annuelle')
    on conflict (id) do update set
      cycle_id = excluded.cycle_id, code = excluded.code, nom = excluded.nom,
      organisme = excluded.organisme, mois_session = excluded.mois_session
    returning * into v;
  exception when unique_violation then
    raise exception 'CODE_DEJA_UTILISE' using errcode = '22023';
  end;
  return v;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Programmes nationaux et matières
-- ---------------------------------------------------------------------------
create or replace function public.enregistrer_programme_national(
  p_id uuid,
  p_niveau uuid,
  p_filiere uuid default null,
  p_nom text default null,
  p_annee text default null
)
returns public.programmes_officiels
language plpgsql security definer set search_path = public
as $$
declare
  v public.programmes_officiels;
  n public.niveaux_educatifs;
  v_filiere text;
begin
  perform public.exiger_gere_referentiel();
  select * into n from public.niveaux_educatifs where id = p_niveau;
  if not found then raise exception 'NIVEAU_INTROUVABLE' using errcode = '22023'; end if;
  if p_filiere is not null then
    select code into v_filiere from public.filieres_educatives where id = p_filiere and pays_code = n.pays_code;
    if not found then raise exception 'SERIE_INTROUVABLE' using errcode = '22023'; end if;
  end if;
  begin
    insert into public.programmes_officiels (id, pays_code, niveau_id, filiere_id, code, nom, annee_scolaire)
    values (p_id, n.pays_code, p_niveau, p_filiere,
            'NAT-' || n.code || coalesce('-' || v_filiere, ''),
            coalesce(nullif(btrim(p_nom), ''), 'Programme national · ' || n.nom || coalesce(' · ' || v_filiere, '')),
            nullif(btrim(p_annee), ''))
    on conflict (id) do update set nom = excluded.nom, annee_scolaire = excluded.annee_scolaire
    returning * into v;
  exception when unique_violation then
    raise exception 'PROGRAMME_EXISTANT' using errcode = '22023';
  end;
  if v.etablissement_id is not null then
    raise exception 'PERMISSION_REFUSEE' using errcode = '42501';   -- programme d'une école
  end if;
  return v;
end;
$$;

create or replace function public.enregistrer_matiere_nationale(
  p_id uuid,
  p_programme uuid,
  p_code text,
  p_nom text,
  p_ordre int default 0,
  p_nature text default 'tronc_commun'
)
returns public.programmes_matieres
language plpgsql security definer set search_path = public
as $$
declare
  v public.programmes_matieres;
  p public.programmes_officiels;
begin
  perform public.exiger_gere_referentiel();
  select * into p from public.programmes_officiels where id = p_programme;
  if not found or p.etablissement_id is not null then
    raise exception 'PROGRAMME_INTROUVABLE' using errcode = '22023';
  end if;
  if btrim(coalesce(p_code, '')) = '' or btrim(coalesce(p_nom, '')) = '' then
    raise exception 'NOM_REQUIS' using errcode = '22023';
  end if;
  begin
    -- Sans coefficient : chaque école fixe les siens.
    insert into public.programmes_matieres (id, programme_id, code, nom, ordre, nature, statut)
    values (p_id, p_programme, upper(btrim(p_code)), btrim(p_nom), coalesce(p_ordre, 0), coalesce(p_nature, 'tronc_commun'),
            case when p.statut = 'publie' then 'publie'::public.statut_referentiel else 'brouillon' end)
    on conflict (id) do update set code = excluded.code, nom = excluded.nom, ordre = excluded.ordre, nature = excluded.nature
    returning * into v;
  exception when unique_violation then
    raise exception 'CODE_DEJA_UTILISE' using errcode = '22023';
  end;
  return v;
end;
$$;

create or replace function public.publier_programme_national(p_programme uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  p public.programmes_officiels;
begin
  perform public.exiger_gere_referentiel();
  select * into p from public.programmes_officiels where id = p_programme for update;
  if not found or p.etablissement_id is not null then
    raise exception 'PROGRAMME_INTROUVABLE' using errcode = '22023';
  end if;
  if not exists (select 1 from public.programmes_matieres m where m.programme_id = p_programme) then
    raise exception 'MATIERE_REQUISE' using errcode = '22023';
  end if;
  if not exists (select 1 from public.niveaux_educatifs n where n.id = p.niveau_id and n.statut = 'publie') then
    raise exception 'NIVEAU_NON_PUBLIE' using errcode = '22023';
  end if;
  update public.programmes_officiels set statut = 'publie' where id = p_programme;
  update public.programmes_matieres set statut = 'publie' where programme_id = p_programme and statut = 'brouillon';
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Suppression : seulement ce dont rien ne dépend
-- ---------------------------------------------------------------------------
create or replace function public.supprimer_element_referentiel(p_type text, p_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_statut public.statut_referentiel;
begin
  perform public.exiger_gere_referentiel();
  case p_type
    when 'cycle' then
      select statut into v_statut from public.cycles_educatifs where id = p_id;
      if exists (select 1 from public.niveaux_educatifs where cycle_id = p_id) then
        raise exception 'ELEMENT_UTILISE' using errcode = '22023';
      end if;
      if v_statut = 'publie' then raise exception 'ELEMENT_PUBLIE' using errcode = '22023'; end if;
      delete from public.cycles_educatifs where id = p_id;
    when 'niveau' then
      select statut into v_statut from public.niveaux_educatifs where id = p_id;
      if public.niveau_utilise(p_id)
         or exists (select 1 from public.programmes_officiels where niveau_id = p_id) then
        raise exception 'ELEMENT_UTILISE' using errcode = '22023';
      end if;
      if v_statut = 'publie' then raise exception 'ELEMENT_PUBLIE' using errcode = '22023'; end if;
      delete from public.niveaux_educatifs where id = p_id;
    when 'examen' then
      select statut into v_statut from public.examens_nationaux where id = p_id;
      if exists (select 1 from public.epreuves_examen where examen_id = p_id) then
        raise exception 'ELEMENT_UTILISE' using errcode = '22023';
      end if;
      if v_statut = 'publie' then raise exception 'ELEMENT_PUBLIE' using errcode = '22023'; end if;
      delete from public.examens_nationaux where id = p_id;
    when 'programme' then
      if not exists (select 1 from public.programmes_officiels where id = p_id and etablissement_id is null) then
        raise exception 'PROGRAMME_INTROUVABLE' using errcode = '22023';
      end if;
      if exists (select 1 from public.questions q join public.programmes_matieres m on m.id = q.matiere_id
                  where m.programme_id = p_id) then
        raise exception 'QUESTIONS_EXISTANTES' using errcode = '22023';
      end if;
      if exists (select 1 from public.programmes_officiels where id = p_id and statut = 'publie') then
        raise exception 'ELEMENT_PUBLIE' using errcode = '22023';
      end if;
      delete from public.programmes_officiels where id = p_id;
    when 'matiere' then
      -- La suppression emporterait les questions de la banque (cascade).
      if exists (select 1 from public.questions where matiere_id = p_id) then
        raise exception 'QUESTIONS_EXISTANTES' using errcode = '22023';
      end if;
      if not exists (select 1 from public.programmes_matieres m join public.programmes_officiels p on p.id = m.programme_id
                      where m.id = p_id and p.etablissement_id is null) then
        raise exception 'PROGRAMME_INTROUVABLE' using errcode = '22023';
      end if;
      delete from public.programmes_matieres where id = p_id;
    else
      raise exception 'TYPE_INCONNU' using errcode = '22023';
  end case;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Contrôle avant publication
-- ---------------------------------------------------------------------------
create or replace function public.controle_referentiel(p_pays text)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_pays public.pays_pedagogiques;
  v_res jsonb := '[]'::jsonb;
  v_min int;
  v_max int;
  v_nb int;
  r record;
begin
  perform public.exiger_gere_referentiel();
  select * into v_pays from public.pays_pedagogiques where code_iso = upper(p_pays);
  if not found then raise exception 'PAYS_INTROUVABLE' using errcode = '22023'; end if;

  if v_pays.points_a_verifier is not null then
    v_res := v_res || jsonb_build_object('bloquant', true,
      'message', 'Des points restent à vérifier sur les textes officiels : videz le champ une fois confirmés.');
  end if;
  if not exists (select 1 from public.cycles_educatifs where pays_code = v_pays.code_iso) then
    v_res := v_res || jsonb_build_object('bloquant', true, 'message', 'Aucun cycle.');
  end if;
  for r in select c.nom from public.cycles_educatifs c
            where c.pays_code = v_pays.code_iso
              and not exists (select 1 from public.niveaux_educatifs n where n.cycle_id = c.id) loop
    v_res := v_res || jsonb_build_object('bloquant', true, 'message', format('Le cycle « %s » n''a aucun niveau.', r.nom));
  end loop;

  select min(grade_level_normalise), max(grade_level_normalise), count(*)
    into v_min, v_max, v_nb from public.niveaux_educatifs where pays_code = v_pays.code_iso;
  if v_nb > 0 and v_nb <> v_max - v_min + 1 then
    v_res := v_res || jsonb_build_object('bloquant', true,
      'message', 'Les rangs des niveaux ne se suivent pas : la montée de classe passerait un niveau.');
  end if;
  if v_nb > 0 and v_max >= 1 and not exists (
       select 1 from public.niveaux_educatifs where pays_code = v_pays.code_iso and grade_level_normalise = 1) then
    v_res := v_res || jsonb_build_object('bloquant', true,
      'message', 'Aucun niveau au rang 1 (première année du primaire, repère commun à tous les pays).');
  end if;
  for r in select n.nom from public.niveaux_educatifs n join public.cycles_educatifs c on c.id = n.cycle_id
            where n.pays_code = v_pays.code_iso and (n.isced < c.isced_min or n.isced > c.isced_max) loop
    v_res := v_res || jsonb_build_object('bloquant', false,
      'message', format('« %s » : niveau ISCED hors de celui de son cycle.', r.nom));
  end loop;
  for r in select e.code, c.nom from public.examens_nationaux e join public.cycles_educatifs c on c.id = e.cycle_id
            where e.pays_code = v_pays.code_iso
              and not exists (select 1 from public.niveaux_educatifs n where n.cycle_id = c.id and n.est_niveau_examinateur) loop
    v_res := v_res || jsonb_build_object('bloquant', true,
      'message', format('%s : aucune classe d''examen dans le cycle « %s ».', r.code, r.nom));
  end loop;
  if not exists (select 1 from public.examens_nationaux where pays_code = v_pays.code_iso) then
    v_res := v_res || jsonb_build_object('bloquant', false, 'message', 'Aucun examen national décrit.');
  end if;
  if not exists (select 1 from public.programmes_officiels p
                  where p.pays_code = v_pays.code_iso and p.etablissement_id is null) then
    v_res := v_res || jsonb_build_object('bloquant', false,
      'message', 'Aucun programme national : la banque de questions et les révisions resteront vides pour ce pays.');
  end if;
  return v_res;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Publication d'un pays
-- ---------------------------------------------------------------------------
create or replace function public.publier_pays_referentiel(p_pays text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_code text := upper(p_pays);
  v_n jsonb;
  c int; n int; e int;
begin
  perform public.exiger_gere_referentiel();
  if exists (select 1 from jsonb_array_elements(public.controle_referentiel(v_code)) x where (x ->> 'bloquant')::boolean) then
    raise exception 'REFERENTIEL_INCOMPLET' using errcode = '22023';
  end if;
  update public.cycles_educatifs set statut = 'publie' where pays_code = v_code and statut = 'brouillon';
  get diagnostics c = row_count;
  update public.niveaux_educatifs set statut = 'publie' where pays_code = v_code and statut = 'brouillon';
  get diagnostics n = row_count;
  update public.examens_nationaux set statut = 'publie' where pays_code = v_code and statut = 'brouillon';
  get diagnostics e = row_count;
  update public.pays_pedagogiques
     set statut_deploiement = 'deploye', publie_le = coalesce(publie_le, now()), publie_par = coalesce(publie_par, auth.uid())
   where code_iso = v_code;
  v_n := jsonb_build_object('cycles', c, 'niveaux', n, 'examens', e);
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Lecture du back-office (brouillons compris)
-- ---------------------------------------------------------------------------
create or replace function public.pays_back_office()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  perform public.exiger_gere_referentiel();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'code', p.code_iso, 'nom', p.nom, 'type_systeme', p.type_systeme, 'zone', p.zone,
             'statut', p.statut_deploiement, 'a_verifier', p.points_a_verifier is not null,
             'niveaux', (select count(*) from public.niveaux_educatifs n where n.pays_code = p.code_iso),
             'brouillons', (select count(*) from public.niveaux_educatifs n where n.pays_code = p.code_iso and n.statut = 'brouillon')
                         + (select count(*) from public.examens_nationaux x where x.pays_code = p.code_iso and x.statut = 'brouillon'),
             'examens', (select count(*) from public.examens_nationaux x where x.pays_code = p.code_iso),
             'programmes', (select count(*) from public.programmes_officiels o
                             where o.pays_code = p.code_iso and o.etablissement_id is null))
           order by p.statut_deploiement desc, p.zone, p.nom)
      from public.pays_pedagogiques p), '[]'::jsonb);
end;
$$;

create or replace function public.referentiel_back_office(p_pays text)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_code text := upper(p_pays);
begin
  perform public.exiger_gere_referentiel();
  return (
    select jsonb_build_object(
      'pays', to_jsonb(p) - 'publie_par',
      'controle', public.controle_referentiel(v_code),
      'cycles', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', c.id, 'code', c.code, 'nom', c.nom, 'ordre', c.ordre, 'age_min', c.age_min, 'age_max', c.age_max,
                 'duree', c.duree_annees, 'isced_min', c.isced_min, 'isced_max', c.isced_max, 'statut', c.statut,
                 'niveaux', coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'id', n.id, 'code', n.code, 'nom', n.nom, 'grade', n.grade_level_normalise, 'isced', n.isced,
                            'ordre', n.ordre, 'examinateur', n.est_niveau_examinateur, 'statut', n.statut,
                            'utilise', public.niveau_utilise(n.id),
                            'programmes', coalesce((
                              select jsonb_agg(jsonb_build_object(
                                       'id', o.id, 'nom', o.nom, 'statut', o.statut, 'annee', o.annee_scolaire,
                                       'filiere', (select f.code from public.filieres_educatives f where f.id = o.filiere_id),
                                       'matieres', coalesce((
                                         select jsonb_agg(jsonb_build_object(
                                                  'id', m.id, 'code', m.code, 'nom', m.nom, 'ordre', m.ordre, 'nature', m.nature,
                                                  'questions', (select count(*) from public.questions q where q.matiere_id = m.id))
                                                order by m.ordre, m.nom)
                                           from public.programmes_matieres m where m.programme_id = o.id), '[]'::jsonb))
                                     order by o.code)
                                from public.programmes_officiels o
                               where o.niveau_id = n.id and o.etablissement_id is null and o.statut <> 'archive'), '[]'::jsonb))
                          order by n.grade_level_normalise)
                     from public.niveaux_educatifs n where n.cycle_id = c.id), '[]'::jsonb))
               order by c.ordre)
          from public.cycles_educatifs c where c.pays_code = v_code), '[]'::jsonb),
      'examens', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', e.id, 'code', e.code, 'nom', e.nom, 'organisme', e.organisme, 'mois', e.mois_session,
                 'cycle_id', e.cycle_id, 'statut', e.statut)
               order by (select c.ordre from public.cycles_educatifs c where c.id = e.cycle_id), e.code)
          from public.examens_nationaux e where e.pays_code = v_code), '[]'::jsonb),
      'series', coalesce((
        select jsonb_agg(jsonb_build_object('id', f.id, 'code', f.code, 'nom', f.nom) order by f.ordre, f.code)
          from public.filieres_educatives f where f.pays_code = v_code), '[]'::jsonb)
    )
    from public.pays_pedagogiques p where p.code_iso = v_code
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Droits
-- ---------------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'public.exiger_gere_referentiel()',
    'public.enregistrer_pays_referentiel(text, text, text, text, text, text, text, text, text)',
    'public.enregistrer_cycle_referentiel(uuid, text, text, text, int, int, int, int, int, int)',
    'public.niveau_utilise(uuid)',
    'public.enregistrer_niveau_referentiel(uuid, uuid, text, text, int, int, int, boolean)',
    'public.enregistrer_examen_referentiel(uuid, text, uuid, text, text, text, int)',
    'public.enregistrer_programme_national(uuid, uuid, uuid, text, text)',
    'public.enregistrer_matiere_nationale(uuid, uuid, text, text, int, text)',
    'public.publier_programme_national(uuid)',
    'public.supprimer_element_referentiel(text, uuid)',
    'public.controle_referentiel(text)',
    'public.publier_pays_referentiel(text)',
    'public.pays_back_office()',
    'public.referentiel_back_office(text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 9. Pays de la sous-région, en brouillon (recherche REG-38, à confirmer)
-- ---------------------------------------------------------------------------
update public.pays_pedagogiques set zone = 'cedeao' where code_iso in ('GN', 'SN', 'GH');

insert into public.pays_pedagogiques
  (code_iso, nom, type_systeme, langue_enseignement_principale, organisme_examinateur, devise_code,
   statut_deploiement, zone, sources, points_a_verifier)
values
  ('CI', 'Côte d''Ivoire', 'francophone_cfa', 'fr', 'DECO (Direction des Examens et Concours)', 'XOF', 'brouillon', 'cedeao',
   'Calendriers officiels des « examens à grand tirage » (CEPE, BEPC, BAC), presse nationale 2024-2026.',
   'Mois des sessions de l''année en cours ; noms officiels des classes.'),
  ('BJ', 'Bénin', 'francophone_cfa', 'fr', 'Office du Baccalauréat / Direction des examens et concours', 'XOF', 'brouillon', 'cedeao',
   'Ministère des Enseignements secondaire (communiqués BEPC) ; structure 6 + 4 + 3.',
   'Nom officiel du certificat de fin de primaire (CEP) ; mois des sessions.'),
  ('TG', 'Togo', 'francophone_cfa', 'fr', 'Direction des Examens, Concours et Certifications', 'XOF', 'brouillon', 'cedeao',
   'Calendrier officiel des examens 2023-2024 (CEPD, BEPC, BAC I, BAC II).',
   'Le BAC I (classe de Première) est-il maintenu cette année ? Supprimer l''examen sinon.'),
  ('NG', 'Nigeria', 'anglophone_waec', 'en', 'WAEC / NECO', 'NGN', 'brouillon', 'cedeao',
   'Structure 6-3-3 (Primary 1-6, JSS 1-3, SS 1-3) ; SSCE de WAEC et de NECO.',
   'Organisme du BECE (État ou NECO) ; réforme 9-3-4 annoncée : vérifier la structure en vigueur.'),
  ('SL', 'Sierra Leone', 'anglophone_waec', 'en', 'WAEC', 'SLE', 'brouillon', 'cedeao',
   'Structure 6-3-3 ; NPSE, BECE et WASSCE organisés par WAEC.',
   'Le lycée (SSS) dure-t-il 3 ou 4 ans ? Le pays a alterné entre les deux.'),
  ('LR', 'Liberia', 'anglophone_waec', 'en', 'WAEC', 'LRD', 'brouillon', 'cedeao',
   'Structure 6-3-3 ; WASSCE adopté en 2011 (30 % contrôle continu, 70 % examen).',
   'Examens nationaux de 6e et de 9e année (WAEC) : encore organisés ?'),
  ('GM', 'Gambie', 'anglophone_waec', 'en', 'WAEC', 'GMD', 'brouillon', 'cedeao',
   'Structure : Lower Basic 1-6, Upper Basic 7-9, Senior Secondary 10-12 ; WASSCE en fin de 12e.',
   'Nom et organisme de l''examen de fin de 9e année (GABECE).'),
  ('CV', 'Cap-Vert', 'lusophone', 'pt', 'Ministério da Educação', 'CVE', 'brouillon', 'cedeao',
   null, 'Saisir les cycles et niveaux d''après la loi de base du système éducatif (ensino básico, secundário).'),
  ('GW', 'Guinée-Bissau', 'lusophone', 'pt', 'Ministério da Educação Nacional', 'XOF', 'brouillon', 'cedeao',
   null, 'Saisir les cycles et niveaux d''après la loi de base du système éducatif.'),
  ('ML', 'Mali', 'francophone_cfa', 'fr', 'Centre National des Examens et Concours de l''Éducation', 'XOF', 'brouillon', 'aes',
   'Enseignement fondamental 6 + 3 ans (CEP, DEF), secondaire 3 ans (BAC).',
   'Le CEP de fin de 6e année est-il encore organisé ? Noms officiels des classes du lycée.'),
  ('BF', 'Burkina Faso', 'francophone_cfa', 'fr', 'Office du Baccalauréat / DGEC', 'XOF', 'brouillon', 'aes',
   'Primaire CP1-CM2 (CEP), post-primaire 6e-3e (BEPC), secondaire 2nde-Terminale (BAC).',
   'Mois des sessions ; réforme des examens en cours.'),
  ('NE', 'Niger', 'francophone_cfa', 'fr', 'Ministère de l''Éducation nationale / Office du Bac', 'XOF', 'brouillon', 'aes',
   'Primaire CI-CM2 (CFEPD), collège 6e-3e (BEPC), lycée 2nde-Terminale (BAC).',
   'Mois des sessions ; organisme du BAC.')
on conflict (code_iso) do nothing;

-- Cycles (en brouillon).
insert into public.cycles_educatifs (pays_code, code, nom, ordre, age_min, age_max, duree_annees, isced_min, isced_max)
select v.pays, v.code, v.nom, v.ordre, v.amin, v.amax, v.duree, v.imin, v.imax
from (values
  ('CI', 'primaire', 'Primaire', 1, 6, 11, 6, 1, 1), ('CI', 'college', 'Collège', 2, 12, 15, 4, 2, 2), ('CI', 'lycee', 'Lycée', 3, 16, 18, 3, 3, 3),
  ('BJ', 'primaire', 'Primaire', 1, 6, 11, 6, 1, 1), ('BJ', 'college', 'Premier cycle du secondaire', 2, 12, 15, 4, 2, 2),
  ('BJ', 'lycee', 'Second cycle du secondaire', 3, 16, 18, 3, 3, 3),
  ('TG', 'primaire', 'Primaire', 1, 6, 11, 6, 1, 1), ('TG', 'college', 'Collège', 2, 12, 15, 4, 2, 2), ('TG', 'lycee', 'Lycée', 3, 16, 18, 3, 3, 3),
  ('BF', 'primaire', 'Primaire', 1, 6, 11, 6, 1, 1), ('BF', 'post_primaire', 'Post-primaire', 2, 12, 15, 4, 2, 2),
  ('BF', 'secondaire', 'Secondaire', 3, 16, 18, 3, 3, 3),
  ('NE', 'primaire', 'Primaire', 1, 6, 11, 6, 1, 1), ('NE', 'college', 'Collège', 2, 12, 15, 4, 2, 2), ('NE', 'lycee', 'Lycée', 3, 16, 18, 3, 3, 3),
  ('ML', 'fondamental_1', 'Fondamental, premier cycle', 1, 7, 12, 6, 1, 1),
  ('ML', 'fondamental_2', 'Fondamental, second cycle', 2, 13, 15, 3, 2, 2),
  ('ML', 'secondaire', 'Secondaire', 3, 16, 18, 3, 3, 3),
  ('NG', 'primary', 'Primary', 1, 6, 11, 6, 1, 1), ('NG', 'junior_secondary', 'Junior Secondary', 2, 12, 14, 3, 2, 2),
  ('NG', 'senior_secondary', 'Senior Secondary', 3, 15, 17, 3, 3, 3),
  ('SL', 'primary', 'Primary', 1, 6, 11, 6, 1, 1), ('SL', 'junior_secondary', 'Junior Secondary', 2, 12, 14, 3, 2, 2),
  ('SL', 'senior_secondary', 'Senior Secondary', 3, 15, 17, 3, 3, 3),
  ('LR', 'primary', 'Primary', 1, 6, 11, 6, 1, 1), ('LR', 'junior_high', 'Junior High', 2, 12, 14, 3, 2, 2),
  ('LR', 'senior_high', 'Senior High', 3, 15, 17, 3, 3, 3),
  ('GM', 'lower_basic', 'Lower Basic', 1, 7, 12, 6, 1, 1), ('GM', 'upper_basic', 'Upper Basic', 2, 13, 15, 3, 2, 2),
  ('GM', 'senior_secondary', 'Senior Secondary', 3, 16, 18, 3, 3, 3)
) as v(pays, code, nom, ordre, amin, amax, duree, imin, imax)
on conflict (pays_code, code) do nothing;

-- Niveaux (en brouillon) : rang 1 = première année du primaire partout.
insert into public.niveaux_educatifs
  (cycle_id, pays_code, code, nom, grade_level_normalise, isced, ordre, est_niveau_examinateur)
select c.id, v.pays, v.code, v.nom, v.grade, c.isced_min, v.ordre, v.examen
from (values
  ('CI', 'primaire', 'CP1', 'Cours Préparatoire 1ère année', 1, 1, false), ('CI', 'primaire', 'CP2', 'Cours Préparatoire 2ème année', 2, 2, false),
  ('CI', 'primaire', 'CE1', 'Cours Élémentaire 1ère année', 3, 3, false), ('CI', 'primaire', 'CE2', 'Cours Élémentaire 2ème année', 4, 4, false),
  ('CI', 'primaire', 'CM1', 'Cours Moyen 1ère année', 5, 5, false), ('CI', 'primaire', 'CM2', 'Cours Moyen 2ème année', 6, 6, true),
  ('CI', 'college', '6e', 'Sixième', 7, 1, false), ('CI', 'college', '5e', 'Cinquième', 8, 2, false),
  ('CI', 'college', '4e', 'Quatrième', 9, 3, false), ('CI', 'college', '3e', 'Troisième', 10, 4, true),
  ('CI', 'lycee', '2nde', 'Seconde', 11, 1, false), ('CI', 'lycee', '1ere', 'Première', 12, 2, false),
  ('CI', 'lycee', 'Terminale', 'Terminale', 13, 3, true),

  ('BJ', 'primaire', 'CI', 'Cours d''Initiation', 1, 1, false), ('BJ', 'primaire', 'CP', 'Cours Préparatoire', 2, 2, false),
  ('BJ', 'primaire', 'CE1', 'Cours Élémentaire 1ère année', 3, 3, false), ('BJ', 'primaire', 'CE2', 'Cours Élémentaire 2ème année', 4, 4, false),
  ('BJ', 'primaire', 'CM1', 'Cours Moyen 1ère année', 5, 5, false), ('BJ', 'primaire', 'CM2', 'Cours Moyen 2ème année', 6, 6, true),
  ('BJ', 'college', '6e', 'Sixième', 7, 1, false), ('BJ', 'college', '5e', 'Cinquième', 8, 2, false),
  ('BJ', 'college', '4e', 'Quatrième', 9, 3, false), ('BJ', 'college', '3e', 'Troisième', 10, 4, true),
  ('BJ', 'lycee', '2nde', 'Seconde', 11, 1, false), ('BJ', 'lycee', '1ere', 'Première', 12, 2, false),
  ('BJ', 'lycee', 'Terminale', 'Terminale', 13, 3, true),

  ('TG', 'primaire', 'CP1', 'Cours Préparatoire 1ère année', 1, 1, false), ('TG', 'primaire', 'CP2', 'Cours Préparatoire 2ème année', 2, 2, false),
  ('TG', 'primaire', 'CE1', 'Cours Élémentaire 1ère année', 3, 3, false), ('TG', 'primaire', 'CE2', 'Cours Élémentaire 2ème année', 4, 4, false),
  ('TG', 'primaire', 'CM1', 'Cours Moyen 1ère année', 5, 5, false), ('TG', 'primaire', 'CM2', 'Cours Moyen 2ème année', 6, 6, true),
  ('TG', 'college', '6e', 'Sixième', 7, 1, false), ('TG', 'college', '5e', 'Cinquième', 8, 2, false),
  ('TG', 'college', '4e', 'Quatrième', 9, 3, false), ('TG', 'college', '3e', 'Troisième', 10, 4, true),
  ('TG', 'lycee', '2nde', 'Seconde', 11, 1, false), ('TG', 'lycee', '1ere', 'Première', 12, 2, true),
  ('TG', 'lycee', 'Terminale', 'Terminale', 13, 3, true),

  ('BF', 'primaire', 'CP1', 'Cours Préparatoire 1ère année', 1, 1, false), ('BF', 'primaire', 'CP2', 'Cours Préparatoire 2ème année', 2, 2, false),
  ('BF', 'primaire', 'CE1', 'Cours Élémentaire 1ère année', 3, 3, false), ('BF', 'primaire', 'CE2', 'Cours Élémentaire 2ème année', 4, 4, false),
  ('BF', 'primaire', 'CM1', 'Cours Moyen 1ère année', 5, 5, false), ('BF', 'primaire', 'CM2', 'Cours Moyen 2ème année', 6, 6, true),
  ('BF', 'post_primaire', '6e', 'Sixième', 7, 1, false), ('BF', 'post_primaire', '5e', 'Cinquième', 8, 2, false),
  ('BF', 'post_primaire', '4e', 'Quatrième', 9, 3, false), ('BF', 'post_primaire', '3e', 'Troisième', 10, 4, true),
  ('BF', 'secondaire', '2nde', 'Seconde', 11, 1, false), ('BF', 'secondaire', '1ere', 'Première', 12, 2, false),
  ('BF', 'secondaire', 'Terminale', 'Terminale', 13, 3, true),

  ('NE', 'primaire', 'CI', 'Cours d''Initiation', 1, 1, false), ('NE', 'primaire', 'CP', 'Cours Préparatoire', 2, 2, false),
  ('NE', 'primaire', 'CE1', 'Cours Élémentaire 1ère année', 3, 3, false), ('NE', 'primaire', 'CE2', 'Cours Élémentaire 2ème année', 4, 4, false),
  ('NE', 'primaire', 'CM1', 'Cours Moyen 1ère année', 5, 5, false), ('NE', 'primaire', 'CM2', 'Cours Moyen 2ème année', 6, 6, true),
  ('NE', 'college', '6e', 'Sixième', 7, 1, false), ('NE', 'college', '5e', 'Cinquième', 8, 2, false),
  ('NE', 'college', '4e', 'Quatrième', 9, 3, false), ('NE', 'college', '3e', 'Troisième', 10, 4, true),
  ('NE', 'lycee', '2nde', 'Seconde', 11, 1, false), ('NE', 'lycee', '1ere', 'Première', 12, 2, false),
  ('NE', 'lycee', 'Terminale', 'Terminale', 13, 3, true),

  ('ML', 'fondamental_1', '1A', '1ère année', 1, 1, false), ('ML', 'fondamental_1', '2A', '2e année', 2, 2, false),
  ('ML', 'fondamental_1', '3A', '3e année', 3, 3, false), ('ML', 'fondamental_1', '4A', '4e année', 4, 4, false),
  ('ML', 'fondamental_1', '5A', '5e année', 5, 5, false), ('ML', 'fondamental_1', '6A', '6e année', 6, 6, true),
  ('ML', 'fondamental_2', '7A', '7e année', 7, 1, false), ('ML', 'fondamental_2', '8A', '8e année', 8, 2, false),
  ('ML', 'fondamental_2', '9A', '9e année', 9, 3, true),
  ('ML', 'secondaire', '10A', '10e année', 10, 1, false), ('ML', 'secondaire', '11A', '11e année', 11, 2, false),
  ('ML', 'secondaire', 'Terminale', 'Terminale (12e année)', 12, 3, true),

  ('NG', 'primary', 'P1', 'Primary 1', 1, 1, false), ('NG', 'primary', 'P2', 'Primary 2', 2, 2, false),
  ('NG', 'primary', 'P3', 'Primary 3', 3, 3, false), ('NG', 'primary', 'P4', 'Primary 4', 4, 4, false),
  ('NG', 'primary', 'P5', 'Primary 5', 5, 5, false), ('NG', 'primary', 'P6', 'Primary 6', 6, 6, false),
  ('NG', 'junior_secondary', 'JSS1', 'Junior Secondary School 1', 7, 1, false),
  ('NG', 'junior_secondary', 'JSS2', 'Junior Secondary School 2', 8, 2, false),
  ('NG', 'junior_secondary', 'JSS3', 'Junior Secondary School 3', 9, 3, true),
  ('NG', 'senior_secondary', 'SS1', 'Senior Secondary 1', 10, 1, false),
  ('NG', 'senior_secondary', 'SS2', 'Senior Secondary 2', 11, 2, false),
  ('NG', 'senior_secondary', 'SS3', 'Senior Secondary 3', 12, 3, true),

  ('SL', 'primary', 'C1', 'Class 1', 1, 1, false), ('SL', 'primary', 'C2', 'Class 2', 2, 2, false),
  ('SL', 'primary', 'C3', 'Class 3', 3, 3, false), ('SL', 'primary', 'C4', 'Class 4', 4, 4, false),
  ('SL', 'primary', 'C5', 'Class 5', 5, 5, false), ('SL', 'primary', 'C6', 'Class 6', 6, 6, true),
  ('SL', 'junior_secondary', 'JSS1', 'Junior Secondary School 1', 7, 1, false),
  ('SL', 'junior_secondary', 'JSS2', 'Junior Secondary School 2', 8, 2, false),
  ('SL', 'junior_secondary', 'JSS3', 'Junior Secondary School 3', 9, 3, true),
  ('SL', 'senior_secondary', 'SSS1', 'Senior Secondary School 1', 10, 1, false),
  ('SL', 'senior_secondary', 'SSS2', 'Senior Secondary School 2', 11, 2, false),
  ('SL', 'senior_secondary', 'SSS3', 'Senior Secondary School 3', 12, 3, true),

  ('LR', 'primary', 'G1', 'Grade 1', 1, 1, false), ('LR', 'primary', 'G2', 'Grade 2', 2, 2, false),
  ('LR', 'primary', 'G3', 'Grade 3', 3, 3, false), ('LR', 'primary', 'G4', 'Grade 4', 4, 4, false),
  ('LR', 'primary', 'G5', 'Grade 5', 5, 5, false), ('LR', 'primary', 'G6', 'Grade 6', 6, 6, false),
  ('LR', 'junior_high', 'G7', 'Grade 7', 7, 1, false), ('LR', 'junior_high', 'G8', 'Grade 8', 8, 2, false),
  ('LR', 'junior_high', 'G9', 'Grade 9', 9, 3, false),
  ('LR', 'senior_high', 'G10', 'Grade 10', 10, 1, false), ('LR', 'senior_high', 'G11', 'Grade 11', 11, 2, false),
  ('LR', 'senior_high', 'G12', 'Grade 12', 12, 3, true),

  ('GM', 'lower_basic', 'G1', 'Grade 1', 1, 1, false), ('GM', 'lower_basic', 'G2', 'Grade 2', 2, 2, false),
  ('GM', 'lower_basic', 'G3', 'Grade 3', 3, 3, false), ('GM', 'lower_basic', 'G4', 'Grade 4', 4, 4, false),
  ('GM', 'lower_basic', 'G5', 'Grade 5', 5, 5, false), ('GM', 'lower_basic', 'G6', 'Grade 6', 6, 6, false),
  ('GM', 'upper_basic', 'G7', 'Grade 7', 7, 1, false), ('GM', 'upper_basic', 'G8', 'Grade 8', 8, 2, false),
  ('GM', 'upper_basic', 'G9', 'Grade 9', 9, 3, true),
  ('GM', 'senior_secondary', 'G10', 'Grade 10', 10, 1, false), ('GM', 'senior_secondary', 'G11', 'Grade 11', 11, 2, false),
  ('GM', 'senior_secondary', 'G12', 'Grade 12', 12, 3, true)
) as v(pays, cycle, code, nom, grade, ordre, examen)
join public.cycles_educatifs c on c.pays_code = v.pays and c.code = v.cycle
on conflict (pays_code, code) do nothing;

-- Examens (en brouillon).
insert into public.examens_nationaux (pays_code, cycle_id, code, nom, organisme, mois_session, periodicite)
select v.pays, c.id, v.code, v.nom, v.organisme, v.mois, 'annuelle'
from (values
  ('CI', 'primaire', 'CEPE', 'Certificat d''Études Primaires Élémentaires', 'DECO', 5),
  ('CI', 'college', 'BEPC', 'Brevet d''Études du Premier Cycle', 'DECO', 6),
  ('CI', 'lycee', 'BAC', 'Baccalauréat', 'DECO', 6),
  ('BJ', 'primaire', 'CEP', 'Certificat d''Études Primaires', 'Ministère', 6),
  ('BJ', 'college', 'BEPC', 'Brevet d''Études du Premier Cycle', 'Ministère', 6),
  ('BJ', 'lycee', 'BAC', 'Baccalauréat', 'Office du Baccalauréat', 6),
  ('TG', 'primaire', 'CEPD', 'Certificat d''Études du Premier Degré', 'DECC', 6),
  ('TG', 'college', 'BEPC', 'Brevet d''Études du Premier Cycle', 'DECC', 6),
  ('TG', 'lycee', 'BAC1', 'Baccalauréat, première partie (BAC I)', 'DECC', 5),
  ('TG', 'lycee', 'BAC2', 'Baccalauréat, deuxième partie (BAC II)', 'DECC', 6),
  ('BF', 'primaire', 'CEP', 'Certificat d''Études Primaires', 'Ministère', 6),
  ('BF', 'post_primaire', 'BEPC', 'Brevet d''Études du Premier Cycle', 'Ministère', 6),
  ('BF', 'secondaire', 'BAC', 'Baccalauréat', 'Office du Baccalauréat', 7),
  ('NE', 'primaire', 'CFEPD', 'Certificat de Fin d''Études du Premier Degré', 'Ministère', 6),
  ('NE', 'college', 'BEPC', 'Brevet d''Études du Premier Cycle', 'Ministère', 6),
  ('NE', 'lycee', 'BAC', 'Baccalauréat', 'Ministère', 7),
  ('ML', 'fondamental_1', 'CEP', 'Certificat d''Études Primaires', 'CNECE', 6),
  ('ML', 'fondamental_2', 'DEF', 'Diplôme d''Études Fondamentales', 'CNECE', 6),
  ('ML', 'secondaire', 'BAC', 'Baccalauréat', 'CNECE', 7),
  ('NG', 'junior_secondary', 'BECE', 'Basic Education Certificate Examination', 'NECO / États', 6),
  ('NG', 'senior_secondary', 'WASSCE', 'West African Senior School Certificate Examination', 'WAEC', 5),
  ('NG', 'senior_secondary', 'NECO_SSCE', 'Senior School Certificate Examination (NECO)', 'NECO', 6),
  ('SL', 'primary', 'NPSE', 'National Primary School Examination', 'WAEC', 6),
  ('SL', 'junior_secondary', 'BECE', 'Basic Education Certificate Examination', 'WAEC', 6),
  ('SL', 'senior_secondary', 'WASSCE', 'West African Senior School Certificate Examination', 'WAEC', 5),
  ('LR', 'senior_high', 'WASSCE', 'West African Senior School Certificate Examination', 'WAEC', 5),
  ('GM', 'upper_basic', 'GABECE', 'Gambia Basic Education Certificate Examination', 'WAEC', 6),
  ('GM', 'senior_secondary', 'WASSCE', 'West African Senior School Certificate Examination', 'WAEC', 5)
) as v(pays, cycle, code, nom, organisme, mois)
join public.cycles_educatifs c on c.pays_code = v.pays and c.code = v.cycle
on conflict (pays_code, code) do nothing;
