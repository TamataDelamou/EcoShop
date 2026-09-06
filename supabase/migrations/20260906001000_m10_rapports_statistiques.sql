-- ===========================================================================
-- M10 — Rapports & Statistiques académiques
-- Consolidation M6 (notes) × M7 (assiduité) × M8 (RH) × M9 (communication).
-- Tableaux de bord, exports différés, détection d'anomalies, recommandations
-- stratégiques et résumé exécutif en langage naturel (NLG).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 0. Types énumérés (idempotent)
-- ---------------------------------------------------------------------------
do $$
begin
  create type public.type_export as enum ('pdf', 'excel', 'csv', 'json');
exception when duplicate_object then null; end $$;

do $$
begin
  create type public.statut_rapport as enum ('demande', 'en_attente', 'genere', 'echec', 'expire');
exception when duplicate_object then null; end $$;

do $$
begin
  create type public.statut_anomalie as enum ('ouverte', 'confirmee', 'rejetee', 'traitee');
exception when duplicate_object then null; end $$;

do $$
begin
  create type public.statut_recommandation as enum ('proposee', 'validee', 'mise_en_oeuvre', 'rejetee');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 1. Permissions fines (jamais codées en dur dans le client)
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domaine, libelle, description) values
  ('rapports.consulter',   'rapports', 'Consulter les rapports',       'Lire les indicateurs et rapports de son établissement'),
  ('rapports.generer',     'rapports', 'Générer les rapports',         'Lancer les analyses, détections et générations de rapports'),
  ('rapports.administrer', 'rapports', 'Administrer les rapports',     'Valider les anomalies et les recommandations stratégiques')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 2. Rapports — demandes de génération (bulletin, relevé, stats, personnalisé)
--    La génération est différée : statut « demande » → traitement → « genere ».
--    Hors-ligne : `demande_hors_ligne` + `cache_valide_jus` (cache côté client).
-- ---------------------------------------------------------------------------
create table if not exists public.rapports (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  periode_id uuid references public.periodes_scolaires (id) on delete set null,
  classe_id uuid references public.classes (id) on delete cascade,
  fiche_eleve_id uuid references public.fiches_eleves (id) on delete cascade,
  type text not null check (length(type) > 0),   -- bulletin | releve_notes | statistiques_globales | personnalise | resume_executif
  format public.type_export not null default 'pdf',
  filtres jsonb not null default '{}'::jsonb,
  statut public.statut_rapport not null default 'demande',
  contenu jsonb,
  fichier_url text,
  signature_sha256 text,
  genere_par uuid references public.profiles (id) on delete set null,
  genere_le timestamptz,
  demande_hors_ligne boolean not null default false,
  cache_valide_jus date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

drop trigger if exists rapports_set_updated_at on public.rapports;
create trigger rapports_set_updated_at
  before update on public.rapports
  for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3. Indicateurs clés — KPI pré-calculés des tableaux de bord
-- ---------------------------------------------------------------------------
create table if not exists public.indicateurs_cles (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  periode_id uuid references public.periodes_scolaires (id) on delete set null,
  classe_id uuid references public.classes (id) on delete cascade,
  code text not null,                 -- effectifs | taux_reussite | absentisme | turnover | masse_salariale | engagement_parents
  valeur_numeric numeric(12,4),
  valeur_texte text,
  valeur_jsonb jsonb,
  calcule_le timestamptz not null default now(),
  version int not null default 1
);

create unique index if not exists idx_indicateurs_etab_annee_code_unique
  on public.indicateurs_cles (etablissement_id, annee_scolaire_id, code)
  where periode_id is null and classe_id is null;

-- ---------------------------------------------------------------------------
-- 4. Anomalies statistiques — données aberrantes à validation humaine
-- ---------------------------------------------------------------------------
create table if not exists public.anomalies_statistiques (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  classe_id uuid references public.classes (id) on delete cascade,
  fiche_eleve_id uuid references public.fiches_eleves (id) on delete cascade,
  employe_id uuid references public.employes (id) on delete cascade,
  type text not null check (length(type) > 0),          -- note | absence | retard | paie | autre
  severite text not null check (severite in ('faible', 'moyenne', 'elevee')),
  description text not null,
  valeur_observee numeric(12,4),
  valeur_attendue numeric(12,4),
  ecart numeric(12,4),
  contexte jsonb not null default '{}'::jsonb,
  signature text not null,
  statut public.statut_anomalie not null default 'ouverte',
  detectee_le timestamptz not null default now(),
  traitee_par uuid references public.profiles (id) on delete set null,
  traitee_le timestamptz,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists idx_anomalies_etab_signature_unique
  on public.anomalies_statistiques (etablissement_id, signature);

-- ---------------------------------------------------------------------------
-- 5. Recommandations stratégiques — actions correctives proposées par l'IA,
--    validées par un humain (direction/RH).
-- ---------------------------------------------------------------------------
create table if not exists public.recommandations_strategiques (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements (id) on delete cascade,
  annee_scolaire_id uuid not null references public.annees_scolaires (id) on delete cascade,
  classe_id uuid references public.classes (id) on delete cascade,
  type text not null check (type in ('renforcement', 'tutorat', 'effectifs', 'autre')),
  titre text not null,
  description text not null,
  justification jsonb not null default '{}'::jsonb,   -- traçabilité (valeurs sources)
  priorite text not null check (priorite in ('basse', 'moyenne', 'haute')),
  statut public.statut_recommandation not null default 'proposee',
  cree_le timestamptz not null default now(),
  validee_par uuid references public.profiles (id) on delete set null,
  validee_le timestamptz,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists idx_recos_classe_type_unique
  on public.recommandations_strategiques (etablissement_id, annee_scolaire_id, classe_id, type)
  where classe_id is not null;

-- ---------------------------------------------------------------------------
-- 6. Garde-fous multi-tenant — l'établissement des clés étrangères doit
--    toujours coïncider avec l'établissement de la ligne.
-- ---------------------------------------------------------------------------
create or replace function public.rapports_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  if new.annee_scolaire_id is not null then
    select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'RAPPORT_ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;
  if new.classe_id is not null then
    select etablissement_id into v_etab from public.classes where id = new.classe_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'RAPPORT_CLASSE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;
  if new.fiche_eleve_id is not null then
    select etablissement_id into v_etab from public.fiches_eleves where id = new.fiche_eleve_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'RAPPORT_FICHE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists rapports_verifie_tenant_trg on public.rapports;
create trigger rapports_verifie_tenant_trg
  before insert or update on public.rapports
  for each row execute procedure public.rapports_verifie_tenant();

create or replace function public.indicateurs_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'INDICATEUR_ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  if new.classe_id is not null then
    select etablissement_id into v_etab from public.classes where id = new.classe_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'INDICATEUR_CLASSE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists indicateurs_verifie_tenant_trg on public.indicateurs_cles;
create trigger indicateurs_verifie_tenant_trg
  before insert or update on public.indicateurs_cles
  for each row execute procedure public.indicateurs_verifie_tenant();

create or replace function public.anomalies_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'ANOMALIE_ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  if new.classe_id is not null then
    select etablissement_id into v_etab from public.classes where id = new.classe_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'ANOMALIE_CLASSE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;
  if new.fiche_eleve_id is not null then
    select etablissement_id into v_etab from public.fiches_eleves where id = new.fiche_eleve_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'ANOMALIE_FICHE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;
  if new.employe_id is not null then
    select etablissement_id into v_etab from public.employes where id = new.employe_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'ANOMALIE_EMPLOYE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists anomalies_verifie_tenant_trg on public.anomalies_statistiques;
create trigger anomalies_verifie_tenant_trg
  before insert or update on public.anomalies_statistiques
  for each row execute procedure public.anomalies_verifie_tenant();

create or replace function public.recommandations_verifie_tenant()
returns trigger language plpgsql set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.annees_scolaires where id = new.annee_scolaire_id;
  if v_etab is distinct from new.etablissement_id then
    raise exception 'RECOMMANDATION_ANNEE_AUTRE_ETABLISSEMENT' using errcode = '23514';
  end if;
  if new.classe_id is not null then
    select etablissement_id into v_etab from public.classes where id = new.classe_id;
    if v_etab is distinct from new.etablissement_id then
      raise exception 'RECOMMANDATION_CLASSE_AUTRE_ETABLISSEMENT' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists recommandations_verifie_tenant_trg on public.recommandations_strategiques;
create trigger recommandations_verifie_tenant_trg
  before insert or update on public.recommandations_strategiques
  for each row execute procedure public.recommandations_verifie_tenant();

-- ---------------------------------------------------------------------------
-- 7. Fonctions IA (SECURITY DEFINER, gated par est_personnel)
-- ---------------------------------------------------------------------------

-- 7.1 Consolidation des indicateurs clés d'un établissement pour une année.
create or replace function public.consolider_indicateurs_etablissement(p_etab uuid, p_annee uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  v_effectifs numeric; v_reussite numeric; v_absenteisme numeric;
  v_turnover numeric; v_masse numeric; v_engagement numeric;
  v_d date; v_f date;
begin
  if not public.est_personnel(p_etab) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;
  select date_debut, date_fin into v_d, v_f from public.annees_scolaires where id = p_annee;

  select count(*) into v_effectifs
  from public.inscriptions i
  where i.etablissement_id = p_etab and i.annee_scolaire_id = p_annee
    and i.statut = 'active' and i.deleted_at is null;

  select case when count(*) = 0 then 0
              else count(*) filter (where n.valeur / e.bareme >= 0.5)::numeric / count(*)::numeric end
  into v_reussite
  from public.notes n
  join public.evaluations e on e.id = n.evaluation_id
  where n.etablissement_id = p_etab and e.annee_scolaire_id = p_annee
    and n.deleted_at is null and e.deleted_at is null
    and n.absent = false and n.valeur is not null;

  select case when count(*) = 0 then 0
              else count(*) filter (where p.statut <> 'present')::numeric / count(*)::numeric end
  into v_absenteisme
  from public.presences p
  where p.etablissement_id = p_etab and p.annee_scolaire_id = p_annee and p.deleted_at is null;

  select case when count(*) = 0 then 0
              else count(*) filter (where emp.statut in ('demissionnaire','suspendu','retraite'))::numeric / count(*)::numeric end
  into v_turnover
  from public.employes emp
  where emp.etablissement_id = p_etab and emp.deleted_at is null;

  select coalesce(sum(pb.net), 0) into v_masse
  from public.paie_bulletins pb
  where pb.etablissement_id = p_etab and pb.deleted_at is null
    and pb.periode_debut between v_d and v_f;

  select case when count(*) = 0 then 0
              else count(*) filter (where n.date_lecture is not null)::numeric / count(*)::numeric end
  into v_engagement
  from public.notifications n
  where n.etablissement_id = p_etab and n.deleted_at is null
    and n.date_envoi is not null
    and n.date_envoi::date between v_d and v_f;

  insert into public.indicateurs_cles (etablissement_id, annee_scolaire_id, code, valeur_numeric, calcule_le, version)
  values
    (p_etab, p_annee, 'effectifs',          v_effectifs,  now(), 1),
    (p_etab, p_annee, 'taux_reussite',      v_reussite,   now(), 1),
    (p_etab, p_annee, 'absentisme',         v_absenteisme,now(), 1),
    (p_etab, p_annee, 'turnover',           v_turnover,   now(), 1),
    (p_etab, p_annee, 'masse_salariale',    v_masse,      now(), 1),
    (p_etab, p_annee, 'engagement_parents', v_engagement, now(), 1)
  on conflict (etablissement_id, annee_scolaire_id, code) where periode_id is null and classe_id is null
  do update set valeur_numeric = excluded.valeur_numeric,
                calcule_le = now(),
                version = public.indicateurs_cles.version + 1;

  return 6;
end $$;

-- 7.2 Détection d'anomalies (notes aberrantes, absentéisme excessif).
create or replace function public.detecter_anomalies(p_etab uuid, p_annee uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_total int := 0;
  v_cnt int;
begin
  if not public.est_personnel(p_etab) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  -- Notes : écart > 2 écarts-types à la moyenne de l'évaluation, ou > barème.
  for r in
    select e.id, e.bareme, e.classe_id, avg(n.valeur) as moyenne, stddev_pop(n.valeur) as ecart_type
    from public.evaluations e
    join public.notes n on n.evaluation_id = e.id
    where e.etablissement_id = p_etab and e.annee_scolaire_id = p_annee
      and e.deleted_at is null and n.deleted_at is null and n.absent = false
    group by e.id, e.bareme, e.classe_id
    having count(n.valeur) >= 3
  loop
    insert into public.anomalies_statistiques
      (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, type, severite,
       description, valeur_observee, valeur_attendue, ecart, contexte, signature, statut, detectee_le)
    select n.etablissement_id, p_annee, r.classe_id, n.fiche_eleve_id, 'note',
           case when n.valeur > r.bareme then 'elevee' else 'moyenne' end,
           'Note aberrante : écart statistique à la moyenne de l''évaluation ou dépassement du barème.',
           n.valeur, round(r.moyenne, 2),
           round(abs(n.valeur - r.moyenne), 2),
           jsonb_build_object('evaluation_id', r.id, 'moyenne', round(r.moyenne,2),
                              'ecart_type', round(coalesce(r.ecart_type,0),2), 'bareme', r.bareme),
           md5(p_annee::text || ':note:' || n.fiche_eleve_id::text || ':' || r.id::text),
           'ouverte', now()
    from public.notes n
    where n.evaluation_id = r.id and n.deleted_at is null and n.absent = false and n.valeur is not null
      and (n.valeur > r.bareme or abs(n.valeur - r.moyenne) > 2 * coalesce(r.ecart_type, 0))
    on conflict (etablissement_id, signature) do nothing;
    get diagnostics v_cnt = row_count;
    v_total := v_total + v_cnt;
  end loop;

  -- Absences : taux individuel > 30 % sur l'année (au moins 5 séances).
  for r in
    select i.fiche_eleve_id as fiche, i.classe_id as classe,
           count(*) as total,
           count(*) filter (where p.statut <> 'present') as absences
    from public.presences p
    join public.inscriptions i on i.fiche_eleve_id = p.fiche_eleve_id
                              and i.annee_scolaire_id = p_annee and i.statut = 'active' and i.deleted_at is null
    where p.etablissement_id = p_etab and p.annee_scolaire_id = p_annee and p.deleted_at is null
    group by i.fiche_eleve_id, i.classe_id
    having count(*) >= 5
       and count(*) filter (where p.statut <> 'present')::numeric / count(*)::numeric > 0.3
  loop
    insert into public.anomalies_statistiques
      (etablissement_id, annee_scolaire_id, classe_id, fiche_eleve_id, type, severite,
       description, valeur_observee, valeur_attendue, ecart, contexte, signature, statut, detectee_le)
    values
      (p_etab, p_annee, r.classe, r.fiche, 'absence', 'elevee',
       'Absentéisme individuel excessif (taux > 30 %).',
       round(r.absences::numeric / r.total::numeric, 4), 0.30,
       round(r.absences::numeric / r.total::numeric - 0.30, 4),
       jsonb_build_object('total_seances', r.total, 'absences', r.absences),
       md5(p_annee::text || ':absence:' || r.fiche::text),
       'ouverte', now())
    on conflict (etablissement_id, signature) do nothing;
    get diagnostics v_cnt = row_count;
    v_total := v_total + v_cnt;
  end loop;

  return v_total;
end $$;

-- 7.3 Score de risque prédictif d'une classe (notes × assiduité × alertes).
create or replace function public.risque_classe(p_classe uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_etab uuid; v_annee uuid; v_effectif int;
  v_reussite numeric; v_absenteisme numeric; v_alertes int;
  v_score numeric; v_niveau text;
begin
  select c.etablissement_id, c.annee_scolaire_id into v_etab, v_annee
  from public.classes c where c.id = p_classe and c.deleted_at is null;

  if v_etab is null or not public.est_personnel(v_etab) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  select count(*) into v_effectif
  from public.inscriptions i
  where i.classe_id = p_classe and i.statut = 'active' and i.deleted_at is null;

  select case when count(*) = 0 then 0
              else count(*) filter (where n.valeur / e.bareme >= 0.5)::numeric / count(*)::numeric end
  into v_reussite
  from public.notes n
  join public.evaluations e on e.id = n.evaluation_id
  where e.classe_id = p_classe and n.deleted_at is null and e.deleted_at is null
    and n.absent = false and n.valeur is not null;

  select case when count(*) = 0 then 0
              else count(*) filter (where p.statut <> 'present')::numeric / count(*)::numeric end
  into v_absenteisme
  from public.presences p
  where p.classe_id = p_classe and p.deleted_at is null;

  select count(*) into v_alertes
  from public.alertes_decrochage a
  where a.etablissement_id = v_etab and a.annee_scolaire_id = v_annee
    and a.statut in ('ouverte', 'transmise') and a.deleted_at is null
    and exists (
      select 1 from public.inscriptions i
      where i.fiche_eleve_id = a.fiche_eleve_id and i.classe_id = p_classe and i.deleted_at is null
    );

  v_score := round(
    0.50 * v_absenteisme
    + 0.30 * (1 - v_reussite)
    + 0.20 * least(1.0, v_alertes::numeric / greatest(v_effectif, 1)::numeric),
    4);
  v_niveau := case when v_score >= 0.6 then 'eleve' when v_score >= 0.35 then 'moyen' else 'faible' end;

  return jsonb_build_object(
    'classe_id', p_classe,
    'effectif', v_effectif,
    'taux_reussite', round(v_reussite, 4),
    'taux_absenteisme', round(v_absenteisme, 4),
    'alertes_decrochage', v_alertes,
    'score_risque', v_score,
    'niveau_risque', v_niveau
  );
end $$;

-- 7.4 Recommandations stratégiques : renforcement/tutorat selon le risque.
create or replace function public.recommander_actions(p_etab uuid, p_annee uuid)
returns int
language plpgsql security definer set search_path = public as $$
declare
  r record; v_score numeric; v_type text; v_priorite text; v_titre text; v_desc text;
begin
  if not public.est_personnel(p_etab) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  for r in
    select id from public.classes c
    where c.etablissement_id = p_etab and c.annee_scolaire_id = p_annee
      and c.actif and c.deleted_at is null
  loop
    select (public.risque_classe(r.id)->>'score_risque')::numeric into v_score;

    if v_score >= 0.6 then
      v_type := 'tutorat'; v_priorite := 'haute';
      v_titre := 'Plan de tutorat et de renforcement pour la classe à risque';
      v_desc := 'Score de risque élevé (' || round(v_score,2)
             || '). Séances de renforcement et suivi tutorat ciblé des élèves fragiles.';
    elsif v_score >= 0.35 then
      v_type := 'renforcement'; v_priorite := 'moyenne';
      v_titre := 'Renforcement pédagogique de la classe';
      v_desc := 'Score de risque moyen (' || round(v_score,2)
             || '). Consolider les acquis et surveiller l''assiduité.';
    else
      continue;
    end if;

    insert into public.recommandations_strategiques
      (etablissement_id, annee_scolaire_id, classe_id, type, titre, description,
       justification, priorite, statut, cree_le)
    values
      (p_etab, p_annee, r.id, v_type, v_titre, v_desc,
       jsonb_build_object('score_risque', v_score, 'classe_id', r.id),
       v_priorite, 'proposee', now())
    on conflict (etablissement_id, annee_scolaire_id, classe_id, type)
      where classe_id is not null do nothing;
  end loop;

  return (select count(*) from public.recommandations_strategiques
          where etablissement_id = p_etab and annee_scolaire_id = p_annee);
end $$;

-- 7.5 Résumé exécutif en langage naturel (NLG structurée et traçable).
create or replace function public.generer_resume_executif(p_etab uuid, p_annee uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_libelle text;
  v_effectifs numeric; v_reussite numeric; v_absenteisme numeric;
  v_turnover numeric; v_masse numeric; v_engagement numeric;
  v_recos text := ''; v_nb int := 0; r record; v_resume text;
begin
  if not public.est_personnel(p_etab) then
    raise exception 'ACCES_REFUSE' using errcode = '42501';
  end if;

  select libelle into v_libelle from public.annees_scolaires where id = p_annee;
  perform public.consolider_indicateurs_etablissement(p_etab, p_annee);

  select coalesce(valeur_numeric, 0) into v_effectifs  from public.indicateurs_cles where etablissement_id = p_etab and annee_scolaire_id = p_annee and code = 'effectifs';
  select coalesce(valeur_numeric, 0) into v_reussite   from public.indicateurs_cles where etablissement_id = p_etab and annee_scolaire_id = p_annee and code = 'taux_reussite';
  select coalesce(valeur_numeric, 0) into v_absenteisme from public.indicateurs_cles where etablissement_id = p_etab and annee_scolaire_id = p_annee and code = 'absentisme';
  select coalesce(valeur_numeric, 0) into v_turnover   from public.indicateurs_cles where etablissement_id = p_etab and annee_scolaire_id = p_annee and code = 'turnover';
  select coalesce(valeur_numeric, 0) into v_masse      from public.indicateurs_cles where etablissement_id = p_etab and annee_scolaire_id = p_annee and code = 'masse_salariale';
  select coalesce(valeur_numeric, 0) into v_engagement from public.indicateurs_cles where etablissement_id = p_etab and annee_scolaire_id = p_annee and code = 'engagement_parents';

  for r in
    select titre from public.recommandations_strategiques
    where etablissement_id = p_etab and annee_scolaire_id = p_annee
      and statut in ('proposee', 'validee')
    order by case priorite when 'haute' then 0 when 'moyenne' then 1 else 2 end, cree_le desc
    limit 3
  loop
    if v_nb > 0 then v_recos := v_recos || ' ; '; end if;
    v_recos := v_recos || r.titre;
    v_nb := v_nb + 1;
  end loop;

  v_resume := 'Résumé exécutif — ' || coalesce(v_libelle, 'année scolaire') || E'\n'
    || 'Effectifs : ' || v_effectifs || ' élèves inscrits.' || E'\n'
    || 'Taux de réussite : ' || round(v_reussite * 100, 1) || ' %.' || E'\n'
    || 'Absentéisme : ' || round(v_absenteisme * 100, 1) || ' %.' || E'\n'
    || 'Turn-over RH : ' || round(v_turnover * 100, 1) || ' %.' || E'\n'
    || 'Masse salariale : ' || v_masse || '.' || E'\n'
    || 'Engagement des parents (taux d''ouverture) : ' || round(v_engagement * 100, 1) || ' %.' || E'\n';

  if v_nb > 0 then
    v_resume := v_resume || 'Recommandations : ' || v_recos || '.';
  else
    v_resume := v_resume || 'Aucune recommandation stratégique en attente.';
  end if;

  return v_resume;
end $$;

-- ---------------------------------------------------------------------------
-- 8. RLS — isolation par établissement, visibilité par rôle
-- ---------------------------------------------------------------------------
alter table public.rapports enable row level security;
alter table public.indicateurs_cles enable row level security;
alter table public.anomalies_statistiques enable row level security;
alter table public.recommandations_strategiques enable row level security;

-- Rapports : personnel, ou le parent/élève concerné pour un rapport individuel.
create policy rapports_select on public.rapports for select to authenticated
  using (public.est_personnel(etablissement_id)
         or (fiche_eleve_id is not null and public.fiche_visible(fiche_eleve_id)));
create policy rapports_insert on public.rapports for insert to authenticated
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'rapports.generer'));
create policy rapports_update on public.rapports for update to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'rapports.generer'))
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'rapports.generer'));
create policy rapports_delete on public.rapports for delete to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'rapports.administrer'));

-- Indicateurs clés : lecture personnel ; écriture administration uniquement.
create policy indicateurs_select on public.indicateurs_cles for select to authenticated
  using (public.est_personnel(etablissement_id));
create policy indicateurs_insert on public.indicateurs_cles for insert to authenticated
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'rapports.administrer'));
create policy indicateurs_update on public.indicateurs_cles for update to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'rapports.administrer'))
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'rapports.administrer'));
create policy indicateurs_delete on public.indicateurs_cles for delete to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'rapports.administrer'));

-- Anomalies : lecture personnel, détection par fonction, traitement par administrateur.
create policy anomalies_select on public.anomalies_statistiques for select to authenticated
  using (public.est_personnel(etablissement_id));
create policy anomalies_insert on public.anomalies_statistiques for insert to authenticated
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'rapports.generer'));
create policy anomalies_update on public.anomalies_statistiques for update to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'rapports.administrer'))
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'rapports.administrer'));
create policy anomalies_delete on public.anomalies_statistiques for delete to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'rapports.administrer'));

-- Recommandations : lecture personnel, proposition par fonction, validation administrateur.
create policy recos_select on public.recommandations_strategiques for select to authenticated
  using (public.est_personnel(etablissement_id));
create policy recos_insert on public.recommandations_strategiques for insert to authenticated
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'rapports.generer'));
create policy recos_update on public.recommandations_strategiques for update to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'rapports.administrer'))
  with check (public.est_personnel(etablissement_id)
              and public.a_permission(etablissement_id, 'rapports.administrer'));
create policy recos_delete on public.recommandations_strategiques for delete to authenticated
  using (public.est_personnel(etablissement_id)
         and public.a_permission(etablissement_id, 'rapports.administrer'));

-- ---------------------------------------------------------------------------
-- 9. Droits d'exécution
-- ---------------------------------------------------------------------------
grant select, insert, update, delete on public.rapports to authenticated;
grant select, insert, update, delete on public.indicateurs_cles to authenticated;
grant select, insert, update, delete on public.anomalies_statistiques to authenticated;
grant select, insert, update, delete on public.recommandations_strategiques to authenticated;

grant execute on function public.consolider_indicateurs_etablissement(uuid, uuid) to authenticated;
grant execute on function public.detecter_anomalies(uuid, uuid) to authenticated;
grant execute on function public.risque_classe(uuid) to authenticated;
grant execute on function public.recommander_actions(uuid, uuid) to authenticated;
grant execute on function public.generer_resume_executif(uuid, uuid) to authenticated;
